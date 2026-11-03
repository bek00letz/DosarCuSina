import Foundation

/// The few plain questions a category of the person's own answers ("Are acte", "Are facturi
/// și contracte", "Are revizii" and how often, one box or one per section), read from and
/// written to the category's own data: its pockets, its behaviour, a counter field and a
/// service blueprint. Nothing stores the switches themselves, so there is one source of truth
/// and a custom category behaves exactly like a built-in with the same data.
///
/// Each switch touches only what it owns. Pockets it doesn't own (people, money, products…),
/// fields and blueprints the category had before stay as they are, and applying the switches
/// a definition reads changes nothing. Turning a switch off never deletes anything: a hidden
/// pocket's records stay, a counter's values and readings stay under their own key, and the
/// deadlines it made keep going until the person says otherwise (`TemplateStore.editCustom`).
public struct CategorySwitches: Hashable, Sendable {
    /// What a service is counted by. Raw values name the service blueprint
    /// (`custom.service.<raw>`) and are part of the `.dosar` contract.
    public enum Counter: String, Hashable, Sendable, CaseIterable {
        /// Every so many months, with no counter (a piano, a boiler of one's own).
        case time = "yearly"
        /// Every so many kilometres, or once a year (a trailer, a motorbike).
        case kilometres
        /// Every so many engine hours, or once a year (a boat, a generator).
        case engineHours

        /// The counter the hero shows, when it has one.
        public var unit: MeasurementUnit? {
            switch self {
            case .time: nil
            case .kilometres: .kilometres
            case .engineHours: .engineHours
            }
        }

        /// What `Service.every` counts: months, kilometres or hours.
        public var everyUnit: MeasurementUnit { unit ?? .months }

        /// Where the interval starts: the car's 10.000 km, 100 hours, a year.
        public var defaultEvery: Int {
            switch self {
            case .time: 12
            case .kilometres: 10_000
            case .engineHours: 100
            }
        }
    }

    /// A regular service: what it is counted by, and every how many months, kilometres or hours.
    public struct Service: Hashable, Sendable {
        public var counter: Counter
        /// Months for `.time`, kilometres or hours for a counter; at least 1.
        public var every: Int

        public init(_ counter: Counter, every: Int? = nil) {
            self.counter = counter
            self.every = max(1, every ?? counter.defaultEvery)
        }
    }

    /// How the category shows on the Dosar grid.
    public enum Boxes: Hashable, Sendable {
        /// One box for each section: the boat, the other boat.
        case perSection
        /// One box for the whole category, which lists its sections.
        case oneForAll
    }

    /// Its sections keep photos and PDFs (the Acte pocket).
    public var hasDocuments: Bool
    /// Its sections keep ongoing contracts with their bills (the Abonamente pocket), and bills
    /// and contracts read from a photo can be filed under them, as under a home.
    public var hasBills: Bool
    /// Its sections have a regular service; nil for none.
    public var service: Service?
    public var boxes: Boxes

    public init(hasDocuments: Bool = true, hasBills: Bool = false, service: Service? = nil, boxes: Boxes = .perSection) {
        self.hasDocuments = hasDocuments
        self.hasBills = hasBills
        self.service = service
        self.boxes = boxes
    }

    /// A sensible category with no changes: it keeps documents, one box per section.
    public static let defaults = CategorySwitches()

    // MARK: Keys (part of the `.dosar` contract: never rename them)

    /// The field section that holds the counter.
    public static let counterSectionKey = "custom.counter"
    /// Service blueprints start with this; the rest names what they count by.
    public static let serviceBlueprintPrefix = "custom.service."

    /// The counter's field: one key per unit, so a value typed in hours never reads as kilometres.
    public static func counterFieldKey(_ unit: MeasurementUnit) -> String { "custom.counter.\(unit.key)" }

    public static func serviceBlueprintKey(_ counter: Counter) -> String { serviceBlueprintPrefix + counter.rawValue }

    /// Whether a blueprint is one the switches make.
    public static func isServiceBlueprint(_ key: String) -> Bool { key.hasPrefix(serviceBlueprintPrefix) }

    /// The pockets every new category of one's own starts with; the switches add theirs.
    public static let basePockets: [SectionPocket] = [.upcoming, .history, .people, .money, .keyFacts]

    // MARK: Reading

    /// The switches a category's data answers. The interval is read from the service
    /// blueprint's own rule, so it lives in one place.
    public init(reading definition: TemplateDefinition) {
        hasDocuments = definition.pockets.contains(.documents)
        hasBills = definition.pockets.contains(.subscriptions)
        service = Counter.allCases.lazy.compactMap { counter -> Service? in
            guard let blueprint = definition.blueprints.first(where: { $0.key == Self.serviceBlueprintKey(counter) }) else { return nil }
            return Service(counter, every: Self.every(in: blueprint.recurrence))
        }.first
        boxes = definition.behavior.box == .wholeCategory ? .oneForAll : .perSection
    }

    /// The interval a service blueprint's rule says, in its counter's unit; nil when it says none.
    static func every(in rule: RecurrenceRule) -> Int? {
        switch rule {
        case .metric(let every, _, _): Int(every.rounded())
        case .interval(let interval, _) where interval.unit == .month: interval.every
        case .interval(let interval, _) where interval.unit == .year: interval.every * 12
        default: nil
        }
    }

    // MARK: Writing

    /// `definition` with these answers. Only what differs from what it answers now changes.
    public func applied(to definition: TemplateDefinition) -> TemplateDefinition {
        let current = CategorySwitches(reading: definition)
        var result = definition

        var pockets = Set(definition.pockets)
        if hasDocuments != current.hasDocuments {
            if hasDocuments { pockets.insert(.documents) } else { pockets.remove(.documents) }
        }
        if hasBills != current.hasBills {
            if hasBills { pockets.insert(.subscriptions) } else { pockets.remove(.subscriptions) }
            // A place bills and contracts are filed under, like a home. Another part it
            // plays (one imported from a newer version) is left alone.
            if hasBills, result.behavior.role == nil { result.behavior.role = .home }
            if !hasBills, result.behavior.role == .home { result.behavior.role = nil }
        }
        result.pockets = SectionPocket.ordered(pockets)

        if boxes != current.boxes {
            result.behavior.box = boxes == .oneForAll ? .wholeCategory : .perSection
        }

        if service != current.service {
            if let service, let old = current.service, old.counter == service.counter,
               let index = result.blueprints.firstIndex(where: { $0.key == Self.serviceBlueprintKey(service.counter) }) {
                // Only how often: the same blueprint, in place, with its new rule.
                result.blueprints[index] = Self.serviceBlueprint(service)
            } else {
                result.blueprints.removeAll { Self.isServiceBlueprint($0.key) }
                result.sections.removeAll { $0.key == Self.counterSectionKey }
                if let service {
                    result.blueprints.append(Self.serviceBlueprint(service))
                    if let field = Self.counterField(service.counter) {
                        result.sections.append(FieldSection(key: Self.counterSectionKey, title: field.label, fields: [field]))
                    }
                }
            }
        }
        return result
    }

    /// A new category of the person's own with these answers.
    public func definition(key: String, name: String, symbol: String, tint: TemplateTint) -> TemplateDefinition {
        let base = TemplateDefinition(key: key, name: name, symbol: symbol, tint: tint, sections: [], pockets: Self.basePockets)
        return applied(to: base)
    }

    // MARK: What a service brings

    /// The counter the hero shows and the service counts by; nil for a service by time.
    public static func counterField(_ counter: Counter) -> FieldDefinition? {
        guard let unit = counter.unit else { return nil }
        let label = switch counter {
        case .kilometres: String(localized: "Kilometraj", comment: "Counter field of a category of one's own, in kilometres.")
        case .engineHours: String(localized: "Ore de motor", comment: "Counter field of a category of one's own, in engine hours.")
        case .time: ""
        }
        return FieldDefinition(key: counterFieldKey(unit), label: label, type: .metric, role: .heroMetric, isEssential: true, unit: unit)
    }

    /// The months of a service by time, as whole years when they are.
    static func interval(months: Int) -> RecurrenceInterval {
        months % 12 == 0 ? .years(months / 12) : .months(months)
    }

    /// The service deadline it suggests, like a car's "Revizie periodică": by its counter or
    /// once a year, whichever comes first (or every so many months, for one by time),
    /// reminded two weeks and a day before, with a month's grace.
    public static func serviceBlueprint(_ service: Service) -> ObligationBlueprint {
        let every = service.every
        let recurrence: RecurrenceRule
        let firstDue: RecurrenceInterval
        let note: String
        switch service.counter {
        case .time:
            recurrence = .interval(interval(months: every), anchor: .completion)
            firstDue = interval(months: every)
            note = String(localized: "O dată la \(every) luni.", comment: "Note of the service deadline of a category of one's own: every so many months.")
        case .kilometres:
            recurrence = .metric(every: Double(every), unit: .kilometres, fallback: .years(1))
            firstDue = .years(1)
            note = String(localized: "La \(every) km sau o dată pe an, ce vine întâi.", comment: "Note of the service deadline of a category of one's own: every so many kilometres.")
        case .engineHours:
            recurrence = .metric(every: Double(every), unit: .engineHours, fallback: .years(1))
            firstDue = .years(1)
            note = String(localized: "La \(every) ore de motor sau o dată pe an, ce vine întâi.", comment: "Note of the service deadline of a category of one's own: every so many engine hours.")
        }
        return ObligationBlueprint(
            key: serviceBlueprintKey(service.counter),
            title: String(localized: "Revizie periodică", comment: "Service deadline of a category of one's own."),
            kind: .maintenance,
            recurrence: recurrence,
            firstDue: .afterInterval(firstDue),
            reminders: ReminderProfile(leadDays: [14, 1], consequence: .comfort, graceDays: 30),
            note: note
        )
    }
}
