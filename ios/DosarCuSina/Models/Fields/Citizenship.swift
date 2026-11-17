import Foundation

/// The countries a person can be a citizen of, as data: each by its ISO 3166-1 code (the
/// stored key is `country.` and the two-letter code, "country.RO"), the three-letter code a
/// document's machine-readable zone prints ("ROU"), and whether its citizens move freely in
/// the EU (the 27 member states, the other EEA states and Switzerland). Names are written in
/// Romanian, from the app's locale.
///
/// A person's citizenship is kept on them (`MemberFields.citizenship`), read from their
/// passport, identity card or residence permit where the document prints it
/// (`DocumentFields.nationality`), and changed on their page. The trip check reads its rules
/// from the group a citizenship falls in (`Citizenship.Group`, `TravelRules`), never from a
/// country named in code.
public enum Citizenship {
    /// One country of citizenship.
    public struct Country: Hashable, Sendable {
        /// ISO 3166-1 alpha-2: "RO".
        public let code: String
        /// The three-letter code documents print: ISO 3166-1 alpha-3, or ICAO's where it differs.
        public let printedCode: String
        /// Other codes documents print for the same citizenship (Germany's "D").
        let otherCodes: [String]

        init(_ code: String, _ printedCode: String, also otherCodes: [String] = []) {
            self.code = code
            self.printedCode = printedCode
            self.otherCodes = otherCodes
        }

        public var key: String { Citizenship.key(code) }

        /// Whether its citizens move freely in the EU: an EU or EEA state, or Switzerland.
        public var movesFreely: Bool { Citizenship.freeMovement.contains(code) }
    }

    /// What the travel rules know of a person's citizenship.
    public enum Group: String, Hashable, Sendable, CaseIterable {
        /// A citizen of an EU or EEA state, or of Switzerland.
        case freeMovement
        /// Any other citizenship, or none (stateless).
        case thirdCountry
        /// Not known yet: the trip check asks.
        case unknown
    }

    /// The stored key of a country, by its two-letter code.
    public static func key(_ code: String) -> String { "country." + code }

    /// Romania's key, the citizenship most of the binder's people have. Never assumed: it is
    /// only what a person or their documents say.
    public static let romania = key("RO")
    /// A person with no citizenship (apatrid): the rules of a citizen of a country outside the EU.
    public static let stateless = "country.stateless"

    /// The EU's 27 member states, the other EEA states (Iceland, Liechtenstein, Norway) and
    /// Switzerland, whose citizens travel in the EU with an identity card or a passport.
    static let freeMovement: Set<String> = [
        "AT", "BE", "BG", "HR", "CY", "CZ", "DK", "EE", "FI", "FR", "DE", "GR", "HU", "IE", "IT", "LV", "LT", "LU",
        "MT", "NL", "PL", "PT", "RO", "SK", "SI", "ES", "SE",
        "IS", "LI", "NO",
        "CH",
    ]

    /// Every country with a citizenship of its own: the UN's members, the Holy See, Palestine,
    /// Kosovo and Taiwan. Territories whose people hold another state's citizenship aren't here.
    public static let countries: [Country] = [
        Country("AD", "AND"), Country("AE", "ARE"), Country("AF", "AFG"), Country("AG", "ATG"), Country("AL", "ALB"),
        Country("AM", "ARM"), Country("AO", "AGO"), Country("AR", "ARG"), Country("AT", "AUT"), Country("AU", "AUS"),
        Country("AZ", "AZE"), Country("BA", "BIH"), Country("BB", "BRB"), Country("BD", "BGD"), Country("BE", "BEL"),
        Country("BF", "BFA"), Country("BG", "BGR"), Country("BH", "BHR"), Country("BI", "BDI"), Country("BJ", "BEN"),
        Country("BN", "BRN"), Country("BO", "BOL"), Country("BR", "BRA"), Country("BS", "BHS"), Country("BT", "BTN"),
        Country("BW", "BWA"), Country("BY", "BLR"), Country("BZ", "BLZ"), Country("CA", "CAN"), Country("CD", "COD"),
        Country("CF", "CAF"), Country("CG", "COG"), Country("CH", "CHE"), Country("CI", "CIV"), Country("CL", "CHL"),
        Country("CM", "CMR"), Country("CN", "CHN"), Country("CO", "COL"), Country("CR", "CRI"), Country("CU", "CUB"),
        Country("CV", "CPV"), Country("CY", "CYP"), Country("CZ", "CZE"), Country("DE", "DEU", also: ["D"]), Country("DJ", "DJI"),
        Country("DK", "DNK"), Country("DM", "DMA"), Country("DO", "DOM"), Country("DZ", "DZA"), Country("EC", "ECU"),
        Country("EE", "EST"), Country("EG", "EGY"), Country("ER", "ERI"), Country("ES", "ESP"), Country("ET", "ETH"),
        Country("FI", "FIN"), Country("FJ", "FJI"), Country("FM", "FSM"), Country("FR", "FRA"), Country("GA", "GAB"),
        Country("GB", "GBR", also: ["GBD", "GBN", "GBO", "GBP", "GBS"]), Country("GD", "GRD"), Country("GE", "GEO"),
        Country("GH", "GHA"), Country("GM", "GMB"), Country("GN", "GIN"), Country("GQ", "GNQ"), Country("GR", "GRC"),
        Country("GT", "GTM"), Country("GW", "GNB"), Country("GY", "GUY"), Country("HN", "HND"), Country("HR", "HRV"),
        Country("HT", "HTI"), Country("HU", "HUN"), Country("ID", "IDN"), Country("IE", "IRL"), Country("IL", "ISR"),
        Country("IN", "IND"), Country("IQ", "IRQ"), Country("IR", "IRN"), Country("IS", "ISL"), Country("IT", "ITA"),
        Country("JM", "JAM"), Country("JO", "JOR"), Country("JP", "JPN"), Country("KE", "KEN"), Country("KG", "KGZ"),
        Country("KH", "KHM"), Country("KI", "KIR"), Country("KM", "COM"), Country("KN", "KNA"), Country("KP", "PRK"),
        Country("KR", "KOR"), Country("KW", "KWT"), Country("KZ", "KAZ"), Country("LA", "LAO"), Country("LB", "LBN"),
        Country("LC", "LCA"), Country("LI", "LIE"), Country("LK", "LKA"), Country("LR", "LBR"), Country("LS", "LSO"),
        Country("LT", "LTU"), Country("LU", "LUX"), Country("LV", "LVA"), Country("LY", "LBY"), Country("MA", "MAR"),
        Country("MC", "MCO"), Country("MD", "MDA"), Country("ME", "MNE"), Country("MG", "MDG"), Country("MH", "MHL"),
        Country("MK", "MKD"), Country("ML", "MLI"), Country("MM", "MMR"), Country("MN", "MNG"), Country("MR", "MRT"),
        Country("MT", "MLT"), Country("MU", "MUS"), Country("MV", "MDV"), Country("MW", "MWI"), Country("MX", "MEX"),
        Country("MY", "MYS"), Country("MZ", "MOZ"), Country("NA", "NAM"), Country("NE", "NER"), Country("NG", "NGA"),
        Country("NI", "NIC"), Country("NL", "NLD"), Country("NO", "NOR"), Country("NP", "NPL"), Country("NR", "NRU"),
        Country("NZ", "NZL"), Country("OM", "OMN"), Country("PA", "PAN"), Country("PE", "PER"), Country("PG", "PNG"),
        Country("PH", "PHL"), Country("PK", "PAK"), Country("PL", "POL"), Country("PS", "PSE"), Country("PT", "PRT"),
        Country("PW", "PLW"), Country("PY", "PRY"), Country("QA", "QAT"), Country("RO", "ROU"), Country("RS", "SRB"),
        Country("RU", "RUS"), Country("RW", "RWA"), Country("SA", "SAU"), Country("SB", "SLB"), Country("SC", "SYC"),
        Country("SD", "SDN"), Country("SE", "SWE"), Country("SG", "SGP"), Country("SI", "SVN"), Country("SK", "SVK"),
        Country("SL", "SLE"), Country("SM", "SMR"), Country("SN", "SEN"), Country("SO", "SOM"), Country("SR", "SUR"),
        Country("SS", "SSD"), Country("ST", "STP"), Country("SV", "SLV"), Country("SY", "SYR"), Country("SZ", "SWZ"),
        Country("TD", "TCD"), Country("TG", "TGO"), Country("TH", "THA"), Country("TJ", "TJK"), Country("TL", "TLS"),
        Country("TM", "TKM"), Country("TN", "TUN"), Country("TO", "TON"), Country("TR", "TUR"), Country("TT", "TTO"),
        Country("TV", "TUV"), Country("TW", "TWN"), Country("TZ", "TZA"), Country("UA", "UKR"), Country("UG", "UGA"),
        Country("US", "USA"), Country("UY", "URY"), Country("UZ", "UZB"), Country("VA", "VAT"), Country("VC", "VCT"),
        Country("VE", "VEN"), Country("VN", "VNM"), Country("VU", "VUT"), Country("WS", "WSM"), Country("XK", "RKS", also: ["XKK"]),
        Country("YE", "YEM"), Country("ZA", "ZAF"), Country("ZM", "ZMB"), Country("ZW", "ZWE"),
    ]

    /// The codes documents print for having no citizenship (ICAO: stateless, refugee).
    static let statelessCodes = ["XXA", "XXB", "XXC"]

    /// How a citizenship is said on a Romanian document beside its code ("Română / ROU").
    static let adjectives: [String: [String]] = [
        "RO": ["Română", "Român", "Romana", "Roman", "Romanian"],
        "MD": ["Moldoveană", "Moldovean", "Moldovan"],
    ]

    /// A country's name, in Romanian. A few of the system's names are written as a
    /// citizenship is said ("China", not the mainland).
    public static func name(of country: Country) -> String {
        if let own = ownNames[country.code] { return own }
        return Locale.dosarDefault.localizedString(forRegionCode: country.code) ?? country.code
    }

    private static var ownNames: [String: String] {
        [
            "CN": String(localized: "China", comment: "A citizenship: China."),
            "PS": String(localized: "Palestina", comment: "A citizenship: Palestine."),
            "CD": String(localized: "Republica Democratică Congo", comment: "A citizenship: the Democratic Republic of the Congo."),
            "CG": String(localized: "Republica Congo", comment: "A citizenship: the Republic of the Congo."),
        ]
    }

    /// The choice of countries a person's citizenship field offers, by name, with "Fără
    /// cetățenie" last. A country is also matched by its codes and, for Romania and Moldova,
    /// by how their documents say it. Made once: the names don't change while the app runs.
    public static let options: [ChoiceOption] = makeOptions()

    private static func makeOptions() -> [ChoiceOption] {
        let named = countries.map { country in
            ChoiceOption(key: country.key, label: name(of: country),
                         aliases: [country.code, country.printedCode] + country.otherCodes + (adjectives[country.code] ?? []))
        }
        .sorted { $0.label.compare($1.label, locale: Locale.dosarDefault) == .orderedAscending }
        let none = ChoiceOption(key: stateless, label: String(localized: "Fără cetățenie (apatrid)", comment: "A citizenship choice: none, stateless."),
                                aliases: statelessCodes + ["Apatrid", "Stateless"])
        return named + [none]
    }

    /// The country of a stored key.
    public static func country(forKey key: String?) -> Country? {
        guard let key, key.hasPrefix("country.") else { return nil }
        let code = String(key.dropFirst("country.".count))
        return countries.first { $0.code == code }
    }

    /// The country's name for a stored key ("România"), or "Fără cetățenie (apatrid)".
    public static func label(for key: String?) -> String? {
        guard let key else { return nil }
        return options.option(for: key)?.label
    }

    /// The stored key of the citizenship a document's nationality names: its code, as the
    /// machine-readable zone prints it ("ROU", "MDA", "D"), "Română / ROU" as an identity
    /// card prints it, a country's name, or a key already. Nil for anything else.
    public static func key(forNationality text: String?) -> String? {
        guard let text = text?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else { return nil }
        if let option = options.option(for: text) { return option.key }
        // "Română / ROU": the parts, each on its own.
        let parts = text.split { !$0.isLetter && $0 != " " }.map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        for part in parts {
            if let option = options.option(for: part) { return option.key }
        }
        return nil
    }

    /// The group a stored citizenship falls in, for the travel rules.
    public static func group(of key: String?) -> Group {
        guard let key else { return .unknown }
        if key == stateless { return .thirdCountry }
        guard let country = country(forKey: key) else { return .unknown }
        return country.movesFreely ? .freeMovement : .thirdCountry
    }

    /// A person's citizenship: what is kept on them, else what their documents say
    /// (`DocumentFields.nationality`; a free-movement citizenship first, for a person with
    /// two). Nil when neither says.
    public static func of(person: FieldValues?, documents: [FieldValues]) -> String? {
        if let kept = person?[MemberFields.citizenship]?.textValue, let key = options.option(for: kept)?.key { return key }
        return read(fromDocuments: documents)
    }

    /// The citizenship a person's documents print: a free-movement one first, else the first.
    public static func read(fromDocuments documents: [FieldValues]) -> String? {
        let read = documents.compactMap { key(forNationality: $0[DocumentFields.nationality]?.textValue) }
        return read.first { group(of: $0) == .freeMovement } ?? read.first
    }
}
