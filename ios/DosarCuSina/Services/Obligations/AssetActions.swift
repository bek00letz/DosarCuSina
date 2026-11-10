import Foundation
import SwiftData

public enum AssetActionError: LocalizedError, Equatable {
    case wouldCreateLoop
    /// The place chosen to move something to is gone.
    case missingDestination
    /// A new person was asked for without a name.
    case missingName

    public var errorDescription: String? {
        switch self {
        case .wouldCreateLoop:
            return String(localized: "Nu poți pune un element sub unul care e deja sub el.")
        case .missingDestination:
            return String(localized: "Locul ales nu mai există. Alege altul.")
        case .missingName:
            return String(localized: "Scrie numele persoanei.")
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
    /// The clock its steps give their change times by (`UnitOfWork`).
    let now: () -> Date
    /// Seals secret fields (PIN codes) before they are saved.
    private let sealer: SecretSealer

    public init(context: ModelContext, calendar: Calendar = .dosar, now: @escaping () -> Date = { Date() }, sealer: SecretSealer = .device) {
        self.context = context
        self.calendar = calendar
        self.now = now
        self.sealer = sealer
    }

    /// The template's blueprints with first dates worked out from `values`, for the add flow.
    public func plannedObligations(for template: CategoryTemplate, values: FieldValues) -> [PlannedObligation] {
        plannedObligations(for: template.definition, values: values)
    }

    /// The same for a category not saved yet: one of the person's own, while they describe it.
    public func plannedObligations(for definition: TemplateDefinition, values: FieldValues) -> [PlannedObligation] {
        let today = CalendarDay(now(), calendar: calendar)
        let values = values.applyingRules(of: definition, previous: nil, calendar: calendar)
        return definition.blueprints.filter { $0.appliesWhen?.isMet(by: values) ?? true }.map { blueprint in
            PlannedObligation(
                blueprint: blueprint,
                firstDue: RecurrenceEngine.firstDue(for: blueprint, values: values, today: today, calendar: calendar),
                isSelected: blueprint.isSuggested
            )
        }
    }

    /// A parent made together with the asset: a new household member and their first
    /// document, or a new home and its first subscription (with the address its bill printed).
    public struct NewParent {
        public var name: String
        public var template: CategoryTemplate
        public var values: FieldValues

        public init(name: String, template: CategoryTemplate, values: FieldValues = FieldValues()) {
            self.name = name
            self.template = template
            self.values = values
        }
    }

    /// Creates the asset and the selected obligations in one save. With `newParent`, the
    /// parent is created in the same save, so a failure leaves neither behind.
    @discardableResult
    public func create(
        name: String,
        template: CategoryTemplate,
        values: FieldValues,
        notes: String? = nil,
        obligations: [PlannedObligation] = [],
        parent: Asset? = nil,
        newParent: NewParent? = nil,
        isExample: Bool = false
    ) throws -> Asset {
        // Something of the person's never lands inside an example without asking.
        try ExampleOwnership.requireReal(parent, creatingExample: isExample)
        // No field keeps a card number: the unit of work masks it as it saves (`FreeText`), and a
        // secret before it is sealed.
        func prepare(_ values: FieldValues, for template: CategoryTemplate) throws -> FieldValues {
            try SecretFields.sealing(
                values.normalizingChoices(for: template.definition).applyingRules(of: template.definition, previous: nil, calendar: calendar),
                definition: template.definition, sealer: sealer
            )
        }
        let prepared = try prepare(values, for: template)
        let parentValues = try newParent.map { try prepare($0.values, for: $0.template) }
        let today = CalendarDay(now(), calendar: calendar)
        // One step: a failure part-way leaves no section without its deadlines. Inside a
        // caller's unit this joins it, and only that unit rolls back.
        return try UnitOfWork.perform(in: context, now: now()) {
            let asset = Asset(name: name, templateKey: template.key, values: prepared, notes: notes, isExample: isExample)
            context.insert(asset)
            if let newParent {
                let holder = Asset(name: newParent.name, templateKey: newParent.template.key, values: parentValues ?? FieldValues(), notes: nil, isExample: isExample)
                context.insert(holder)
                asset.parent = holder
            } else {
                asset.parent = parent
            }
            for planned in obligations where planned.isSelected {
                try HouseholdMutations.makeObligation(from: planned.blueprint, for: asset, firstDue: planned.firstDue, today: today, calendar: calendar, in: context)
            }
            // A new section has no readings before its first, so this never asks.
            if let reading = HouseholdMutations.heroMetricValue(of: asset, template: template.definition) {
                try HouseholdMutations.recordReading(reading, on: asset, at: now(), source: .person,
                                                     unit: HouseholdMutations.heroMetricUnit(template: template.definition), in: context)
            }
            try HouseholdRules.reconcile(in: context, today: today, calendar: calendar)
            return asset
        }
    }

    /// Saves edits. Obligations whose first date comes from a field (a document's
    /// renewal follows its expiry date) move with that field, and their reminders follow a
    /// changed value they depend on (`DeadlineReminders.follow`). A changed hero value (the
    /// kilometres) is a new reading through `recordReading`, dated `readingDate` (a
    /// document's date) or now; a lower counter throws `LowerReadingQuestion` until
    /// `lowerReading` answers it, and the hero value is then worked out from the readings.
    /// A subscription whose direct debit changed pauses or resumes its bill reminder
    /// (`BillReminders`); the outcome says so, with the receipt that takes back the whole edit.
    @discardableResult
    public func update(
        _ asset: Asset,
        name: String,
        values: FieldValues,
        notes: String?,
        readingSource: ReadingSource = .person,
        readingDate: Date? = nil,
        lowerReading: LowerReadingAnswer? = nil
    ) throws -> EditOutcome {
        let previous = asset.values
        let template = try TemplateStore(context: context).template(forKey: asset.templateKey)
        let values = try template.map {
            try SecretFields.sealing(
                values.normalizingChoices(for: $0.definition).applyingRules(of: $0.definition, previous: previous, calendar: calendar),
                definition: $0.definition, sealer: sealer
            )
        } ?? values
        // Every question first, before anything is written (`StepQuestion`).
        let reading = template.flatMap { plannedReading(asset, values: values, template: $0.definition, source: readingSource, date: readingDate) }
        try HouseholdMutations.askAboutReading(reading, answer: lowerReading)
        return try UnitOfWork.perform(in: context, now: now()) {
            var outcome = EditOutcome()
            asset.name = name
            asset.values = values
            asset.notes = notes
            if let template {
                // A value the deadlines' reminders depend on changed (the document's type, a
                // pet's species): they remind as the new value asks, unless the person set them.
                DeadlineReminders.follow(asset, template: template.definition, from: previous)
                let blueprints = Dictionary(template.blueprints.map { ($0.key, $0) }, uniquingKeysWith: { first, _ in first })
                for obligation in asset.activeObligations {
                    guard let key = obligation.blueprintKey, let blueprint = blueprints[key],
                          case .field(let fieldKey, let offset) = blueprint.firstDue,
                          !blueprint.recurrence.repeats,
                          previous[fieldKey] != values[fieldKey],
                          let day = values[fieldKey]?.dateValue else { continue }
                    obligation.setDueDay(day.adding(days: offset, calendar: calendar), calendar: calendar)
                }
                // A field that drives a deadline gets a value and the section has none from
                // it: the deadline is made, as adding the section would have (a policy's end
                // typed in later, a warranty's end read off a receipt).
                let today = CalendarDay(now(), calendar: calendar)
                let kept = Set((asset.obligations ?? []).filter { $0.status == .active || $0.status == .paused }.compactMap(\.blueprintKey))
                for blueprint in template.blueprints where !kept.contains(blueprint.key) {
                    guard case .field(let fieldKey, _) = blueprint.firstDue,
                          previous[fieldKey] != values[fieldKey], values[fieldKey]?.dateValue != nil,
                          blueprint.appliesWhen?.isMet(by: values) ?? true,
                          let day = RecurrenceEngine.firstDue(for: blueprint, values: values, today: today, calendar: calendar),
                          blueprint.isWorthScheduling(on: day, today: today, values: values) else { continue }
                    try HouseholdMutations.makeObligation(from: blueprint, for: asset, firstDue: day, today: today, calendar: calendar, in: context)
                }
                if let reading {
                    try HouseholdMutations.recordReading(reading, answer: lowerReading, in: context)
                }
            }
            // A subscription's direct debit changed: its bill reminder pauses or comes back.
            outcome.billReminder = try BillReminders.follow(asset, from: previous, actions: ObligationActions(context: context, calendar: calendar, now: now),
                                                            today: CalendarDay(now(), calendar: calendar), calendar: calendar)
            try save()
            return outcome
        }
    }

    /// The reading saving `values` on `asset` records: its hero value (the kilometres), when
    /// it changed, dated `date` (a document's) or now. Asked about before the step's unit
    /// opens, by `update` and by a flow that writes values inside a larger step (`CaptureFiler`).
    func plannedReading(updating asset: Asset, to values: FieldValues, source: ReadingSource = .person, date: Date? = nil) throws -> PlannedReading? {
        guard let template = try TemplateStore(context: context).template(forKey: asset.templateKey) else { return nil }
        let prepared = values.normalizingChoices(for: template.definition).applyingRules(of: template.definition, previous: asset.values, calendar: calendar)
        return plannedReading(asset, values: prepared, template: template.definition, source: source, date: date)
    }

    /// Asks what saving `values` on `asset` with `update` would ask (a lower counter), without
    /// changing anything: for a screen that saves the edit with other changes in one unit of
    /// work (a section's photo and its fields), so it asks before the unit writes the photo.
    public func askFirst(updating asset: Asset, to values: FieldValues, lowerReading: LowerReadingAnswer?) throws {
        try HouseholdMutations.askAboutReading(try plannedReading(updating: asset, to: values), answer: lowerReading)
    }

    /// The one rule: the hero value of `values` (as saving writes them), when it isn't the one kept now.
    private func plannedReading(_ asset: Asset, values: FieldValues, template: TemplateDefinition, source: ReadingSource, date: Date?) -> PlannedReading? {
        guard let reading = HouseholdMutations.heroMetricValue(values: values, template: template),
              reading != HouseholdMutations.heroMetricValue(of: asset, template: template) else { return nil }
        return PlannedReading(reading, on: asset, at: date ?? now(), source: source, unit: HouseholdMutations.heroMetricUnit(template: template))
    }

    /// What saving an edit changed beyond the values, for the screen to say.
    public struct EditOutcome {
        /// The subscription's bill reminder followed its direct debit, with the receipt that
        /// takes back the whole edit.
        public var billReminder: Undoable<BillReminders.Change>?
    }

    /// Records a counter reading on its own (the kilometres read today), through the one
    /// path: an estimate is never stored, a lower counter asks first, and the hero value
    /// follows the readings. Returns the reading kept, or nil for an estimate.
    @discardableResult
    public func recordReading(
        _ value: Double,
        on asset: Asset,
        at date: Date? = nil,
        source: ReadingSource,
        lowerReading: LowerReadingAnswer? = nil
    ) throws -> MeasurementLog? {
        let template = try TemplateStore(context: context).template(forKey: asset.templateKey)
        let unit = template.flatMap { HouseholdMutations.heroMetricUnit(template: $0.definition) }
        // Every question first, before anything is written (`StepQuestion`).
        let isExample = try ExampleOwnership.requireReal(asset)
        let reading = PlannedReading(value, on: asset, at: date ?? now(), source: source, unit: unit)
        try HouseholdMutations.askAboutReading(reading, answer: lowerReading)
        let log = try HouseholdMutations.recordReading(reading, answer: lowerReading, isExample: isExample, in: context)
        if log != nil { try save() }
        return log
    }

    /// Replaces the free label–value rows shown under Date importante. A secret
    /// row (a code) is sealed before it is saved, like a PIN field; a card number in any row is
    /// kept as its last four digits (`FreeText`).
    @discardableResult
    public func setCustomFacts(_ asset: Asset, _ facts: [CustomFact]) throws -> UndoReceipt {
        try UnitOfWork.performUndoable(in: context, now: now()) {
            let kept = facts.filter { !$0.label.trimmingCharacters(in: .whitespaces).isEmpty || !$0.value.trimmingCharacters(in: .whitespaces).isEmpty }
            asset.customFacts = try SecretFields.sealingFacts(kept, sealer: sealer)
            try save()
        }.receipt
    }

    /// Records a measured value of any kind (a meter index, a weight, a lab value) through the
    /// one reading path. Counter readings (odometer, shots) also update the hero value.
    @discardableResult
    public func recordMeasurement(
        on asset: Asset,
        kind: MeasurementKind,
        name: String? = nil,
        value: Double,
        unit: MeasurementUnit? = nil,
        at date: Date? = nil,
        asExample: Bool = false,
        lowerReading: LowerReadingAnswer? = nil
    ) throws -> MeasurementLog {
        // Every question first, before anything is written (`StepQuestion`).
        let isExample = try ExampleOwnership.requireReal(asset, creatingExample: asExample)
        let reading = PlannedReading(value, on: asset, at: date ?? now(), source: .person, unit: unit, kind: kind, name: name ?? "")
        try HouseholdMutations.askAboutReading(reading, answer: lowerReading)
        let log = try HouseholdMutations.recordReading(reading, answer: lowerReading, isExample: isExample, in: context)
        try save()
        // Only an estimate returns nil, and this records what was measured.
        return log!
    }

    /// What happens to the assets filed under one that is deleted. The screen asks,
    /// using `Asset.childCount`.
    public enum ChildrenOnDelete: Sendable {
        /// Keep them as standalone assets.
        case keep
        /// Delete them too (and, in turn, whatever is filed under them).
        case delete
    }

    /// Deletes the section with its deadlines, history, readings and documents (their
    /// pages too), and, when asked, everything filed under it; what stays (`.keep`) goes to
    /// the top. A household deadline that only it needed (the rental income declaration)
    /// goes too. One undoable step: the receipt brings all of it back with every link,
    /// and the side effects follow the save as always.
    @discardableResult
    public func delete(_ asset: Asset, children: ChildrenOnDelete = .keep) throws -> UndoReceipt {
        try UnitOfWork.performUndoable(in: context, now: now()) {
            if children == .delete {
                for child in Self.descendants(of: asset) { context.delete(child) }
            }
            context.delete(asset)
            try HouseholdRules.reconcile(in: context, today: CalendarDay(now(), calendar: calendar), calendar: calendar)
            try save()
        }.receipt
    }

    /// Files `child` under `parent`, or makes it standalone with nil. Refuses to
    /// create a loop (an asset under its own descendant).
    public func setParent(_ child: Asset, _ parent: Asset?) throws {
        if let parent, !Self.canFile(child, under: parent) {
            throw AssetActionError.wouldCreateLoop
        }
        child.parent = parent
        try save()
    }

    /// The one rule for filing something under something else, in the app and
    /// in a restored backup: never under itself, nor under anything filed under it.
    nonisolated static func canFile(_ child: Asset, under parent: Asset) -> Bool {
        var seen: Set<UUID> = []
        var current: Asset? = parent
        while let next = current {
            guard next.id != child.id, seen.insert(next.id).inserted else { return false }
            current = next.parent
        }
        return true
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
        try UnitOfWork.save(context, now: now())
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

    static func recurrenceContext(for obligation: Obligation, currentMetric: Double?, calendar: Calendar = .dosar) -> RecurrenceContext {
        // Only completions that moved the date take part (not the one being recorded now).
        let steps = obligation.history.filter { $0.nextDueDate != nil }.map {
            RecurrenceEngine.SeriesStep(
                cycle: $0.cycleDueDate.map { CalendarDay($0, calendar: calendar) },
                next: $0.nextDueDate.map { CalendarDay($0, calendar: calendar) }
            )
        }
        let seriesDay = RecurrenceEngine.seriesStart(current: obligation.dueDay(in: calendar), completions: steps).day
        guard let asset = obligation.asset else { return RecurrenceContext(currentMetric: currentMetric, seriesDayOfMonth: seriesDay) }
        let series = readingSeries(of: asset, unit: obligation.metricUnit)
        let readings = series.readings
        return RecurrenceContext(
            assetValues: asset.values,
            readings: readings,
            currentMetric: currentMetric ?? readings.last?.metric ?? self.currentMetric(of: asset),
            seriesDayOfMonth: seriesDay
        )
    }

    /// The asset's counter: the last reading of the cleaned series, else its hero metric field.
    static func currentMetric(of asset: Asset) -> Double? {
        let counters = (asset.measurements ?? []).filter { $0.kind.isCumulative && !$0.isDeleted }
        if let unit = counters.max(by: { $0.recordedAt < $1.recordedAt })?.measurementUnit,
           let current = readingSeries(of: asset, unit: unit).current {
            return current
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

    static func heroMetricUnit(template: TemplateDefinition) -> MeasurementUnit? {
        heroMetricField(of: template)?.unit
    }
}

extension MeasurementKind {
    /// The usual kind for a unit, used when a reading comes from a template field.
    public static func forUnit(_ unit: MeasurementUnit?) -> MeasurementKind {
        let kinds: [MeasurementUnit: MeasurementKind] = [
            .kilometres: .odometer, .kilograms: .bodyWeight, .engineHours: .engineHours, .kilowattHours: .electricity,
        ]
        return unit.flatMap { kinds[$0] } ?? .cycles
    }
}
