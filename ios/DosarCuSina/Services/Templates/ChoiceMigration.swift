import Foundation
import SwiftData

/// Rewrites choice values stored as display text (from builds before option
/// keys) as option keys. Runs at launch after the built-in templates are
/// installed; saves only when something changed.
@MainActor
public enum ChoiceMigration {
    @discardableResult
    public static func migrateStoredValues(in context: ModelContext) throws -> Int {
        let templates = try TemplateStore(context: context).templatesByKey()
        var changed = 0
        for asset in try context.fetch(FetchDescriptor<Asset>()) {
            guard let definition = templates[asset.templateKey]?.definition ?? BuiltInTemplates.definition(for: asset.templateKey) else { continue }
            let values = asset.values
            let normalized = values.normalizingChoices(for: definition)
            if normalized != values {
                asset.valuesData = StoredJSON.encode(normalized)
                changed += 1
            }
        }
        if changed > 0 {
            do {
                try context.save()
            } catch {
                context.rollback()
                throw error
            }
        }
        return changed
    }
}
