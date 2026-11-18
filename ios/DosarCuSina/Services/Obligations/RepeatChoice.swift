import Foundation

/// What "Se repetă" edits (`DSRepeatField`): never, or every so many days, weeks, months or
/// years, counted from the due day or from the day it was done. It is a plain view of a
/// `RecurrenceRule` of that shape and writes one back; a deadline that repeats on fixed dates,
/// by a counter or by a legal rule has no choice here (`init?(rule:)` is nil) and shows its
/// rule in words only (`RepeatWording.sentence`).
public struct RepeatChoice: Hashable, Sendable {
    /// "Nu se repetă", "Zilnic", "Săptămânal", "Lunar", "Anual".
    public enum Frequency: String, CaseIterable, Identifiable, Hashable, Sendable {
        case never, day, week, month, year

        public var id: String { rawValue }

        public var unit: RecurrenceInterval.Unit? {
            switch self {
            case .never: nil
            case .day: .day
            case .week: .week
            case .month: .month
            case .year: .year
            }
        }

        init(_ unit: RecurrenceInterval.Unit) {
            switch unit {
            case .day: self = .day
            case .week: self = .week
            case .month: self = .month
            case .year: self = .year
            }
        }
    }

    public var frequency: Frequency
    /// How many of the unit: "la fiecare 3 zile" is 3. At least 1.
    public var every: Int
    /// What the next due day counts from: the due day (a payment, every cycle its own) or the
    /// day it was done (watering, a service).
    public var anchor: RecurrenceAnchor

    public static let never = RepeatChoice(frequency: .never, every: 1, anchor: .dueDate)

    public init(frequency: Frequency, every: Int = 1, anchor: RecurrenceAnchor? = nil) {
        self.frequency = frequency
        self.every = frequency.unit.map { RecurrenceInterval.allowed(every, in: $0) } ?? max(1, every)
        self.anchor = anchor ?? frequency.unit.map(Self.usualAnchor) ?? .dueDate
    }

    /// The choice a rule is, when it is one this control offers: never, or an interval.
    public init?(rule: RecurrenceRule) {
        switch rule {
        case .none:
            self = .never
        case .interval(let interval, let anchor):
            self.init(frequency: Frequency(interval.unit), every: interval.every, anchor: anchor)
        case .fixedDates, .metric, .legal, .unreadable:
            return nil
        }
    }

    public var repeats: Bool { frequency != .never }

    /// The rule this choice is.
    public var rule: RecurrenceRule {
        guard let unit = frequency.unit else { return .none }
        return .interval(RecurrenceInterval(every: every, unit: unit), anchor: anchor)
    }

    /// The same choice repeating by `frequency`. From "Nu se repetă" it starts at one of the
    /// unit, counted the way that unit usually is (`usualAnchor`); between units it keeps the
    /// number (within the new unit's range) and what it counts from.
    public func choosing(_ frequency: Frequency) -> RepeatChoice {
        guard frequency != self.frequency else { return self }
        guard let unit = frequency.unit else { return RepeatChoice(frequency: .never, every: 1, anchor: anchor) }
        guard repeats else { return RepeatChoice(frequency: frequency) }
        return RepeatChoice(frequency: frequency, every: min(every, Self.upperBound(for: unit)), anchor: anchor)
    }

    /// What a new repeat counts from by default: something done every few days or weeks
    /// (watering, a filter) from the day it was done, so a late one doesn't leave the next
    /// already late; a monthly or yearly one from its due day, like a payment.
    public static func usualAnchor(for unit: RecurrenceInterval.Unit) -> RecurrenceAnchor {
        switch unit {
        case .day, .week: .completion
        case .month, .year: .dueDate
        }
    }

    /// The most the stepper offers for a unit: a year of days, two years of weeks, ten years
    /// of months, twenty years.
    public static func upperBound(for unit: RecurrenceInterval.Unit) -> Int {
        switch unit {
        case .day: 365
        case .week: 104
        case .month: 120
        case .year: 20
        }
    }

    /// The numbers the stepper offers, holding a larger number a rule already has, never past
    /// the longest an interval can be (`RecurrenceInterval.longest(in:)`).
    public var everyRange: ClosedRange<Int> {
        guard let unit = frequency.unit else { return 1...1 }
        return 1...min(max(Self.upperBound(for: unit), every), RecurrenceInterval.longest(in: unit))
    }

    /// The numbers „+” and „−” stop at, in the unit's own steps: days one by one to two weeks,
    /// then whole weeks to eight, then about a month at a time (60, 90 … 360); weeks one by one
    /// to twelve, then four at a time to a year, then half a year; months one by one to a year,
    /// then a quarter to two years, then a year; years one by one. So 7, 14 and 21 days, a
    /// quarter of months and a year of weeks are each a step away, and a year of days is a few
    /// dozen steps, never 364.
    public static func ladder(for unit: RecurrenceInterval.Unit) -> [Int] {
        switch unit {
        case .day: Array(1...13) + Array(stride(from: 14, through: 56, by: 7)) + Array(stride(from: 60, through: 360, by: 30))
        case .week: Array(1...12) + Array(stride(from: 16, through: 52, by: 4)) + [78, 104]
        case .month: Array(1...12) + [15, 18, 21, 24] + Array(stride(from: 36, through: 120, by: 12))
        case .year: Array(1...20)
        }
    }

    /// The number „+” or „−” gives after `value` (a tap, a held press or a VoiceOver swipe): the
    /// next stop of the unit's ladder (`ladder(for:)`) above or below it, so a number between two
    /// stops (a rule's 40 days) goes to the nearest one each way, and the range's ends are stops
    /// too. It stays inside `range`.
    public static func stepped(_ value: Int, up: Bool, unit: RecurrenceInterval.Unit, in range: ClosedRange<Int>) -> Int {
        let stops = ladder(for: unit) + [range.lowerBound, range.upperBound]
        let next = up ? stops.filter { $0 > value }.min() : stops.filter { $0 < value }.max()
        return min(max(next ?? value, range.lowerBound), range.upperBound)
    }
}
