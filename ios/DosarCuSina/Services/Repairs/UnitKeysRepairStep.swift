import Foundation
import SwiftData

// MARK: - Units stored by their label (runs by itself)

/// Before units had keys, a reading, a deadline counted in a unit and a category of the
/// person's own stored the unit's label ("m³", "mc", "kWh", "cafele"). They are rewritten to
/// the unit's key (`MeasurementUnit`). The unit and the number stay the same, so it runs
/// without asking. Built-in categories get keys when the catalog upgrades them.
///
/// Only the unit is touched: a stored recurrence or category is rewritten in place, never
/// read into this version's types and written back, so nothing a newer version wrote is lost.
struct UnitKeysStep: DataRepairStep {
    static let id = DataRepairStepID.unitKeys
    var title: String { String(localized: "Unități de măsură", comment: "Repair group: units stored by their label in older builds.") }
    var runsByItself: Bool { true }

    /// How many records changed.
    @discardableResult
    func migrate(in context: ModelContext) throws -> Int {
        var changed = 0
        for log in try context.fetch(FetchDescriptor<MeasurementLog>()) {
            let key = MeasurementUnit.storedKey(for: log.unit)
            guard key != log.unit else { continue }
            log.unit = key
            changed += 1
        }
        for obligation in try context.fetch(FetchDescriptor<Obligation>()) {
            guard let data = StoredUnitKeys.recurrence(obligation.recurrenceData) else { continue }
            obligation.recurrenceData = data
            changed += 1
        }
        for template in try context.fetch(FetchDescriptor<CategoryTemplate>()) where !template.isBuiltIn {
            var touched = false
            if let data = StoredUnitKeys.sections(template.sectionsData) {
                template.sectionsData = data
                touched = true
            }
            if let data = StoredUnitKeys.blueprints(template.blueprintsData) {
                template.blueprintsData = data
                touched = true
            }
            if touched { changed += 1 }
        }
        return changed
    }

    func runByItself(in context: ModelContext) throws {
        try migrate(in: context)
    }
}

/// Rewrites the units inside stored JSON to their keys, leaving everything else as it was.
/// Each returns nil when nothing changes (or the data can't be read), so a second run
/// changes nothing.
enum StoredUnitKeys {
    /// A recurrence (`{"type": "metric", "unit": "m³", …}`).
    static func recurrence(_ data: Data?) -> Data? {
        guard var object = json(data) as? [String: Any], rewriteRecurrence(&object) else { return nil }
        return encode(object)
    }

    /// A category's sections: each field's `unit`.
    static func sections(_ data: Data?) -> Data? {
        guard var sections = json(data) as? [[String: Any]] else { return nil }
        var changed = false
        for index in sections.indices {
            guard var fields = sections[index]["fields"] as? [[String: Any]] else { continue }
            for field in fields.indices where rewriteUnit(in: &fields[field]) { changed = true }
            sections[index]["fields"] = fields
        }
        return changed ? encode(sections) : nil
    }

    /// A category's deadlines: each metric recurrence's `unit`.
    static func blueprints(_ data: Data?) -> Data? {
        guard var blueprints = json(data) as? [[String: Any]] else { return nil }
        var changed = false
        for index in blueprints.indices {
            guard var recurrence = blueprints[index]["recurrence"] as? [String: Any], rewriteRecurrence(&recurrence) else { continue }
            blueprints[index]["recurrence"] = recurrence
            changed = true
        }
        return changed ? encode(blueprints) : nil
    }

    private static func rewriteRecurrence(_ object: inout [String: Any]) -> Bool {
        guard object["type"] as? String == "metric" else { return false }
        return rewriteUnit(in: &object)
    }

    private static func rewriteUnit(in object: inout [String: Any]) -> Bool {
        guard let text = object["unit"] as? String else { return false }
        let key = MeasurementUnit.storedKey(for: text)
        guard !key.isEmpty, key != text else { return false }
        object["unit"] = key
        return true
    }

    private static func json(_ data: Data?) -> Any? {
        guard let data else { return nil }
        return try? JSONSerialization.jsonObject(with: data)
    }

    private static func encode(_ object: Any) -> Data? {
        try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys, .withoutEscapingSlashes])
    }
}
