import Foundation
import SwiftData

// MARK: - Numbers kept a step off (runs by itself)

/// Earlier versions turned a number read into a Double through `NSDecimalNumber.doubleValue`,
/// which can miss the nearest Double by a step or two (ULPs): a water index printed 0,011 was kept
/// as 0.011000000000000001, where the Android app keeps 0.011. Each Double a reader wrote
/// is put back on the short number it stands for, by the one rule
/// (`RomanianNumber.correction(of:as:)`), with the decimals of the kind it was read as:
///
/// - a reading's value and its second value, by its unit (`NumberKind.forField(unit:)`);
/// - a record's counter (`HistoryEntry.metricReading`, the visit form's odometer), by the unit
///   its section's counter is in (`HouseholdMutations.heroMetricUnit`), the one its reading has;
/// - a section's numbers, by their field (`FieldFormatter.numberKind(of:unit:)`); a value whose
///   field the category doesn't list stays.
///
/// A deadline's counted due (`dueMetric`) is a sum the app works out, not a number read, and a
/// category's counted interval is a whole number, which the old conversion never missed: both stay.
///
/// What anyone sees stays the same (the app writes at most the kind's decimals) and only how the
/// number is stored changes, so it runs without asking, as the app's own step: no change time.
struct DecimalDoublesStep: DataRepairStep {
    static let id = DataRepairStepID.decimalDoubles
    var title: String { String(localized: "Numere cu zecimale", comment: "Repair group: numbers with decimals an earlier version kept a hair off.") }
    var runsByItself: Bool { true }

    /// How many records changed.
    @discardableResult
    func migrate(in context: ModelContext) throws -> Int {
        var changed = 0
        for log in try context.fetch(FetchDescriptor<MeasurementLog>()) {
            let kind = NumberKind.forField(unit: log.measurementUnit)
            var touched = false
            if let value = RomanianNumber.correction(of: log.value, as: kind) {
                log.value = value
                touched = true
            }
            if let second = log.secondaryValue, let value = RomanianNumber.correction(of: second, as: kind) {
                log.secondaryValue = value
                touched = true
            }
            if touched { changed += 1 }
        }

        let templates = try TemplateStore(context: context).templatesByKey()
        func definition(of asset: Asset?) -> TemplateDefinition? {
            guard let key = asset?.templateKey else { return nil }
            return templates[key]?.definition ?? BuiltInTemplates.definition(for: key)
        }
        for entry in try context.fetch(FetchDescriptor<HistoryEntry>()) {
            guard let reading = entry.metricReading else { continue }
            let unit = definition(of: entry.asset).flatMap(HouseholdMutations.heroMetricUnit(template:))
            guard let value = RomanianNumber.correction(of: reading, as: NumberKind.forField(unit: unit)) else { continue }
            entry.metricReading = value
            changed += 1
        }
        for asset in try context.fetch(FetchDescriptor<Asset>()) {
            guard let definition = definition(of: asset) else { continue }
            var values = asset.values
            var touched = false
            for (key, stored) in asset.values.storage {
                guard case .number(let number) = stored, let field = definition.field(key),
                      let value = RomanianNumber.correction(of: number, as: FieldFormatter.numberKind(of: field.type, unit: field.unit)) else { continue }
                values[key] = .number(value)
                touched = true
            }
            guard touched else { continue }
            asset.values = values
            changed += 1
        }
        return changed
    }

    func runByItself(in context: ModelContext) throws {
        try migrate(in: context)
    }
}
