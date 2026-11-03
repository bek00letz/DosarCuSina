import Foundation
import SwiftData

/// A personal document typed in by hand under a household member: its type,
/// the variant when the type has real ones, and the expiry. The name comes by
/// itself ("Cazier judiciar – Manole Corina") unless the person changes it.
struct PersonalDocumentDraft: Equatable {
    var type: String?
    var variant: String?
    /// Nil keeps the automatic name.
    var customName: String?
    var expiry: CalendarDay?

    /// The type's variants, empty for types that have none.
    var variantOptions: [ChoiceOption] {
        type.map(DocumentType.variants(of:)) ?? []
    }

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

    /// The template values: type, variant and expiry.
    var values: FieldValues {
        var values = FieldValues()
        values[DocumentType.typeFieldKey] = type.map(FieldValue.text)
        values[DocumentType.variantFieldKey] = variant.map(FieldValue.text)
        values["document.expiry"] = expiry.map(FieldValue.date)
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

    /// "Expiră pe … Te anunț cu 3 luni și cu o lună înainte.", from the type's reminder profile.
    static func reminderLine(_ draft: PersonalDocumentDraft, template: CategoryTemplate, actions: AssetActions, today: CalendarDay) -> String? {
        guard let expiry = draft.expiry,
              let plan = planned(draft, template: template, actions: actions).first(where: { $0.isSelected }) else { return nil }
        return ReminderWording.expiryLine(expiry, leadDays: plan.blueprint.reminders(for: draft.values).leadDays, today: today)
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
                     calendar: Calendar = .current, now: @escaping () -> Date = { Date() }) throws -> Asset {
        guard draft.type != nil else { throw PersonalDocumentError.missingType }
        guard let template = try TemplateStore(context: context).template(withRole: .personalDocument) else {
            throw PersonalDocumentError.missingTemplate
        }
        let actions = AssetActions(context: context, calendar: calendar, now: now)
        return try UnitOfWork.perform(in: context) {
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
