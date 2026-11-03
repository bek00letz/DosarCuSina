import Foundation

/// A calendar day with no time or time zone, such as an expiry date or a due date.
///
/// Encodes as `"yyyy-MM-dd"` so the same day means the same thing on every
/// device and platform, whatever the time zone.
public struct CalendarDay: Hashable, Comparable, Sendable, Codable, CustomStringConvertible {
    public var year: Int
    public var month: Int
    public var day: Int

    public init(year: Int, month: Int, day: Int) {
        self.year = year
        self.month = month
        self.day = day
    }

    /// The day that contains `date` in `calendar`'s time zone.
    public init(_ date: Date, calendar: Calendar = .current) {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        self.init(year: parts.year ?? 1970, month: parts.month ?? 1, day: parts.day ?? 1)
    }

    /// Parses `"yyyy-MM-dd"`. Also accepts a full ISO 8601 timestamp and keeps its date part.
    public init?(isoString: String) {
        let datePart = isoString.prefix(10)
        let parts = datePart.split(separator: "-")
        guard parts.count == 3,
              let year = Int(parts[0]), let month = Int(parts[1]), let day = Int(parts[2]),
              (1...12).contains(month), (1...31).contains(day) else { return nil }
        self.init(year: year, month: month, day: day)
    }

    public var isoString: String {
        "\(ISODigits.padded(year, to: 4))-\(ISODigits.padded(month, to: 2))-\(ISODigits.padded(day, to: 2))"
    }

    public var description: String { isoString }

    /// Midnight at the start of this day in `calendar`'s time zone.
    public func startDate(in calendar: Calendar = .current) -> Date {
        var parts = DateComponents()
        parts.year = year
        parts.month = month
        parts.day = day
        return calendar.date(from: parts) ?? Date(timeIntervalSince1970: 0)
    }

    /// Noon on this day in `calendar`'s time zone. Stored dates use noon so the
    /// day survives travel across time zones up to ±11 hours.
    public func noonDate(in calendar: Calendar = .current) -> Date {
        calendar.date(byAdding: .hour, value: 12, to: startDate(in: calendar)) ?? startDate(in: calendar)
    }

    public func adding(days: Int, calendar: Calendar = .current) -> CalendarDay {
        let shifted = calendar.date(byAdding: .day, value: days, to: startDate(in: calendar)) ?? startDate(in: calendar)
        return CalendarDay(shifted, calendar: calendar)
    }

    /// The same day `months` calendar months away, or that month's last day when it is
    /// shorter (31 March less one month is 28 or 29 February).
    public func adding(months: Int, calendar: Calendar = .current) -> CalendarDay {
        let shifted = calendar.date(byAdding: .month, value: months, to: startDate(in: calendar)) ?? startDate(in: calendar)
        return CalendarDay(shifted, calendar: calendar)
    }

    /// Whole days from `self` to `other` (negative when `other` is earlier).
    public func days(to other: CalendarDay, calendar: Calendar = .current) -> Int {
        calendar.dateComponents([.day], from: startDate(in: calendar), to: other.startDate(in: calendar)).day ?? 0
    }

    public static func < (lhs: CalendarDay, rhs: CalendarDay) -> Bool {
        (lhs.year, lhs.month, lhs.day) < (rhs.year, rhs.month, rhs.day)
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let raw = try container.decode(String.self)
        guard let day = CalendarDay(isoString: raw) else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Expected yyyy-MM-dd, got \(raw)")
        }
        self = day
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(isoString)
    }
}

/// A month and day that repeats every year, such as 31 March for local taxes.
/// Encodes as `"MM-dd"`.
public struct MonthDay: Hashable, Comparable, Sendable, Codable {
    public var month: Int
    public var day: Int

    public init(month: Int, day: Int) {
        self.month = month
        self.day = day
    }

    public init?(isoString: String) {
        let parts = isoString.split(separator: "-")
        guard parts.count == 2, let month = Int(parts[0]), let day = Int(parts[1]),
              (1...12).contains(month), (1...31).contains(day) else { return nil }
        self.init(month: month, day: day)
    }

    public var isoString: String { "\(ISODigits.padded(month, to: 2))-\(ISODigits.padded(day, to: 2))" }

    /// This month-day in `year`, clamped to the month's last day (29 February becomes 28 in common years).
    public func day(inYear year: Int, calendar: Calendar = .current) -> CalendarDay {
        let probe = CalendarDay(year: year, month: month, day: 1).startDate(in: calendar)
        let length = calendar.range(of: .day, in: .month, for: probe)?.count ?? 28
        return CalendarDay(year: year, month: month, day: min(day, length))
    }

    public static func < (lhs: MonthDay, rhs: MonthDay) -> Bool {
        (lhs.month, lhs.day) < (rhs.month, rhs.day)
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let raw = try container.decode(String.self)
        guard let value = MonthDay(isoString: raw) else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Expected MM-dd, got \(raw)")
        }
        self = value
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(isoString)
    }
}

/// Digits for machine text such as ISO days: ASCII, zero-padded, never localized.
enum ISODigits {
    /// `padded(7, to: 2)` is "07"; a longer number is kept whole.
    static func padded(_ number: Int, to width: Int) -> String {
        let digits = String(number)
        return String(repeating: "0", count: max(0, width - digits.count)) + digits
    }
}
