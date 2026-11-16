import Foundation
import SwiftData

/// What completing one deadline asks, found once for every screen that completes it (its page,
/// Urmează's row, the sheet, a chore's toast): what its blueprint states, from its section's
/// category (a household deadline's from `HouseholdRules`), else, for a deadline of one's own,
/// what its kind gives (`CompletionKind.own`). Never decide it from the kind where a blueprint
/// states it.
extension Obligation {
    /// The completion kind this deadline's blueprint states, read in `template`, its section's
    /// category.
    func completionKind(template: TemplateDefinition?) -> CompletionKind {
        guard CompletionKind.statedByBlueprints else { return .own(kind) }
        guard let key = blueprintKey else { return .own(kind) }
        let blueprints = (template?.blueprints ?? []) + HouseholdRules.blueprints
        return blueprints.first { $0.key == key }?.completion ?? .own(kind)
    }

    /// What completing it asks, in `template`, its section's category.
    func completion(template: TemplateDefinition?) -> CompletionShape {
        completionKind(template: template).asked
    }

    /// What completing it asks, its category read from `context`.
    @MainActor
    func completion(in context: ModelContext) -> CompletionShape {
        let template = asset.flatMap { try? TemplateStore(context: context).template(forKey: $0.templateKey) }
        return completion(template: template?.definition)
    }
}

extension CompletionKind {
    /// What the app asks for this kind: its shape, or, with the first way back off
    /// (`CompletionShape.asksByKind`), what every deadline asked before the shapes.
    var asked: CompletionShape {
        CompletionShape.asksByKind ? shape : CompletionShape.everyKindBefore
    }

    /// The way back: off, every deadline completes as its kind did before blueprints stated
    /// their own (`own(_:)`, the kind's shape). Remove once the owner agrees.
    static let statedByBlueprints = true
}
