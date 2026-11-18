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
    /// the citizenship's ISO code, with the requirement they set. Romania's Ministry of Foreign
    /// Affairs, „Condiții de călătorie” (mae.ro/travel-conditions), read in November 2026:
    /// Republica Moldova (3739), Serbia (3742), Muntenegru (3728), Macedonia de Nord (3721),
    /// Albania (3664) and Bosnia și Herțegovina (3675) each let a Romanian citizen in with a
    /// valid identity card or passport. Kosovo isn't among them: Serbia's and Montenegro's pages
    /// send travellers there with a passport. Other EU citizens are not listed until their own
    /// country's rules are checked, so they are asked for a passport.
    static let identityCards: [TripPlan.Region: (citizens: Set<String>, requirement: TravelRequirement)] = [
        .moldovaAndWesternBalkans: (["RO"], identityOrPassportPastReturn),
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

/// What the trip check says about a need, declared once per need and document type.
enum TravelWording {
    /// The title of a need nothing in the binder meets yet.
    static func title(of requirement: TravelRequirement) -> String {
        switch requirement.need {
        case .identity: String(localized: "Carte de identitate sau pașaport", comment: "Trip check: an EU citizen's identity document, either one.")
        case .passport: DocumentType.label(for: DocumentType.passport) ?? ""
        case .residencePermit: DocumentType.label(for: DocumentType.residencePermit) ?? ""
        }
    }

    /// "3 luni", for the months a destination asks after the trip.
    private static func months(_ requirement: TravelRequirement) -> String {
        CalendarCount.months(requirement.monthsValidAfterReturn)
    }

    /// A document that covers the whole trip. `instead` is set when an earlier choice of the
    /// need is in the binder but doesn't (the identity card ends before the passport).
    static func valid(_ requirement: TravelRequirement, type: String, until: CalendarDay, instead: Bool) -> String {
        let day = DosarFormat.longDay(until)
        let past = requirement.monthsValidAfterReturn > 0
        switch (requirement.need, type) {
        case (.identity, DocumentType.idCard):
            return past
                ? String(localized: "Valabilă până pe \(day), și la \(months(requirement)) după ce te întorci, cât cer țările de acolo.", comment: "Trip check: an ID card valid long enough after a trip to Moldova or the Western Balkans. The second argument is a number of months.")
                : String(localized: "Valabilă până pe \(day). Ajunge pentru toată UE.", comment: "Trip check: an ID card valid for the whole trip.")
        case (.identity, _):
            switch (instead, past) {
            case (true, true):
                return String(localized: "Valabil până pe \(day). Ia-l pe el: cartea de identitate nu mai e valabilă la \(months(requirement)) după ce te întorci.", comment: "Trip check: the ID card isn't valid long enough after a trip to Moldova or the Western Balkans; the passport is. The second argument is a number of months.")
            case (true, false):
                return String(localized: "Valabil până pe \(day). Ia-l pe el: cartea de identitate nu mai e valabilă la întoarcere.", comment: "Trip check: the ID card ends before return, the passport covers the trip.")
            case (false, true):
                return String(localized: "Valabil până pe \(day), și la \(months(requirement)) după ce te întorci, cât cer țările de acolo.", comment: "Trip check: a passport valid long enough after a trip to Moldova or the Western Balkans. The second argument is a number of months.")
            case (false, false):
                return String(localized: "Valabil până pe \(day). În UE ajunge și pașaportul.", comment: "Trip check: no ID card, but the passport is valid inside the EU.")
            }
        case (.passport, _):
            return requirement.countsTravelCutoff
                ? String(localized: "Bun de călătorit până pe \(day), după ce te întorci.", comment: "Trip check: the passport is good for travel past the end of the trip.")
                : String(localized: "Valabil până pe \(day).", comment: "Readiness: a deadline valid until a day.")
        case (.residencePermit, _):
            return String(localized: "Valabil până pe \(day). Ia-l cu tine: îți trebuie ca să intri înapoi în țară.", comment: "Trip check: the residence permit covers the trip; it is needed to come back.")
        }
    }

    /// The best document of the need doesn't last: it ended before `today`, stops being good
    /// for travel by its kind (`travelEnd`: an identity card without a chip), ends before the
    /// trip does, or before the months after it the destination asks. A day already passed is
    /// said as passed.
    static func ends(_ requirement: TravelRequirement, type: String, expiry: CalendarDay, goodUntil: CalendarDay, today: CalendarDay) -> String {
        let day = DosarFormat.longDay(expiry)
        let good = DosarFormat.longDay(goodUntil)
        let expired = expiry < today
        let past = requirement.monthsValidAfterReturn > 0
        switch (requirement.need, type) {
        case (.identity, DocumentType.idCard):
            if expired {
                return String(localized: "A expirat pe \(day). Fă-ți alta sau ia un pașaport valabil.", comment: "Trip check: the ID card has already expired.")
            }
            if goodUntil < expiry {
                return String(localized: "Fără cip, e bună de călătorit doar până pe \(good). Fă-ți cartea electronică sau ia un pașaport valabil.", comment: "Trip check: an ID card without a chip stops being a travel document before the trip ends (EU rules).")
            }
            return past
                ? String(localized: "Expiră pe \(day), la mai puțin de \(months(requirement)) după ce te întorci, iar țările de acolo o cer valabilă cel puțin atât. Fă-ți alta sau ia un pașaport valabil.", comment: "Trip check: the ID card isn't valid long enough after a trip to Moldova or the Western Balkans. The second argument is a number of months.")
                : String(localized: "Expiră pe \(day), înainte să te întorci. Fă-ți alta sau ia un pașaport valabil.", comment: "Trip check: the ID card expires before the end of an EU trip.")
        case (.identity, _):
            if expired {
                return String(localized: "A expirat pe \(day). Fă-ți altul sau ia o carte de identitate valabilă.", comment: "Trip check: the passport, an EU citizen's only identity document, has already expired.")
            }
            return past
                ? String(localized: "Expiră pe \(day), la mai puțin de \(months(requirement)) după ce te întorci, iar țările de acolo îl cer valabil cel puțin atât. Fă-ți altul sau ia o carte de identitate valabilă.", comment: "Trip check: the passport isn't valid long enough after a trip to Moldova or the Western Balkans. The second argument is a number of months.")
                : String(localized: "Expiră pe \(day), înainte să te întorci. Fă-ți altul sau ia o carte de identitate valabilă.", comment: "Trip check: the passport, an EU citizen's only identity document, expires before the end of an EU trip.")
        case (.passport, _):
            if expired {
                return String(localized: "A expirat pe \(day). Fă-ți altul înainte de plecare.", comment: "Trip check: the passport has already expired.")
            }
            guard requirement.countsTravelCutoff else {
                return String(localized: "Expiră pe \(day), înainte să te întorci. Fă-ți altul înainte de plecare.", comment: "Trip check: the passport expires before the end of an EU trip, for a citizen of a country outside the EU.")
            }
            return goodUntil < today
                ? String(localized: "Era bun de călătorit doar până pe \(good). Expiră pe \(day), iar multe țări nu primesc un pașaport atât de aproape de expirare. Fă-ți altul înainte de plecare.", comment: "Trip check: the passport's travel cut-off has already passed, though it hasn't expired.")
                : String(localized: "Bun de călătorit doar până pe \(good). Expiră pe \(day), iar multe țări nu primesc un pașaport atât de aproape de expirare. Fă-ți altul înainte de plecare.", comment: "Trip check: the passport's travel cut-off falls before the end of a trip outside the EU.")
        case (.residencePermit, _):
            return expired
                ? String(localized: "A expirat pe \(day). Fără un permis valabil nu poți intra înapoi în țară. Întreabă la Imigrări ce poți face înainte de plecare.", comment: "Trip check: the residence permit has already expired.")
                : String(localized: "Expiră pe \(day), înainte să te întorci. Cere prelungirea cu cel puțin 30 de zile înainte să expire.", comment: "Trip check: the residence permit expires before the end of the trip.")
        }
    }

    /// Nothing in the binder meets the need.
    static func missing(_ requirement: TravelRequirement) -> String {
        switch requirement.need {
        case .identity:
            requirement.monthsValidAfterReturn > 0
                ? String(localized: "Nu sunt în dosar. Acolo merge oricare, dacă e valabil și la \(months(requirement)) după ce te întorci. Adaugă-l cu o poză și verific.", comment: "Trip check: neither an ID card nor a passport in the binder, for a trip to Moldova or the Western Balkans. The argument is a number of months.")
                : String(localized: "Nu sunt în dosar. Adaugă unul dintre ele cu o poză și verific până când e valabil.", comment: "Trip check: neither an ID card nor a passport in the binder, for an EU citizen.")
        case .passport:
            requirement.countsTravelCutoff
                ? String(localized: "Nu e în dosar. Pentru drumul acesta ai nevoie de pașaport. Adaugă-l cu o poză și verific până când e bun.", comment: "Trip check: no passport for a trip outside the EU and the Schengen area.")
                : String(localized: "Nu e în dosar. Fără cetățenie europeană, ai nevoie de pașaport și în UE. Adaugă-l cu o poză și verific până când e valabil.", comment: "Trip check: no passport for an EU trip, for a citizen of a country outside the EU.")
        case .residencePermit:
            String(localized: "Nu e în dosar. Fără el nu poți intra înapoi în țară. Adaugă-l cu o poză și verific până când e valabil.", comment: "Trip check: no residence permit in the binder.")
        }
    }

    /// The only identity documents in the binder are no travel document (`TravelRules.notForTravel`).
    static var notATravelDocument: String {
        String(localized: "Cartea de identitate simplă nu e act de călătorie: e bună doar în țară. Ia un pașaport sau fă-ți cartea electronică.", comment: "Trip check: the simple identity card (CIS) isn't a travel document.")
    }

    /// A document of the need with no expiry written down.
    static var undated: String {
        String(localized: "Nu știu până când e valabil. Adaugă data de expirare.", comment: "Trip check: an identity document without an expiry date.")
    }

    // MARK: Citizenship

    static var citizenshipTitle: String {
        String(localized: "Cetățenia", comment: "Trip check: a traveller's citizenship, not known yet.")
    }

    /// The citizenship isn't known: asked once, kept on the person.
    static var citizenshipAsked: String {
        String(localized: "Spune-mi ce cetățenie are, ca să știu ce acte îi trebuie.", comment: "Trip check: a member's citizenship isn't known; tapping asks it.")
    }

    /// Documents filed under no one: their holder's citizenship can't be kept until they are.
    static var citizenshipOfUnfiled: String {
        String(localized: "Nu știu ce cetățenie are titularul. Mută actele la persoana lor și spune-mi ce cetățenie are.", comment: "Trip check: documents filed under no one, with no citizenship known.")
    }

    // MARK: Visa

    static var visaTitle: String {
        String(localized: "Viza pentru țara în care mergi", comment: "Trip reminder: look up the destination's visa rules.")
    }

    static var visaDetail: String {
        String(localized: "Unele țări cer viză sau o autorizație de călătorie, după cetățenie. Verifică ce cere țara înainte de plecare.", comment: "Trip reminder: visa rules depend on the destination and the citizenship.")
    }
}
