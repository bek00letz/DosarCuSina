import Foundation
import SwiftData

/// The one save path for a reviewed capture. It only orchestrates the engine:
/// - the section: `AssetActions.create` or `AssetActions.update` with the values read;
/// - the deadline: `ObligationActions` (complete the old cycle and move to the new
///   date, or create it from the template's blueprint);
/// - who issued it: `ProviderActions`;
/// - a bill or a contract: its ongoing contract, a subscription found by
///   `SubscriptionMatcher` or made under its home; a bill is logged in its history
///   (`HistoryActions`) with its own due date to pay by;
/// - the document itself: `AttachmentActions.fileCaptured`, linked to all of the above.
/// Side effects (reminders, widgets) follow every save through `SideEffectsCoordinator`.
@MainActor
struct CaptureFiler {
    let context: ModelContext
    var store: CaptureDocumentStore = .shared()
    var calendar: Calendar = .current
    var now: () -> Date = { Date() }

    struct Outcome {
        var asset: Asset?
        var obligation: Obligation?
        var attachment: Attachment?
        /// A completion written for the cycle the document closed.
        var completion: HistoryEntry?
        /// A bill, logged in its subscription's history.
        var bill: HistoryEntry?
    }

    enum FilingError: LocalizedError, Equatable {
        case missingSection
        case missingName

        var errorDescription: String? {
            switch self {
            case .missingSection: return String(localized: "Secțiunea aleasă nu mai există. Alege alta.")
            case .missingName: return String(localized: "Scrie un nume pentru secțiunea nouă.")
            }
        }
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

    /// One "Salvează" is one unit of work: the section, the deadline, who issued it
    /// and the document are all kept, or none of them is (see `UnitOfWork`).
    func save(_ review: CaptureReview) async throws -> Outcome {
        try await UnitOfWork.perform(in: context) { try await fileAll(review) }
    }

    private func fileAll(_ review: CaptureReview) async throws -> Outcome {
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
            if let template = templates[asset.templateKey] {
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
                    try AssetActions(context: context, calendar: calendar, now: now).update(asset, name: asset.name, values: merged, notes: asset.notes)
                }
            }
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
                let due = existing.dueDay(in: calendar)
                if due < day {
                    if blueprint.recurrence.repeats {
                        // A new policy or inspection closes the cycle that was due and sets the next date.
                        outcome.completion = try obligations.complete(existing, cost: review.total)
                        if existing.status == .active, existing.dueDay(in: calendar) != day {
                            try obligations.reschedule(existing, to: day)
                        }
                    } else if due != day {
                        try obligations.reschedule(existing, to: day)
                    }
                }
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
        let provider = try provider(for: review, asset: outcome.asset)

        // 4. The document, linked to all of it: the new pages, or the copy already
        // kept when the same photo was filed before (it moves here, never lost).
        if let documentID = review.documentID ?? review.duplicateAttachmentID {
            let title = review.title.trimmingCharacters(in: .whitespacesAndNewlines)
            outcome.attachment = try await AttachmentActions(context: context, calendar: calendar).fileCaptured(
                documentID: documentID,
                from: store,
                title: title.isEmpty ? nil : title,
                kind: CaptureMapping.documentKind(for: review.kind),
                extractedText: review.result.recognizedText.isEmpty ? nil : review.result.recognizedText,
                documentDate: review.documentDay,
                asset: outcome.asset,
                obligation: outcome.obligation,
                historyEntry: outcome.completion ?? outcome.bill,
                provider: provider
            )
        }
        return outcome
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

    /// Drops the pages of a capture the person didn't keep.
    func discard(_ review: CaptureReview) async {
        if let id = review.documentID { await store.discard(id: id) }
    }

    private func provider(for review: CaptureReview, asset: Asset?) throws -> Provider? {
        guard let trade = CaptureMapping.providerTrade(for: review.kind),
              let name = review.value(.provider)?.text?.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty else { return nil }
        let actions = ProviderActions(context: context, now: now)
        let wanted = SearchText.normalize(name)
        if let existing = try context.fetch(FetchDescriptor<Provider>()).first(where: { SearchText.normalize($0.name) == wanted }) {
            if let asset { try actions.link(existing, to: asset) }
            return existing
        }
        return try actions.create(name: name, trades: [trade], phone: review.value(.providerPhone)?.text, linkedTo: asset.map { [$0] } ?? [])
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
