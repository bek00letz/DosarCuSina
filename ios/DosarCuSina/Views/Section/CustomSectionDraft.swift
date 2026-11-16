import Foundation

/// A category of its own, described in the "Altceva…" step and created only
/// when the person finishes, so cancelling never leaves an empty category behind.
/// What it is and what it offers; its words are `AddSectionWording`'s.
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

    /// The key the category it describes carries while it is only described, before
    /// `TemplateStore.createCustom` gives it its own.
    static let draftKey = "draft"

    /// The category it describes, as it would be saved.
    func definition(key: String) -> TemplateDefinition {
        if CustomSectionStep.offersPocketList {
            return TemplateDefinition(key: key, name: name, symbol: symbol, tint: Self.tint, sections: [], pockets: Array(pockets), behavior: .standard)
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

    /// Pockets a section of one's own can have, each with a one-line explanation
    /// (`AddSectionWording.pocketExplanation(_:)`).
    static let offeredPockets: [SectionPocket] = [.upcoming, .documents, .history, .people, .money, .keyFacts, .products, .subscriptions]
}
