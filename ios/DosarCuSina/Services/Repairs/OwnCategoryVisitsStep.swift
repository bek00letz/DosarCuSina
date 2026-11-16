import Foundation
import SwiftData

// MARK: - The visits of a category of one's own, as its switch says (runs by itself)

/// Before a visit's form came from its kind (`VisitKind`), every category without one of its own
/// logged visits on the one plain form, „Am făcut o lucrare”. Now a category of one's own has
/// visits only with „Are revizii sau lucrări” on, of the kind that switch gives
/// (`CategorySwitches.visit(for:)`): one an earlier version made with the switch on stored no kind
/// and would read as none, so this gives it its kind, and its sections keep logging visits as
/// before. Nothing anyone used goes, so it runs without asking, at launch and after every import.
/// A kind already stated stays; a category with the switch off has no visits, by the rule itself.
struct OwnCategoryVisitsStep: DataRepairStep {
    static let id = DataRepairStepID.ownCategoryVisits
    var title: String { String(localized: "Vizitele categoriilor tale", comment: "Repair group: a category of one's own gets the visits its switch gives.") }
    var runsByItself: Bool { true }

    /// How many categories changed.
    @discardableResult
    func migrate(in context: ModelContext) throws -> Int {
        var changed = 0
        for template in try TemplateStore(context: context).all() where !template.isBuiltIn && template.behavior.visit == .none {
            let kind = CategorySwitches.visit(for: CategorySwitches(reading: template).service)
            guard kind != .none else { continue }
            template.behavior.visit = kind
            changed += 1
        }
        return changed
    }

    func runByItself(in context: ModelContext) throws {
        try migrate(in: context)
    }
}
