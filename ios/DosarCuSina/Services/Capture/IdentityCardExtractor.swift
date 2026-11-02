import Foundation

/// The front of a Romanian identity card, read from its printed labels.
///
/// Two layouts are in use:
/// - the electronic card (2021+): bilingual labels ("Nume / Surname") with the
///   value beside or under the label, and no machine-readable zone on the front;
/// - the older card: trilingual labels ("Nume/Nom/Last name"), "SERIA XX NR 123456"
///   at the top and the validity as one range ("12.03.18-12.03.2028").
///
/// Every date must sit under its own label, so a birth date is never taken for an
/// issue or expiry date. The CNP is accepted only with a valid control digit.
extension RomanianFieldExtractor {

    struct IdentityFields {
        var surname: (String, String)?
        var givenNames: (String, String)?
        var personalNumber: (String, String)?
        var documentNumber: (String, String)?
        var birthDate: (CaptureDay, String)?
        var issueDate: (CaptureDay, String)?
        var expiryDate: (CaptureDay, String)?
        var issuer: (String, String)?
        var sex: (String, String)?
    }

    /// Labels in folded form (lowercase, no diacritics), as printed on either layout.
    /// `other` lists labels whose values aren't read, so they're never taken for a value.
    enum IdentityLabel: CaseIterable, Hashable {
        case surname, givenNames, personalNumber, documentNumber, birthDate, issueDate, expiryDate, validity, issuer, sex, other

        var words: [String] {
            switch self {
            case .surname: ["nume / surname", "nume/surname", "nume/nom/last name", "nume/nom", "surname", "last name"]
            case .givenNames: ["prenume / given names", "prenume/given names", "prenume/prenom/first name", "prenume/prenom", "given names", "first name", "prenume"]
            case .personalNumber: ["cnp / pin", "cnp/pin", "cnp"]
            case .documentNumber: ["nr. document / document no", "nr. document/document no", "document no", "nr. document"]
            case .birthDate: ["data nasterii / date of birth", "data nasterii", "date of birth"]
            case .issueDate: ["data emiterii / date of issue", "data emiterii", "date of issue", "data eliberarii"]
            case .expiryDate: ["data expirarii / date of expiry", "data expirarii", "date of expiry"]
            case .validity: ["valabilitate/validite/validity", "valabilitate", "validity"]
            case .issuer: ["emisa de / issued by", "emisa de/delivree par/issued by", "emisa de", "issued by", "autoritatea emitenta", "issuing authority"]
            case .sex: ["sex / sex", "sex/sexe/sex", "sex"]
            case .other: [
                "cetatenie", "nationality", "nationalite", "loc nastere", "locul nasterii", "place of birth", "lieu de naissance",
                "domiciliu", "address", "adresse", "semnatura", "signature", "romania", "roumanie", "carte de identitate",
                "identity card", "carte d'identite", "carte electronica",
            ]
            }
        }
    }

    /// The fields printed on an identity card front.
    static func identityCardFields(in text: CaptureText) -> IdentityFields {
        var result = IdentityFields()
        let layout = LabelledLayout(text: text, labels: IdentityLabel.allCases.map { ($0, $0.words) })

        func value(for label: IdentityLabel) -> (value: String, source: String)? { layout.value(for: label) }

        if let name = value(for: .surname), let clean = personName(name.value) { result.surname = (clean, name.source) }
        if let name = value(for: .givenNames), let clean = personName(name.value) { result.givenNames = (clean, name.source) }
        if let issuer = value(for: .issuer), issuer.value.contains(where: \.isLetter) { result.issuer = (issuer.value, issuer.source) }
        if let sex = value(for: .sex), let letter = sex.value.uppercased().first(where: { $0 == "M" || $0 == "F" }) {
            result.sex = (String(letter), sex.source)
        }

        // The CNP: anywhere on the card, but only with a valid control digit.
        if let cnp = personalNumber(in: text) {
            result.personalNumber = cnp
            if let birth = birthDate(fromCNP: cnp.0) { result.birthDate = (birth, cnp.1) }
        }

        // Document number: "SERIA XT NR 123456" (older card) or under "Nr. document".
        if let match = text.original.lazy.compactMap({ TextPattern.first(#"\bseria\s+([A-Z]{2})\s*,?\s*nr\.?\s*(\d{6,7})\b"#, in: $0) }).first,
           let series = match[1], let number = match[2] {
            result.documentNumber = (series.uppercased() + number, series.uppercased() + " " + number)
        } else if let number = value(for: .documentNumber),
                  let match = TextPattern.first(#"\b([A-Z]{2})\s?(\d{6,7})\b"#, in: number.value),
                  let series = match[1], let digits = match[2] {
            result.documentNumber = (series.uppercased() + digits, number.source)
        }

        // Dates, each from its own label.
        if result.birthDate == nil, let birth = layout.day(for: .birthDate) { result.birthDate = birth }
        if let issue = layout.day(for: .issueDate) { result.issueDate = issue }
        if let expiry = layout.day(for: .expiryDate) { result.expiryDate = expiry }
        // The older card prints the validity as one range on one line.
        if result.expiryDate == nil, let line = layout.line(of: .validity) {
            let candidates = [line, line + 1].filter { $0 < text.folded.count }
            for line in candidates {
                let found = dates(inLine: text.folded[line], index: line)
                if found.count == 2, found[0].day < found[1].day {
                    if result.issueDate == nil { result.issueDate = (found[0].day, text.original[line]) }
                    result.expiryDate = (found[1].day, text.original[line])
                    break
                }
            }
        }
        // A birth date is never an issue or expiry date.
        if let birth = result.birthDate?.0 {
            if result.issueDate?.0 == birth { result.issueDate = nil }
            if result.expiryDate?.0 == birth { result.expiryDate = nil }
        }
        return result
    }

    // MARK: - CNP

    /// A Romanian personal numeric code with a valid control digit (key 279146358279).
    public static func isValidCNP(_ digits: String) -> Bool {
        let numbers = digits.compactMap(\.wholeNumberValue)
        guard numbers.count == 13, digits.count == 13, (1...9).contains(numbers[0]) else { return false }
        let key = [2, 7, 9, 1, 4, 6, 3, 5, 8, 2, 7, 9]
        let sum = zip(numbers.prefix(12), key).reduce(0) { $0 + $1.0 * $1.1 }
        let control = sum % 11 == 10 ? 1 : sum % 11
        return control == numbers[12]
    }

    /// The first valid CNP in the text, with the line it was on.
    static func personalNumber(in text: CaptureText) -> (String, String)? {
        for (index, line) in text.original.enumerated() {
            let compact = line.filter { !$0.isWhitespace }
            for match in TextPattern.matches(#"(?<!\d)(\d{13})(?!\d)"#, in: compact) {
                if let digits = match[1], isValidCNP(digits) { return (digits, text.original[index]) }
            }
        }
        return nil
    }

    /// The birth date a CNP encodes: sex and century digit, then YYMMDD.
    static func birthDate(fromCNP cnp: String) -> CaptureDay? {
        let numbers = cnp.compactMap(\.wholeNumberValue)
        guard numbers.count == 13 else { return nil }
        let century: Int
        switch numbers[0] {
        case 1, 2: century = 1900
        case 3, 4: century = 1800
        case 5, 6: century = 2000
        default: return nil // 7–9: residents, century not encoded
        }
        let year = century + numbers[1] * 10 + numbers[2]
        let month = numbers[3] * 10 + numbers[4]
        let day = numbers[5] * 10 + numbers[6]
        guard (1...12).contains(month), (1...31).contains(day) else { return nil }
        return CaptureDay(year: year, month: month, day: day)
    }

    /// A printed name in capitals, kept only if it looks like a name.
    static func personName(_ raw: String) -> String? {
        let letters = raw.trimmingCharacters(in: .whitespacesAndNewlines.union(CharacterSet(charactersIn: "<.,:")))
        guard letters.count >= 2, letters.count <= 60,
              letters.allSatisfy({ $0.isLetter || $0 == " " || $0 == "-" || $0 == "'" }) else { return nil }
        return letters
    }
}
