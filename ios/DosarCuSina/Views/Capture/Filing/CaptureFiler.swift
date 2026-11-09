import Foundation
import SwiftData

/// The one filer for every captured document, whichever way it came in: the review's
/// "Salvează", "Am rezolvat" with a photo of the new document, and a visit with its
/// invoice (`Intent`). Each is one unit of work, and each writes the same way:
/// - the values read, onto the section: `AssetActions.create` or `AssetActions.update`;
/// - the deadline: one rule (`renew`) for a new document's date, through `ObligationActions`
///   (close the cycle that was due and move to the new date, write the field a document's
///   expiry drives, or create it from the template's blueprint);
/// - who issued it: `ProviderActions`, an existing firm by name before a new one;
/// - a bill or a contract: its ongoing contract, a subscription found by
///   `SubscriptionMatcher` or made under its home; a bill is logged in its history
///   (`HistoryActions`) with its own due date to pay by;
/// - the document itself: `AttachmentActions.fileCaptured`, new pages or a kept copy
///   that moves here, linked to all of the above.
///
/// What takes time happens before the unit opens: Face ID for a locked section the
/// filing writes into or moves a document out of, and the pages from capture's store.
/// Side effects (reminders, widgets) follow every save through `SideEffectsCoordinator`.
@MainActor
struct CaptureFiler {
    let context: ModelContext
    var store: CaptureDocumentStore = .shared()
    var calendar: Calendar = .current
    var now: () -> Date = { Date() }
    /// Opens locked sections before the filing writes into one.
    var vault: BiometricVaultManager = .shared
    /// The person's answer when a counter reading in this filing is lower than an earlier one
    /// (`LowerReadingQuestion`); nil until they have been asked.
    var lowerReading: LowerReadingAnswer?

    /// What the person is filing.
    enum Intent {
        /// The review's "Salvează".
        case review(CaptureReview)
        /// "Am rezolvat" with what the person has in hand.
        case completion(Completion)
        /// A visit (a service, a repair, a check-up) with its invoice.
        case visit(Visit)
    }

    /// "Am rezolvat": the date, what it cost, and optionally the new document (the new
    /// policy, the ITP report), whose date sets the next deadline and whose values
    /// update the section, as a review would.
    struct Completion {
        var obligation: Obligation
        var date: Date
        var cost: Money?
        var document: CaptureResult?
        /// The person asked to keep the photo of a document kept only on request (a bank card).
        var keepsPhotoOnRequest = false
    }

    /// A visit from the visit form, with the invoice it was read from.
    struct Visit {
        enum ProviderChoice {
            case none
            case existing(Provider)
            /// Typed or read off the invoice (with the CUI read, if any): an existing firm with
            /// this name is used before a new one.
            case named(String, trade: ProviderTrade, taxID: String? = nil)
        }
        var asset: Asset
        var kind: HistoryKind
        var occurredAt: Date
        var checklist: [HistoryActions.ChecklistItem]
        var extraItems: [LineItemDraft] = []
        var totalCost: Money?
        var odometer: Double?
        /// Read off the invoice or typed; an estimate never reaches the filer.
        var odometerSource: ReadingSource = .person
        var provider: ProviderChoice = .none
        var rating: Int?
        var document: CapturedDocumentRef?
        var documentTitle: String?
        var documentText: String?
    }

    struct Outcome {
        var asset: Asset?
        var obligation: Obligation?
        var attachment: Attachment?
        /// A completion written for the cycle the document closed.
        var completion: HistoryEntry?
        /// A bill, logged in its subscription's history.
        var bill: HistoryEntry?
        /// The visit logged.
        var visit: HistoryEntry?
        /// A bill's meter index, as a reading on its subscription.
        var reading: MeasurementLog?
        /// The deadline's next date, when the filing moved one.
        var nextDue: CalendarDay?
        /// Takes the whole filing back: what it made goes, what it changed or moved
        /// (a kept document, the section's values, the deadline) goes back as it was.
        var receipt: UndoReceipt?
    }

    enum FilingError: LocalizedError, Equatable {
        case missingSection
        case missingName
        /// The section is locked and wasn't opened.
        case locked

        var errorDescription: String? {
            switch self {
            case .missingSection: return String(localized: "Secțiunea aleasă nu mai există. Alege alta.")
            case .missingName: return String(localized: "Scrie un nume pentru secțiunea nouă.")
            case .locked: return String(localized: "Secțiunea e protejată. Deschide-o cu Face ID sau cu codul, apoi salvează.")
            }
        }
    }

    /// The next deadline printed on a captured document: the day its kind's deadline
    /// follows, else any expiry, next dose, warranty end or due date it carries.
    static func nextDay(in result: CaptureResult) -> CalendarDay? {
        let keys: [CaptureFieldKey] = (result.kind.profile.deadlineField.map { [$0] } ?? []) + [.expiryDate, .nextDoseDate, .warrantyUntil, .dueDate]
        return keys.lazy.compactMap { result.field($0)?.value.day }.first.map(CaptureMapping.calendarDay)
    }

    // MARK: Plan

    /// Template values the review would write to `template`, from the fields read.
    static func values(from review: CaptureReview, for template: TemplateDefinition) -> FieldValues {
        values(from: review, for: template, deadline: review.deadlineBlueprint(in: template))
    }

    /// The same, for the deadline `deadline` the document sets in `template`: a policy's
    /// facts go where that deadline keeps them.
    static func values(from review: CaptureReview, for template: TemplateDefinition, deadline: ObligationBlueprint?) -> FieldValues {
        var values = FieldValues()
        for field in review.fields {
            guard let value = field.value,
                  let key = CaptureMapping.fieldKey(for: field.key, kind: review.kind, in: template, deadline: deadline),
                  let definition = template.field(key),
                  let converted = CaptureMapping.fieldValue(value, for: definition) else { continue }
            if values[key] == nil { values[key] = converted }
        }
        // A contract's minimum period ends where the review says (its printed end, or the
        // person's corrected start and length), so the deadline and the field agree.
        if review.kind.profile.deadlineField == .minimumPeriodEnd, let end = review.minimumPeriodEnd, template.field(SubscriptionFields.minimumUntil) != nil {
            values[SubscriptionFields.minimumUntil] = .date(end)
        }
        // A bill's amount is the subscription's last bill (`updateSubscription` keeps the newest).
        if review.kind.profile.deadlineIsOptIn, let total = review.total, template.field(SubscriptionFields.lastBill) != nil {
            values[SubscriptionFields.lastBill] = .money(total)
        }
        // Direct debit only when the person confirmed what the bill says; never from the reading alone.
        if review.turnsOnDirectDebit, template.field(SubscriptionFields.directDebit) != nil {
            values[SubscriptionFields.directDebit] = .bool(true)
        }
        if let type = review.kind.profile.documentType, template.field(DocumentType.typeFieldKey) != nil {
            values[DocumentType.typeFieldKey] = .text(type)
            // The layout that was read says which variant this is (the electronic card or the older one).
            if let variant = review.value(.documentVariant)?.text,
               DocumentType.variants(of: type).contains(where: { $0.key == variant }),
               template.field(DocumentType.variantFieldKey) != nil {
                values[DocumentType.variantFieldKey] = .text(variant)
            }
        }
        return values
    }

    /// What saving `review` will do, as the review shows it (`CaptureFilingPlan`).
    func plan(for review: CaptureReview) throws -> CaptureFilingPlan {
        CaptureFilingPlan.make(for: review, templates: try TemplateStore(context: context).templatesByKey(),
                               assets: try context.fetch(FetchDescriptor<Asset>()), today: CalendarDay(now(), calendar: calendar), calendar: calendar)
    }

    /// Whether saving would create or move a deadline, so the reminder permission is worth asking first.
    func touchesReminders(_ review: CaptureReview) -> Bool {
        (try? plan(for: review))?.schedulesReminder ?? false
    }

    // MARK: Save

    /// The review's "Salvează": the section, the deadline, who issued it and the
    /// document are all kept, or none of them is (see `UnitOfWork`).
    func save(_ review: CaptureReview) async throws -> Outcome {
        try await file(.review(review))
    }

    /// Files what the person confirmed, as one unit of work.
    func file(_ intent: Intent) async throws -> Outcome {
        let ref = documentRef(of: intent)
        let documents = AttachmentActions(context: context, calendar: calendar)
        // What takes time comes first: opening a locked section, then the pages.
        try await openLockedSections(for: intent, keptDocument: ref?.keptAttachmentID.flatMap(documents.attachment(id:)))
        var document: CapturedDocument?
        if let ref { document = try await documents.resolve(ref, from: store) }
        // A page the person turned, or the whole photo they chose, is drawn now too.
        var pictures: PictureChange?
        if case .review(let review) = intent, let document {
            pictures = await documents.pictureChange(for: document, choices: review.pageChoices)
        }
        // From here nothing waits: one step, everything or nothing.
        let filing = try UnitOfWork.performUndoable(in: context) {
            switch intent {
            case .review(let review): try fileReview(review, document: document, pictures: pictures)
            case .completion(let completion): try fileCompletion(completion, document: document)
            case .visit(let visit): try fileVisit(visit, document: document)
            }
        }
        var outcome = filing.value
        outcome.receipt = filing.receipt
        // Kept: this capture's hold on its pages ends (they're in the binder now).
        if let ref { await store.release(ref) }
        return outcome
    }

    /// The document an intent files, if any.
    private func documentRef(of intent: Intent) -> CapturedDocumentRef? {
        switch intent {
        case .review(let review): review.document
        case .completion(let completion): completion.document?.document
        case .visit(let visit): visit.document
        }
    }

    // MARK: Intents

    private func fileReview(_ review: CaptureReview, document: CapturedDocument?, pictures: PictureChange?) throws -> Outcome {
        let templates = try TemplateStore(context: context).templatesByKey()
        var outcome = Outcome()
        let today = CalendarDay(now(), calendar: calendar)
        let obligations = ObligationActions(context: context, calendar: calendar, now: now)
        // What the review showed is what happens: one plan, worked out before anything changes.
        let plan = CaptureFilingPlan.make(for: review, templates: templates, assets: try context.fetch(FetchDescriptor<Asset>()),
                                          today: today, calendar: calendar)

        // 1. The section.
        switch review.destination {
        case .none:
            break
        case .asset(let id):
            var descriptor = FetchDescriptor<Asset>(predicate: #Predicate { $0.id == id })
            descriptor.fetchLimit = 1
            guard let asset = try context.fetch(descriptor).first else { throw FilingError.missingSection }
            // What was read never lands in an example without the person keeping it as theirs.
            try ExampleOwnership.requireReal(asset)
            if let documentsKey = try Self.personalDocumentsKey(for: review, destinationTemplateKey: asset.templateKey, templates: templates) {
                // A person: the document becomes one of their documents, named after them.
                // Named after its holder as printed, else after the person it goes to.
                let namesHolder = review.kind.isPersonalDocument && CaptureMapping.holderName(review.valuesByKey) != nil
                let name = namesHolder ? review.title : DocumentNaming.name(document: review.title, holder: asset.name)
                outcome.asset = try createSection(review, templateKey: documentsKey, name: name, parent: asset, plan: plan, templates: templates)
                break
            }
            if Self.filesUnderSubscription(review, destinationTemplateKey: asset.templateKey, templates: templates) {
                // A home: the bill or contract goes to its subscription there, or a new one.
                try fillHomeAddress(asset, from: review, templates: templates)
                outcome.asset = try subscription(for: review, under: asset, plan: plan, templates: templates)
                break
            }
            if templates.plays(.subscription, asset.templateKey), review.kind.profile.filing == .subscription,
               let template = templates[asset.templateKey] {
                try fillHomeAddress(asset.parent, from: review, templates: templates)
                try updateSubscription(asset, from: review, template: template)
                outcome.asset = asset
                break
            }
            try writeValues(of: review, to: asset, templates: templates)
            outcome.asset = asset
        case .newAsset(let templateKey):
            let name = review.newAssetName.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty else { throw FilingError.missingName }
            if let documentsKey = try Self.personalDocumentsKey(for: review, destinationTemplateKey: templateKey, templates: templates) {
                // A new person, named after the holder, with the document filed under them,
                // in one save: a failure leaves neither behind.
                guard let memberTemplate = templates[templateKey] else { throw FilingError.missingSection }
                outcome.asset = try createSection(review, templateKey: documentsKey, name: review.title,
                                                  newParent: AssetActions.NewParent(name: name, template: memberTemplate), plan: plan, templates: templates)
            } else if Self.filesUnderSubscription(review, destinationTemplateKey: templateKey, templates: templates) {
                // A new home with the bill's or contract's subscription under it, in one save.
                guard let homeTemplate = templates[templateKey], let subscriptions = templates.key(withRole: .subscription) else { throw FilingError.missingSection }
                let home = AssetActions.NewParent(name: name, template: homeTemplate, values: Self.homeValues(from: review, for: homeTemplate.definition))
                outcome.asset = try createSection(review, templateKey: subscriptions, name: Self.subscriptionName(review),
                                                  newParent: home, plan: plan, templates: templates)
            } else {
                outcome.asset = try createSection(review, templateKey: templateKey, name: name, parent: nil, plan: plan, templates: templates)
            }
        }

        // The policy's bonus-malus class, on the person it insures (never on the car).
        try keepBonusMalus(plan.bonusMalus, on: outcome.asset, deadline: plan.blueprint)

        // 2. The deadline, as the plan says: the section's own moves (or its cycle closes),
        // or a new one is made. A new section already made it with its other deadlines.
        if let asset = outcome.asset, let blueprint = plan.blueprint {
            if let deadline = plan.deadline {
                if let existing = CaptureFilingPlan.existingDeadline(blueprint, in: asset, takesUpPaused: review.kind.profile.deadlineIsOptIn) {
                    // A bill reminder paused while the bank paid: this bill asks for one again.
                    if existing.status == .paused { try obligations.resume(existing) }
                    outcome.completion = try renew(existing, to: deadline.day, done: false, on: nil, cost: review.total)
                } else {
                    _ = try obligations.create(from: deadline.blueprint, for: asset, firstDue: deadline.day)
                }
            }
            outcome.obligation = asset.activeObligations.first { $0.blueprintKey == blueprint.key }
            if let deadline = plan.deadline, review.kind.profile.deadlineIsOptIn, let bill = outcome.obligation, bill.dueDay(in: calendar) == deadline.day {
                // This bill's amount and number on its reminder.
                try obligations.setDetails(bill, estimatedCost: review.total, reference: review.value(.invoiceNumber)?.text)
            }
        }
        outcome.nextDue = outcome.obligation?.dueDay(in: calendar)

        // A bill, in its subscription's history: what it came to and when, for the trend
        // and for knowing when the next one is due.
        if review.kind.profile.deadlineIsOptIn, let asset = outcome.asset, templates.plays(.subscription, asset.templateKey) {
            outcome.bill = try HistoryActions(context: context, now: now).record(
                on: asset,
                kind: .payment,
                title: review.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? CaptureMapping.defaultTitle(for: review.kind, fields: review.valuesByKey) : review.title,
                occurredAt: Self.billDay(review, today: today).noonDate(in: calendar),
                totalCost: review.total,
                note: review.value(.invoiceNumber)?.text.map { String(localized: "Factura nr. \($0)") }
            )
        }

        // 3. Who issued it.
        let provider = try self.provider(plan.provider, asset: outcome.asset)

        // 4. The document, linked to all of it: the new pages, or the copy already
        // kept when the same photo was filed before (it moves here, never lost). A bank
        // card's photo only when the person asked: it shows the card's whole number.
        if let document, plan.keepsPhoto {
            let title = review.title.trimmingCharacters(in: .whitespacesAndNewlines)
            let filed = try AttachmentActions(context: context, calendar: calendar).fileCaptured(
                document,
                pictures: pictures,
                title: title.isEmpty ? nil : title,
                kind: review.kind.profile.documentKind,
                extractedText: review.result.recognizedText.isEmpty ? nil : review.result.recognizedText,
                documentDate: review.documentDay,
                validUntil: review.validUntil,
                asset: outcome.asset,
                obligation: outcome.obligation,
                historyEntry: outcome.completion ?? outcome.bill,
                provider: provider
            )
            outcome.attachment = filed
        }

        // 5. A bill's meter index, as the plan says: a reading on its subscription, from the
        // document, linked to it.
        let subscription = outcome.asset.flatMap { templates.plays(.subscription, $0.templateKey) ? $0 : nil }
        outcome.reading = try recordMeterReading(subscription == nil ? nil : plan.meter?.reading, on: subscription,
                                                 document: outcome.attachment, templates: templates)
        return outcome
    }

    /// "Am rezolvat": the same steps as the review, for the deadline the person closed.
    private func fileCompletion(_ completion: Completion, document: CapturedDocument?) throws -> Outcome {
        let obligation = completion.obligation
        let today = CalendarDay(now(), calendar: calendar)
        var outcome = Outcome(asset: obligation.asset, obligation: obligation)
        let review = try completion.document.map { result -> CaptureReview in
            if obligation.asset != nil { try ExampleOwnership.requireReal(obligation.asset) }
            var review = CaptureReview(result: result, assets: [], context: context)
            review.destination = obligation.asset.map { .asset($0.id) } ?? .none
            review.keepsPhotoOnRequest = completion.keepsPhotoOnRequest
            return review
        }

        // 1. The values read, onto the section: a new RCA policy brings its number, insurer and
        // claims phone, into the fields of the deadline being closed (a CASCO's into CASCO's).
        if let review, let asset = obligation.asset {
            let templates = try TemplateStore(context: context).templatesByKey()
            let closing = obligation.blueprintKey.flatMap { key in templates[asset.templateKey]?.blueprints.first { $0.key == key } }
            try writeValues(of: review, to: asset, templates: templates, deadline: closing)
            try keepBonusMalus(bonusMalusChoice(for: review), on: asset, deadline: closing)
        }

        // 2. The deadline: the cycle closes, and the new document's date sets the next one.
        let newDay = completion.document.flatMap(Self.nextDay(in:)).flatMap { $0 > today ? $0 : nil }
        outcome.completion = try renew(obligation, to: newDay, done: true, on: completion.date, cost: completion.cost)
        if obligation.status == .active { outcome.nextDue = obligation.dueDay(in: calendar) }

        // 3. Who issued it, and 4. the document (a bank card's photo only on request).
        if let review, let document, review.keepsPhoto {
            let provider = try self.provider(Self.provider(of: review), asset: obligation.asset)
            let filed = try AttachmentActions(context: context, calendar: calendar).fileCaptured(
                document,
                title: CaptureMapping.defaultTitle(for: review.kind, fields: review.valuesByKey),
                kind: review.kind.profile.documentKind,
                extractedText: review.result.recognizedText.isEmpty ? nil : review.result.recognizedText,
                documentDate: review.documentDay ?? CalendarDay(completion.date, calendar: calendar),
                validUntil: review.validUntil,
                asset: obligation.asset,
                obligation: obligation,
                historyEntry: outcome.completion,
                provider: provider
            )
            outcome.attachment = filed
        }
        return outcome
    }

    /// A visit with its invoice: the provider, the entry and the document, together.
    private func fileVisit(_ visit: Visit, document: CapturedDocument?) throws -> Outcome {
        let provider: Provider? = switch visit.provider {
        case .none: nil
        case .existing(let provider): provider
        case .named(let name, let trade, let taxID):
            try ProviderActions(context: context, now: now).findOrCreate(name: name, taxID: taxID, trade: trade, linkedTo: visit.asset)
        }
        if let provider, case .existing = visit.provider { try ProviderActions(context: context, now: now).link(provider, to: visit.asset) }
        let entry = try HistoryActions(context: context, now: now).recordVisit(
            on: visit.asset,
            kind: visit.kind,
            occurredAt: visit.occurredAt,
            checklist: visit.checklist,
            extraItems: visit.extraItems,
            totalCost: visit.totalCost,
            odometer: visit.odometer,
            provider: provider,
            rating: visit.rating,
            calendar: calendar,
            odometerSource: visit.odometerSource,
            lowerReading: lowerReading
        ).value
        var outcome = Outcome(asset: visit.asset, visit: entry)
        if let document {
            let filed = try AttachmentActions(context: context, calendar: calendar).fileCaptured(
                document,
                title: visit.documentTitle,
                kind: .invoice,
                extractedText: visit.documentText,
                documentDate: CalendarDay(visit.occurredAt, calendar: calendar),
                asset: visit.asset,
                historyEntry: entry,
                provider: provider
            )
            outcome.attachment = filed
        }
        return outcome
    }

    // MARK: Shared steps

    /// Records a bill's meter index on its subscription through the one reading path
    /// (`HouseholdMutations.recordReading`: from a document, a lower index asks first), and
    /// links it to the document. A bill records one index, and it follows the bill as filed
    /// now: filed again, it keeps the reading it recorded when nothing changed, and replaces
    /// it when the person corrected the index or moved the bill (to no subscription, or with
    /// the index cleared, it goes). The same index on the same day is the same reading too
    /// (the bill read again from another photo), so it is never kept twice. Nil `reading`:
    /// the filing keeps no index.
    private func recordMeterReading(_ reading: SubscriptionMeter.Reading?, on subscription: Asset?, document: Attachment?,
                                    templates: [String: CategoryTemplate]) throws -> MeasurementLog? {
        // Only a reading a bill recorded on a subscription is the document's to replace.
        if let earlier = document?.measurement, !earlier.isDeleted, let owner = earlier.asset, templates.plays(.subscription, owner.templateKey) {
            if let reading, owner.id == subscription?.id, reading.isRecorded(by: earlier, calendar: calendar) { return earlier }
            document?.measurement = nil
            HouseholdMutations.removeReading(earlier, from: owner, in: context)
            HouseholdMutations.syncHeroMetric(of: owner, in: context)
        }
        guard let reading, let subscription else { return nil }
        if let same = (subscription.measurements ?? []).first(where: { reading.isRecorded(by: $0, calendar: calendar) }) {
            document?.measurement = same
            return same
        }
        let log = try HouseholdMutations.recordReading(
            reading.value, on: subscription, at: reading.day.noonDate(in: calendar), source: .document,
            unit: reading.unit, kind: reading.kind, answer: lowerReading, in: context
        )
        document?.measurement = log
        return log
    }

    /// Where a policy's bonus-malus class goes, worked out from the household as it is now.
    private func bonusMalusChoice(for review: CaptureReview?) -> CaptureFilingPlan.BonusMalus? {
        review.flatMap { CaptureFilingPlan.bonusMalus(for: $0, people: Policyholders.people(in: context)) }
    }

    /// A policy's bonus-malus class, kept on the person it insures, and that person named
    /// in the policy's facts on the section (`BlueprintFactRole.policyholder`), so the
    /// policy's page reads the class from them and it is never kept twice. Nothing is kept
    /// when the household doesn't know who the policy insures.
    private func keepBonusMalus(_ choice: CaptureFilingPlan.BonusMalus?, on asset: Asset?, deadline: ObligationBlueprint?) throws {
        guard case .keep(let classKey, let memberID, let memberName) = choice else { return }
        let actions = AssetActions(context: context, calendar: calendar, now: now)
        var descriptor = FetchDescriptor<Asset>(predicate: #Predicate { $0.id == memberID })
        descriptor.fetchLimit = 1
        if let member = try context.fetch(descriptor).first, member.values[MemberFields.bonusMalus]?.textValue != classKey {
            var values = member.values
            values[MemberFields.bonusMalus] = .text(classKey)
            try actions.update(member, name: member.name, values: values, notes: member.notes)
        }
        if let asset, let field = deadline?.facts?.policyholder, asset.values[field]?.textValue != memberName {
            var values = asset.values
            values[field] = .text(memberName)
            try actions.update(asset, name: asset.name, values: values, notes: asset.notes)
        }
    }

    /// What a captured document's values change on a section that already exists: what
    /// was read replaces what was there, except a value that only differs in how it's written.
    /// `deadline` is the deadline the values belong to, when the caller knows it better than
    /// the document does ("Am rezolvat" on a CASCO).
    private func writeValues(of review: CaptureReview, to asset: Asset, templates: [String: CategoryTemplate], deadline: ObligationBlueprint? = nil) throws {
        guard let template = templates[asset.templateKey] else { return }
        let read = Self.values(from: review, for: template.definition, deadline: deadline ?? review.deadlineBlueprint(in: template.definition))
        let merged = Self.merging(read, into: asset.values)
        if merged != asset.values {
            // A reading on the document (the kilometres on an invoice) is dated by the document.
            try AssetActions(context: context, calendar: calendar, now: now).update(
                asset, name: asset.name, values: merged, notes: asset.notes,
                readingSource: .document, readingDate: review.documentDay?.noonDate(in: calendar), lowerReading: lowerReading
            )
        }
    }

    /// What a reading brings to values already kept: what was read replaces what was there,
    /// except a value that only differs in how it's written ("B 123 ABC" read off a policy
    /// doesn't rewrite the "B-123-ABC" the person typed). The one rule for filing onto a
    /// section and for reading a filed document again (`DocumentReading`).
    static func merging(_ read: FieldValues, into current: FieldValues) -> FieldValues {
        var merged = current
        for (key, value) in read where merged[key] != value {
            if let old = merged[key]?.textValue, let new = value.textValue,
               CaptureMapping.normalizedIdentifier(old) == CaptureMapping.normalizedIdentifier(new) { continue }
            merged[key] = value
        }
        return merged
    }

    /// The one rule for what a new document's date does to the deadline it renews,
    /// for the review and for "Am rezolvat":
    /// - a deadline whose date comes from a field (a document's expiry): the field takes the
    ///   new date, and the deadline follows it;
    /// - a repeating one: the cycle that was due closes (a completion in the history) and the
    ///   next date is the document's;
    /// - a one-off: it moves to the document's date.
    /// An older date never moves a deadline back. `done` is the person's "Am rezolvat": the
    /// cycle closes even when the document has no later date. Returns the completion written.
    private func renew(_ obligation: Obligation, to day: CalendarDay?, done: Bool, on date: Date?, cost: Money?) throws -> HistoryEntry? {
        let actions = ObligationActions(context: context, calendar: calendar, now: now)
        let due = obligation.dueDay(in: calendar)
        guard done || (day.map { $0 > due } ?? false) else { return nil }
        if let day, let asset = obligation.asset, let field = fieldDrivingDueDate(of: obligation) {
            if asset.values[field] != .date(day) {
                var values = asset.values
                values[field] = .date(day)
                try AssetActions(context: context, calendar: calendar, now: now).update(asset, name: asset.name, values: values, notes: asset.notes)
            }
            return nil
        }
        if done || obligation.recurrence.repeats {
            let entry = try actions.complete(obligation, on: date, cost: cost).value
            if obligation.status == .active, let day, obligation.dueDay(in: calendar) != day {
                try actions.reschedule(obligation, to: day)
            }
            return entry
        }
        if let day { try actions.reschedule(obligation, to: day) }
        return nil
    }

    /// The asset field a one-off obligation takes its date from (a document's expiry).
    private func fieldDrivingDueDate(of obligation: Obligation) -> String? {
        guard let key = obligation.blueprintKey, let asset = obligation.asset,
              let template = try? TemplateStore(context: context).template(forKey: asset.templateKey),
              let blueprint = template.blueprints.first(where: { $0.key == key }),
              !blueprint.recurrence.repeats,
              case .field(let field, _) = blueprint.firstDue else { return nil }
        return field
    }

    /// Asks for Face ID or the passcode before the filing writes into a locked section
    /// that already exists, or moves a document out of one. A new section reveals
    /// nothing, so it doesn't ask. Nothing is written when the person doesn't open it.
    private func openLockedSections(for intent: Intent, keptDocument: Attachment?) async throws {
        let templates = try TemplateStore(context: context).templatesByKey()
        var keys: [String] = []
        func add(_ asset: Asset?) {
            var current = asset
            while let node = current { keys.append(node.templateKey); current = node.parent }
        }
        switch intent {
        case .review(let review):
            switch review.destination {
            case .none: break
            case .asset(let id):
                add(try context.fetch(FetchDescriptor<Asset>(predicate: #Predicate { $0.id == id })).first)
            case .newAsset:
                break
            }
        case .completion(let completion):
            if completion.document != nil { add(completion.obligation.asset) }
        case .visit(let visit):
            add(visit.asset)
        }
        add(keptDocument?.asset)
        // The person whose bonus-malus class the policy brings.
        let review: CaptureReview? = switch intent {
        case .review(let review): review
        case .completion(let completion): completion.document.map { CaptureReview(result: $0, assets: [], context: context) }
        case .visit: nil
        }
        if case .keep(_, let memberID, _) = bonusMalusChoice(for: review) {
            add(try context.fetch(FetchDescriptor<Asset>(predicate: #Predicate { $0.id == memberID })).first)
        }
        guard keys.contains(where: { templates[$0]?.isSensitive == true }), !vault.isSessionUnlocked else { return }
        let result = await vault.unlock(reason: String(localized: "Deschide secțiunea protejată ca să salvez actul."))
        guard result == .success else { throw FilingError.locked }
    }

    /// The category a document becomes when it is filed under a person (a category whose
    /// part is `holder`): a personal document, or a capture started from their documents
    /// (`filesAsPersonalDocument`) whatever its kind, becomes one of their personal
    /// documents. Nil otherwise.
    static func holderDocumentTemplateKey(for review: CaptureReview, destinationTemplateKey: String, templates: [String: CategoryTemplate]) -> String? {
        guard filesAsPersonalDocument(review, destinationTemplateKey: destinationTemplateKey, templates: templates) else { return nil }
        return templates.key(withRole: .personalDocument)
    }

    /// Whether the review files a personal document of the person it goes to: an identity
    /// document, or anything started from their documents.
    static func filesAsPersonalDocument(_ review: CaptureReview, destinationTemplateKey: String, templates: [String: CategoryTemplate]) -> Bool {
        templates.plays(.holder, destinationTemplateKey) && (review.kind.isPersonalDocument || review.filesAsPersonalDocument)
    }

    /// The category a personal document is filed in, for a review that files one; the
    /// filing can't go on without it.
    private static func personalDocumentsKey(for review: CaptureReview, destinationTemplateKey: String, templates: [String: CategoryTemplate]) throws -> String? {
        guard filesAsPersonalDocument(review, destinationTemplateKey: destinationTemplateKey, templates: templates) else { return nil }
        guard let key = templates.key(withRole: .personalDocument) else { throw FilingError.missingSection }
        return key
    }

    /// The category the document's values land in, when it is filed under `destinationTemplateKey`.
    static func filedTemplateKey(for review: CaptureReview, destinationTemplateKey: String, templates: [String: CategoryTemplate]) -> String {
        if filesUnderSubscription(review, destinationTemplateKey: destinationTemplateKey, templates: templates),
           let subscriptions = templates.key(withRole: .subscription) {
            return subscriptions
        }
        return holderDocumentTemplateKey(for: review, destinationTemplateKey: destinationTemplateKey, templates: templates) ?? destinationTemplateKey
    }

    // MARK: Subscriptions

    /// A bill or a contract filed under a home goes to the home's subscription for it.
    static func filesUnderSubscription(_ review: CaptureReview, destinationTemplateKey: String, templates: [String: CategoryTemplate]) -> Bool {
        review.kind.profile.filing == .subscription && templates.plays(.home, destinationTemplateKey)
    }

    /// What a new subscription made from the review is called.
    static func subscriptionName(_ review: CaptureReview) -> String {
        let name = review.newAssetName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !name.isEmpty, case .newAsset(let key) = review.destination, review.behaviors.plays(.subscription, key) { return name }
        return SubscriptionNaming.name(provider: review.value(.provider)?.text, service: review.value(.serviceKind)?.text)
    }

    /// What a bill or a contract tells the home it is filed under: the address it is
    /// supplied at, for the home's own address. Nothing for any other document.
    static func homeValues(from review: CaptureReview, for home: TemplateDefinition) -> FieldValues {
        var values = FieldValues()
        guard review.kind.profile.filing == .subscription, let address = review.value(.supplyAddress),
              let key = CaptureMapping.fieldKey(for: .supplyAddress, kind: review.kind, in: home, deadline: nil),
              let definition = home.field(key), let value = CaptureMapping.fieldValue(address, for: definition) else { return values }
        values[key] = value
        return values
    }

    /// A home without an address takes the one its bill is supplied at, so the next bill
    /// finds it. An address the person wrote is never changed.
    private func fillHomeAddress(_ home: Asset?, from review: CaptureReview, templates: [String: CategoryTemplate]) throws {
        guard let home, templates.plays(.home, home.templateKey), let template = templates[home.templateKey] else { return }
        var merged = home.values
        for (key, value) in Self.homeValues(from: review, for: template.definition)
        where (merged[key]?.textValue ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            merged[key] = value
        }
        guard merged != home.values else { return }
        try AssetActions(context: context, calendar: calendar, now: now).update(home, name: home.name, values: merged, notes: home.notes)
    }

    /// The day a bill is logged on: the day it was issued, else today.
    static func billDay(_ review: CaptureReview, today: CalendarDay) -> CalendarDay {
        review.value(.issueDate)?.day.map(CaptureMapping.calendarDay) ?? today
    }

    /// The home's subscription the bill or contract belongs to, updated with what was
    /// read, or a new one under the home.
    private func subscription(for review: CaptureReview, under home: Asset, plan: CaptureFilingPlan,
                              templates: [String: CategoryTemplate]) throws -> Asset {
        guard let key = templates.key(withRole: .subscription), let template = templates[key] else { throw FilingError.missingSection }
        let children = (home.children ?? []).filter { templates.plays(.subscription, $0.templateKey) }
        let decision = SubscriptionMatcher.match(
            review.subscriptionReading,
            subscriptions: children.map { SubscriptionMatcher.Subscription(id: $0.id, parentID: home.id, values: $0.values) },
            homes: [], within: home.id
        )
        if case .existing(let id) = decision, let existing = children.first(where: { $0.id == id }) {
            try updateSubscription(existing, from: review, template: template)
            return existing
        }
        return try createSection(review, templateKey: key, name: Self.subscriptionName(review), parent: home, plan: plan, templates: templates)
    }

    /// What a bill or a contract adds to a subscription that already exists. A bill fills
    /// what is still empty and, when it is the newest, sets the last bill; it never
    /// rewrites what the person keeps there. A contract (or an addendum) also brings its
    /// terms: the number, the start, the minimum period and the price.
    private func updateSubscription(_ subscription: Asset, from review: CaptureReview, template: CategoryTemplate) throws {
        let read = Self.values(from: review, for: template.definition)
        let terms: Set<String> = review.kind.profile.deadlineField == .minimumPeriodEnd
            ? [SubscriptionFields.contractNumber, SubscriptionFields.startDate, SubscriptionFields.minimumMonths,
               SubscriptionFields.minimumUntil, SubscriptionFields.price]
            : []
        var merged = subscription.values
        for (key, value) in read where key != SubscriptionFields.lastBill {
            if merged[key] == nil || (terms.contains(key) && merged[key] != value) { merged[key] = value }
        }
        // The person confirmed the bill's direct debit: it turns on, and the bill reminder
        // already made pauses with it (`BillReminders`, through `AssetActions.update`).
        if let directDebit = read[SubscriptionFields.directDebit] { merged[SubscriptionFields.directDebit] = directDebit }
        if let lastBill = read[SubscriptionFields.lastBill] {
            let issued = Self.billDay(review, today: CalendarDay(now(), calendar: calendar))
            let newest = (subscription.history ?? []).filter { $0.kind == .payment && !$0.isCompletion }
                .map { CalendarDay($0.occurredAt, calendar: calendar) }.max()
            if newest.map({ issued >= $0 }) ?? true { merged[SubscriptionFields.lastBill] = lastBill }
        }
        guard merged != subscription.values else { return }
        try AssetActions(context: context, calendar: calendar, now: now).update(subscription, name: subscription.name, values: merged, notes: subscription.notes)
    }

    /// The loose "Factură <provider>" payment obligation bills used to create, not tied to
    /// any subscription. Kept, not called, as a way back until filing bills under their
    /// subscription is proven; obligations it made before stay as they are.
    @available(*, deprecated, message: "Bills remind through their subscription's \"subscription.bill\" deadline.")
    private func looseBillReminder(_ review: CaptureReview, asset: Asset?, today: CalendarDay) throws -> Obligation? {
        guard review.kind == .utilityInvoice, review.remindsToPay, let day = review.reminderDay, day >= today else { return nil }
        let provider = review.value(.provider)?.text
        return try ObligationActions(context: context, calendar: calendar, now: now).create(
            title: provider.map { String(localized: "Factură \($0)") } ?? String(localized: "Factură de plătit"),
            kind: .payment,
            dueDay: day,
            for: asset,
            estimatedCost: review.total,
            reference: review.value(.invoiceNumber)?.text
        )
    }

    /// A new section with the values read and the deadlines its template plans. The
    /// document's own deadline is the plan's: on its day, or not made when the plan says so.
    private func createSection(_ review: CaptureReview, templateKey: String, name: String, parent: Asset? = nil,
                               newParent: AssetActions.NewParent? = nil, plan: CaptureFilingPlan,
                               templates: [String: CategoryTemplate]) throws -> Asset {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let template = templates[templateKey] else { throw FilingError.missingSection }
        let actions = AssetActions(context: context, calendar: calendar, now: now)
        let values = Self.values(from: review, for: template.definition)
        let today = CalendarDay(now(), calendar: calendar)
        let planned = actions.plannedObligations(for: template, values: values).map { planned -> PlannedObligation in
            var planned = planned
            if planned.blueprint.key == plan.blueprint?.key {
                // The document's own deadline: its day, or none when it isn't wanted or has passed.
                planned.firstDue = plan.deadline?.day
                planned.isSelected = plan.deadline != nil
            } else if planned.blueprint.isFieldDriven, let day = planned.firstDue {
                // Another date the document fills follows the same rule (`isWorthScheduling`).
                planned.isSelected = planned.isSelected && planned.blueprint.isWorthScheduling(on: day, today: today, values: values)
            }
            // Dates the person still has to give (the current ITP) are left for the section page.
            planned.isSelected = planned.isSelected && planned.firstDue != nil
            return planned
        }
        return try actions.create(name: name.isEmpty ? CaptureMapping.kindTitle(review.kind) : name, template: template, values: values, obligations: planned, parent: parent, newParent: newParent)
    }

    /// Who issued a document a review files, as its plan names them.
    static func provider(of review: CaptureReview) -> CaptureFilingPlan.Provider? {
        guard let trade = review.kind.profile.trade, let name = review.value(.provider)?.text else { return nil }
        return CaptureFilingPlan.Provider(name: name, taxID: review.value(.providerTaxID)?.text, trade: trade, phone: review.value(.providerPhone)?.text)
    }

    /// The firm in Agendă, by its CUI, else by its name, else a new one, linked to the section.
    private func provider(_ provider: CaptureFilingPlan.Provider?, asset: Asset?) throws -> Provider? {
        guard let provider else { return nil }
        return try ProviderActions(context: context, now: now).findOrCreate(
            name: provider.name, taxID: provider.taxID, trade: provider.trade, phone: provider.phone, linkedTo: asset
        )
    }
}

/// The reminder a review will set, in plain words, read from its filing plan:
/// "Expiră pe 12 august 2031. Te anunț cu 3 luni și cu o lună înainte." It names a
/// reminder exactly when saving makes or moves one.
enum CaptureReminderPreview {
    @MainActor
    static func text(for review: CaptureReview, templates: [String: CategoryTemplate], assets: [Asset], calendar: Calendar = .current, today: CalendarDay) -> String? {
        text(for: review, plan: CaptureFilingPlan.make(for: review, templates: templates, assets: assets, today: today, calendar: calendar), today: today)
    }

    static func text(for review: CaptureReview, plan: CaptureFilingPlan, today: CalendarDay) -> String? {
        guard let day = plan.day else { return nil }
        let date = DueWording.date(day, today: today)
        let field = review.kind.profile.deadlineField
        let opening: String = switch field {
        case .dueDate?: String(localized: "De plătit până pe \(date).")
        case .minimumPeriodEnd?: String(localized: "Perioada minimă se termină pe \(date). De atunci poți, de regulă, renunța fără penalități.")
        case .nextDoseDate?: String(localized: "Următoarea doză e pe \(date).")
        case .warrantyUntil?: String(localized: "Garanția se termină pe \(date).")
        case .expiryDate? where review.validityEnd == day:
            // Not printed: the document's rule gives it (a cazier judiciar, six months from its issue).
            ReminderWording.validityOpening(day, months: review.validityMonths ?? 0, today: today)
        default: String(localized: "Expiră pe \(date).")
        }
        if let deadline = plan.deadline {
            let travel = ReminderWording.travelLine(expiring: day, profile: deadline.reminders, today: today)
            return [opening, travel, ReminderWording.sentence(deadline.reminders)].compactMap { $0 }.joined(separator: " ")
        }
        switch plan.quiet {
        case .notWanted?:
            return nil
        case .paidByDirectDebit?:
            return String(localized: "De plătit până pe \(date). Se plătește prin debit direct, așa că nu îți amintesc.")
        case .needsPlace?:
            if review.kind.profile.deadlineIsOptIn {
                return opening + " " + String(localized: "Alege abonamentul ei ca să îți amintesc s-o plătești.")
            }
            return opening + " " + String(localized: "Alege unde îl pui ca să te anunț din timp.")
        case .dayPassed?:
            if field == .minimumPeriodEnd {
                // The minimum period is over: nothing to remind about, but worth knowing.
                return String(localized: "Perioada minimă s-a terminat pe \(date). De regulă, poți renunța oricând, anunțând cu cel mult o lună înainte.")
            }
            return opening + " " + String(localized: "Data a trecut, așa că nu îți mai amintesc.")
        case .alreadyLater(let later)?:
            return opening + " " + String(localized: "Termenul de aici e deja pe \(DueWording.date(later, today: today)), așa că rămâne așa.")
        case .noSuchDeadline?:
            return opening + " " + String(localized: "Categoria aleasă nu are acest termen, așa că nu îți amintesc.")
        case nil:
            return nil
        }
    }
}
