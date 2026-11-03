import Foundation

/// The few plain questions a category of the person's own answers ("Are acte", "Are facturi
/// și contracte", "Are revizii", one box or one per section), read from and written to the
/// category's own data: its pockets, its behaviour, a counter field and a service blueprint.
/// Nothing stores the switches themselves, so there is one source of truth and a custom
/// category behaves exactly like a built-in with the same data.
///
/// Each switch touches only what it owns. Pockets it doesn't own (people, money, products…),
/// fields and blueprints the category had before stay as they are, and applying the switches
/// a definition reads changes nothing. Turning a switch off never deletes anything: a hidden
/// pocket's records stay, a counter's values and readings stay under their own key, and the
/// deadlines it made keep going until the person says otherwise (`TemplateStore.applySwitches`).
public struct CategorySwitches: Hashable, Sendable {
    /// What a service is counted by.
    public enum Service: String, Hashable, Sendable, CaseIterable {
        /// Once a year, with no counter (a piano, a boiler of one's own).
        case yearly
        /// Every so many kilometres, or once a year (a trailer, a motorbike).
        case kilometres
        /// Every so many engine hours, or once a year (a boat, a generator).
        case engineHours

        /// The counter it reads, when it has one.
        public var unit: MeasurementUnit? {
            switch self {
            case .yearly: nil
            case .kilometres: .kilometres
            case .engineHours: .engineHours
            }
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
    /// Its sections have a regular service, counted by time or by a counter; nil for none.
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

    public static func serviceBlueprintKey(_ service: Service) -> String { serviceBlueprintPrefix + service.rawValue }

    /// Whether a blueprint is one the switches make.
    public static func isServiceBlueprint(_ key: String) -> Bool { key.hasPrefix(serviceBlueprintPrefix) }

    /// The pockets every new category of one's own starts with; the switches add theirs.
    public static let basePockets: [SectionPocket] = [.upcoming, .history, .people, .money, .keyFacts]

    // MARK: Reading

    /// The switches a category's data answers.
    public init(reading definition: TemplateDefinition) {
        hasDocuments = definition.pockets.contains(.documents)
        hasBills = definition.pockets.contains(.subscriptions)
        service = Service.allCases.first { service in
            definition.blueprints.contains { $0.key == Self.serviceBlueprintKey(service) }
        }
        boxes = definition.behavior.box == .wholeCategory ? .oneForAll : .perSection
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
            result.blueprints.removeAll { Self.isServiceBlueprint($0.key) }
            result.sections.removeAll { $0.key == Self.counterSectionKey }
            if let service {
                result.blueprints.append(Self.serviceBlueprint(service))
                if let field = Self.counterField(service) {
                    result.sections.append(FieldSection(key: Self.counterSectionKey, title: field.label, fields: [field]))
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

    /// The counter the hero shows and the service counts by; nil for a yearly service.
    public static func counterField(_ service: Service) -> FieldDefinition? {
        guard let unit = service.unit else { return nil }
        let label = switch service {
        case .kilometres: String(localized: "Kilometraj", comment: "Counter field of a category of one's own, in kilometres.")
        case .engineHours: String(localized: "Ore de motor", comment: "Counter field of a category of one's own, in engine hours.")
        case .yearly: ""
        }
        return FieldDefinition(key: counterFieldKey(unit), label: label, type: .metric, role: .heroMetric, isEssential: true, unit: unit)
    }

    /// The service deadline it suggests, like a car's "Revizie periodică": by its counter or
    /// once a year, whichever comes first, reminded two weeks and a day before, with a month's grace.
    public static func serviceBlueprint(_ service: Service) -> ObligationBlueprint {
        let recurrence: RecurrenceRule = switch service {
        case .yearly: .interval(.years(1), anchor: .completion)
        case .kilometres: .metric(every: 10_000, unit: .kilometres, fallback: .years(1))
        case .engineHours: .metric(every: 100, unit: .engineHours, fallback: .years(1))
        }
        let note: String? = switch service {
        case .yearly: nil
        case .kilometres: String(localized: "La 10.000 km sau o dată pe an, ce vine întâi.", comment: "Note of the service deadline of a category of one's own.")
        case .engineHours: String(localized: "La 100 de ore de motor sau o dată pe an, ce vine întâi.", comment: "Note of the service deadline of a category of one's own.")
        }
        return ObligationBlueprint(
            key: serviceBlueprintKey(service),
            title: String(localized: "Revizie periodică", comment: "Service deadline of a category of one's own."),
            kind: .maintenance,
            recurrence: recurrence,
            firstDue: .afterInterval(.years(1)),
            reminders: ReminderProfile(leadDays: [14, 1], consequence: .comfort, graceDays: 30),
            note: note
        )
    }
}
