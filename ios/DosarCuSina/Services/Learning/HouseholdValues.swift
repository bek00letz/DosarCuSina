import Foundation
import SwiftData

/// What the binder keeps that names the household, wherever it is kept: the people's names (the
/// sections that play a holder), and every value of a field that says where the household lives
/// or what it drives (an address, with its locality; a plate; an email), whatever section keeps
/// it. A label capture would learn holding one of their words is the person's, never an issuer's
/// (`CaptureLessonLearner`), and a lesson kept from before that rule holding one is offered to be
/// forgotten (`PersonalLessonLabelsStep`).
///
/// By the field's type and the category's part (`CategoryBehavior.Role.holder`), never by a
/// built-in's key, so a category of one's own is read the same way.
enum HouseholdValues {
    /// The kinds of field whose values name the household.
    static let fieldTypes: Set<FieldType> = [.address, .plate, .email]

    /// The folded words of every such value (`CaptureLessonLearner.words`).
    static func words(in context: ModelContext) throws -> Set<String> {
        let templates = try TemplateStore.templatesByKey(in: context)
        var texts: [String] = []
        for asset in try context.fetch(FetchDescriptor<Asset>()) where !asset.isDeleted {
            let template = templates[asset.templateKey]
            if template?.behavior.role == .holder { texts.append(asset.name) }
            let values = asset.values
            for field in template?.definition.allFields ?? [] where fieldTypes.contains(field.type) {
                if let text = values[field.key]?.textValue { texts.append(text) }
            }
        }
        return CaptureLessonLearner.words(of: texts)
    }
}
