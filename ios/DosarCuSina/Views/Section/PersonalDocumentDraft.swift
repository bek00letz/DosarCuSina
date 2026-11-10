import Foundation
import SwiftData

/// A personal document typed in by hand under a household member: its type,
/// the variant when the type has real ones, and the date printed on it: the expiry,
/// or for a type dated by its issue (a cazier) the day it was issued. The name comes by
/// itself ("Cazier judiciar – Manole Corina") unless the person changes it.
struct PersonalDocumentDraft: Equatable {
    var type: String?
    var variant: String?
    /// Nil keeps the automatic name.
    var customName: String?
    var expiry: CalendarDay?
    /// The day it was issued, asked instead of the expiry for a type dated by its issue.
    var issued: CalendarDay?

    /// The type's variants, empty for types that have none.
    var variantOptions: [ChoiceOption] {
        type.map(DocumentType.variants(of:)) ?? []
    }

    /// The type prints the day it was issued, not an expiry (`DocumentType.isDatedByIssue`):
    /// the form asks "Eliberat pe", and the expiry follows only where a rule gives one.
    var isDatedByIssue: Bool { DocumentType.isDatedByIssue(type) }

    /// How long it is valid after its issue, when its type and variant have a rule (six
    /// months for a cazier judiciar).
    var validityMonths: Int? { DocumentType.validityMonths(type: type, variant: variant) }

    var isEmpty: Bool { self == PersonalDocumentDraft() }

    /// Picks a type; a variant of another type no longer fits.
    mutating func choose(type newType: String) {
        guard newType != type else { return }
        type = newType
        if let variant, !DocumentType.variants(of: newType).contains(where: { $0.key == variant }) { self.variant = nil }
    }

    /// "Cazier judiciar – Manole Corina", once a type is chosen.
    func automaticName(holder: String) -> String? {
        type.map { DocumentNaming.name(document: DocumentType.documentName(type: $0, variant: variant), holder: holder) }
    }

    /// The name it is saved with: the person's own, else the automatic one.
    func name(holder: String) -> String {
        if let custom = customName?.trimmingCharacters(in: .whitespacesAndNewlines), !custom.isEmpty { return custom }
        return automaticName(holder: holder) ?? String(localized: "Document")
    }

    /// The template values: type, variant and the date the form asked for. For a type dated
    /// by its issue that is the issue date, and the documents category works out the
    /// expiry from it by the type's rule (`FieldDerivation.validityAfterIssue`).
    var values: FieldValues {
        var values = FieldValues()
        values[DocumentType.typeFieldKey] = type.map(FieldValue.text)
        values[DocumentType.variantFieldKey] = variant.map(FieldValue.text)
        if isDatedByIssue {
            values[DocumentFields.issueDate] = issued.map(FieldValue.date)
        } else {
            values[DocumentFields.expiry] = expiry.map(FieldValue.date)
        }
        return values
    }
}

enum PersonalDocumentError: LocalizedError, Equatable {
    case missingType
    case missingTemplate

    var errorDescription: String? {
        switch self {
        case .missingType: String(localized: "Alege ce act e.", comment: "Error when saving a personal document without a type.")
        case .missingTemplate: String(localized: "Categoria Acte lipsește. Închide aplicația și deschide-o din nou.", comment: "Error when the documents category is missing.")
        }
    }
}

/// Saving a typed-in personal document and finding the one capture just filed,
/// through the engine's actions.
@MainActor
enum PersonalDocumentFiling {
    /// The deadlines the document would start with: the template's own, with
    /// first dates from the expiry. Ones without a date are left for later.
    static func planned(_ draft: PersonalDocumentDraft, template: CategoryTemplate, actions: AssetActions) -> [PlannedObligation] {
        actions.plannedObligations(for: template, values: draft.values).map { plan in
            var plan = plan
            plan.isSelected = plan.isSelected && plan.firstDue != nil
            return plan
        }
    }

    /// The last day the document is valid: the expiry typed, or for a type dated by its
    /// issue, the one the documents category works out from the issue date (the same
    /// derivation saving runs). Nil when there is none.
    static func expiry(_ draft: PersonalDocumentDraft, template: CategoryTemplate, calendar: Calendar = .dosar) -> CalendarDay? {
        draft.values.applyingRules(of: template.definition, previous: nil, calendar: calendar)[DocumentFields.expiry]?.dateValue
    }

    /// "Expiră pe … Te anunț cu 3 luni și cu o lună înainte.", from the type's reminder
    /// profile; for a cazier judiciar "E valabil până pe …, la 6 luni de la eliberare. …".
    static func reminderLine(_ draft: PersonalDocumentDraft, template: CategoryTemplate, actions: AssetActions, today: CalendarDay,
                             calendar: Calendar = .dosar) -> String? {
        guard let expiry = expiry(draft, template: template, calendar: calendar),
              let plan = planned(draft, template: template, actions: actions).first(where: { $0.isSelected }) else { return nil }
        return ReminderWording.expiryLine(expiry, profile: plan.blueprint.reminders(for: draft.values), today: today,
                                          validityMonths: draft.isDatedByIssue ? draft.validityMonths : nil, calendar: calendar)
    }

    /// How urgent the expiry is, by the deadline it would start: what the badge on the
    /// expiry field shows, and what the document's page will show once it is saved.
    static func urgencyRule(_ draft: PersonalDocumentDraft, template: CategoryTemplate, actions: AssetActions) -> UrgencyRule {
        planned(draft, template: template, actions: actions).first(where: { $0.isSelected })?
            .blueprint.reminders(for: draft.values).urgencyRule ?? .noReminders
    }

    /// Creates the document under `holder` with its deadline, as one step.
    @discardableResult
    static func save(_ draft: PersonalDocumentDraft, holder: Asset, context: ModelContext,
                     calendar: Calendar = .dosar, now: @escaping () -> Date = { Date() }) throws -> Asset {
        guard draft.type != nil else { throw PersonalDocumentError.missingType }
        guard let template = try TemplateStore(context: context).template(withRole: .personalDocument) else {
            throw PersonalDocumentError.missingTemplate
        }
        let actions = AssetActions(context: context, calendar: calendar, now: now)
        return try UnitOfWork.perform(in: context, now: now()) {
            try actions.create(
                name: draft.name(holder: holder.name),
                template: template,
                values: draft.values,
                obligations: planned(draft, template: template, actions: actions),
                parent: holder,
                isExample: holder.isExample
            )
        }
    }
}
