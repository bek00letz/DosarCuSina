import Foundation

/// A Romanian postal address split into the parts that tell two places apart, as people
/// and providers write it: "Str. Exemplului nr. 1, bl. A1, sc. B, ap. 12, sector 3,
/// București". The same place is written many ways ("Strada" or "Str.", "nr." or none,
/// with or without diacritics), so two addresses are compared part by part, never as text.
///
/// Pure: text in, parts out, so every rule is pinned by tests.
public struct PostalAddress: Hashable, Sendable {
    /// The street's name in folded words, without its type: "exemplului".
    public var street: [String] = []
    /// The street's type, in one form ("strada", "bulevardul", "calea"…), when printed.
    public var streetType: String?
    public var number: String?
    public var block: String?
    public var staircase: String?
    public var apartment: String?
    public var sector: String?
    /// The city, town, commune or village, in folded words.
    public var locality: [String] = []
    /// The county, when printed ("jud. Brașov"). Not compared: the town tells places apart.
    public var county: [String] = []
    /// Whether any address marker was printed ("nr.", "bl.", "ap.", "sector", a town).
    private var hasMarkers = false

    /// Reads an address. Nil when the text doesn't name a place: a street with its type or
    /// a number, or a village or town with a number.
    public init?(_ text: String) {
        parse(text)
        // A street without its type counts only beside a printed marker ("nr.", "bl.", a town):
        // "Cod client 1000000000" is not "street Cod client, number 1000000000".
        let hasStreet = !street.isEmpty && (streetType != nil || (number != nil && hasMarkers))
        let hasVillage = street.isEmpty && !locality.isEmpty && number != nil
        guard hasStreet || hasVillage else { return nil }
    }

    /// Whether a line names only where a street is ("Sector 3, București", "Jud. Brașov"):
    /// the rest of an address printed on two lines.
    static func namesOnlyThePlace(_ line: String) -> Bool {
        var parts = PostalAddress()
        parts.parse(line)
        let unit = [parts.number, parts.block, parts.staircase, parts.apartment].contains { $0 != nil }
        return parts.street.isEmpty && parts.streetType == nil && !unit
            && (parts.sector != nil || !parts.locality.isEmpty || !parts.county.isEmpty)
    }

    private init() {}

    // MARK: - Comparing

    /// How sure it is that two addresses name the same place, from least to most.
    public enum Agreement: Int, Comparable, Hashable, Sendable {
        /// A part both print differs: another number, block, staircase, apartment, sector
        /// or town, or another street altogether.
        case different
        /// Too little to compare.
        case unknown
        /// Nothing differs, but something is missing or only nearly the same: the same
        /// street without a number on one side, an apartment only one side names, a street
        /// name spelled a little differently.
        case likely
        /// The same street and number and, at the most precise level either one names
        /// (the apartment, else the staircase, else the block), the same unit.
        case same

        public static func < (lhs: Self, rhs: Self) -> Bool { lhs.rawValue < rhs.rawValue }
    }

    public func agreement(with other: PostalAddress) -> Agreement {
        // A part both print and that differs is another place, whatever else agrees.
        let parts: [(String?, String?)] = [(number, other.number), (block, other.block), (staircase, other.staircase),
                                           (apartment, other.apartment), (sector, other.sector)]
        for (mine, theirs) in parts {
            if let mine, let theirs, mine != theirs { return .different }
        }
        if !locality.isEmpty, !other.locality.isEmpty, Set(locality).isDisjoint(with: other.locality) { return .different }

        switch Self.compareStreets(street, other.street) {
        case .different:
            return .different
        case .unknown:
            // A village without streets: the same village and the same number.
            if street.isEmpty, other.street.isEmpty, !locality.isEmpty, !other.locality.isEmpty,
               let number, number == other.number { return .likely }
            return .unknown
        case .similar:
            return .likely
        case .same:
            guard number != nil, other.number != nil else { return .likely }
            if let mine = streetType, let theirs = other.streetType, mine != theirs { return .likely }
            return sameUnit(as: other) ? .same : .likely
        }
    }

    /// The most precise unit either address names (an apartment, else a staircase, else a
    /// block) is named by both. Coarser parts only one side prints don't count against it:
    /// "bl. A1, ap. 12" is the same flat as "bl. A1, sc. B, ap. 12". Neither naming one: a house.
    private func sameUnit(as other: PostalAddress) -> Bool {
        let levels: [(String?, String?)] = [(apartment, other.apartment), (staircase, other.staircase), (block, other.block)]
        guard let precise = levels.first(where: { $0.0 != nil || $0.1 != nil }) else { return true }
        return precise.0 != nil && precise.1 != nil
    }

    enum StreetAgreement: Equatable { case same, similar, different, unknown }

    /// Two street names: every word on each side found on the other (an abbreviation counts,
    /// "Gh." for "Gheorghe"); or, at least, a longer word they share or nearly share
    /// ("Exemplu" and "Exemplului").
    static func compareStreets(_ mine: [String], _ theirs: [String]) -> StreetAgreement {
        let left = significant(mine), right = significant(theirs)
        guard !left.isEmpty, !right.isEmpty else { return .unknown }
        let allFound = left.allSatisfy { word in right.contains { sameWord(word, $0) } }
            && right.allSatisfy { word in left.contains { sameWord(word, $0) } }
        if allFound { return .same }
        let shares = left.contains { word in word.count >= 4 && right.contains { sameWord(word, $0) || nearlySameWord(word, $0) } }
        return shares ? .similar : .different
    }

    /// Words that name a street: not initials, not "de" or "la".
    private static func significant(_ words: [String]) -> [String] {
        words.filter { ($0.count >= 2 || $0.allSatisfy(\.isNumber)) && !fillers.contains($0) }
    }

    private static let fillers: Set<String> = ["de", "la", "si", "lui", "din", "cu"]

    /// The same word, or a short abbreviation of it.
    private static func sameWord(_ a: String, _ b: String) -> Bool {
        if a == b { return true }
        let (short, long) = a.count < b.count ? (a, b) : (b, a)
        return short.count >= 2 && short.count <= 3 && !short.contains(where: \.isNumber) && long.hasPrefix(short)
    }

    /// Another ending of the same word: "exemplu", "exemplului".
    private static func nearlySameWord(_ a: String, _ b: String) -> Bool {
        let shared = zip(a, b).prefix { $0 == $1 }.count
        return shared >= 5 && Double(shared) >= 0.8 * Double(min(a.count, b.count))
    }

    // MARK: - Reading

    /// What a printed marker introduces.
    private enum Marker {
        case streetType(String)
        case number, block, staircase, floor, apartment, sector, county, postalCode
        case locality
    }

    /// Markers as they are printed, folded: "Str.", "Strada", "B-dul", "nr.", "bl.", "sc.", "ap.".
    private static let markers: [String: Marker] = {
        var table: [String: Marker] = [:]
        let streetTypes: [String: [String]] = [
            "strada": ["str", "strada", "stra"],
            "bulevardul": ["bd", "bdul", "blvd", "bulevardul", "bulevard"],
            "calea": ["calea", "cal"],
            "soseaua": ["sos", "soseaua", "sosea"],
            "aleea": ["al", "aleea", "alee"],
            "piata": ["piata", "pta"],
            "intrarea": ["intrarea", "intr"],
            "splaiul": ["splaiul", "spl"],
            "drumul": ["drumul"],
            "prelungirea": ["prelungirea", "prel"],
            "fundatura": ["fundatura", "fdt"],
        ]
        for (type, words) in streetTypes { for word in words { table[word] = .streetType(type) } }
        for word in ["nr", "numar", "numarul"] { table[word] = .number }
        for word in ["bl", "bloc", "blocul"] { table[word] = .block }
        for word in ["sc", "scara"] { table[word] = .staircase }
        for word in ["et", "etaj", "etajul"] { table[word] = .floor }
        for word in ["ap", "apt", "apart", "apartament", "apartamentul"] { table[word] = .apartment }
        for word in ["sector", "sectorul", "sect"] { table[word] = .sector }
        for word in ["jud", "judet", "judetul"] { table[word] = .county }
        for word in ["cp"] { table[word] = .postalCode }
        for word in ["loc", "localitatea", "mun", "municipiul", "oras", "orasul", "com", "comuna", "sat", "satul"] { table[word] = .locality }
        return table
    }()

    /// The capital, named without a marker.
    private static let capital = "bucuresti"
    /// Words that say nothing about the place: the country.
    private static let ignored: Set<String> = ["romania"]

    private mutating func parse(_ text: String) {
        let folded = RomanianText.fold(text).replacingOccurrences(of: "b-dul", with: "bd ")
        let segments = folded.split(whereSeparator: { ",;\n|".contains($0) }).map { segment in
            segment.split(whereSeparator: { !$0.isLetter && !$0.isNumber }).map(String.init)
        }
        // A number read without "nr." ("Str. Exemplului 1"); a printed "nr." replaces it.
        var numberIsInferred = false
        var seenStreet = false
        for tokens in segments {
            var filling: Marker?
            var loose: [String] = []
            var index = 0
            while index < tokens.count {
                let token = tokens[index]
                // "cod poștal 012345" is not the street's number.
                if token == "cod", index + 1 < tokens.count, tokens[index + 1] == "postal" {
                    index += 3
                    continue
                }
                if token == Self.capital {
                    hasMarkers = true
                    if !locality.contains(token) { locality.append(token) }
                    filling = nil
                    index += 1
                    continue
                }
                if Self.ignored.contains(token) {
                    index += 1
                    continue
                }
                if let marker = Self.markers[token] {
                    hasMarkers = true
                    switch marker {
                    case .streetType(let type):
                        if case .streetType? = filling {
                            // Part of the name: "Str. Al. I. Cuza".
                            street.append(token)
                        } else if streetType == nil, street.isEmpty {
                            streetType = type
                            filling = marker
                        } else {
                            filling = nil
                        }
                        index += 1
                    case .locality, .county:
                        filling = marker
                        index += 1
                    case .number, .block, .staircase, .floor, .apartment, .sector, .postalCode:
                        let (value, used) = Self.value(in: tokens, at: index + 1)
                        if let value {
                            if case .number = marker, numberIsInferred {
                                number = nil
                                numberIsInferred = false
                            }
                            assign(value, to: marker)
                        }
                        index += 1 + used
                        filling = nil
                    }
                    continue
                }
                switch filling {
                case .streetType?:
                    if token.allSatisfy(\.isNumber), number == nil, street.contains(where: { $0.first?.isLetter == true }) {
                        // "Str. Exemplului 1": the number after the name.
                        number = token
                        numberIsInferred = true
                        filling = nil
                    } else {
                        street.append(token)
                    }
                case .locality?:
                    locality.append(token)
                case .county?:
                    county.append(token)
                default:
                    loose.append(token)
                }
                index += 1
            }
            if !street.isEmpty { seenStreet = true }
            guard !loose.isEmpty else { continue }
            if !seenStreet, streetType == nil, loose.first?.first?.isLetter == true {
                // A street written without its type: "Exemplului 1".
                let name = loose.prefix { !$0.contains(where: \.isNumber) }
                street = Array(name)
                if number == nil, let next = loose.dropFirst(name.count).first, next.allSatisfy(\.isNumber) {
                    number = next
                    numberIsInferred = true
                }
                seenStreet = true
            } else if locality.isEmpty, seenStreet, loose.allSatisfy({ !$0.contains(where: \.isNumber) }) {
                // A town after the street, without a marker: "…, Brașov".
                locality = loose
            }
        }
    }

    /// The value after a marker: one token, or a letter and a number written apart
    /// ("A 1" for block A1, "12 A" for number 12A). Returns how many tokens it used.
    private static func value(in tokens: [String], at index: Int) -> (String?, Int) {
        guard index < tokens.count, markers[tokens[index]] == nil else { return (nil, 0) }
        let first = tokens[index]
        if index + 1 < tokens.count, markers[tokens[index + 1]] == nil {
            let next = tokens[index + 1]
            let letterThenNumber = first.count == 1 && first.first?.isLetter == true && next.allSatisfy(\.isNumber)
            let numberThenLetter = first.allSatisfy(\.isNumber) && next.count == 1 && next.first?.isLetter == true
            if letterThenNumber || numberThenLetter { return (first + next, 2) }
        }
        return (first, 1)
    }

    private mutating func assign(_ value: String, to marker: Marker) {
        // "nr. 01" is number 1; "0" (a ground floor) stays.
        let trimmed = String(value.drop { $0 == "0" })
        let value = trimmed.isEmpty ? value : trimmed
        switch marker {
        case .number: if number == nil { number = value }
        case .block: if block == nil { block = value }
        case .staircase: if staircase == nil { staircase = value }
        case .apartment: if apartment == nil { apartment = value }
        case .sector: if sector == nil, value.allSatisfy(\.isNumber) { sector = value }
        case .floor, .postalCode, .county, .locality, .streetType: break
        }
    }
}
