import Foundation

/// One thing a traveller must carry: a need (an identity document, a passport, a residence
/// permit), the document types that meet it, any one of them, and how long a passport counts.
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

    public init(_ need: Need, accepted: [String], countsTravelCutoff: Bool = false) {
        self.need = need
        self.accepted = accepted
        self.countsTravelCutoff = countsTravelCutoff
    }
}

/// What each traveller carries, by their citizenship's group (`Citizenship.Group`) and where
/// they go, declared once: the trip check reads this table and never names a country.
///
/// - An EU, EEA or Swiss citizen travels in the EU with an identity card or a passport,
///   valid until they come back.
/// - A citizen of a country outside the EU who lives in Romania carries a passport and a
///   valid residence permit, wherever they go: the permit is what lets them back in.
/// - Outside the EU everyone needs a passport good for travel until the trip ends, and is
///   reminded to look up the destination's visa rules (the binder keeps no visa rules).
/// - With the citizenship not known, the check asks it first; outside the EU the passport
///   is checked meanwhile, since everyone needs one there.
public enum TravelRules {
    static let identityOrPassport = TravelRequirement(.identity, accepted: [DocumentType.idCard, DocumentType.passport])
    static let passport = TravelRequirement(.passport, accepted: [DocumentType.passport])
    static let passportForTravel = TravelRequirement(.passport, accepted: [DocumentType.passport], countsTravelCutoff: true)
    static let residencePermit = TravelRequirement(.residencePermit, accepted: [DocumentType.residencePermit])

    static let table: [Citizenship.Group: [TripPlan.Region: [TravelRequirement]]] = [
        .freeMovement: [.europeanUnion: [identityOrPassport], .outsideEU: [passportForTravel]],
        .thirdCountry: [.europeanUnion: [passport, residencePermit], .outsideEU: [passportForTravel, residencePermit]],
        .unknown: [.europeanUnion: [], .outsideEU: [passportForTravel]],
    ]

    /// What a traveller of `group` carries in `region`, in the order the check lists it.
    public static func requirements(for group: Citizenship.Group, in region: TripPlan.Region) -> [TravelRequirement] {
        table[group]?[region] ?? []
    }

    /// Whether the check reminds everyone going to look up the destination's visa rules.
    public static func remindsOfVisa(in region: TripPlan.Region) -> Bool { region == .outsideEU }

    /// Whether the European health card is checked: inside the EU, whoever goes.
    public static func checksHealthCard(in region: TripPlan.Region) -> Bool { region == .europeanUnion }
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

    /// A document that covers the whole trip. `instead` is set when an earlier choice of the
    /// need is in the binder but doesn't (the identity card ends before the passport).
    static func valid(_ requirement: TravelRequirement, type: String, until: CalendarDay, instead: Bool) -> String {
        let day = DosarFormat.longDay(until)
        switch (requirement.need, type) {
        case (.identity, DocumentType.idCard):
            return String(localized: "Valabilă până pe \(day). Ajunge pentru toată UE.", comment: "Trip check: an ID card valid for the whole trip.")
        case (.identity, _):
            return instead
                ? String(localized: "Valabil până pe \(day). Ia-l pe el: cartea de identitate nu mai e valabilă la întoarcere.", comment: "Trip check: the ID card ends before return, the passport covers the trip.")
                : String(localized: "Valabil până pe \(day). În UE ajunge și pașaportul.", comment: "Trip check: no ID card, but the passport is valid inside the EU.")
        case (.passport, _):
            return requirement.countsTravelCutoff
                ? String(localized: "Bun de călătorit până pe \(day), după ce te întorci.", comment: "Trip check: the passport is good for travel past the end of the trip.")
                : String(localized: "Valabil până pe \(day).", comment: "Readiness: a deadline valid until a day.")
        case (.residencePermit, _):
            return String(localized: "Valabil până pe \(day). Ia-l cu tine: îți trebuie ca să intri înapoi în țară.", comment: "Trip check: the residence permit covers the trip; it is needed to come back.")
        }
    }

    /// The best document of the need ends before the trip does.
    static func ends(_ requirement: TravelRequirement, type: String, expiry: CalendarDay, goodUntil: CalendarDay) -> String {
        let day = DosarFormat.longDay(expiry)
        switch (requirement.need, type) {
        case (.identity, DocumentType.idCard):
            return String(localized: "Expiră pe \(day), înainte să te întorci. Fă-ți alta sau ia un pașaport valabil.", comment: "Trip check: the ID card expires before the end of an EU trip.")
        case (.identity, _):
            return String(localized: "Expiră pe \(day), înainte să te întorci. Fă-ți altul sau ia o carte de identitate valabilă.", comment: "Trip check: the passport, an EU citizen's only identity document, expires before the end of an EU trip.")
        case (.passport, _):
            return requirement.countsTravelCutoff
                ? String(localized: "Bun de călătorit doar până pe \(DosarFormat.longDay(goodUntil)). Expiră pe \(day), iar multe țări nu primesc un pașaport atât de aproape de expirare. Fă-ți altul înainte de plecare.", comment: "Trip check: the passport's travel cut-off falls before the end of a trip outside the EU.")
                : String(localized: "Expiră pe \(day), înainte să te întorci. Fă-ți altul înainte de plecare.", comment: "Trip check: the passport expires before the end of an EU trip, for a citizen of a country outside the EU.")
        case (.residencePermit, _):
            return String(localized: "Expiră pe \(day), înainte să te întorci. Cere prelungirea cu cel puțin 30 de zile înainte să expire.", comment: "Trip check: the residence permit expires before the end of the trip.")
        }
    }

    /// Nothing in the binder meets the need.
    static func missing(_ requirement: TravelRequirement) -> String {
        switch requirement.need {
        case .identity:
            String(localized: "Nu sunt în dosar. Adaugă unul dintre ele cu o poză și verific până când e valabil.", comment: "Trip check: neither an ID card nor a passport in the binder, for an EU citizen.")
        case .passport:
            requirement.countsTravelCutoff
                ? String(localized: "Nu e în dosar. În afara UE ai nevoie de pașaport. Adaugă-l cu o poză și verific până când e bun.", comment: "Trip check: no passport for a trip outside the EU.")
                : String(localized: "Nu e în dosar. Fără cetățenie europeană, ai nevoie de pașaport și în UE. Adaugă-l cu o poză și verific până când e valabil.", comment: "Trip check: no passport for an EU trip, for a citizen of a country outside the EU.")
        case .residencePermit:
            String(localized: "Nu e în dosar. Fără el nu poți intra înapoi în țară. Adaugă-l cu o poză și verific până când e valabil.", comment: "Trip check: no residence permit in the binder.")
        }
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
