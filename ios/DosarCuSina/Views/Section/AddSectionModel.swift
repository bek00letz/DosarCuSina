import Foundation
import SwiftData
import Observation

/// A category of its own, described in the "Altceva…" step and created only
/// when the person finishes, so cancelling never leaves an empty category behind.
struct CustomSectionDraft: Equatable {
    var name = ""
    var symbol = CustomSectionDraft.symbols[0]
    /// What it keeps, as a few plain questions (`CategorySwitches`).
    var switches = CategorySwitches.defaults
    /// The first version's free choice of pockets. Kept, not shown, as a way back until
    /// the switches are proven (`CustomSectionStep.offersPocketList`).
    var pockets: Set<SectionPocket> = Set(SectionPocket.standard)

    /// Whether it can be saved: it has a name, and a service says how often.
    var isComplete: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && (switches.service?.every ?? 1) > 0
    }

    /// The colour every category of one's own gets.
    static let tint: TemplateTint = .gray

    /// The category it describes, as it would be saved.
    func definition(key: String) -> TemplateDefinition {
        if CustomSectionStep.offersPocketList {
            return TemplateDefinition(key: key, name: name, symbol: symbol, tint: Self.tint, sections: [], pockets: Array(pockets))
        }
        return switches.definition(key: key, name: name, symbol: symbol, tint: Self.tint)
    }

    /// Symbols offered for a section of one's own.
    static let symbols = [
        "square.grid.2x2.fill", "bicycle", "sailboat.fill", "tent.fill", "camera.fill", "guitars.fill",
        "laptopcomputer", "tv.fill", "washer.fill", "refrigerator.fill", "leaf.fill", "tree.fill",
        "building.2.fill", "briefcase.fill", "graduationcap.fill", "cross.case.fill", "figure.child", "dumbbell.fill",
        "gamecontroller.fill", "key.fill", "wrench.and.screwdriver.fill", "shippingbox.fill", "gift.fill", "star.fill",
    ]

    /// Pockets a section of one's own can have, each with a one-line explanation.
    static let offeredPockets: [SectionPocket] = [.upcoming, .documents, .history, .people, .money, .keyFacts, .products, .subscriptions]

    static func explanation(for pocket: SectionPocket) -> String {
        switch pocket {
        case .upcoming: String(localized: "Termene, cu amintiri din timp.", comment: "Pocket explanation.")
        case .tenants: String(localized: "Contractele chiriașilor și chiria.", comment: "Pocket explanation.")
        case .products: String(localized: "Lucruri cumpărate, cu garanția lor.", comment: "Pocket explanation.")
        case .subscriptions: String(localized: "Ce plătești lunar sau anual.", comment: "Pocket explanation.")
        case .documents: String(localized: "Poze și PDF-uri cu actele și facturile.", comment: "Pocket explanation.")
        case .history: String(localized: "Ce s-a făcut, când și cât a costat.", comment: "Pocket explanation.")
        case .people: String(localized: "Cine are grijă de el, cu telefonul lui.", comment: "Pocket explanation.")
        case .money: String(localized: "Cât ai cheltuit pe el.", comment: "Pocket explanation.")
        case .keyFacts: String(localized: "Coduri, numere și tot ce cauți des.", comment: "Pocket explanation.")
        }
    }
}

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
        return custom.definition(key: "draft")
    }

    /// The fields asked for when adding: only those marked essential.
    var essentialFields: [FieldDefinition] {
        definition?.allFields.filter(\.isEssential) ?? []
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
    }

    func chooseCustom(_ draft: CustomSectionDraft) {
        template = nil
        custom = draft
        values = FieldValues()
        name = draft.name
    }

    /// Works out the suggested obligations from what was typed so far.
    func planObligations(context: ModelContext) {
        guard let definition else { planned = []; return }
        let previous = Dictionary(planned.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        planned = AssetActions(context: context).plannedObligations(for: definition, values: values).map { plan in
            guard let old = previous[plan.id] else { return plan }
            var merged = plan
            merged.isSelected = old.isSelected
            if plan.firstDue == nil { merged.firstDue = old.firstDue }
            return merged
        }
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
            name: effectiveName.isEmpty ? category.name : effectiveName,
            template: category,
            values: values,
            obligations: planned,
            parent: parent
        )
        // A top-level section of a category hidden from home brings the category back.
        if parent == nil, !category.isOnHome, category.behavior.hasSectionBoxes {
            try store.setOnHome(category, true)
        }
        return asset
    }

    /// A name from what was typed: "Volkswagen Golf", "Pașaport", else the category.
    static func suggestedName(values: FieldValues, definition: TemplateDefinition) -> String {
        let words = definition.fields(withRole: .subtitle).compactMap { field -> String? in
            guard let value = values[field.key] else { return nil }
            if case .number = value { return nil }
            return FieldFormatter.display(value, field: field)
        }
        if !words.isEmpty { return words.prefix(2).joined(separator: " ") }
        if let identifier = AssetFacts.text(.identifier, in: values, template: definition) { return identifier }
        return definition.name
    }
}

enum AddSectionError: LocalizedError {
    case noCategory

    var errorDescription: String? {
        String(localized: "Alege mai întâi ce vrei să adaugi.", comment: "Error when finishing the add flow without a category.")
    }
}
