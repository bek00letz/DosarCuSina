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
        /// The deadline's next date, when the filing moved one.
        var nextDue: CalendarDay?
        /// Where a kept document was before it moved here, to take the move back.
        var movedDocument: RefileReceipt?
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

    /// The next deadline printed on a captured document (expiry, due date, next dose).
    static func nextDay(in result: CaptureResult) -> CalendarDay? {
        let keys: [CaptureFieldKey] = [.expiryDate, .nextDoseDate, .warrantyUntil, .dueDate]
        return keys.lazy.compactMap { result.field($0)?.value.day }.first.map(CaptureMapping.calendarDay)
    }

    // MARK: Plan

    /// Template values the review would write to `template`, from the fields read.
    static func values(from review: CaptureReview, for template: TemplateDefinition) -> FieldValues {
        var values = FieldValues()
        for field in review.fields {
            guard let value = field.value,
                  let key = CaptureMapping.fieldKey(for: field.key, kind: review.kind, in: template, coverage: review.value(.coverageType)?.text),
                  let definition = template.field(key),
                  let converted = CaptureMapping.fieldValue(value, for: definition) else { continue }
            if values[key] == nil { values[key] = converted }
        }
        // A contract's minimum period ends where the review says (its printed end, or the
        // person's corrected start and length), so the deadline and the field agree.
        if review.kind == .contract, let end = review.minimumPeriodEnd, template.field(SubscriptionFields.minimumUntil) != nil {
            values[SubscriptionFields.minimumUntil] = .date(end)
        }
        // A bill's amount is the subscription's last bill (`updateSubscription` keeps the newest).
        if review.kind == .utilityInvoice, let total = review.total, template.field(SubscriptionFields.lastBill) != nil {
            values[SubscriptionFields.lastBill] = .money(total)
        }
        if let type = CaptureMapping.documentType(for: review.kind), template.field(DocumentType.typeFieldKey) != nil {
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

    /// Whether saving would create or move a deadline, so the reminder permission is worth asking first.
    func touchesReminders(_ review: CaptureReview) -> Bool {
        let assets = (try? context.fetch(FetchDescriptor<Asset>())) ?? []
        guard let day = review.reminderDay, review.destination != .none else { return false }
        if CaptureMapping.filesUnderSubscription(review.kind) {
            return Self.deadline(for: review, paysByDirectDebit: review.paysByDirectDebit(assets: assets),
                                 today: CalendarDay(now(), calendar: calendar)) != nil && day >= CalendarDay(now(), calendar: calendar)
        }
        return review.blueprintKey != nil || review.kind.isIdentityDocument || review.kind == .warrantyCertificate || review.kind == .fiscalReceipt
    }

    /// The deadline a review sets: its blueprint and day. A bill's only when the person
    /// wants the reminder, the bank doesn't pay it by itself and the day is still ahead;
    /// the end of a minimum period only while it is ahead (once it passed, there is no
    /// moment left to act on).
    static func deadline(for review: CaptureReview, paysByDirectDebit: Bool, today: CalendarDay) -> (key: String, day: CalendarDay)? {
        guard let key = review.blueprintKey, let day = review.reminderDay else { return nil }
        switch key {
        case SubscriptionFields.billBlueprint:
            guard review.remindsToPay, !paysByDirectDebit, day >= today else { return nil }
        case SubscriptionFields.minimumEndsBlueprint:
            guard day >= today else { return nil }
        default:
            break
        }
        return (key, day)
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
        // From here nothing waits: one step, everything or nothing.
        let outcome = try UnitOfWork.perform(in: context) {
            switch intent {
            case .review(let review): try fileReview(review, document: document)
            case .completion(let completion): try fileCompletion(completion, document: document)
            case .visit(let visit): try fileVisit(visit, document: document)
            }
        }
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

    private func fileReview(_ review: CaptureReview, document: CapturedDocument?) throws -> Outcome {
        let templates = try TemplateStore(context: context).templatesByKey()
        var outcome = Outcome()
        let today = CalendarDay(now(), calendar: calendar)
        let obligations = ObligationActions(context: context, calendar: calendar, now: now)
        let assets = try context.fetch(FetchDescriptor<Asset>())
        var deadline = Self.deadline(for: review, paysByDirectDebit: review.paysByDirectDebit(assets: assets), today: today)

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
            if let documentsKey = Self.holderDocumentTemplateKey(for: review, destinationTemplateKey: asset.templateKey) {
                // A person: the document becomes one of their documents, named after them.
                let name = review.kind.isIdentityDocument ? review.title : DocumentNaming.name(document: review.title, holder: asset.name)
                outcome.asset = try createSection(review, templateKey: documentsKey, name: name, parent: asset, deadline: deadline, templates: templates)
                break
            }
            if Self.filesUnderSubscription(review, destinationTemplateKey: asset.templateKey) {
                // A home: the bill or contract goes to its subscription there, or a new one.
                outcome.asset = try subscription(for: review, under: asset, deadline: deadline, templates: templates)
                break
            }
            if asset.templateKey == BuiltInTemplates.Key.subscription, CaptureMapping.filesUnderSubscription(review.kind),
               let template = templates[asset.templateKey] {
                try updateSubscription(asset, from: review, template: template)
                outcome.asset = asset
                break
            }
            try writeValues(of: review, to: asset, templates: templates)
            outcome.asset = asset
        case .newAsset(let templateKey):
            let name = review.newAssetName.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty else { throw FilingError.missingName }
            if let documentsKey = Self.holderDocumentTemplateKey(for: review, destinationTemplateKey: templateKey) {
                // A new person, named after the holder, with the document filed under them,
                // in one save: a failure leaves neither behind.
                guard let memberTemplate = templates[templateKey] else { throw FilingError.missingSection }
                outcome.asset = try createSection(review, templateKey: documentsKey, name: review.title,
                                                  newParent: AssetActions.NewParent(name: name, template: memberTemplate), deadline: deadline, templates: templates)
            } else if Self.filesUnderSubscription(review, destinationTemplateKey: templateKey) {
                // A new home with the bill's or contract's subscription under it, in one save.
                guard let homeTemplate = templates[templateKey] else { throw FilingError.missingSection }
                outcome.asset = try createSection(review, templateKey: BuiltInTemplates.Key.subscription, name: Self.subscriptionName(review),
                                                  newParent: AssetActions.NewParent(name: name, template: homeTemplate), deadline: deadline, templates: templates)
            } else {
                outcome.asset = try createSection(review, templateKey: templateKey, name: name, parent: nil, deadline: deadline, templates: templates)
            }
        }

        // A bill's own deadline waits for the bank: none when it pays by direct debit.
        if review.kind == .utilityInvoice, let asset = outcome.asset, SubscriptionFields.paysByDirectDebit(asset.values) {
            deadline = nil
        }

        // 2. The deadline.
        if let asset = outcome.asset, let deadline,
           let blueprint = templates[asset.templateKey]?.blueprints.first(where: { $0.key == deadline.key }) {
            let key = deadline.key, day = deadline.day
            if let existing = asset.activeObligations.first(where: { $0.blueprintKey == key }) {
                outcome.obligation = existing
                outcome.completion = try renew(existing, to: day, done: false, on: nil, cost: review.total)
            } else if day >= today {
                outcome.obligation = try obligations.create(from: blueprint, for: asset, firstDue: day)
            }
            if key == SubscriptionFields.billBlueprint, let bill = outcome.obligation, bill.dueDay(in: calendar) == day {
                // This bill's amount and number on its reminder.
                try obligations.setDetails(bill, estimatedCost: review.total, reference: review.value(.invoiceNumber)?.text)
            }
        } else if let asset = outcome.asset, review.kind.isIdentityDocument || review.kind == .warrantyCertificate || review.kind == .fiscalReceipt {
            // Field-driven deadlines (a document's renewal, a warranty's end) follow the values written above.
            outcome.obligation = asset.activeObligations.first
        }
        outcome.nextDue = outcome.obligation?.dueDay(in: calendar)

        // A bill, in its subscription's history: what it came to and when, for the trend
        // and for knowing when the next one is due.
        if review.kind == .utilityInvoice, let asset = outcome.asset, asset.templateKey == BuiltInTemplates.Key.subscription {
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
        let provider = try self.provider(for: review, asset: outcome.asset)

        // 4. The document, linked to all of it: the new pages, or the copy already
        // kept when the same photo was filed before (it moves here, never lost).
        if let document {
            let title = review.title.trimmingCharacters(in: .whitespacesAndNewlines)
            let filed = try AttachmentActions(context: context, calendar: calendar).fileCaptured(
                document,
                title: title.isEmpty ? nil : title,
                kind: CaptureMapping.documentKind(for: review.kind),
                extractedText: review.result.recognizedText.isEmpty ? nil : review.result.recognizedText,
                documentDate: review.documentDay,
                asset: outcome.asset,
                obligation: outcome.obligation,
                historyEntry: outcome.completion ?? outcome.bill,
                provider: provider
            )
            outcome.attachment = filed.attachment
            outcome.movedDocument = filed.moved
        }
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
            return review
        }

        // 1. The values read, onto the section: a new RCA policy brings its number, insurer and claims phone.
        if let review, let asset = obligation.asset {
            try writeValues(of: review, to: asset, templates: try TemplateStore(context: context).templatesByKey())
        }

        // 2. The deadline: the cycle closes, and the new document's date sets the next one.
        let newDay = completion.document.flatMap(Self.nextDay(in:)).flatMap { $0 > today ? $0 : nil }
        outcome.completion = try renew(obligation, to: newDay, done: true, on: completion.date, cost: completion.cost)
        if obligation.status == .active { outcome.nextDue = obligation.dueDay(in: calendar) }

        // 3. Who issued it, and 4. the document.
        if let review, let document {
            let provider = try self.provider(for: review, asset: obligation.asset)
            let filed = try AttachmentActions(context: context, calendar: calendar).fileCaptured(
                document,
                title: CaptureMapping.defaultTitle(for: review.kind, fields: review.valuesByKey),
                kind: CaptureMapping.documentKind(for: review.kind),
                extractedText: review.result.recognizedText.isEmpty ? nil : review.result.recognizedText,
                documentDate: review.documentDay ?? CalendarDay(completion.date, calendar: calendar),
                asset: obligation.asset,
                obligation: obligation,
                historyEntry: outcome.completion,
                provider: provider
            )
            outcome.attachment = filed.attachment
            outcome.movedDocument = filed.moved
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
        )
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
            outcome.attachment = filed.attachment
            outcome.movedDocument = filed.moved
        }
        return outcome
    }

    // MARK: Shared steps

    /// What a captured document's values change on a section that already exists: what
    /// was read replaces what was there, except a value that only differs in how it's written.
    private func writeValues(of review: CaptureReview, to asset: Asset, templates: [String: CategoryTemplate]) throws {
        guard let template = templates[asset.templateKey] else { return }
        var merged = asset.values
        var changed = false
        for (key, value) in Self.values(from: review, for: template.definition) where merged[key] != value {
            // "B 123 ABC" read off a policy doesn't rewrite the "B-123-ABC" the person typed.
            if let old = merged[key]?.textValue, let new = value.textValue,
               CaptureMapping.normalizedIdentifier(old) == CaptureMapping.normalizedIdentifier(new) { continue }
            merged[key] = value
            changed = true
        }
        if changed {
            // A reading on the document (the kilometres on an invoice) is dated by the document.
            try AssetActions(context: context, calendar: calendar, now: now).update(
                asset, name: asset.name, values: merged, notes: asset.notes,
                readingSource: .document, readingDate: review.documentDay?.noonDate(in: calendar), lowerReading: lowerReading
            )
        }
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
            let entry = try actions.complete(obligation, on: date, cost: cost)
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
        guard keys.contains(where: { templates[$0]?.isSensitive == true }), !vault.isSessionUnlocked else { return }
        let result = await vault.unlock(reason: String(localized: "Deschide secțiunea protejată ca să salvez actul."))
        guard result == .success else { throw FilingError.locked }
    }

    /// The template a document becomes when it is filed under a person: an identity
    /// document going to a household member becomes one of their documents. Nil otherwise.
    static func holderDocumentTemplateKey(for kind: CaptureDocumentKind, destinationTemplateKey: String) -> String? {
        guard kind.isIdentityDocument, destinationTemplateKey == BuiltInTemplates.Key.member else { return nil }
        return CaptureMapping.templateKey(for: kind)
    }

    /// The same for a review: a capture started from a household member's documents
    /// (`filesAsPersonalDocument`) becomes one of their documents whatever its kind.
    static func holderDocumentTemplateKey(for review: CaptureReview, destinationTemplateKey: String) -> String? {
        if let key = holderDocumentTemplateKey(for: review.kind, destinationTemplateKey: destinationTemplateKey) { return key }
        guard review.filesAsPersonalDocument, destinationTemplateKey == BuiltInTemplates.Key.member else { return nil }
        return BuiltInTemplates.Key.documents
    }

    /// The template the document's values land in, for the review's reminder preview.
    static func filedTemplateKey(for review: CaptureReview, destinationTemplateKey: String) -> String {
        if filesUnderSubscription(review, destinationTemplateKey: destinationTemplateKey) { return BuiltInTemplates.Key.subscription }
        return holderDocumentTemplateKey(for: review, destinationTemplateKey: destinationTemplateKey) ?? destinationTemplateKey
    }

    // MARK: Subscriptions

    /// A bill or a contract filed under a home goes to the home's subscription for it.
    static func filesUnderSubscription(_ review: CaptureReview, destinationTemplateKey: String) -> Bool {
        CaptureMapping.filesUnderSubscription(review.kind) && destinationTemplateKey == BuiltInTemplates.Key.home
    }

    /// What a new subscription made from the review is called.
    static func subscriptionName(_ review: CaptureReview) -> String {
        let name = review.newAssetName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !name.isEmpty, case .newAsset(let key) = review.destination, key == BuiltInTemplates.Key.subscription { return name }
        return SubscriptionNaming.name(provider: review.value(.provider)?.text, service: review.value(.serviceKind)?.text)
    }

    /// The day a bill is logged on: the day it was issued, else today.
    static func billDay(_ review: CaptureReview, today: CalendarDay) -> CalendarDay {
        review.value(.issueDate)?.day.map(CaptureMapping.calendarDay) ?? today
    }

    /// The home's subscription the bill or contract belongs to, updated with what was
    /// read, or a new one under the home.
    private func subscription(for review: CaptureReview, under home: Asset, deadline: (key: String, day: CalendarDay)?,
                              templates: [String: CategoryTemplate]) throws -> Asset {
        guard let template = templates[BuiltInTemplates.Key.subscription] else { throw FilingError.missingSection }
        let children = (home.children ?? []).filter { $0.templateKey == BuiltInTemplates.Key.subscription }
        let decision = SubscriptionMatcher.match(
            review.subscriptionReading,
            subscriptions: children.map { SubscriptionMatcher.Subscription(id: $0.id, parentID: home.id, values: $0.values) },
            homes: [], within: home.id
        )
        if case .existing(let id) = decision, let existing = children.first(where: { $0.id == id }) {
            try updateSubscription(existing, from: review, template: template)
            return existing
        }
        return try createSection(review, templateKey: BuiltInTemplates.Key.subscription, name: Self.subscriptionName(review),
                                 parent: home, deadline: deadline, templates: templates)
    }

    /// What a bill or a contract adds to a subscription that already exists. A bill fills
    /// what is still empty and, when it is the newest, sets the last bill; it never
    /// rewrites what the person keeps there. A contract (or an addendum) also brings its
    /// terms: the number, the start, the minimum period and the price.
    private func updateSubscription(_ subscription: Asset, from review: CaptureReview, template: CategoryTemplate) throws {
        let read = Self.values(from: review, for: template.definition)
        let terms: Set<String> = review.kind == .contract
            ? [SubscriptionFields.contractNumber, SubscriptionFields.startDate, SubscriptionFields.minimumMonths,
               SubscriptionFields.minimumUntil, SubscriptionFields.price]
            : []
        var merged = subscription.values
        for (key, value) in read where key != SubscriptionFields.lastBill {
            if merged[key] == nil || (terms.contains(key) && merged[key] != value) { merged[key] = value }
        }
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

    /// A new section with the values read and the deadlines its template plans.
    private func createSection(_ review: CaptureReview, templateKey: String, name: String, parent: Asset? = nil,
                               newParent: AssetActions.NewParent? = nil, deadline: (key: String, day: CalendarDay)?,
                               templates: [String: CategoryTemplate]) throws -> Asset {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let template = templates[templateKey] else { throw FilingError.missingSection }
        let actions = AssetActions(context: context, calendar: calendar, now: now)
        let values = Self.values(from: review, for: template.definition)
        let planned = actions.plannedObligations(for: template, values: values).map { planned -> PlannedObligation in
            var planned = planned
            if planned.blueprint.key == review.blueprintKey {
                // The document's own deadline: its day, or none when it isn't wanted or has passed.
                planned.firstDue = deadline?.day
                planned.isSelected = deadline != nil
            }
            // Dates the person still has to give (the current ITP) are left for the section page.
            planned.isSelected = planned.isSelected && planned.firstDue != nil
            return planned
        }
        return try actions.create(name: name.isEmpty ? CaptureMapping.kindTitle(review.kind) : name, template: template, values: values, obligations: planned, parent: parent, newParent: newParent)
    }

    private func provider(for review: CaptureReview, asset: Asset?) throws -> Provider? {
        guard let trade = CaptureMapping.providerTrade(for: review.kind), let name = review.value(.provider)?.text else { return nil }
        return try ProviderActions(context: context, now: now).findOrCreate(
            name: name, taxID: review.value(.providerTaxID)?.text, trade: trade, phone: review.value(.providerPhone)?.text, linkedTo: asset
        )
    }
}

/// The reminder a review will set, in plain words: "Expiră pe 12 august 2031. Te anunț cu 6 luni și cu 2 luni înainte."
enum CaptureReminderPreview {
    @MainActor
    static func text(for review: CaptureReview, templates: [String: CategoryTemplate], assets: [Asset], calendar: Calendar = .current, today: CalendarDay) -> String? {
        guard let day = review.reminderDay else { return nil }
        if review.kind == .utilityInvoice && !review.remindsToPay { return nil }
        let date = DueWording.date(day, today: today)
        if review.kind == .utilityInvoice, review.paysByDirectDebit(assets: assets) {
            return String(localized: "De plătit până pe \(date). Se plătește prin debit direct, așa că nu îți amintesc.")
        }
        if review.kind == .contract, day < today {
            // The minimum period is over: nothing to remind about, but worth knowing.
            return String(localized: "Perioada minimă s-a terminat pe \(date). De regulă, poți renunța oricând, anunțând cu cel mult o lună înainte.")
        }
        let leadDays: [Int]
        if review.kind == .utilityInvoice {
            leadDays = ObligationKind.payment.defaultProfile.leadDays
        } else if let blueprint = blueprint(for: review, templates: templates, assets: assets) {
            let values = templateValues(for: review, templates: templates, assets: assets)
            leadDays = blueprint.reminders(for: values).leadDays
        } else {
            leadDays = review.result.reminder?.leadDays ?? []
        }
        let opening: String
        switch CaptureMapping.reminderField(for: review.kind) {
        case .dueDate?: opening = String(localized: "De plătit până pe \(date).")
        case .minimumPeriodEnd?: opening = String(localized: "Perioada minimă se termină pe \(date). De atunci poți, de regulă, renunța fără penalități.")
        case .nextDoseDate?: opening = String(localized: "Următoarea doză e pe \(date).")
        case .warrantyUntil?: opening = String(localized: "Garanția se termină pe \(date).")
        default: opening = String(localized: "Expiră pe \(date).")
        }
        guard review.destination != .none else {
            if review.kind == .utilityInvoice {
                return opening + " " + String(localized: "Alege abonamentul ei ca să îți amintesc s-o plătești.")
            }
            return opening + " " + String(localized: "Alege unde îl pui ca să te anunț din timp.")
        }
        return opening + " " + ReminderWording.sentence(leadDays: leadDays)
    }

    @MainActor
    private static func templateKey(for review: CaptureReview, assets: [Asset]) -> String? {
        switch review.destination {
        case .none: return nil
        case .asset(let id): return assets.first { $0.id == id }.map { CaptureFiler.filedTemplateKey(for: review, destinationTemplateKey: $0.templateKey) }
        case .newAsset(let key): return CaptureFiler.filedTemplateKey(for: review, destinationTemplateKey: key)
        }
    }

    @MainActor
    private static func blueprint(for review: CaptureReview, templates: [String: CategoryTemplate], assets: [Asset]) -> ObligationBlueprint? {
        guard let templateKey = templateKey(for: review, assets: assets), let template = templates[templateKey] else { return nil }
        if let key = review.blueprintKey, let blueprint = template.blueprints.first(where: { $0.key == key }) { return blueprint }
        // Field-driven deadlines: the blueprint whose first date comes from the field the reminder follows.
        let values = CaptureFiler.values(from: review, for: template.definition)
        return template.blueprints.first { blueprint in
            if case .field(let key, _) = blueprint.firstDue, values[key] != nil { return true }
            return false
        }
    }

    @MainActor
    private static func templateValues(for review: CaptureReview, templates: [String: CategoryTemplate], assets: [Asset]) -> FieldValues {
        guard let key = templateKey(for: review, assets: assets), let template = templates[key] else { return FieldValues() }
        return CaptureFiler.values(from: review, for: template.definition)
    }
}
