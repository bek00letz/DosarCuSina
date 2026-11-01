import Foundation

/// What kind of duty an obligation is. It decides how much missing it costs,
/// which drives the Radar ranking and how loudly reminders speak.
///
/// Raw values are part of the `.dosar` contract.
public enum ObligationKind: String, Codable, CaseIterable, Sendable {
    /// A legal requirement with penalties: ITP, gas installation checks, rovinietă.
    case legal
    /// Taxes and declarations to the state: local taxes, Declarația Unică.
    case tax
    /// Insurance that lapses: RCA, PAD, CASCO.
    case insurance
    /// Health and prevention: vaccines, screenings, prescriptions.
    case health
    /// Documents that expire and take time to renew: ID card, passport.
    case renewal
    /// Bills and recurring payments: rent, subscriptions, utilities.
    case payment
    /// Upkeep that prevents bigger costs: oil change, boiler service.
    case maintenance
    /// Everyday chores: watering plants, cleaning filters.
    case routine

    /// Relative cost of missing it, used to rank attention (higher matters more).
    public var consequenceWeight: Int {
        switch self {
        case .legal: return 100
        case .tax: return 90
        case .insurance: return 90
        case .health: return 70
        case .renewal: return 60
        case .payment: return 50
        case .maintenance: return 30
        case .routine: return 10
        }
    }

    /// How many days ahead an item of this kind starts to need attention now.
    public var attentionLeadDays: Int {
        switch self {
        case .legal, .tax, .insurance: return 14
        case .renewal: return 30
        case .health: return 7
        case .payment: return 5
        case .maintenance: return 7
        case .routine: return 2
        }
    }

    /// Whether the last reminders (the day before and the day itself) may break through Focus.
    public var allowsTimeSensitiveReminders: Bool {
        switch self {
        case .legal, .tax, .insurance, .health, .renewal, .payment: return true
        case .maintenance, .routine: return false
        }
    }
}

/// Where an obligation is in its life.
public enum ObligationStatus: String, Codable, CaseIterable, Sendable {
    case active
    /// Temporarily off: no reminders, hidden from attention, kept in the list.
    case paused
    /// A one-off obligation that was completed.
    case done
    /// Kept for history only.
    case archived
}

/// A calendar step: `every` units of time.
public struct RecurrenceInterval: Hashable, Sendable, Codable {
    public enum Unit: String, Codable, Sendable, CaseIterable {
        case day, week, month, year
    }

    public var every: Int
    public var unit: Unit

    public init(every: Int, unit: Unit) {
        self.every = max(1, every)
        self.unit = unit
    }

    public static func days(_ n: Int) -> RecurrenceInterval { .init(every: n, unit: .day) }
    public static func weeks(_ n: Int) -> RecurrenceInterval { .init(every: n, unit: .week) }
    public static func months(_ n: Int) -> RecurrenceInterval { .init(every: n, unit: .month) }
    public static func years(_ n: Int) -> RecurrenceInterval { .init(every: n, unit: .year) }
}

/// The date a repeating obligation counts its next cycle from.
public enum RecurrenceAnchor: String, Codable, Sendable {
    /// From the previous due date. Every cycle is its own payment (rent, taxes, insurance).
    case dueDate
    /// From the day it was done. Validity starts when the work happens (ITP, oil change, watering).
    case completion
}

/// Legal rules that need asset data to compute the next date.
public enum LegalRule: String, Codable, Sendable, CaseIterable {
    /// ITP for passenger cars (OUG 195/2002, RNTR 1): every 2 years up to 12 years old,
    /// every year after, every 6 months for ridesharing and taxis.
    case vehicleITP
}

/// How an obligation repeats.
///
/// Encoding (the `.dosar` contract):
/// - `{"type": "none"}`
/// - `{"type": "interval", "every": 2, "unit": "year", "anchor": "completion"}`
/// - `{"type": "fixedDates", "dates": ["03-31", "09-30"]}`
/// - `{"type": "metric", "every": 10000, "unit": "km", "fallbackEvery": 1, "fallbackUnit": "year"}`
/// - `{"type": "legal", "rule": "vehicleITP"}`
public enum RecurrenceRule: Hashable, Sendable, Codable {
    case none
    case interval(RecurrenceInterval, anchor: RecurrenceAnchor)
    /// Due on the same calendar days every year, such as 31 March and 30 September.
    case fixedDates([MonthDay])
    /// Due every `every` units of an asset counter, with a calendar fallback when there are no readings.
    case metric(every: Double, unit: String, fallback: RecurrenceInterval?)
    case legal(LegalRule)

    public var repeats: Bool {
        if case .none = self { return false }
        return true
    }

    private enum CodingKeys: String, CodingKey {
        case type, every, unit, anchor, dates, fallbackEvery, fallbackUnit, rule
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        switch try c.decode(String.self, forKey: .type) {
        case "interval":
            let unit = RecurrenceInterval.Unit(rawValue: try c.decode(String.self, forKey: .unit)) ?? .day
            let anchor = RecurrenceAnchor(rawValue: try c.decodeIfPresent(String.self, forKey: .anchor) ?? "") ?? .dueDate
            self = .interval(RecurrenceInterval(every: try c.decode(Int.self, forKey: .every), unit: unit), anchor: anchor)
        case "fixedDates":
            self = .fixedDates(try c.decode([MonthDay].self, forKey: .dates))
        case "metric":
            var fallback: RecurrenceInterval?
            if let every = try c.decodeIfPresent(Int.self, forKey: .fallbackEvery),
               let unit = RecurrenceInterval.Unit(rawValue: try c.decodeIfPresent(String.self, forKey: .fallbackUnit) ?? "") {
                fallback = RecurrenceInterval(every: every, unit: unit)
            }
            self = .metric(every: try c.decode(Double.self, forKey: .every), unit: try c.decode(String.self, forKey: .unit), fallback: fallback)
        case "legal":
            if let rule = LegalRule(rawValue: try c.decode(String.self, forKey: .rule)) {
                self = .legal(rule)
            } else {
                self = .none
            }
        default:
            self = .none
        }
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .none:
            try c.encode("none", forKey: .type)
        case .interval(let interval, let anchor):
            try c.encode("interval", forKey: .type)
            try c.encode(interval.every, forKey: .every)
            try c.encode(interval.unit.rawValue, forKey: .unit)
            try c.encode(anchor.rawValue, forKey: .anchor)
        case .fixedDates(let dates):
            try c.encode("fixedDates", forKey: .type)
            try c.encode(dates.sorted(), forKey: .dates)
        case .metric(let every, let unit, let fallback):
            try c.encode("metric", forKey: .type)
            try c.encode(every, forKey: .every)
            try c.encode(unit, forKey: .unit)
            if let fallback {
                try c.encode(fallback.every, forKey: .fallbackEvery)
                try c.encode(fallback.unit.rawValue, forKey: .fallbackUnit)
            }
        case .legal(let rule):
            try c.encode("legal", forKey: .type)
            try c.encode(rule.rawValue, forKey: .rule)
        }
    }
}

/// How a blueprint picks the first due date when an asset is created.
///
/// Encoding: `{"type": "field", "field": "document.expiry", "offsetDays": 0}`,
/// `{"type": "afterInterval", "every": 1, "unit": "year"}`, `{"type": "nextFixedDate"}`,
/// `{"type": "ask"}`.
public enum FirstDueRule: Hashable, Sendable, Codable {
    /// Taken from a date field on the asset, shifted by `offsetDays`.
    case field(key: String, offsetDays: Int)
    /// One interval after today.
    case afterInterval(RecurrenceInterval)
    /// The next of the recurrence rule's fixed dates.
    case nextFixedDate
    /// The person enters the date (for example the current ITP expiry).
    case ask

    private enum CodingKeys: String, CodingKey { case type, field, offsetDays, every, unit }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        switch try c.decode(String.self, forKey: .type) {
        case "field":
            self = .field(key: try c.decode(String.self, forKey: .field), offsetDays: try c.decodeIfPresent(Int.self, forKey: .offsetDays) ?? 0)
        case "afterInterval":
            let unit = RecurrenceInterval.Unit(rawValue: try c.decode(String.self, forKey: .unit)) ?? .day
            self = .afterInterval(RecurrenceInterval(every: try c.decode(Int.self, forKey: .every), unit: unit))
        case "nextFixedDate":
            self = .nextFixedDate
        default:
            self = .ask
        }
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .field(let key, let offset):
            try c.encode("field", forKey: .type)
            try c.encode(key, forKey: .field)
            try c.encode(offset, forKey: .offsetDays)
        case .afterInterval(let interval):
            try c.encode("afterInterval", forKey: .type)
            try c.encode(interval.every, forKey: .every)
            try c.encode(interval.unit.rawValue, forKey: .unit)
        case .nextFixedDate:
            try c.encode("nextFixedDate", forKey: .type)
        case .ask:
            try c.encode("ask", forKey: .type)
        }
    }
}

/// A suggested obligation that comes with a template (ITP and RCA for a car,
/// vaccines for a pet). Creating an asset turns chosen blueprints into obligations.
public struct ObligationBlueprint: Hashable, Sendable, Codable, Identifiable {
    /// Stable key, unique within the template, such as `vehicle.itp`.
    public var key: String
    public var title: String
    public var kind: ObligationKind
    public var recurrence: RecurrenceRule
    public var firstDue: FirstDueRule
    /// Days before the due date to remind, such as `[30, 7, 1, 0]`.
    public var reminderOffsetsDays: [Int]
    public var estimatedCost: Money?
    /// Pre-selected in the add flow.
    public var isSuggested: Bool
    /// One short sentence explaining why it matters, shown in the add flow.
    public var note: String?

    public var id: String { key }

    public init(
        key: String,
        title: String,
        kind: ObligationKind,
        recurrence: RecurrenceRule,
        firstDue: FirstDueRule = .ask,
        reminderOffsetsDays: [Int] = [30, 7, 1, 0],
        estimatedCost: Money? = nil,
        isSuggested: Bool = true,
        note: String? = nil
    ) {
        self.key = key
        self.title = title
        self.kind = kind
        self.recurrence = recurrence
        self.firstDue = firstDue
        self.reminderOffsetsDays = reminderOffsetsDays
        self.estimatedCost = estimatedCost
        self.isSuggested = isSuggested
        self.note = note
    }

    private enum CodingKeys: String, CodingKey {
        case key, title, kind, recurrence, firstDue, reminderOffsetsDays, estimatedCost, isSuggested, note
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        key = try c.decode(String.self, forKey: .key)
        title = try c.decode(String.self, forKey: .title)
        kind = ObligationKind(rawValue: try c.decode(String.self, forKey: .kind)) ?? .routine
        recurrence = try c.decodeIfPresent(RecurrenceRule.self, forKey: .recurrence) ?? .none
        firstDue = try c.decodeIfPresent(FirstDueRule.self, forKey: .firstDue) ?? .ask
        reminderOffsetsDays = try c.decodeIfPresent([Int].self, forKey: .reminderOffsetsDays) ?? [30, 7, 1, 0]
        estimatedCost = try c.decodeIfPresent(Money.self, forKey: .estimatedCost)
        isSuggested = try c.decodeIfPresent(Bool.self, forKey: .isSuggested) ?? true
        note = try c.decodeIfPresent(String.self, forKey: .note)
    }
}
