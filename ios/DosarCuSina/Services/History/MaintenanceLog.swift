import Foundation
import SwiftData

/// One line item with the facts of the history entry it belongs to, as plain values.
public struct HistoryItemSnapshot: Hashable, Sendable, Identifiable {
    public var id: UUID
    public var entryId: UUID
    public var assetId: UUID?
    public var componentKey: String?
    public var name: String
    public var occurredAt: Date
    /// The entry's counter reading (km, engine hours) at the time.
    public var metricReading: Double?
    public var cost: Money?
    public var partBrandOrCode: String?
    public var supplierName: String?
    /// Who did the work (the entry's providers).
    public var providerNames: [String]
    public var providerIds: [UUID]

    public init(
        id: UUID = UUID(),
        entryId: UUID = UUID(),
        assetId: UUID? = nil,
        componentKey: String?,
        name: String,
        occurredAt: Date,
        metricReading: Double? = nil,
        cost: Money? = nil,
        partBrandOrCode: String? = nil,
        supplierName: String? = nil,
        providerNames: [String] = [],
        providerIds: [UUID] = []
    ) {
        self.id = id
        self.entryId = entryId
        self.assetId = assetId
        self.componentKey = componentKey
        self.name = name
        self.occurredAt = occurredAt
        self.metricReading = metricReading
        self.cost = cost
        self.partBrandOrCode = partBrandOrCode
        self.supplierName = supplierName
        self.providerNames = providerNames
        self.providerIds = providerIds
    }
}

/// The answer to "when did I last change it".
public struct ComponentOccurrence: Hashable, Sendable {
    public var entryId: UUID
    public var componentKey: String
    public var name: String
    public var date: Date
    /// Counter reading when it was done.
    public var metricAtTime: Double?
    /// How far the counter has moved since ("acum 18.200 km").
    public var metricSince: Double?
    public var daysSince: Int
    public var cost: Money?
    public var partBrandOrCode: String?
    public var supplierName: String?
    public var providerNames: [String]
    public var providerIds: [UUID]
}

/// A guess at the next time a component needs doing.
public struct NextEstimate: Hashable, Sendable {
    public enum Basis: String, Sendable {
        /// From the typical distance and how fast the counter has been moving.
        case distance
        /// From the typical time between jobs.
        case time
    }

    public var day: CalendarDay
    public var metric: Double?
    public var basis: Basis
    /// How many past intervals it rests on; show it as an estimate either way.
    public var sampleCount: Int
}

/// How often a component is usually replaced, from the asset's own history.
public struct TypicalInterval: Hashable, Sendable {
    /// Median counter distance between replacements.
    public var metric: Double?
    /// Median days between replacements.
    public var days: Int?
    /// How many replacements the estimate rests on.
    public var sampleCount: Int
}

/// Pure questions about an asset's maintenance history.
public enum MaintenanceLog {
    /// Every time the component was done, newest first. How far the counter moved since is
    /// counted over `readings`' counters (`ReadingSeries.distance`), so a new meter or
    /// dashboard since then is never a drop.
    public static func occurrences(
        of componentKey: String,
        in items: [HistoryItemSnapshot],
        currentMetric: Double? = nil,
        readings: [CadenceCalculator.TelemetryReading] = [],
        now: Date = Date(),
        calendar: Calendar = .dosar
    ) -> [ComponentOccurrence] {
        let today = CalendarDay(now, calendar: calendar)
        let series = ReadingSeries(readings)
        return items
            .filter { $0.componentKey == componentKey }
            .sorted { $0.occurredAt > $1.occurredAt }
            .map { item in
                ComponentOccurrence(
                    entryId: item.entryId,
                    componentKey: componentKey,
                    name: item.name,
                    date: item.occurredAt,
                    metricAtTime: item.metricReading,
                    metricSince: both(currentMetric, item.metricReading).map { current, then in
                        series.distance(from: (item.occurredAt, then), to: (now, current))
                    },
                    daysSince: CalendarDay(item.occurredAt, calendar: calendar).days(to: today, calendar: calendar),
                    cost: item.cost,
                    partBrandOrCode: item.partBrandOrCode,
                    supplierName: item.supplierName,
                    providerNames: item.providerNames,
                    providerIds: item.providerIds
                )
            }
    }

    public static func lastOccurrence(
        of componentKey: String,
        in items: [HistoryItemSnapshot],
        currentMetric: Double? = nil,
        readings: [CadenceCalculator.TelemetryReading] = [],
        now: Date = Date(),
        calendar: Calendar = .dosar
    ) -> ComponentOccurrence? {
        occurrences(of: componentKey, in: items, currentMetric: currentMetric, readings: readings, now: now, calendar: calendar).first
    }

    /// The median gap between consecutive replacements, in counter units and days.
    /// Needs at least two occurrences. The distance between two jobs is counted over
    /// `readings`' counters, so one before a new meter or dashboard and one after still pair.
    public static func typicalInterval(of componentKey: String, in items: [HistoryItemSnapshot],
                                       readings: [CadenceCalculator.TelemetryReading] = [], calendar: Calendar = .dosar) -> TypicalInterval? {
        let ordered = items.filter { $0.componentKey == componentKey }.sorted { $0.occurredAt < $1.occurredAt }
        guard ordered.count >= 2 else { return nil }
        let series = ReadingSeries(readings)
        let pairs = zip(ordered, ordered.dropFirst())
        let days = pairs.map { CalendarDay($0.occurredAt, calendar: calendar).days(to: CalendarDay($1.occurredAt, calendar: calendar), calendar: calendar) }
        let metrics = pairs.compactMap { pair -> Double? in
            guard let a = pair.0.metricReading, let b = pair.1.metricReading else { return nil }
            let moved = series.distance(from: (pair.0.occurredAt, a), to: (pair.1.occurredAt, b))
            return moved > 0 ? moved : nil
        }
        return TypicalInterval(metric: median(metrics), days: median(days.map(Double.init)).map { Int($0.rounded()) }, sampleCount: ordered.count - 1)
    }

    /// How far the counter moves in 30 days, from readings that span at least
    /// `minimumSpanDays`, over the one cleaned series (`ReadingSeries.progress`): a reading
    /// that breaks the order is skipped, and each counter counts on its own, so a new meter
    /// or dashboard is never a drop or a jump. Nil when there isn't enough to say honestly.
    public static func monthlyRate(_ readings: [CadenceCalculator.TelemetryReading], minimumSpanDays: Int = 30) -> Double? {
        guard let progress = ReadingSeries(readings).progress(),
              progress.days >= Double(minimumSpanDays), progress.distance > 0 else { return nil }
        return progress.distance / progress.days * 30
    }

    /// When a component will probably need doing again, from its own history.
    /// Uses the typical distance and the recent pace of the counter when both are
    /// known, else the typical time between jobs. Nil when there are fewer than two
    /// past jobs: one job is not a pattern.
    public static func nextEstimate(
        of componentKey: String,
        in items: [HistoryItemSnapshot],
        readings: [CadenceCalculator.TelemetryReading] = [],
        currentMetric: Double? = nil,
        now: Date = Date(),
        calendar: Calendar = .dosar
    ) -> NextEstimate? {
        let current = currentMetric ?? ReadingSeries(readings).current
        guard let typical = typicalInterval(of: componentKey, in: items, readings: readings, calendar: calendar),
              let last = lastOccurrence(of: componentKey, in: items, currentMetric: current, readings: readings, now: now, calendar: calendar) else { return nil }
        let today = CalendarDay(now, calendar: calendar)
        let lastDay = CalendarDay(last.date, calendar: calendar)
        // On the counter in use now: what is left of the usual distance since the last job,
        // added to where the counter is (on one counter, the last job's reading plus the usual).
        let dueMetric = both(current, last.metricSince).flatMap { current, since in typical.metric.map { current + $0 - since } }
            ?? both(last.metricAtTime, typical.metric).map { $0 + $1 }

        if let dueMetric, let rate = monthlyRate(readings), let current {
            let days = Int(((dueMetric - current) / rate * 30).rounded())
            return NextEstimate(day: today.adding(days: max(0, days), calendar: calendar), metric: dueMetric, basis: .distance, sampleCount: typical.sampleCount)
        }
        if let days = typical.days {
            return NextEstimate(day: lastDay.adding(days: days, calendar: calendar), metric: dueMetric, basis: .time, sampleCount: typical.sampleCount)
        }
        return nil
    }

    /// Components that have history, newest activity first.
    public static func trackedComponents(in items: [HistoryItemSnapshot]) -> [String] {
        var latest: [String: Date] = [:]
        for item in items {
            guard let key = item.componentKey else { continue }
            latest[key] = max(latest[key] ?? .distantPast, item.occurredAt)
        }
        return latest.sorted { $0.value > $1.value }.map(\.key)
    }

    static func median(_ values: [Double]) -> Double? {
        guard !values.isEmpty else { return nil }
        let sorted = values.sorted()
        let middle = sorted.count / 2
        return sorted.count.isMultiple(of: 2) ? (sorted[middle - 1] + sorted[middle]) / 2 : sorted[middle]
    }

    private static func both(_ a: Double?, _ b: Double?) -> (Double, Double)? {
        guard let a, let b else { return nil }
        return (a, b)
    }
}

extension HistoryItemSnapshot {
    /// Line items of one asset's history. Reads the records only, on whatever
    /// context they belong to (search builds its index off the main thread).
    public static func items(of asset: Asset) -> [HistoryItemSnapshot] {
        (asset.history ?? []).flatMap { entry in
            (entry.items ?? []).map { item in
                HistoryItemSnapshot(
                    id: item.id,
                    entryId: entry.id,
                    assetId: asset.id,
                    componentKey: item.componentKey,
                    name: item.name,
                    occurredAt: entry.occurredAt,
                    metricReading: entry.metricReading,
                    cost: item.totalCost,
                    partBrandOrCode: item.partBrandOrCode,
                    supplierName: item.supplier?.name,
                    providerNames: entry.providerNames,
                    providerIds: entry.providerIds
                )
            }
        }
    }
}
