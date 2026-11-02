import Foundation
import SwiftData

/// The one save path for a reviewed capture. It only orchestrates the engine:
/// - the section: `AssetActions.create` or `AssetActions.update` with the values read;
/// - the deadline: `ObligationActions` (complete the old cycle and move to the new
///   date, or create it from the template's blueprint);
/// - who issued it: `ProviderActions`;
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
                  let key = CaptureMapping.fieldKey(for: field.key, kind: review.kind, in: template),
                  let definition = template.field(key),
                  let converted = CaptureMapping.fieldValue(value, for: definition) else { continue }
            if values[key] == nil { values[key] = converted }
        }
        if let type = CaptureMapping.documentType(for: review.kind), template.field("document.type") != nil {
            values["document.type"] = .text(type)
        }
        return values
    }

    /// Whether saving would create or move a deadline, so the reminder permission is worth asking first.
    func touchesReminders(_ review: CaptureReview) -> Bool {
        if review.kind == .utilityInvoice, review.remindsToPay, review.reminderDay != nil { return true }
        guard review.reminderDay != nil, review.destination != .none else { return false }
        return review.blueprintKey != nil || review.kind.isIdentityDocument || review.kind == .warrantyCertificate || review.kind == .fiscalReceipt
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

        // 1. The section.
        switch review.destination {
        case .none:
            break
        case .asset(let id):
            var descriptor = FetchDescriptor<Asset>(predicate: #Predicate { $0.id == id })
            descriptor.fetchLimit = 1
            guard let asset = try context.fetch(descriptor).first else { throw FilingError.missingSection }
            if let documentsKey = Self.holderDocumentTemplateKey(for: review.kind, destinationTemplateKey: asset.templateKey) {
                // A person: the document becomes one of their documents.
                outcome.asset = try createSection(review, templateKey: documentsKey, name: review.title, parent: asset, templates: templates)
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
            if let documentsKey = Self.holderDocumentTemplateKey(for: review.kind, destinationTemplateKey: templateKey) {
                // A new person, named after the holder, with the document filed under them,
                // in one save: a failure leaves neither behind.
                guard let memberTemplate = templates[templateKey] else { throw FilingError.missingSection }
                outcome.asset = try createSection(review, templateKey: documentsKey, name: review.title,
                                                  newParent: AssetActions.NewParent(name: name, template: memberTemplate), templates: templates)
            } else {
                outcome.asset = try createSection(review, templateKey: templateKey, name: name, parent: nil, templates: templates)
            }
        }

        // 2. The deadline.
        if let asset = outcome.asset, let key = review.blueprintKey, let day = review.reminderDay,
           let blueprint = templates[asset.templateKey]?.blueprints.first(where: { $0.key == key }) {
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
        } else if let asset = outcome.asset, review.kind.isIdentityDocument || review.kind == .warrantyCertificate || review.kind == .fiscalReceipt {
            // Field-driven deadlines (a document's renewal, a warranty's end) follow the values written above.
            outcome.obligation = asset.activeObligations.first
        }

        // A bill to pay by a date.
        if review.kind == .utilityInvoice, review.remindsToPay, let day = review.reminderDay, day >= today {
            let provider = review.value(.provider)?.text
            outcome.obligation = try obligations.create(
                title: provider.map { String(localized: "Factură \($0)") } ?? String(localized: "Factură de plătit"),
                kind: .payment,
                dueDay: day,
                for: outcome.asset,
                estimatedCost: review.total,
                reference: review.value(.invoiceNumber)?.text
            )
        }

        // 3. Who issued it.
        let provider = try provider(for: review, asset: outcome.asset)

        // 4. The document, linked to all of it.
        if let documentID = review.documentID {
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
                historyEntry: outcome.completion,
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

    /// The template the document's values land in, for the review's reminder preview.
    static func filedTemplateKey(for review: CaptureReview, destinationTemplateKey: String) -> String {
        holderDocumentTemplateKey(for: review.kind, destinationTemplateKey: destinationTemplateKey) ?? destinationTemplateKey
    }

    /// A new section with the values read and the deadlines its template plans.
    private func createSection(_ review: CaptureReview, templateKey: String, name: String, parent: Asset? = nil,
                               newParent: AssetActions.NewParent? = nil, templates: [String: CategoryTemplate]) throws -> Asset {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let template = templates[templateKey] else { throw FilingError.missingSection }
        let actions = AssetActions(context: context, calendar: calendar, now: now)
        let values = Self.values(from: review, for: template.definition)
        let planned = actions.plannedObligations(for: template, values: values).map { planned -> PlannedObligation in
            var planned = planned
            if planned.blueprint.key == review.blueprintKey, let day = review.reminderDay {
                planned.firstDue = day
                planned.isSelected = true
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
        let leadDays: [Int]
        if review.kind == .utilityInvoice {
            leadDays = ObligationKind.payment.defaultProfile.leadDays
        } else if let blueprint = blueprint(for: review, templates: templates, assets: assets) {
            let values = templateValues(for: review, templates: templates, assets: assets)
            leadDays = blueprint.reminders(for: values).leadDays
        } else {
            leadDays = review.result.reminder?.leadDays ?? []
        }
        let date = DueWording.date(day, today: today, calendar: calendar)
        let opening: String
        switch CaptureMapping.reminderField(for: review.kind) {
        case .dueDate?: opening = String(localized: "De plătit până pe \(date).")
        case .nextDoseDate?: opening = String(localized: "Următoarea doză e pe \(date).")
        case .warrantyUntil?: opening = String(localized: "Garanția se termină pe \(date).")
        default: opening = String(localized: "Expiră pe \(date).")
        }
        guard review.destination != .none || review.kind == .utilityInvoice else {
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
