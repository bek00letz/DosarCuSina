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

/// The person's answer when a counter reading is lower than an earlier one.
public enum LowerReadingAnswer: Sendable, Hashable {
    /// "Corectează citirea veche": the earlier, higher readings were wrong. They go, and the new one counts.
    case correctOld
    /// "Lasă citirea veche": the new reading is kept aside. It stays in the list but doesn't count
    /// while the readings before it are higher.
    case keepAside
}

/// Thrown by `HouseholdMutations.recordReading` when a counter reading is lower than one
/// recorded before it and nobody has answered yet. Screens ask with `.readingPrompt`
/// and save again with the answer; nothing was saved.
public struct LowerReadingQuestion: LocalizedError, Equatable, Sendable {
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
        return String(localized: "Ultima dată: \(before), pe \(day). Acum: \(now). Dacă o corectezi, citirea veche se șterge. Dacă o lași, cea nouă rămâne deoparte.", comment: "Explains the lower-reading question: the earlier reading, the new one, and what each answer does.")
    }

    public var errorDescription: String? { question }
}

/// One cleaned series of counter readings, the only input to every rate and projection
/// (`CadenceCalculator`, `MaintenanceLog`, the visit form's estimate) and to the hero
/// value. A counter only goes up, so the series is the longest run of readings that never
/// goes down, in date order; on a tie the earlier readings win. A reading left out (a
/// typo, one kept aside) is skipped, never a reason to stop projecting.
public struct ReadingSeries: Sendable, Equatable {
    public typealias Reading = CadenceCalculator.TelemetryReading

    /// The readings that count, oldest first.
    public let readings: [Reading]
    /// Readings that break the order and are left out.
    public let setAside: [Reading]

    public init(_ raw: [Reading], cumulative: Bool = true) {
        let ordered = raw.sorted { ($0.date, $0.metric) < ($1.date, $1.metric) }
        guard cumulative, ordered.count > 1 else {
            readings = ordered
            setAside = []
            return
        }
        // Longest non-decreasing run by date. Ties keep the earlier readings.
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
        readings = ordered.indices.filter { kept.contains($0) }.map { ordered[$0] }
        setAside = ordered.indices.filter { !kept.contains($0) }.map { ordered[$0] }
    }

    /// The counter now: the last reading that counts.
    public var current: Double? { readings.last?.metric }
    public var latest: Reading? { readings.last }
}

extension HouseholdMutations {
    /// The asset's readings in `unit` (all units when nil), as the one cleaned series.
    static func readingSeries(of asset: Asset, unit: MeasurementUnit?) -> ReadingSeries {
        let logs = (asset.measurements ?? []).filter { !$0.isDeleted && (unit == nil || $0.measurementUnit == unit) }
        let cumulative = logs.allSatisfy(\.kind.isCumulative)
        return ReadingSeries(logs.map { .init(date: $0.recordedAt, metric: $0.value) }, cumulative: cumulative)
    }

    /// The one way to record a reading on an asset, for every action: the edit form, the
    /// visit form, "Gata", capture and examples. Doesn't save.
    ///
    /// - An estimate is never stored (returns nil).
    /// - A counter reading lower than one recorded before its date asks first: without
    ///   `answer` it throws `LowerReadingQuestion`; `.correctOld` removes the higher earlier
    ///   readings (and the visit readings that logged them); `.keepAside` keeps the new one,
    ///   which the series then leaves aside.
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
        guard source != .estimate, value.isFinite else { return nil }
        let kind = kind ?? MeasurementKind.forUnit(unit)
        let unit = unit ?? kind.defaultUnit
        if kind.isCumulative {
            let earlier = (asset.measurements ?? []).filter {
                !$0.isDeleted && $0.measurementUnit == unit && $0.kind.isCumulative && $0.recordedAt <= date
            }
            let higher = earlier.filter { $0.value > value }
            if let highest = higher.max(by: { $0.value < $1.value }) {
                switch answer {
                case nil:
                    throw LowerReadingQuestion(previous: highest.value, previousDate: highest.recordedAt, value: value, unit: unit)
                case .correctOld?:
                    for log in higher { removeReading(log, from: asset, in: context) }
                case .keepAside?:
                    break
                }
            }
        }
        let log = MeasurementLog(kind: kind, name: name, value: value, unit: unit, recordedAt: date)
        log.isExample = isExample ?? asset.isExample
        context.insert(log)
        log.asset = asset
        syncHeroMetric(of: asset, in: context)
        return log
    }

    /// Takes back the reading a history entry recorded (a visit, "Gata"): the logs with the
    /// entry's date and reading, then works the hero value out again.
    static func removeReading(recordedBy entry: HistoryEntry, in context: ModelContext) {
        guard let asset = entry.asset, let reading = entry.metricReading else { return }
        for log in (asset.measurements ?? []) where !log.isDeleted && log.recordedAt == entry.occurredAt && log.value == reading {
            context.delete(log)
        }
        syncHeroMetric(of: asset, in: context)
    }

    /// Removes a wrong reading, and the same number on the visit that logged it.
    static func removeReading(_ log: MeasurementLog, from asset: Asset, in context: ModelContext) {
        for entry in asset.history ?? [] where entry.occurredAt == log.recordedAt && entry.metricReading == log.value {
            entry.metricReading = nil
        }
        context.delete(log)
    }

    /// Keeps the hero field equal to the readings: for a counter, the last reading of the
    /// cleaned series; for anything else (a weight), the newest. Leaves it alone when there
    /// are no readings in its unit. Readings are the source of truth.
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
