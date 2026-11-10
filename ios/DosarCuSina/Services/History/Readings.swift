import Foundation
import SwiftData

/// Where a counter reading comes from.
public enum ReadingSource: Sendable, Hashable {
    /// Read off the counter by the person: the edit form, the visit form, "Gata".
    case person
    /// Printed on a document (an invoice's "Km bord"), dated by the document.
    case document
    /// Worked out from the pace so far. Only ever a placeholder in a field: never stored.
    case estimate
}

/// The person's answer when a counter reading is lower than an earlier one, in the order the
/// question offers them (`.readingPrompt`).
public enum LowerReadingAnswer: Sendable, Hashable, CaseIterable {
    /// "Corectează citirea veche": the earlier, higher readings were wrong. They go, and the new one counts.
    case correctOld
    /// "Lasă citirea veche": the new reading is kept aside. It stays in the list but doesn't count
    /// while the readings before it are higher.
    case keepAside
    /// "Contor nou": the meter or the dashboard was replaced, or the counter went round. The new
    /// reading starts a new counter (`MeasurementLog.startsCounter`): the older readings stay as
    /// the old counter's history, and nothing after it is compared with them again.
    case newCounter

    /// The answer's button.
    public var title: String {
        switch self {
        case .correctOld: String(localized: "Corectează citirea veche", comment: "Answer to a lower reading: the earlier, higher readings were wrong.")
        case .keepAside: String(localized: "Lasă citirea veche", comment: "Answer to a lower reading: keep the earlier one, set the new one aside.")
        case .newCounter: String(localized: "Contor nou", comment: "Answer to a lower reading: the meter or the dashboard was replaced, or it went round; the new reading starts a new counter.")
        }
    }
}

/// Thrown by `HouseholdMutations.askAboutReading` when a counter reading is lower than one
/// recorded before it and nobody has answered yet, before the step writes anything.
/// Screens ask with `.readingPrompt` and save again with the answer; nothing was saved.
public struct LowerReadingQuestion: StepQuestion, Equatable, Sendable {
    public let previous: Double
    public let previousDate: Date
    public let value: Double
    public let unit: MeasurementUnit?

    /// "Kilometrajul e mai mic decât ultima dată. Corectez citirea veche?"
    public var question: String {
        unit == .kilometres
            ? String(localized: "Kilometrajul e mai mic decât ultima dată. Corectez citirea veche?", comment: "Asked when a kilometre reading is lower than an earlier one.")
            : String(localized: "Citirea e mai mică decât ultima dată. Corectez citirea veche?", comment: "Asked when a counter reading (a meter, engine hours) is lower than an earlier one.")
    }

    /// What each answer does, with both numbers.
    public var explanation: String {
        let before = MeasurementUnit.written(previous, in: unit)
        let now = MeasurementUnit.written(value, in: unit)
        let day = DosarFormat.day(previousDate)
        return String(localized: "Ultima dată: \(before), pe \(day). Acum: \(now). Dacă o corectezi, citirea veche se șterge. Dacă o lași, cea nouă rămâne deoparte. Dacă e un contor nou, cele vechi rămân în istoric.", comment: "Explains the lower-reading question: the earlier reading, the new one, and what each of the three answers does.")
    }

    public var errorDescription: String? { question }
}

/// A reading a step will record, worked out before the step writes anything: the step asks
/// about it first (`HouseholdMutations.askAboutReading`) and then records exactly what it
/// asked about (`HouseholdMutations.recordReading`). Each action that records a reading
/// says how it plans it (`AssetActions.plannedReading`, `HistoryActions.plannedReading`,
/// `ObligationActions.plannedReading`), so a flow that wraps it asks the same question.
@MainActor
struct PlannedReading {
    let value: Double
    let asset: Asset
    let date: Date
    let source: ReadingSource
    let unit: MeasurementUnit?
    let kind: MeasurementKind
    let name: String
    /// Readings the step takes away before it records this one (the one a document recorded
    /// when it was filed before): they never make it ask.
    let replaces: @MainActor (MeasurementLog) -> Bool
    /// Whether a reading the step replaces started a new counter: this one takes its place and
    /// starts it instead, so filing the same paper again never asks about the old counter.
    /// Worked out when the step is planned, before anything is taken away.
    let continuesCounter: Bool

    init(_ value: Double, on asset: Asset, at date: Date, source: ReadingSource, unit: MeasurementUnit?,
         kind: MeasurementKind? = nil, name: String = "", replacing replaces: @escaping @MainActor (MeasurementLog) -> Bool = { _ in false }) {
        let kind = kind ?? MeasurementKind.forUnit(unit)
        self.value = value
        self.asset = asset
        self.date = date
        self.source = source
        self.unit = unit ?? kind.defaultUnit
        self.kind = kind
        self.name = name
        self.replaces = replaces
        let unit = self.unit
        self.continuesCounter = kind.isCumulative && (asset.measurements ?? []).contains {
            !$0.isDeleted && $0.startsCounter && $0.measurementUnit == unit && replaces($0)
        }
    }

    /// An estimate is never stored, and neither is a number that isn't one.
    var isStored: Bool { source != .estimate && value.isFinite }
}

/// One cleaned series of counter readings, the only input to every rate and projection
/// (`CadenceCalculator`, `MaintenanceLog`, the visit form's estimate) and to the hero
/// value. A counter only goes up, so each counter's readings are the longest run that never
/// goes down, in date order; on a tie the earlier readings win. A reading left out (a typo,
/// one kept aside) is skipped, never a reason to stop projecting.
///
/// A reading that starts a new counter ("Contor nou": a replaced meter or dashboard, one that
/// went round) splits the series: the readings from it on are the new counter's, the ones
/// before stay as the old one's (`counters`). The value now is the newest counter's; how far
/// and how fast the counters moved is added up counter by counter (`progress`, `distance`), so
/// a change of counter is never a drop or a jump.
public struct ReadingSeries: Sendable, Equatable {
    public typealias Reading = CadenceCalculator.TelemetryReading

    /// Each counter's readings that count, oldest counter first, each oldest first.
    public let counters: [[Reading]]
    /// The readings that count, every counter's, oldest first. The first of each counter after
    /// the first says it starts one, so a series made again from them splits the same way.
    public let readings: [Reading]
    /// Readings that break the order of their counter and are left out.
    public let setAside: [Reading]
    /// When each counter after the first starts: the moment of the reading that started it.
    public let counterStarts: [Date]

    public init(_ raw: [Reading], cumulative: Bool = true) {
        guard cumulative else {
            let ordered = raw.sorted { ($0.date, $0.metric) < ($1.date, $1.metric) }
            counters = ordered.isEmpty ? [] : [ordered]
            readings = ordered
            setAside = []
            counterStarts = []
            return
        }
        let split = Self.split(raw, date: \.date, metric: \.metric, startsCounter: \.startsCounter)
        var counters: [[Reading]] = []
        var setAside: [Reading] = []
        for readings in split {
            let run = Self.longestRun(readings)
            counters.append(run.kept)
            setAside += run.left
        }
        self.counters = counters
        self.setAside = setAside
        self.counterStarts = split.dropFirst().compactMap { $0.first?.date }
        self.readings = counters.enumerated().flatMap { index, readings in
            readings.enumerated().map { position, reading in
                Reading(date: reading.date, metric: reading.metric, startsCounter: index > 0 && position == 0)
            }
        }
    }

    /// The counter now: the last reading of the newest counter.
    public var current: Double? { latest?.metric }
    public var latest: Reading? { counters.last?.last }

    /// How far the counters moved and over how many days, counter by counter: each counter's
    /// last reading less its first, over the days between them, added up. The days between one
    /// counter's last reading and the next one's first count for neither, since how far it went
    /// then isn't known. Nil when no counter has two readings. `days` measures the time between
    /// two moments (in days of 24 hours unless told otherwise).
    public func progress(days: (Date, Date) -> Double = { $1.timeIntervalSince($0) / 86_400 }) -> (distance: Double, days: Double)? {
        let measured = counters.filter { $0.count >= 2 }
        guard !measured.isEmpty else { return nil }
        var distance = 0.0, elapsed = 0.0
        for readings in measured {
            distance += readings[readings.count - 1].metric - readings[0].metric
            elapsed += days(readings[0].date, readings[readings.count - 1].date)
        }
        return (distance, elapsed)
    }

    /// How far the counter moved from `start` to `end` (each a value at a moment): on one
    /// counter, the difference; across a new counter, what the old one moved after `start`,
    /// every counter between it whole, and what the new one moved up to `end`. Never below zero.
    public func distance(from start: (date: Date, metric: Double), to end: (date: Date, metric: Double)) -> Double {
        let first = counter(at: start.date), last = counter(at: end.date)
        guard first < last, counters.indices.contains(first), counters.indices.contains(last) else {
            return max(0, end.metric - start.metric)
        }
        var moved = max(0, (counters[first].last?.metric ?? start.metric) - start.metric)
        for index in (first + 1)..<last {
            if let from = counters[index].first, let to = counters[index].last { moved += to.metric - from.metric }
        }
        moved += max(0, end.metric - (counters[last].first?.metric ?? end.metric))
        return moved
    }

    /// The counter a value read at `date` belongs to: the newest one started on or before it.
    public func counter(at date: Date) -> Int {
        counterStarts.filter { $0 <= date }.count
    }

    /// Readings in the one order every counter is read in, split where a new counter starts:
    /// by date, a reading that starts a counter first among those at the same moment, then by
    /// value. The one rule for the series, for the question a lower reading asks and for the
    /// repairs.
    static func split<T>(_ items: [T], date: (T) -> Date, metric: (T) -> Double, startsCounter: (T) -> Bool) -> [[T]] {
        let ordered = items.sorted {
            (date($0), startsCounter($0) ? 0 : 1, metric($0)) < (date($1), startsCounter($1) ? 0 : 1, metric($1))
        }
        var counters: [[T]] = []
        for item in ordered {
            if counters.isEmpty || startsCounter(item) {
                counters.append([item])
            } else {
                counters[counters.count - 1].append(item)
            }
        }
        return counters
    }

    /// The longest run of `ordered` that never goes down (ties keep the earlier readings), and
    /// what is left out.
    private static func longestRun(_ ordered: [Reading]) -> (kept: [Reading], left: [Reading]) {
        guard ordered.count > 1 else { return (ordered, []) }
        var length = Array(repeating: 1, count: ordered.count)
        var previous = Array(repeating: -1, count: ordered.count)
        for i in ordered.indices {
            for j in 0..<i where ordered[j].metric <= ordered[i].metric && length[j] + 1 > length[i] {
                length[i] = length[j] + 1
                previous[i] = j
            }
        }
        var end = 0
        for i in ordered.indices where length[i] > length[end] { end = i }
        var kept = Set<Int>()
        var index = end
        while index >= 0 {
            kept.insert(index)
            index = previous[index]
        }
        return (ordered.indices.filter { kept.contains($0) }.map { ordered[$0] },
                ordered.indices.filter { !kept.contains($0) }.map { ordered[$0] })
    }
}

extension HouseholdMutations {
    /// The asset's readings in `unit` (all units when nil), as the one cleaned series.
    static func readingSeries(of asset: Asset, unit: MeasurementUnit?) -> ReadingSeries {
        let logs = (asset.measurements ?? []).filter { !$0.isDeleted && (unit == nil || $0.measurementUnit == unit) }
        let cumulative = logs.allSatisfy(\.kind.isCumulative)
        return ReadingSeries(logs.map { .init(date: $0.recordedAt, metric: $0.value, startsCounter: $0.startsCounter) }, cumulative: cumulative)
    }

    /// The asset's counter readings in `unit`, counter by counter, in the series' order
    /// (`ReadingSeries.split`): every reading, the ones a counter leaves out too.
    static func counters(of asset: Asset, unit: MeasurementUnit?) -> [[MeasurementLog]] {
        let logs = (asset.measurements ?? []).filter { !$0.isDeleted && $0.kind.isCumulative && $0.measurementUnit == unit }
        return ReadingSeries.split(logs, date: \.recordedAt, metric: \.value, startsCounter: \.startsCounter)
    }

    /// The reading that started the counter in use now ("Contor nou"), when the person said a
    /// new one started; nil while the section has had one counter.
    static func counterStart(of asset: Asset, unit: MeasurementUnit?) -> MeasurementLog? {
        counters(of: asset, unit: unit).last?.first.flatMap { $0.startsCounter ? $0 : nil }
    }

    /// The one way to record a reading on an asset, for every action: the edit form, the
    /// visit form, "Gata", capture and examples. Doesn't save.
    ///
    /// - An estimate is never stored (returns nil).
    /// - A counter reading lower than one recorded before its date, on the same counter, asks
    ///   first: without `answer` it throws `LowerReadingQuestion`; `.correctOld` removes the
    ///   higher earlier readings (and the visit readings that logged them); `.keepAside` keeps
    ///   the new one, which the series then leaves aside; `.newCounter` makes the new one the
    ///   first of a new counter (`MeasurementLog.startsCounter`), so the higher ones stay as the
    ///   old counter's and count no more. An action asks before its unit of work writes
    ///   anything (`askAboutReading`, with the same `PlannedReading`), so inside a unit this
    ///   only ever finds the question already answered.
    /// - The hero value is then worked out from the readings.
    @discardableResult
    static func recordReading(
        _ value: Double,
        on asset: Asset,
        at date: Date,
        source: ReadingSource,
        unit: MeasurementUnit?,
        kind: MeasurementKind? = nil,
        name: String = "",
        answer: LowerReadingAnswer? = nil,
        isExample: Bool? = nil,
        in context: ModelContext
    ) throws -> MeasurementLog? {
        try recordReading(PlannedReading(value, on: asset, at: date, source: source, unit: unit, kind: kind, name: name),
                          answer: answer, isExample: isExample, in: context)
    }

    /// Records `reading` as planned: the same reading the step asked about before its unit opened.
    @discardableResult
    static func recordReading(_ reading: PlannedReading, answer: LowerReadingAnswer?, isExample: Bool? = nil,
                              in context: ModelContext) throws -> MeasurementLog? {
        guard reading.isStored else { return nil }
        try askAboutReading(reading, answer: answer)
        let asset = reading.asset
        let higher = higherReadings(than: reading)
        let log = MeasurementLog(kind: reading.kind, name: reading.name, value: reading.value, unit: reading.unit, recordedAt: reading.date)
        log.isExample = isExample ?? asset.isExample
        log.startsCounter = reading.continuesCounter || (answer == .newCounter && !higher.isEmpty)
        context.insert(log)
        log.asset = asset
        // Taken away once the new reading is in, so a counter one of them started passes on to it.
        if answer == .correctOld {
            for old in higher { removeReading(old, from: asset, in: context) }
        }
        syncHeroMetric(of: asset, in: context)
        return log
    }

    /// Asks the question recording `reading` raises, without changing anything: the one rule
    /// for a lower counter, which every action calls before its unit of work writes anything
    /// (`StepQuestion`). Throws `LowerReadingQuestion` when a counter reading is lower than one
    /// recorded on or before its day on the same counter and `answer` is nil; returns otherwise.
    /// Nil `reading`: the step records none.
    static func askAboutReading(_ reading: PlannedReading?, answer: LowerReadingAnswer?) throws {
        guard let reading, reading.isStored, answer == nil,
              let highest = higherReadings(than: reading).max(by: { $0.value < $1.value }) else { return }
        throw LowerReadingQuestion(previous: highest.value, previousDate: highest.recordedAt, value: reading.value, unit: reading.unit)
    }

    /// The counter readings recording `reading` would find higher than it: on its counter
    /// (from the newest "Contor nou" on or before its day), recorded on or before its day. What
    /// makes it ask first, and what `.correctOld` removes; the one rule `recordReading` and the
    /// question share. Readings the step replaces first don't count, and a reading that takes
    /// the place of one that started a counter starts it, so nothing comes before it.
    private static func higherReadings(than reading: PlannedReading) -> [MeasurementLog] {
        guard reading.kind.isCumulative, !reading.continuesCounter else { return [] }
        let unit = reading.unit
        let logs = (reading.asset.measurements ?? []).filter {
            !$0.isDeleted && $0.measurementUnit == unit && $0.kind.isCumulative && $0.recordedAt <= reading.date && !reading.replaces($0)
        }
        let start = logs.filter(\.startsCounter).map(\.recordedAt).max()
        return logs.filter { log in log.value > reading.value && (start.map { log.recordedAt >= $0 } ?? true) }
    }

    /// Takes back the reading a history entry recorded (a visit, "Gata"): the logs with the
    /// entry's date and reading, then works the hero value out again.
    static func removeReading(recordedBy entry: HistoryEntry, in context: ModelContext) {
        guard let asset = entry.asset, entry.metricReading != nil else { return }
        for log in (asset.measurements ?? []) where !log.isDeleted && isReading(log, recordedBy: entry) {
            deleteReading(log, in: context)
        }
        syncHeroMetric(of: asset, in: context)
    }

    /// Whether `log` is the reading `entry` recorded: its day and its number.
    static func isReading(_ log: MeasurementLog, recordedBy entry: HistoryEntry) -> Bool {
        guard let reading = entry.metricReading else { return false }
        return log.recordedAt == entry.occurredAt && log.value == reading && log.asset?.id == entry.asset?.id
    }

    /// Removes a wrong reading, and the same number on the visit that logged it.
    static func removeReading(_ log: MeasurementLog, from asset: Asset, in context: ModelContext) {
        for entry in asset.history ?? [] where entry.occurredAt == log.recordedAt && entry.metricReading == log.value {
            entry.metricReading = nil
        }
        deleteReading(log, in: context)
    }

    /// The one way a reading goes. A reading that started a new counter hands that on to the
    /// next reading of the same counter, so the counter stays as long as one of its readings
    /// does; with none left, the change is no longer known and the next lower reading asks
    /// again. Doesn't work the hero value out again.
    static func deleteReading(_ log: MeasurementLog, in context: ModelContext) {
        if log.startsCounter, let asset = log.asset,
           let counter = counters(of: asset, unit: log.measurementUnit).first(where: { $0.first?.id == log.id }), counter.count > 1 {
            counter[1].startsCounter = true
        }
        context.delete(log)
    }

    /// Keeps the hero field equal to the readings: for a counter, the last reading of the
    /// cleaned series (of the counter in use); for anything else (a weight), the newest.
    /// Leaves it alone when there are no readings in its unit. Readings are the source of truth.
    static func syncHeroMetric(of asset: Asset, in context: ModelContext) {
        guard let template = try? TemplateStore(context: context).template(forKey: asset.templateKey),
              let field = heroMetricField(of: template.definition) else { return }
        let series = readingSeries(of: asset, unit: field.unit)
        guard let current = series.current, asset.values[field.key]?.numberValue != current else { return }
        var values = asset.values
        values[field.key] = .number(current)
        asset.values = values
    }
}
