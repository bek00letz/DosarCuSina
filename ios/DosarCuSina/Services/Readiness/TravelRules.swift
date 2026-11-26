import Foundation

/// One thing a traveller must carry: a need (an identity document, a passport, a residence
/// permit), the document types that meet it, any one of them, and how long one counts.
public struct TravelRequirement: Hashable, Sendable {
    public enum Need: String, Hashable, Sendable, CaseIterable {
        /// An identity card or a passport, whichever is valid: an EU citizen in the EU.
        case identity
        /// A passport.
        case passport
        /// A valid residence permit: a citizen of a country outside the EU who lives in Romania.
        case residencePermit
    }

    public var need: Need
    /// The document types that meet it, any one of them, in the order they are preferred; the
    /// first is the one a check asks to add.
    public var accepted: [String]
    /// A passport counts until it stops being good for travel (its type's travel margin,
    /// outside the EU), not until its printed expiry.
    public var countsTravelCutoff: Bool
    /// How many months after the trip ends the document must still be valid: what the
    /// destination's countries ask (0: until the trip ends).
    public var monthsValidAfterReturn: Int

    public init(_ need: Need, accepted: [String], countsTravelCutoff: Bool = false, monthsValidAfterReturn: Int = 0) {
        self.need = need
        self.accepted = accepted
        self.countsTravelCutoff = countsTravelCutoff
        self.monthsValidAfterReturn = monthsValidAfterReturn
    }

    /// The last day the trip needs the document valid through: the day back, or as many months
    /// after it as the destination asks.
    public func lastDayNeeded(returning end: CalendarDay, calendar: Calendar) -> CalendarDay {
        monthsValidAfterReturn > 0 ? end.adding(months: monthsValidAfterReturn, calendar: calendar) : end
    }
}

/// What each traveller carries, by their citizenship and where they go, declared once: the
/// trip check reads these tables and never tests for a country in code.
///
/// - In the EU and the rest of the Schengen area (`TripPlan.Region.europeanUnion`: the EU's 27,
///   Switzerland, Norway, Iceland and Liechtenstein), an EU, EEA or Swiss citizen travels with an
///   identity card or a passport, valid until they come back.
/// - In Moldova and the Western Balkans (`moldovaAndWesternBalkans`), the citizenships whose
///   identity card those countries accept (`identityCards`) travel with it or a passport, still
///   valid some months after they come back; everyone else as outside the EU.
/// - A citizen of a country outside the EU who lives in Romania carries a passport and a
///   valid residence permit, wherever they go: the permit is what lets them back in.
/// - Anywhere else everyone needs a passport good for travel until the trip ends, and is
///   reminded to look up the destination's visa rules (the binder keeps no visa rules).
/// - With the citizenship not known, the check asks it first; outside the EU the passport
///   is checked meanwhile, since everyone needs one there.
/// - A person with several citizenships travels on the most favourable for the trip, with the
///   documents of that citizenship (`ReadinessEngine.travellerChecks`).
public enum TravelRules {
    static let identityOrPassport = TravelRequirement(.identity, accepted: [DocumentType.idCard, DocumentType.passport])
    /// Moldova and the Western Balkans: an identity card or a passport still valid three months
    /// after the trip, the longest any of them asks (North Macedonia: 90 days after leaving;
    /// Bosnia and Herzegovina: three months past the stay).
    static let identityOrPassportPastReturn = TravelRequirement(.identity, accepted: [DocumentType.idCard, DocumentType.passport],
                                                                monthsValidAfterReturn: 3)
    static let passport = TravelRequirement(.passport, accepted: [DocumentType.passport])
    static let passportForTravel = TravelRequirement(.passport, accepted: [DocumentType.passport], countsTravelCutoff: true)
    /// A residence permit, or the same right in another of its forms: an EU citizen's family
    /// member's residence card, a British citizen's under the Withdrawal Agreement (its variants).
    static let residencePermit = TravelRequirement(.residencePermit, accepted: [DocumentType.residencePermit])

    /// Every requirement the tables use, for the words and their tests.
    static let allRequirements = [identityOrPassport, identityOrPassportPastReturn, passport, passportForTravel, residencePermit]

    static let table: [Citizenship.Group: [TripPlan.Region: [TravelRequirement]]] = [
        .freeMovement: [.europeanUnion: [identityOrPassport], .moldovaAndWesternBalkans: [passportForTravel], .outsideEU: [passportForTravel]],
        .thirdCountry: [.europeanUnion: [passport, residencePermit], .moldovaAndWesternBalkans: [passportForTravel, residencePermit],
                        .outsideEU: [passportForTravel, residencePermit]],
        .unknown: [.europeanUnion: [], .moldovaAndWesternBalkans: [passportForTravel], .outsideEU: [passportForTravel]],
    ]

    /// Where a region's countries take a citizenship's identity card instead of a passport, by
    /// the citizenship's ISO code, with the requirement they set and where the rule comes from
    /// (written to `shared/travel/` with it). Kosovo isn't among them: Serbia's and Montenegro's
    /// pages send travellers there with a passport. Other EU citizens are not listed until their
    /// own country's rules are checked, so they are asked for a passport.
    static let identityCards: [TripPlan.Region: (citizens: Set<String>, requirement: TravelRequirement, source: String)] = [
        .moldovaAndWesternBalkans: (["RO"], identityOrPassportPastReturn,
                                    "Romania's Ministry of Foreign Affairs, „Condiții de călătorie” (mae.ro/travel-conditions), read in November 2026: "
                                        + "Republica Moldova (3739), Serbia (3742), Muntenegru (3728), Macedonia de Nord (3721), Albania (3664) and "
                                        + "Bosnia și Herțegovina (3675) each let a Romanian citizen in with a valid identity card or passport."),
    ]

    /// What a traveller of `group` carries in `region`, in the order the check lists it.
    public static func requirements(for group: Citizenship.Group, in region: TripPlan.Region) -> [TravelRequirement] {
        table[group]?[region] ?? []
    }

    /// What a citizen of `citizenship` (a stored key; nil when not known) carries in `region`:
    /// the identity card where the region's countries take it, else their group's rules.
    public static func requirements(forCitizenship citizenship: String?, in region: TripPlan.Region) -> [TravelRequirement] {
        if let code = Citizenship.country(forKey: citizenship)?.code, let cards = identityCards[region], cards.citizens.contains(code) {
            return [cards.requirement]
        }
        return requirements(for: Citizenship.group(of: citizenship), in: region)
    }

    /// Whether the check reminds everyone going to look up the destination's visa rules.
    public static func remindsOfVisa(in region: TripPlan.Region) -> Bool { region == .outsideEU }

    /// Whether the European health card is checked: in the EU and the Schengen area, whoever goes.
    public static func checksHealthCard(in region: TripPlan.Region) -> Bool { region == .europeanUnion }

    // MARK: Kinds of document

    /// Kinds of document that are no travel document at all: the simple identity card issued
    /// since 2025 (CIS), good only inside Romania (Ministerul Afacerilor Interne,
    /// carteadeidentitate.gov.ro).
    static let notForTravel: Set<String> = [DocumentType.Variant.idCardSimple]

    /// The last day a kind of document is good for travel, whatever its printed expiry: an
    /// identity card without a chip ceases to be valid by 3 August 2031 (Regulation (EU)
    /// 2019/1157, art. 5(1)), so its last day is 2 August 2031.
    static let travelEnds: [String: CalendarDay] = [
        DocumentType.Variant.idCardWithoutChip: CalendarDay(year: 2031, month: 8, day: 2),
    ]

    static func variant(of values: FieldValues) -> String? {
        values[DocumentType.variantFieldKey]?.textValue
    }

    /// Whether a document can be travelled with at all.
    static func travels(_ values: FieldValues) -> Bool {
        variant(of: values).map { !notForTravel.contains($0) } ?? true
    }

    /// The last day a document is good for travel by its kind, when its kind has one.
    static func travelEnd(of values: FieldValues) -> CalendarDay? {
        variant(of: values).flatMap { travelEnds[$0] }
    }
}


/// What the trip check says about a need, declared once per need and document type, as the
/// kinds of `ReadinessWords`: which sentence is decided here, its words there.
enum TravelWording {
    /// The title of a need nothing in the binder meets yet.
    static func title(of requirement: TravelRequirement) -> ReadinessWords {
        switch requirement.need {
        case .identity: .identityOrPassport
        case .passport: .documentType(DocumentType.passport)
        case .residencePermit: .documentType(DocumentType.residencePermit)
        }
    }

    /// A document that covers the whole trip. `instead` is set when an earlier choice of the
    /// need is in the binder but doesn't (the identity card ends before the passport).
    static func valid(_ requirement: TravelRequirement, type: String, until day: CalendarDay, instead: Bool) -> ReadinessWords {
        let months = requirement.monthsValidAfterReturn
        let past = months > 0
        switch (requirement.need, type) {
        case (.identity, DocumentType.idCard):
            return past ? .idCardValidPastReturn(day, months) : .idCardValid(day)
        case (.identity, _):
            switch (instead, past) {
            case (true, true): return .passportInsteadPastReturn(day, months)
            case (true, false): return .passportInstead(day)
            case (false, true): return .passportValidPastReturn(day, months)
            case (false, false): return .passportValidInEU(day)
            }
        case (.passport, _):
            return requirement.countsTravelCutoff ? .passportGoodForTravel(day) : .validUntil(day)
        case (.residencePermit, _):
            return .residencePermitValid(day)
        }
    }

    /// The best document of the need doesn't last: it ended before `today`, stops being good
    /// for travel by its kind (`travelEnd`: an identity card without a chip), ends before the
    /// trip does, or before the months after it the destination asks. A day already passed is
    /// said as passed.
    static func ends(_ requirement: TravelRequirement, type: String, expiry: CalendarDay, goodUntil: CalendarDay, today: CalendarDay) -> ReadinessWords {
        let expired = expiry < today
        let months = requirement.monthsValidAfterReturn
        let past = months > 0
        switch (requirement.need, type) {
        case (.identity, DocumentType.idCard):
            if expired { return .idCardExpired(expiry) }
            if goodUntil < expiry { return .idCardWithoutChipEnds(goodUntil) }
            return past ? .idCardEndsPastReturn(expiry, months) : .idCardEnds(expiry)
        case (.identity, _):
            if expired { return .identityPassportExpired(expiry) }
            return past ? .identityPassportEndsPastReturn(expiry, months) : .identityPassportEnds(expiry)
        case (.passport, _):
            if expired { return .passportExpired(expiry) }
            guard requirement.countsTravelCutoff else { return .passportEnds(expiry) }
            return goodUntil < today ? .passportCutoffPassed(goodUntil, expiry) : .passportCutoffBeforeReturn(goodUntil, expiry)
        case (.residencePermit, _):
            return expired ? .residencePermitExpired(expiry) : .residencePermitEnds(expiry)
        }
    }

    /// Nothing in the binder meets the need.
    static func missing(_ requirement: TravelRequirement) -> ReadinessWords {
        switch requirement.need {
        case .identity:
            requirement.monthsValidAfterReturn > 0 ? .identityMissingPastReturn(requirement.monthsValidAfterReturn) : .identityMissing
        case .passport:
            requirement.countsTravelCutoff ? .passportMissingForTravel : .passportMissingInEU
        case .residencePermit:
            .residencePermitMissing
        }
    }
}
