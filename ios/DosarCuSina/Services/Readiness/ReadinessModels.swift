import Foundation

// What the readiness checks take in and give back. The rules live in `ReadinessEngine`;
// screens only draw what it returns.

// MARK: - Situations

/// The situations the binder helps prepare for, listed once. Where each is offered and
/// where it opens are decided here, so a screen that gathers every situation (a
/// "Pregătește-te pentru…" section) is a loop over `allCases`, not new rules.
public enum ReadinessSituation: String, CaseIterable, Hashable, Sendable, Codable, Identifiable {
    /// "Pleci din țară": the people going, the car, the pets.
    case trip
    /// "Vinzi mașina": what the buyer asks for, what to cancel after, what is owed.
    case sale
    /// "Ai avut o daună": the right policy's number and phone, what to photograph.
    case claim

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .trip: String(localized: "Pleci din țară", comment: "Situation: travelling abroad.")
        case .sale: String(localized: "Vinzi mașina", comment: "Situation: selling the car.")
        case .claim: String(localized: "Ai avut o daună", comment: "Situation: an accident or damage to report to the insurer.")
        }
    }

    /// One line under the title: what the checklist does.
    public var summary: String {
        switch self {
        case .trip: String(localized: "Actele, mașina și animalele, verificate pentru zilele în care pleci.", comment: "Situation summary: trip.")
        case .sale: String(localized: "Ce cere cumpărătorul, ce anulezi după și ce mai ai de plătit.", comment: "Situation summary: selling the car.")
        case .claim: String(localized: "Numărul poliței, telefonul de daune și ce fotografiezi.", comment: "Situation summary: insurance claim.")
        }
    }

    public var symbol: String {
        switch self {
        case .trip: "airplane.departure"
        case .sale: "key.horizontal.fill"
        case .claim: "exclamationmark.shield.fill"
        }
    }

    /// The situations a section of `template` offers on its page, in this order.
    public static func offered(by template: TemplateDefinition) -> [ReadinessSituation] {
        allCases.filter { $0.isOffered(by: template) }
    }

    /// Whether a section of `template` offers this situation: a trip on a household member,
    /// a sale on a vehicle (a section that keeps an RCA), a claim on anything that keeps a
    /// policy (a car's RCA and CASCO, a home's PAD and optional policy).
    public func isOffered(by template: TemplateDefinition) -> Bool {
        switch self {
        case .trip: template.behavior.role == .holder
        case .sale: template.blueprints.contains { $0.key == BuiltInBlueprints.vehicleRCA }
        case .claim: template.blueprints.contains { $0.facts?.policyNumber != nil || $0.facts?.claimsPhone != nil }
        }
    }

    /// Whether it is about the whole household too, so it is offered outside a section (Urmează).
    public var isHouseholdWide: Bool { self == .trip }

    /// Where it opens: from a section's page (`assetID`), or for the household (nil).
    public func route(for assetID: UUID?) -> AppRoute? {
        switch self {
        case .trip: .readiness(.trip(holderID: assetID))
        case .sale: assetID.map { .readiness(.sale(assetID: $0)) }
        case .claim: assetID.map { .readiness(.claim(assetID: $0)) }
        }
    }
}

/// A checklist screen, as `AppRoute.readiness` carries it.
public enum ReadinessRoute: Hashable, Sendable, Codable {
    /// The trip, for the household or starting from one member (their page).
    case trip(holderID: UUID?)
    case sale(assetID: UUID)
    case claim(assetID: UUID)

    public var situation: ReadinessSituation {
        switch self {
        case .trip: .trip
        case .sale: .sale
        case .claim: .claim
        }
    }

    /// The section it was opened from, if any.
    public var assetID: UUID? {
        switch self {
        case .trip(let id): id
        case .sale(let id), .claim(let id): id
        }
    }
}

// MARK: - Scenarios

/// A situation, with what the person told the checklist about it.
public enum ReadinessScenario: Hashable, Sendable {
    case trip(TripPlan)
    case sellingVehicle(assetId: UUID)
    /// A claim on one of the asset's policies: the deadline `blueprintKey` names (CASCO),
    /// or, when nil, the first of its policies the binder follows.
    case insuranceClaim(assetId: UUID, blueprintKey: String? = nil)
}

/// Who goes on a trip: a household member, or the documents filed under no one.
public enum TripTraveller: Hashable, Sendable, Codable {
    case member(UUID)
    /// Personal documents not filed under anyone ("Fără titular").
    case unfiled

    /// A stable text for item ids.
    var key: String {
        switch self {
        case .member(let id): id.uuidString
        case .unfiled: "unfiled"
        }
    }
}

/// A trip as the person describes it. Kept on this phone only while the trip is ahead
/// (`TripPlanStore`), never in the binder.
public struct TripPlan: Hashable, Sendable, Codable {
    public enum Region: String, Hashable, Sendable, Codable, CaseIterable {
        case europeanUnion
        case outsideEU
    }

    public var start: CalendarDay
    public var end: CalendarDay
    public var region: Region
    /// Where to, in the person's words ("Grecia"); empty when not said.
    public var destination: String
    public var travellers: Set<TripTraveller>
    /// The cars going; none when not driving.
    public var vehicles: Set<UUID>
    public var pets: Set<UUID>

    public init(
        start: CalendarDay,
        end: CalendarDay,
        region: Region,
        destination: String = "",
        travellers: Set<TripTraveller> = [],
        vehicles: Set<UUID> = [],
        pets: Set<UUID> = []
    ) {
        self.start = start
        self.end = end
        self.region = region
        self.destination = destination
        self.travellers = travellers
        self.vehicles = vehicles
        self.pets = pets
    }

    /// Whether it can be checked: it ends on or after the day it starts.
    public var isValid: Bool { end >= start }
}

extension TripPlan.Region {
    public var title: String {
        switch self {
        case .europeanUnion: String(localized: "În Uniunea Europeană", comment: "Trip region: inside the EU.")
        case .outsideEU: String(localized: "În afara UE", comment: "Trip region: outside the EU.")
        }
    }

    /// What the region asks of people's documents, in one line (the rule the checks apply).
    public var summary: String {
        switch self {
        case .europeanUnion: String(localized: "Ajunge cartea de identitate, valabilă până te întorci.", comment: "Trip region rule: inside the EU.")
        case .outsideEU: String(localized: "Ai nevoie de pașaport, bun de călătorit până te întorci.", comment: "Trip region rule: outside the EU.")
        }
    }
}

/// Who and what can go on a trip, from what the binder holds.
public struct TripCandidates: Hashable, Sendable {
    public struct Option: Hashable, Sendable, Identifiable {
        public var id: UUID
        public var name: String
    }

    public struct Traveller: Hashable, Sendable, Identifiable {
        public var traveller: TripTraveller
        public var name: String
        public var id: String { traveller.key }
    }

    public var travellers: [Traveller]
    public var vehicles: [Option]
    public var pets: [Option]
}

// MARK: - Results

/// How one check came out. Problems sort first.
public enum ReadinessStatus: Int, Hashable, Sendable, Comparable, CaseIterable {
    /// Something will go wrong (an expired passport for a non-EU trip).
    case problem = 0
    /// Something the binder doesn't know yet; worth adding.
    case missing = 1
    /// Fine but worth a look (a vignette that ends during the trip).
    case warning = 2
    case ok = 3
    /// Something to do or bring that the binder can't check: ticked off by hand.
    case reminder = 4

    public static func < (lhs: ReadinessStatus, rhs: ReadinessStatus) -> Bool { lhs.rawValue < rhs.rawValue }

    /// Needs the person before the day: a problem or something worth a look.
    public var needsAttention: Bool { self == .problem || self == .warning }
}

/// What a check's row does when tapped.
public enum ReadinessAction: Hashable, Sendable {
    /// See it: the document, the deadline, the section.
    case open(AppRoute)
    /// Add a personal document for a household member, photo first.
    case addPersonalDocument(holderID: UUID)
    /// File a paper on the section, photo first (the policy).
    case addDocument(assetID: UUID)
    /// Add one of the section's usual deadlines (RCA, ITP, the rabies vaccine).
    case addDeadline(assetID: UUID, blueprintKey: String)
    /// Fill in a value the section doesn't have yet (the CIV, the pet's passport).
    case editSection(assetID: UUID)

    /// Whether it adds something rather than opening what is there.
    public var adds: Bool {
        if case .open = self { return false }
        return true
    }
}

public struct ReadinessItem: Hashable, Sendable, Identifiable {
    public var id: String
    public var status: ReadinessStatus
    public var title: String
    /// Why, in plain words.
    public var detail: String
    public var action: ReadinessAction?

    public init(id: String, status: ReadinessStatus, title: String, detail: String, action: ReadinessAction? = nil) {
        self.id = id
        self.status = status
        self.title = title
        self.detail = detail
        self.action = action
    }
}

/// The checks about one thing: a person, the car, a pet, what to photograph.
public struct ReadinessGroup: Hashable, Sendable, Identifiable {
    public var id: String
    public var title: String
    public var symbol: String
    public var items: [ReadinessItem]

    public init(id: String, title: String, symbol: String, items: [ReadinessItem]) {
        self.id = id
        self.title = title
        self.symbol = symbol
        // Problems first; otherwise the order the checks were written in.
        self.items = items.enumerated().sorted { ($0.element.status, $0.offset) < ($1.element.status, $1.offset) }.map(\.element)
    }
}

/// One policy a claim can go to, with the facts its deadline keeps (`BlueprintFacts`).
public struct ReadinessPolicy: Hashable, Sendable, Identifiable {
    public var blueprintKey: String
    /// The deadline's title: "RCA", "CASCO", "Asigurare obligatorie (PAD)".
    public var title: String
    /// When this policy is the one to call, in a few words.
    public var whenToUse: String?
    public var insurer: String?
    public var policyNumber: String?
    public var claimsPhone: String?
    /// The policy's deadline, when the binder follows it.
    public var deadlineID: UUID?
    public var validUntil: CalendarDay?
    /// The bonus-malus class of the person it insures, read from them ("B6").
    public var policyholderClass: String? = nil

    public var id: String { blueprintKey }
}

/// What a situation's screen shows: groups of checks, and for a claim the policy to call.
public struct ReadinessChecklist: Hashable, Sendable {
    public var groups: [ReadinessGroup]
    /// A claim's policy: the one asked for, or the first the binder follows.
    public var policy: ReadinessPolicy?
    /// Every policy the claim could go to, for choosing another.
    public var policyOptions: [ReadinessPolicy]

    public init(groups: [ReadinessGroup], policy: ReadinessPolicy? = nil, policyOptions: [ReadinessPolicy] = []) {
        self.groups = groups.filter { !$0.items.isEmpty }
        self.policy = policy
        self.policyOptions = policyOptions
    }

    /// Every check, problems first.
    public var items: [ReadinessItem] {
        groups.flatMap(\.items).enumerated().sorted { ($0.element.status, $0.offset) < ($1.element.status, $1.offset) }.map(\.element)
    }

    /// How many checks need the person, aren't in the binder, or are ready.
    public var attentionCount: Int { items.filter { $0.status.needsAttention }.count }
    public var missingCount: Int { items.filter { $0.status == .missing }.count }
    /// Whether everything the binder can check is ready.
    public var isAllReady: Bool { attentionCount == 0 && missingCount == 0 }
}

// MARK: - What the checks read

/// An active obligation as the readiness checks see it.
public struct ReadinessObligation: Hashable, Sendable {
    public var id: UUID
    public var due: CalendarDay
    /// The last time it was done.
    public var lastDone: CalendarDay?
    /// Policy or contract number.
    public var reference: String?
    public var title: String
    public var kind: ObligationKind
    public var amount: Money?

    public init(id: UUID = UUID(), due: CalendarDay, lastDone: CalendarDay? = nil, reference: String? = nil,
                title: String = "", kind: ObligationKind = .routine, amount: Money? = nil) {
        self.id = id
        self.due = due
        self.lastDone = lastDone
        self.reference = reference
        self.title = title
        self.kind = kind
        self.amount = amount
    }
}

/// What the readiness checks read about one asset.
public struct ReadinessAsset: Hashable, Sendable {
    public var id: UUID
    public var name: String
    public var templateKey: String
    /// The part its category plays: a household member, a personal document.
    public var role: CategoryBehavior.Role?
    /// The section it is filed under (a document's holder).
    public var parentId: UUID?
    /// Its category asks for Face ID.
    public var isSensitive: Bool
    public var values: FieldValues
    /// Active obligations by blueprint key: due day and the last time it was done.
    public var obligations: [String: ReadinessObligation]
    /// Active obligations of the person's own, with no blueprint.
    public var otherObligations: [ReadinessObligation]
    public var historyCount: Int
    /// Kinds of current (not archived) documents filed on it.
    public var documentKinds: [DocumentKind]
    /// The facts each of its category's deadlines keeps (a policy's number and claims
    /// phone), in the category's order.
    public var facts: [ReadinessFacts]

    public init(
        id: UUID = UUID(),
        name: String,
        templateKey: String,
        role: CategoryBehavior.Role? = nil,
        parentId: UUID? = nil,
        isSensitive: Bool = false,
        values: FieldValues = FieldValues(),
        obligations: [String: ReadinessObligation] = [:],
        otherObligations: [ReadinessObligation] = [],
        historyCount: Int = 0,
        documentKinds: [DocumentKind] = [],
        facts: [ReadinessFacts] = []
    ) {
        self.id = id
        self.name = name
        self.templateKey = templateKey
        self.role = role
        self.parentId = parentId
        self.isSensitive = isSensitive
        self.values = values
        self.obligations = obligations
        self.otherObligations = otherObligations
        self.historyCount = historyCount
        self.documentKinds = documentKinds
        self.facts = facts
    }

    /// Every active obligation, the category's and the person's own.
    public var allObligations: [ReadinessObligation] {
        obligations.values.sorted { $0.due < $1.due } + otherObligations
    }
}

/// One deadline's fact roles, as the readiness checks read them.
public struct ReadinessFacts: Hashable, Sendable {
    public var blueprintKey: String
    /// The deadline's title ("RCA", "CASCO").
    public var title: String
    public var facts: BlueprintFacts

    public init(blueprintKey: String, title: String = "", facts: BlueprintFacts) {
        self.blueprintKey = blueprintKey
        self.title = title
        self.facts = facts
    }

    /// Every deadline of `template` that keeps facts, in the template's order.
    public static func of(_ template: TemplateDefinition) -> [ReadinessFacts] {
        template.blueprints.compactMap { blueprint in
            blueprint.facts.map { ReadinessFacts(blueprintKey: blueprint.key, title: blueprint.title, facts: $0) }
        }
    }
}
