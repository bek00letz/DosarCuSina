import Foundation

/// What missing a deadline costs. Ranking, urgency and how loudly reminders
/// speak all follow from it. Raw values are part of the `.dosar` contract.
public enum Consequence: String, Codable, CaseIterable, Sendable {
    /// Fines, a suspended registration, driving uninsured: ITP, RCA, rovinietă.
    case legal
    /// Penalties or money lost: local tax installments, a trial that turns paid.
    case financial
    /// Health and prevention: vaccines, check-ups.
    case health
    /// Nice to keep up with; nothing bad happens if it slips: watering, grooming.
    case comfort

    /// Relative weight in the Radar ranking.
    public var weight: Int {
        switch self {
        case .legal: return 100
        case .financial: return 80
        case .health: return 60
        case .comfort: return 10
        }
    }

    /// The most days ahead an item of this consequence is promoted to "needs you now"
    /// (30 is a calendar month, like a reminder's lead). Earlier reminders still go out
    /// per the profile's lead days.
    public var maxAttentionWindowDays: Int {
        switch self {
        case .legal: return 30
        case .financial: return 21
        case .health: return 7
        case .comfort: return 3
        }
    }

    /// Whether the last reminders may break through Focus.
    public var allowsTimeSensitiveReminders: Bool { self != .comfort }

    /// What an unknown stored value (from a newer build or archive) behaves as: the
    /// loudest, so a deadline never goes quiet because this build can't read its value.
    public static let loudest = Consequence.legal

    /// A stored value: unknown or missing reads as `loudest`. The stored text is kept as
    /// it was (see `Obligation.reminders`), never written back downgraded.
    public init(stored raw: String?) {
        self = raw.flatMap(Consequence.init(rawValue:)) ?? .loudest
    }
}

/// How an obligation reminds: how far ahead (driven by how long renewing takes),
/// how much missing it costs, how late is still fine, and whether to nudge
/// once after the due date passes.
///
/// Encoding: `{"leadDays": [60, 30], "consequence": "legal", "graceDays": 0, "followUpAfterLapse": true}`,
/// with `"travelMarginDays": 180` only for a document that stops being good for travel
/// before it expires (a passport).
public struct ReminderProfile: Hashable, Sendable, Codable {
    /// Days before the due date to remind, largest first; `0` is the due day. With a
    /// travel margin, they count back from the travel cut-off instead (`UrgencyRule.reminderAnchor`).
    public var leadDays: [Int]
    public var consequence: Consequence
    /// Days after the due date that are still acceptable. Within them, the item
    /// is late but not alarming.
    public var graceDays: Int
    /// One notification the day after the due date if it is still open, then silence.
    public var followUpAfterLapse: Bool
    /// How long before its due day the document stops being good for travel, in days
    /// (180 is six calendar months); 0 for everything that is good until it expires. Comes
    /// only from the document type (`DocumentType.travelMarginDays`), never chosen by hand.
    public var travelMarginDays: Int

    /// Whether a consequence follows up after lapsing by default: yes for legal and financial.
    public static func defaultFollowUp(for consequence: Consequence) -> Bool {
        consequence == .legal || consequence == .financial
    }

    public init(leadDays: [Int], consequence: Consequence, graceDays: Int = 0, followUpAfterLapse: Bool? = nil, travelMarginDays: Int = 0) {
        self.leadDays = Array(Set(leadDays.map(abs))).sorted(by: >)
        self.consequence = consequence
        self.graceDays = max(0, graceDays)
        self.followUpAfterLapse = followUpAfterLapse ?? Self.defaultFollowUp(for: consequence)
        self.travelMarginDays = max(0, travelMarginDays)
    }

    /// How urgent the item is on every surface: it needs the person from its earliest
    /// reminder, capped by what its consequence warrants (an ID card reminds 90 days
    /// ahead but only crowds Urmează in the last month), from its travel cut-off when it
    /// has one, and late within its grace is calm.
    public var urgencyRule: UrgencyRule {
        UrgencyRule(graceDays: graceDays, firstLeadDays: leadDays.first ?? 0, maxWindowDays: consequence.maxAttentionWindowDays,
                    travelMarginDays: travelMarginDays)
    }

    /// It stops being good for travel before it expires (a passport): its leads count from that day.
    public var hasTravelCutoff: Bool { travelMarginDays > 0 }

    /// The same profile with other leads, everything else kept (the travel margin included).
    public func withLeadDays(_ leads: [Int]) -> ReminderProfile {
        ReminderProfile(leadDays: leads, consequence: consequence, graceDays: graceDays, followUpAfterLapse: followUpAfterLapse,
                        travelMarginDays: travelMarginDays)
    }

    private enum CodingKeys: String, CodingKey { case leadDays, consequence, graceDays, followUpAfterLapse, travelMarginDays }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            leadDays: try c.decodeIfPresent([Int].self, forKey: .leadDays) ?? [7, 0],
            consequence: Consequence(stored: try c.decodeIfPresent(String.self, forKey: .consequence)),
            graceDays: try c.decodeIfPresent(Int.self, forKey: .graceDays) ?? 0,
            followUpAfterLapse: try c.decodeIfPresent(Bool.self, forKey: .followUpAfterLapse),
            travelMarginDays: try c.decodeIfPresent(Int.self, forKey: .travelMarginDays) ?? 0
        )
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(leadDays, forKey: .leadDays)
        try c.encode(consequence.rawValue, forKey: .consequence)
        try c.encode(graceDays, forKey: .graceDays)
        try c.encode(followUpAfterLapse, forKey: .followUpAfterLapse)
        // Written only when there is one, so every other profile reads exactly as before.
        if travelMarginDays > 0 { try c.encode(travelMarginDays, forKey: .travelMarginDays) }
    }
}

/// A blueprint's profile that depends on an asset value, such as the document
/// type: an ID card reminds 90 days ahead, a driving licence 60.
///
/// Encoding: `{"field": "document.type", "variants": {"Pașaport": {…profile…}}}`.
public struct ReminderProfileVariants: Hashable, Sendable, Codable {
    public var field: String
    public var variants: [String: ReminderProfile]

    public init(field: String, variants: [String: ReminderProfile]) {
        self.field = field
        self.variants = variants
    }
}

/// A blueprint condition on an asset value: `{"field": "subscription.cycle", "oneOf": ["billing.yearly"]}`.
public struct BlueprintCondition: Hashable, Sendable, Codable {
    public var field: String
    public var oneOf: [String]

    public init(field: String, oneOf: [String]) {
        self.field = field
        self.oneOf = oneOf
    }

    public func isMet(by values: FieldValues) -> Bool {
        guard let value = values[field] else { return false }
        switch value {
        case .text(let text): return oneOf.contains(text)
        case .choices(let items): return items.contains(where: oneOf.contains)
        default: return false
        }
    }
}

/// What kind of duty an obligation is: how it is grouped and labeled, and the
/// reminder profile it starts from when nothing more specific is given.
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

    /// What an unknown stored kind behaves as: the loudest (see `Consequence.loudest`).
    public static let loudest = ObligationKind.legal

    public init(stored raw: String?) {
        self = raw.flatMap(ObligationKind.init(rawValue:)) ?? .loudest
    }

    /// The profile used when a blueprint or the person doesn't give one.
    public var defaultProfile: ReminderProfile {
        switch self {
        case .legal: return ReminderProfile(leadDays: [30, 7, 0], consequence: .legal)
        case .tax: return ReminderProfile(leadDays: [14, 1], consequence: .financial)
        case .insurance: return ReminderProfile(leadDays: [30, 7, 0], consequence: .legal)
        case .health: return ReminderProfile(leadDays: [7, 1], consequence: .health, graceDays: 7)
        case .renewal: return ReminderProfile(leadDays: [60, 30], consequence: .legal)
        case .payment: return ReminderProfile(leadDays: [2, 0], consequence: .financial)
        case .maintenance: return ReminderProfile(leadDays: [14, 1], consequence: .comfort, graceDays: 14)
        case .routine: return ReminderProfile(leadDays: [0], consequence: .comfort, graceDays: 3)
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
/// - `{"type": "metric", "every": 10000, "unit": "km", "fallbackEvery": 1, "fallbackUnit": "year"}` (the unit by its key, `MeasurementUnit`)
/// - `{"type": "legal", "rule": "vehicleITP"}`
public enum RecurrenceRule: Hashable, Sendable, Codable {
    case none
    case interval(RecurrenceInterval, anchor: RecurrenceAnchor)
    /// Due on the same calendar days every year, such as 31 March and 30 September.
    case fixedDates([MonthDay])
    /// Due every `every` units of an asset counter, with a calendar fallback when there are no readings.
    case metric(every: Double, unit: MeasurementUnit, fallback: RecurrenceInterval?)
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
            self = .metric(every: try c.decode(Double.self, forKey: .every), unit: try c.decode(MeasurementUnit.self, forKey: .unit), fallback: fallback)
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

/// A fact a deadline needs at hand, by what it is for, not by how its field is called.
/// Raw values are part of the `.dosar` contract.
public enum BlueprintFactRole: String, Codable, CaseIterable, Sendable {
    /// Who issued the policy.
    case insurer
    case policyNumber
    /// The line to call for a claim or assistance.
    case claimsPhone
}

/// Which of the section's fields hold the facts one deadline needs: a car's CASCO keeps
/// its own insurer, policy number and claims phone, apart from its RCA. The deadline page,
/// the claim checklist and capture's filing all read a deadline's facts through these
/// roles, never by guessing from field names.
public struct BlueprintFacts: Hashable, Sendable, Codable {
    public var insurer: String?
    public var policyNumber: String?
    public var claimsPhone: String?

    public init(insurer: String? = nil, policyNumber: String? = nil, claimsPhone: String? = nil) {
        self.insurer = insurer
        self.policyNumber = policyNumber
        self.claimsPhone = claimsPhone
    }

    /// The field that holds `role`, if the deadline names one.
    public func field(for role: BlueprintFactRole) -> String? {
        switch role {
        case .insurer: insurer
        case .policyNumber: policyNumber
        case .claimsPhone: claimsPhone
        }
    }

    /// Every field the deadline names, with its role.
    public var fields: [(role: BlueprintFactRole, field: String)] {
        BlueprintFactRole.allCases.compactMap { role in field(for: role).map { (role, $0) } }
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
    /// How it reminds by default; the person can change it per obligation.
    public var reminders: ReminderProfile
    /// A different profile depending on an asset value (passport vs ID card).
    public var reminderVariants: ReminderProfileVariants?
    /// Offered only when an asset value matches (a yearly renewal only for yearly billing).
    public var appliesWhen: BlueprintCondition?
    public var estimatedCost: Money?
    /// Pre-selected in the add flow.
    public var isSuggested: Bool
    /// One short sentence explaining why it matters, shown in the add flow.
    public var note: String?
    /// The section's fields that hold this deadline's facts (a policy's insurer, number and claims phone).
    public var facts: BlueprintFacts?

    public var id: String { key }

    public init(
        key: String,
        title: String,
        kind: ObligationKind,
        recurrence: RecurrenceRule,
        firstDue: FirstDueRule = .ask,
        reminders: ReminderProfile? = nil,
        reminderVariants: ReminderProfileVariants? = nil,
        appliesWhen: BlueprintCondition? = nil,
        estimatedCost: Money? = nil,
        isSuggested: Bool = true,
        note: String? = nil,
        facts: BlueprintFacts? = nil
    ) {
        self.facts = facts
        self.key = key
        self.title = title
        self.kind = kind
        self.recurrence = recurrence
        self.firstDue = firstDue
        self.reminders = reminders ?? kind.defaultProfile
        self.reminderVariants = reminderVariants
        self.appliesWhen = appliesWhen
        self.estimatedCost = estimatedCost
        self.isSuggested = isSuggested
        self.note = note
    }

    /// The profile for a particular asset, taking variants into account.
    public func reminders(for values: FieldValues) -> ReminderProfile {
        guard let reminderVariants,
              let value = values[reminderVariants.field]?.textValue,
              let profile = reminderVariants.variants[value] else { return reminders }
        return profile
    }

    private enum CodingKeys: String, CodingKey {
        case key, title, kind, recurrence, firstDue, reminders, reminderVariants, appliesWhen, estimatedCost, isSuggested, note, facts
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        key = try c.decode(String.self, forKey: .key)
        title = try c.decode(String.self, forKey: .title)
        kind = ObligationKind(stored: try c.decode(String.self, forKey: .kind))
        recurrence = try c.decodeIfPresent(RecurrenceRule.self, forKey: .recurrence) ?? .none
        firstDue = try c.decodeIfPresent(FirstDueRule.self, forKey: .firstDue) ?? .ask
        reminders = try c.decodeIfPresent(ReminderProfile.self, forKey: .reminders) ?? kind.defaultProfile
        reminderVariants = try c.decodeIfPresent(ReminderProfileVariants.self, forKey: .reminderVariants)
        appliesWhen = try c.decodeIfPresent(BlueprintCondition.self, forKey: .appliesWhen)
        estimatedCost = try c.decodeIfPresent(Money.self, forKey: .estimatedCost)
        isSuggested = try c.decodeIfPresent(Bool.self, forKey: .isSuggested) ?? true
        note = try c.decodeIfPresent(String.self, forKey: .note)
        facts = try? c.decodeIfPresent(BlueprintFacts.self, forKey: .facts)
    }
}
