import Foundation

/// A calendar day with no time or time zone, such as an expiry date or a due date.
///
/// Encodes as `"yyyy-MM-dd"` so the same day means the same thing on every
/// device and platform, whatever the time zone. Its numbers are Gregorian, and so is its
/// arithmetic: it counts in the app's calendar (`Calendar.dosar`) unless told another one.
public struct CalendarDay: Hashable, Comparable, Sendable, Codable, CustomStringConvertible {
    public var year: Int
    public var month: Int
    public var day: Int

    public init(year: Int, month: Int, day: Int) {
        self.year = year
        self.month = month
        self.day = day
    }

    /// The day with these numbers, or nil when the calendar has no such day: 31 February,
    /// month 13, day 0. For numbers read from outside (a page, an answer); a day the app
    /// works out itself uses ``init(year:month:day:)``.
    public init?(validYear year: Int, month: Int, day: Int) {
        guard (1...12).contains(month), day >= 1,
              day <= CalendarDay(year: year, month: month, day: 1).daysInMonth(calendar: Self.isoCalendar) else { return nil }
        self.init(year: year, month: month, day: day)
    }

    /// The calendar a day's numbers are in: Gregorian, in UTC. For arithmetic on days
    /// alone, whatever the phone's calendar or time zone.
    public static let isoCalendar = Calendar.dosar(in: TimeZone(identifier: "UTC") ?? .gmt)

    /// The day that contains `date` in `calendar`'s time zone.
    public init(_ date: Date, calendar: Calendar = .dosar) {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        self.init(year: parts.year ?? 1970, month: parts.month ?? 1, day: parts.day ?? 1)
    }

    /// Parses `"yyyy-MM-dd"`. Also accepts a full ISO 8601 timestamp and keeps its date part.
    /// A day the calendar doesn't have ("2026-02-30", "2026-04-31") is nil, like any other
    /// text that isn't a day: it would otherwise roll over into the next month.
    public init?(isoString: String) {
        let datePart = isoString.prefix(10)
        let parts = datePart.split(separator: "-")
        guard parts.count == 3,
              let year = Int(parts[0]), let month = Int(parts[1]), let day = Int(parts[2]) else { return nil }
        self.init(validYear: year, month: month, day: day)
    }

    public var isoString: String {
        MachineText.isoDay(year: year, month: month, day: day)
    }

    public var description: String { isoString }

    /// Before every day a record can hold: what a missing day sorts as.
    public static let earliest = CalendarDay(year: 0, month: 1, day: 1)

    /// Midnight at the start of this day in `calendar`'s time zone.
    public func startDate(in calendar: Calendar = .dosar) -> Date {
        var parts = DateComponents()
        parts.year = year
        parts.month = month
        parts.day = day
        return calendar.date(from: parts) ?? Date(timeIntervalSince1970: 0)
    }

    /// Noon on this day in `calendar`'s time zone. Stored dates use noon so the
    /// day survives travel across time zones up to ±11 hours.
    public func noonDate(in calendar: Calendar = .dosar) -> Date {
        calendar.date(byAdding: .hour, value: 12, to: startDate(in: calendar)) ?? startDate(in: calendar)
    }

    public func adding(days: Int, calendar: Calendar = .dosar) -> CalendarDay {
        let shifted = calendar.date(byAdding: .day, value: days, to: startDate(in: calendar)) ?? startDate(in: calendar)
        return CalendarDay(shifted, calendar: calendar)
    }

    /// The same day `months` calendar months away (a year is twelve), or that month's last
    /// day when it is shorter: 31 January and one month is 28 or 29 February, 29 February
    /// and a year is 28 February, 31 March less one month is 28 or 29 February.
    ///
    /// The one month arithmetic of the app, its widgets and the share extension: every
    /// deadline that repeats, every reminder lead in months, every length a document prints.
    /// How long a month is comes only from the calendar (``daysInMonth(calendar:)``), never
    /// from a table of its own.
    ///
    /// - Parameter dayOfMonth: the day a series keeps (31 for "the 31st") instead of this
    ///   day's own, so a series already moved to 28 February comes back to 31 March. With
    ///   no months to add, it moves the day within its own month.
    public func adding(months: Int, dayOfMonth: Int? = nil, calendar: Calendar = .dosar) -> CalendarDay {
        let first = firstOfMonth.startDate(in: calendar)
        let target = CalendarDay(calendar.date(byAdding: .month, value: months, to: first) ?? first, calendar: calendar).firstOfMonth
        let wanted = dayOfMonth ?? day
        return CalendarDay(year: target.year, month: target.month, day: min(max(wanted, 1), target.daysInMonth(calendar: calendar)))
    }

    /// How many days this day's month has in `calendar`: 28 or 29 for February (29 in a
    /// leap year), 30 or 31 for the others. The one place a month's length is known.
    public func daysInMonth(calendar: Calendar = .dosar) -> Int {
        calendar.range(of: .day, in: .month, for: firstOfMonth.startDate(in: calendar))?.count ?? 28
    }

    private var firstOfMonth: CalendarDay { CalendarDay(year: year, month: month, day: 1) }

    /// Whole days from `self` to `other` (negative when `other` is earlier).
    public func days(to other: CalendarDay, calendar: Calendar = .dosar) -> Int {
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

    public var isoString: String { MachineText.isoMonthDay(month: month, day: day) }

    /// This month-day in `year`, clamped to the month's last day (29 February becomes 28 in common years).
    public func day(inYear year: Int, calendar: Calendar = .dosar) -> CalendarDay {
        CalendarDay(year: year, month: month, day: 1).adding(months: 0, dayOfMonth: day, calendar: calendar)
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
