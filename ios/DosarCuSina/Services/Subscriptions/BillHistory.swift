import Foundation
import SwiftData

/// One bill a subscription received: the day it was issued and what it came to.
public struct BillRecord: Hashable, Sendable {
    public var day: CalendarDay
    public var amount: Money?

    public init(day: CalendarDay, amount: Money?) {
        self.day = day
        self.amount = amount
    }
}

/// How a subscription's bills move, in plain words.
public struct BillTrend: Hashable, Sendable {
    public enum Direction: Hashable, Sendable { case up, down, same }

    /// The newest bill with an amount.
    public var last: BillRecord
    /// How much more or less than the one before it in the same currency; nil when there is none.
    public var change: Money?
    public var direction: Direction?
    /// What a bill came to on average over the last twelve months, one amount per currency.
    public var averageLastYear: [Money]
}

/// A bill that hasn't come when it usually does: a calm note, never an alarm.
public struct MissingBill: Hashable, Sendable {
    /// When the last one came.
    public var lastDay: CalendarDay
    /// When this one was expected.
    public var expectedDay: CalendarDay
    public var cycleMonths: Int
}

/// Pure questions about a subscription's bills: the trend of the amounts and whether
/// one is missing. No database, no dates of its own: everything comes from the bills
/// and the day it is asked on.
public enum BillHistory {

    // MARK: The trend

    public static func trend(_ bills: [BillRecord], today: CalendarDay, calendar: Calendar = .dosar) -> BillTrend? {
        let priced = bills.filter { $0.amount != nil }.sorted { $0.day < $1.day }
        guard let last = priced.last, let amount = last.amount else { return nil }
        // The one before it, in the same currency: lei are never compared with euro.
        let previous = priced.dropLast().last { $0.amount?.currency == amount.currency }?.amount
        let change = previous.map { Money(amount.amount - $0.amount, currency: amount.currency) }
        let direction: BillTrend.Direction? = change.map { $0.amount > 0 ? .up : ($0.amount < 0 ? .down : .same) }

        let yearAgo = today.adding(days: -365, calendar: calendar)
        let recent = priced.filter { $0.day > yearAgo }.compactMap(\.amount)
        let averages = Dictionary(grouping: recent, by: \.currency).sorted { $0.key < $1.key }.map { currency, amounts in
            Money((amounts.reduce(Decimal(0)) { $0 + $1.amount } / Decimal(amounts.count)).rounded(scale: 2), currency: currency)
        }
        return BillTrend(last: last, change: change, direction: direction, averageLastYear: averages)
    }

    /// "Cu 32,10 lei mai mult decât cea dinainte", or nil without one to compare with.
    public static func changeSentence(_ trend: BillTrend) -> String? {
        guard let change = trend.change, let direction = trend.direction else { return nil }
        let difference = Money(abs(change.amount), currency: change.currency).formattedCompact()
        switch direction {
        case .up: return String(localized: "Cu \(difference) mai mult decât cea dinainte.", comment: "A bill compared with the one before it.")
        case .down: return String(localized: "Cu \(difference) mai puțin decât cea dinainte.", comment: "A bill compared with the one before it.")
        case .same: return String(localized: "La fel ca cea dinainte.", comment: "A bill compared with the one before it.")
        }
    }

    // MARK: The missing bill

    /// How many days past its usual day a bill may come before it is worth a note:
    /// ten for a monthly bill, longer for longer cycles.
    static func graceDays(cycleMonths: Int) -> Int {
        min(10 * max(cycleMonths, 1), 30)
    }

    /// The most a bill has come late before, counted in days past one cycle after the
    /// previous one, so a provider that always bills a few days late isn't flagged.
    static let usualLatenessCap = 15

    /// After this many cycles without a bill, the note stops: the contract has likely
    /// ended or the bills go elsewhere, and the binder shouldn't keep saying so.
    static let cyclesToKeepSaying = 2

    /// The bill that should have come by now and hasn't, if any.
    public static func missing(_ bills: [BillRecord], cycleMonths: Int, today: CalendarDay, calendar: Calendar = .dosar) -> MissingBill? {
        let months = max(cycleMonths, 1)
        let days = Set(bills.map(\.day)).sorted()
        guard let last = days.last else { return nil }
        func cycleAfter(_ day: CalendarDay, _ cycles: Int = 1) -> CalendarDay {
            RecurrenceEngine.add(.months(months * cycles), to: day, calendar: calendar)
        }
        let usualLateness = zip(days, days.dropFirst())
            .map { previous, next in cycleAfter(previous).days(to: next, calendar: calendar) }
            .max().map { min(max($0, 0), usualLatenessCap) } ?? 0
        let expected = cycleAfter(last)
        let late = expected.days(to: today, calendar: calendar)
        guard late > graceDays(cycleMonths: months) + usualLateness else { return nil }
        guard today < cycleAfter(last, cyclesToKeepSaying + 1) else { return nil }
        return MissingBill(lastDay: last, expectedDay: expected, cycleMonths: months)
    }

    // MARK: From the binder

    /// A subscription's bills: what capture logged in its history, never the "paid"
    /// records completing a deadline writes.
    @MainActor
    public static func bills(of asset: Asset, calendar: Calendar = .dosar) -> [BillRecord] {
        (asset.history ?? [])
            .filter { $0.kind == .payment && !$0.isCompletion }
            .map { BillRecord(day: CalendarDay($0.occurredAt, calendar: calendar), amount: $0.totalCost) }
    }
}

/// The plain facts about one subscription that the missing-bill note needs.
public struct BillWatchSnapshot: Hashable, Sendable, Identifiable {
    public var id: UUID
    public var name: String
    public var provider: String?
    /// Where it is filed: the home, for a gas or electricity contract.
    public var placeName: String?
    public var service: String?
    public var cycleMonths: Int
    public var bills: [BillRecord]
    public var isSensitive: Bool
    public var isExample: Bool

    public init(id: UUID = UUID(), name: String, provider: String? = nil, placeName: String? = nil, service: String?,
                cycleMonths: Int = 1, bills: [BillRecord], isSensitive: Bool = false, isExample: Bool = false) {
        self.id = id
        self.name = name
        self.provider = provider
        self.placeName = placeName
        self.service = service
        self.cycleMonths = cycleMonths
        self.bills = bills
        self.isSensitive = isSensitive
        self.isExample = isExample
    }

    /// Every subscription in the binder (the sections of a category that plays
    /// `.subscription`), as snapshots.
    @MainActor
    public static func fetchAll(in context: ModelContext, calendar: Calendar = .dosar) throws -> [BillWatchSnapshot] {
        let templates = try TemplateStore(context: context).templatesByKey()
        let keys = Array(templates.values.keys(playing: .subscription))
        let subscriptions = try context.fetch(FetchDescriptor<Asset>(predicate: #Predicate { keys.contains($0.templateKey) }))
        return subscriptions.map { asset in
            let values = asset.values
            return BillWatchSnapshot(
                id: asset.id,
                name: asset.name,
                provider: values[SubscriptionFields.provider]?.textValue,
                placeName: asset.parent?.name,
                service: SubscriptionFields.service(of: values),
                cycleMonths: BillingCycle.months(values[SubscriptionFields.cycle]?.textValue),
                bills: BillHistory.bills(of: asset, calendar: calendar),
                // Locked when its category is, or the section it is filed under.
                isSensitive: [asset.templateKey, asset.parent?.templateKey].compactMap { $0 }.contains { templates[$0]?.isSensitive == true },
                isExample: asset.isExample
            )
        }
    }
}
