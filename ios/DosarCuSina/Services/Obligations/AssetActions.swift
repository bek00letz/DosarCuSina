import Foundation
import SwiftData

public enum AssetActionError: LocalizedError, Equatable {
    case wouldCreateLoop

    public var errorDescription: String? {
        switch self {
        case .wouldCreateLoop:
            return String(localized: "Nu poți pune un element sub unul care e deja sub el.")
        }
    }
}

/// An obligation the add flow is about to create: a blueprint and its first date.
public struct PlannedObligation: Hashable, Sendable, Identifiable {
    public var blueprint: ObligationBlueprint
    /// Nil when the person still has to pick it.
    public var firstDue: CalendarDay?
    public var isSelected: Bool

    public var id: String { blueprint.key }

    public init(blueprint: ObligationBlueprint, firstDue: CalendarDay?, isSelected: Bool) {
        self.blueprint = blueprint
        self.firstDue = firstDue
        self.isSelected = isSelected
    }
}

/// Creating, editing, measuring and deleting assets. Each call saves once.
@MainActor
public final class AssetActions {
    public let context: ModelContext
    private let calendar: Calendar
    private let now: () -> Date

    public init(context: ModelContext, calendar: Calendar = .current, now: @escaping () -> Date = { Date() }) {
        self.context = context
        self.calendar = calendar
        self.now = now
    }

    /// The template's blueprints with first dates worked out from `values`, for the add flow.
    public func plannedObligations(for template: CategoryTemplate, values: FieldValues) -> [PlannedObligation] {
        let today = CalendarDay(now(), calendar: calendar)
        return template.blueprints.map { blueprint in
            PlannedObligation(
                blueprint: blueprint,
                firstDue: RecurrenceEngine.firstDue(for: blueprint, values: values, today: today, calendar: calendar),
                isSelected: blueprint.isSuggested
            )
        }
    }

    /// Creates the asset and the selected obligations in one save.
    @discardableResult
    public func create(
        name: String,
        template: CategoryTemplate,
        values: FieldValues,
        notes: String? = nil,
        obligations: [PlannedObligation] = [],
        parent: Asset? = nil,
        isExample: Bool = false
    ) throws -> Asset {
        let asset = Asset(name: name, templateKey: template.key, values: values.normalizingChoices(for: template.definition), notes: notes, isExample: isExample)
        context.insert(asset)
        asset.parent = parent
        let today = CalendarDay(now(), calendar: calendar)
        do {
            for planned in obligations where planned.isSelected {
                try HouseholdMutations.makeObligation(from: planned.blueprint, for: asset, firstDue: planned.firstDue, today: today, calendar: calendar, in: context)
            }
            if let reading = HouseholdMutations.heroMetricValue(of: asset, template: template.definition) {
                HouseholdMutations.addMeasurement(reading, unit: HouseholdMutations.heroMetricUnit(template: template.definition), to: asset, at: now(), in: context)
            }
            try context.save()
        } catch {
            context.rollback()
            throw error
        }
        return asset
    }

    /// Saves edits. Obligations whose first date comes from a field (a document's
    /// renewal follows its expiry date) move with that field.
    public func update(_ asset: Asset, name: String, values: FieldValues, notes: String?) throws {
        let previous = asset.values
        let template = try TemplateStore(context: context).template(forKey: asset.templateKey)
        let values = template.map { values.normalizingChoices(for: $0.definition) } ?? values
        asset.name = name
        asset.values = values
        asset.notes = notes
        asset.updatedAt = now()
        if let template {
            let blueprints = Dictionary(template.blueprints.map { ($0.key, $0) }, uniquingKeysWith: { first, _ in first })
            for obligation in asset.activeObligations {
                guard let key = obligation.blueprintKey, let blueprint = blueprints[key],
                      case .field(let fieldKey, let offset) = blueprint.firstDue,
                      !blueprint.recurrence.repeats,
                      previous[fieldKey] != values[fieldKey],
                      let day = values[fieldKey]?.dateValue else { continue }
                obligation.setDueDay(day.adding(days: offset, calendar: calendar), calendar: calendar)
                obligation.updatedAt = now()
            }
            if let reading = HouseholdMutations.heroMetricValue(of: asset, template: template.definition),
               reading != HouseholdMutations.heroMetricValue(values: previous, template: template.definition) {
                HouseholdMutations.addMeasurement(reading, unit: HouseholdMutations.heroMetricUnit(template: template.definition), to: asset, at: now(), in: context)
            }
        }
        try save()
    }

    /// Records a reading. Counter readings (odometer, shots) also update the asset's hero value.
    @discardableResult
    public func recordMeasurement(
        on asset: Asset,
        kind: MeasurementKind,
        name: String? = nil,
        value: Double,
        unit: String? = nil,
        at date: Date? = nil
    ) throws -> MeasurementLog {
        let log = MeasurementLog(kind: kind, name: name ?? "", value: value, unit: unit, recordedAt: date ?? now())
        log.isExample = asset.isExample
        context.insert(log)
        log.asset = asset
        HouseholdMutations.syncHeroMetric(of: asset, with: log, in: context)
        try save()
        return log
    }

    /// What happens to the assets filed under one that is deleted. The screen asks,
    /// using `Asset.childCount`.
    public enum ChildrenOnDelete: Sendable {
        /// Keep them as standalone assets.
        case keep
        /// Delete them too (and, in turn, whatever is filed under them).
        case delete
    }

    public func delete(_ asset: Asset, children: ChildrenOnDelete = .keep) throws {
        if children == .delete {
            for child in Self.descendants(of: asset) { context.delete(child) }
        }
        context.delete(asset)
        try save()
    }

    /// Files `child` under `parent`, or makes it standalone with nil. Refuses to
    /// create a loop (an asset under its own descendant).
    public func setParent(_ child: Asset, _ parent: Asset?) throws {
        if let parent {
            guard parent.id != child.id, !Self.descendants(of: child).contains(where: { $0.id == parent.id }) else {
                throw AssetActionError.wouldCreateLoop
            }
        }
        child.parent = parent
        child.updatedAt = now()
        try save()
    }

    static func descendants(of asset: Asset) -> [Asset] {
        var result: [Asset] = []
        var queue = asset.children ?? []
        var seen: Set<UUID> = [asset.id]
        while let next = queue.popLast() {
            guard seen.insert(next.id).inserted else { continue }
            result.append(next)
            queue.append(contentsOf: next.children ?? [])
        }
        return result
    }

    private func save() throws {
        do {
            try context.save()
        } catch {
            context.rollback()
            throw error
        }
    }
}

/// Shared, non-saving building blocks for the action types. Callers save.
@MainActor
enum HouseholdMutations {
    @discardableResult
    static func makeObligation(
        from blueprint: ObligationBlueprint,
        for asset: Asset,
        firstDue: CalendarDay?,
        today: CalendarDay,
        calendar: Calendar,
        in context: ModelContext
    ) throws -> Obligation {
        guard let due = firstDue ?? RecurrenceEngine.firstDue(for: blueprint, values: asset.values, today: today, calendar: calendar) else {
            throw ObligationActionError.missingFirstDueDate(blueprintKey: blueprint.key)
        }
        let obligation = Obligation(
            title: blueprint.title,
            kind: blueprint.kind,
            dueDay: due,
            recurrence: blueprint.recurrence,
            reminders: blueprint.reminders(for: asset.values),
            estimatedCost: blueprint.estimatedCost,
            calendar: calendar
        )
        obligation.blueprintKey = blueprint.key
        obligation.notes = blueprint.note
        obligation.isExample = asset.isExample
        if case .metric(let every, _, _) = blueprint.recurrence,
           let reading = currentMetric(of: asset) {
            obligation.dueMetric = reading + every
        }
        context.insert(obligation)
        obligation.asset = asset
        return obligation
    }

    static func recurrenceContext(for obligation: Obligation, currentMetric: Double?) -> RecurrenceContext {
        guard let asset = obligation.asset else { return RecurrenceContext(currentMetric: currentMetric) }
        let unit = obligation.metricUnit
        let readings = (asset.measurements ?? [])
            .filter { $0.kind.isCumulative && (unit == nil || $0.unit == unit) }
            .sorted { $0.recordedAt < $1.recordedAt }
            .map { CadenceCalculator.TelemetryReading(date: $0.recordedAt, metric: $0.value) }
        return RecurrenceContext(
            assetValues: asset.values,
            readings: readings,
            currentMetric: currentMetric ?? readings.last?.metric ?? self.currentMetric(of: asset)
        )
    }

    /// The asset's counter: the latest cumulative reading, else its hero metric field.
    static func currentMetric(of asset: Asset) -> Double? {
        if let latest = (asset.measurements ?? []).filter(\.kind.isCumulative).max(by: { $0.recordedAt < $1.recordedAt }) {
            return latest.value
        }
        let stored: CategoryTemplate? = asset.modelContext.flatMap { try? TemplateStore(context: $0).template(forKey: asset.templateKey) } ?? nil
        guard let definition = stored?.definition ?? BuiltInTemplates.definition(for: asset.templateKey) else {
            return nil
        }
        return heroMetricValue(values: asset.values, template: definition)
    }

    static func heroMetricValue(of asset: Asset, template: TemplateDefinition) -> Double? {
        heroMetricValue(values: asset.values, template: template)
    }

    /// The template's hero number field (a counter or a measured value with a unit).
    static func heroMetricField(of template: TemplateDefinition) -> FieldDefinition? {
        template.fields(withRole: .heroMetric).first { ($0.type == .metric || $0.type == .number) && $0.unit != nil }
    }

    static func heroMetricValue(values: FieldValues, template: TemplateDefinition) -> Double? {
        heroMetricField(of: template).flatMap { values[$0.key]?.numberValue }
    }

    static func heroMetricUnit(template: TemplateDefinition) -> String? {
        heroMetricField(of: template)?.unit
    }

    static func addMeasurement(_ value: Double, unit: String?, to asset: Asset, at date: Date, in context: ModelContext) {
        let kind = MeasurementKind.forUnit(unit)
        let log = MeasurementLog(kind: kind, name: "", value: value, unit: unit ?? kind.defaultUnit, recordedAt: date)
        log.isExample = asset.isExample
        context.insert(log)
        log.asset = asset
    }

    /// Adds a counter reading taken while completing an obligation.
    static func recordReading(_ value: Double, on asset: Asset, at date: Date, unit: String?, in context: ModelContext) {
        let kind = MeasurementKind.forUnit(unit)
        let log = MeasurementLog(kind: kind, name: "", value: value, unit: unit ?? kind.defaultUnit, recordedAt: date)
        log.isExample = asset.isExample
        context.insert(log)
        log.asset = asset
        syncHeroMetric(of: asset, with: log, in: context)
    }

    /// Keeps the hero field equal to the readings: the highest value for counters,
    /// the newest reading for everything else. Readings are the source of truth.
    static func syncHeroMetric(of asset: Asset, with log: MeasurementLog, in context: ModelContext) {
        guard let template = try? TemplateStore(context: context).template(forKey: asset.templateKey),
              let field = heroMetricField(of: template.definition), field.unit == log.unit else { return }
        let sameUnit = (asset.measurements ?? []).filter { $0.unit == log.unit && $0.id != log.id }
        let shouldUpdate: Bool
        if log.kind.isCumulative {
            shouldUpdate = log.value >= (sameUnit.map(\.value).max() ?? -.infinity)
        } else {
            shouldUpdate = log.recordedAt >= (sameUnit.map(\.recordedAt).max() ?? .distantPast)
        }
        guard shouldUpdate else { return }
        var values = asset.values
        values[field.key] = .number(log.value)
        asset.values = values
    }
}

extension MeasurementKind {
    /// The usual kind for a unit, used when a reading comes from a template field.
    public static func forUnit(_ unit: String?) -> MeasurementKind {
        switch unit {
        case "km": return .odometer
        case "kg": return .bodyWeight
        case "h": return .engineHours
        case "kWh": return .electricity
        default: return .cycles
        }
    }
}
