import Foundation
import SwiftData
import Observation

/// The add-a-section flow's state: which category, its essential fields, and the
/// obligations to start with. Creating goes through `AssetActions` in one save.
@MainActor
@Observable
final class AddSectionModel {
    let request: AddSectionRequest
    var template: CategoryTemplate?
    var custom: CustomSectionDraft?
    var name = ""
    var values = FieldValues()
    var planned: [PlannedObligation] = []
    var parentID: UUID?

    init(request: AddSectionRequest) {
        self.request = request
        self.parentID = request.parentID
    }

    var definition: TemplateDefinition? {
        if let template { return template.definition }
        guard let custom else { return nil }
        return custom.definition(key: CustomSectionDraft.draftKey)
    }

    /// What the flow asks and says for the chosen category (`AddSectionForm`).
    var form: AddSectionForm? { definition.map(AddSectionForm.init) }

    /// The fields asked for when adding: only those marked essential.
    var essentialFields: [FieldDefinition] {
        form?.essentialFields ?? []
    }

    var hasChanges: Bool {
        template != nil || custom != nil || !name.isEmpty || !values.isEmpty
    }

    /// The name used when the person leaves it empty.
    var effectiveName: String {
        let typed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if !typed.isEmpty { return typed }
        guard let definition else { return "" }
        return Self.suggestedName(values: values, definition: definition)
    }

    func choose(_ template: CategoryTemplate) {
        self.template = template
        custom = nil
        values = FieldValues()
        name = ""
        // Where it goes when the request didn't say: a plant into the only home
        // (`AssetActions.automaticParent`); the essentials step shows it and can change it.
        parentID = request.parentID ?? template.modelContext.flatMap { AssetActions.automaticParent(for: template.behavior, in: $0)?.id }
    }

    /// The sections the new one can be filed under when the request didn't say (the homes, for a
    /// plant, the cars for a category of one's own that belongs to a car); empty when it isn't
    /// something filed under another.
    func possibleParents(in context: ModelContext) -> [Asset] {
        guard request.parentID == nil, let behavior = definition?.behavior else { return [] }
        return AssetActions.possibleParents(for: behavior, in: context)
    }

    /// The part the new section may belong to (a home, a car, a person), for the words of the choice.
    var belongsTo: CategoryBehavior.Role? { form?.belongsTo }

    /// A category of one's own, described: like a ready-made one, a section of one that belongs to
    /// a car goes under the household's only car by itself (`AssetActions.automaticParent`).
    func chooseCustom(_ draft: CustomSectionDraft, in context: ModelContext? = nil) {
        template = nil
        custom = draft
        values = FieldValues()
        name = draft.name
        let behavior = draft.definition(key: CustomSectionDraft.draftKey).behavior
        parentID = request.parentID ?? context.flatMap { AssetActions.automaticParent(for: behavior, in: $0)?.id }
    }

    /// Works out the suggested obligations from what was typed so far.
    func planObligations(context: ModelContext) {
        guard let definition else { planned = []; return }
        let previous = Dictionary(planned.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        planned = AssetActions(context: context).plannedObligations(for: definition, values: values).map { plan in
            guard let old = previous[plan.id] else { return plan }
            var merged = plan
            // The person's choice stays; one left unticked only because its date had to be
            // asked is ticked once what they typed now works the date out.
            merged.isSelected = old.isSelected || (plan.isSelected && old.asksFirstDate)
            if plan.firstDue == nil { merged.firstDue = old.firstDue }
            return merged
        }
    }

    /// Whether the essentials step leads to deadlines to choose from: some deadline of the
    /// category applies to what was typed so far. Without one, its button adds the section.
    func offersDeadlines(context: ModelContext) -> Bool {
        guard let definition else { return false }
        return !AssetActions(context: context).plannedObligations(for: definition, values: values).isEmpty
    }

    /// Said under the deadlines on offer when some ask for their first date: those can be
    /// added later, or from a photo of the paper (`AddSectionForm.laterNote(for:)`).
    var laterNote: String? {
        form?.laterNote(for: planned)
    }

    /// Selected obligations that still need a date from the person.
    var missingDates: [PlannedObligation] {
        planned.filter { $0.isSelected && $0.firstDue == nil }
    }

    /// Creates the section (and its category, for "Altceva…") with the chosen obligations,
    /// in one step: a failure leaves no empty category behind.
    func create(context: ModelContext) throws -> Asset {
        // Whether it may go into an example is asked before a category of one's own is
        // written (`StepQuestion`).
        try ExampleOwnership.requireReal(try parentSection(in: context))
        return try UnitOfWork.perform(in: context) { try createSection(context: context) }
    }

    /// The section the new one is filed under, if any.
    private func parentSection(in context: ModelContext) throws -> Asset? {
        try parentID.flatMap { id in
            var descriptor = FetchDescriptor<Asset>(predicate: #Predicate { $0.id == id })
            descriptor.fetchLimit = 1
            return try context.fetch(descriptor).first
        }
    }

    private func createSection(context: ModelContext) throws -> Asset {
        let store = TemplateStore(context: context)
        let category: CategoryTemplate
        if let template {
            category = template
        } else if let custom {
            let name = custom.name.trimmingCharacters(in: .whitespacesAndNewlines)
            if CustomSectionStep.offersPocketList {
                category = try store.createCustom(name: name, symbol: custom.symbol, pockets: SectionPocket.ordered(custom.pockets), tint: CustomSectionDraft.tint)
            } else {
                category = try store.createCustom(name: name, symbol: custom.symbol, switches: custom.switches, tint: CustomSectionDraft.tint)
            }
        } else {
            throw AddSectionError.noCategory
        }
        let parent = try parentSection(in: context)
        let asset = try AssetActions(context: context).create(
            name: effectiveName.isEmpty ? category.definition.sectionSingular.name : effectiveName,
            template: category,
            values: values,
            obligations: planned,
            parent: parent
        )
        // A section that shows in a box (its own, or its category's shared one, as a plant in a
        // home) brings its category back to the binder when it was hidden.
        if !category.isOnHome, category.hasBox(forSectionUnder: parent) {
            try store.setOnHome(category, true)
        }
        return asset
    }

    /// A name from what was typed: "Volkswagen Golf", "Pașaport", else what one section of the
    /// category is called („Mașina”, never the category's „Mașini”: `sectionSingular`).
    static func suggestedName(values: FieldValues, definition: TemplateDefinition) -> String {
        let words = definition.fields(withRole: .subtitle).compactMap { field -> String? in
            guard let value = values[field.key] else { return nil }
            if case .number = value { return nil }
            return FieldFormatter.display(value, field: field)
        }
        if !words.isEmpty { return words.prefix(2).joined(separator: " ") }
        if let identifier = AssetFacts.text(.identifier, in: values, template: definition) { return identifier }
        return definition.sectionSingular.name
    }
}

enum AddSectionError: LocalizedError {
    case noCategory

    var errorDescription: String? {
        AddSectionWording.noCategory
    }
}
