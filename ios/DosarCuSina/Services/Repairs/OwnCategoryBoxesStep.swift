import Foundation
import SwiftData

// MARK: - One box for a category of one's own, as its grouping (runs by itself)

/// Before one box for a category's sections was the person's choice (`CategoryTemplate.grouping`),
/// a category of one's own answered „O cutie pentru toate” with a box of the whole category's
/// (`CategoryBehavior.Box.wholeCategory`, as Garanții). Now that switch is the grouping, so such a
/// category gets a box per section, grouped (`TemplateStore.takeBoxAsGrouping`): the same one box
/// on the binder, opening the same page, in the same place, and the box's menu and Setări offer
/// splitting it as for any other. Nothing anyone sees changes, so it runs without asking, at
/// launch and after every import. A grouping already chosen stays; built-ins keep the catalog's box.
struct OwnCategoryBoxesStep: DataRepairStep {
    static let id = DataRepairStepID.ownCategoryBoxes
    var title: String { String(localized: "Cutiile categoriilor tale", comment: "Repair group: a category of one's own whose one box becomes its grouping.") }
    var runsByItself: Bool { true }

    /// How many categories changed.
    @discardableResult
    func migrate(in context: ModelContext) throws -> Int {
        let store = TemplateStore(context: context)
        return try store.all().filter { store.takeBoxAsGrouping($0) }.count
    }

    func runByItself(in context: ModelContext) throws {
        try migrate(in: context)
    }
}
