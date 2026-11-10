import Foundation

/// An IBAN (ISO 13616), as a field checks it and as the card rule leaves it whole wherever it
/// is printed (`PaymentCardNumbers`). In `ios/Shared`, so the share extension reads the same
/// rule as the app.
public enum IBAN {
    /// How many characters an IBAN has in each country that issues them, as the ISO 13616
    /// registry lists them. A country not listed is checked by its check digits alone.
    public static let lengths: [String: Int] = [
        "AD": 24, "AE": 23, "AL": 28, "AT": 20, "AZ": 28, "BA": 20, "BE": 16, "BG": 22, "BH": 22, "BR": 29,
        "BY": 28, "CH": 21, "CR": 22, "CY": 28, "CZ": 24, "DE": 22, "DJ": 27, "DK": 18, "DO": 28, "EE": 20,
        "EG": 29, "ES": 24, "FI": 18, "FK": 18, "FO": 18, "FR": 27, "GB": 22, "GE": 22, "GI": 23, "GL": 18,
        "GR": 27, "GT": 28, "HR": 21, "HU": 28, "IE": 22, "IL": 23, "IQ": 23, "IS": 26, "IT": 27, "JO": 30,
        "KW": 30, "KZ": 20, "LB": 28, "LC": 32, "LI": 21, "LT": 20, "LU": 20, "LV": 21, "LY": 25, "MC": 27,
        "MD": 24, "ME": 22, "MK": 19, "MN": 20, "MR": 27, "MT": 31, "MU": 30, "NL": 18, "NO": 15, "OM": 23,
        "PK": 24, "PL": 28, "PS": 29, "PT": 25, "QA": 29, "RO": 24, "RS": 22, "RU": 33, "SA": 24, "SC": 31,
        "SD": 18, "SE": 24, "SI": 19, "SK": 24, "SM": 27, "SO": 23, "ST": 25, "SV": 28, "TL": 23, "TN": 24,
        "TR": 26, "UA": 29, "VA": 22, "VG": 24, "XK": 20, "YE": 30,
    ]

    /// ISO 13616 check: two letters for the country, two check digits, the country's length
    /// (`lengths`), then the first four characters moved to the end and checked mod 97.
    public static func isValid(_ raw: String) -> Bool {
        let iban = RomanianText.compact(raw)
        guard (15...34).contains(iban.count), iban.allSatisfy(\.isASCII) else { return false }
        let head = Array(iban.prefix(4))
        guard head[0].isLetter, head[1].isLetter, head[2].isNumber, head[3].isNumber else { return false }
        if let length = lengths[String(iban.prefix(2))], iban.count != length { return false }
        let rearranged = iban.dropFirst(4) + iban.prefix(4)
        var remainder = 0
        for character in rearranged {
            let chunk: String
            if let digit = character.wholeNumberValue {
                chunk = String(digit)
            } else if let ascii = character.asciiValue, character.isLetter {
                chunk = String(Int(ascii) - 55)
            } else {
                return false
            }
            for c in chunk {
                remainder = (remainder * 10 + (c.wholeNumberValue ?? 0)) % 97
            }
        }
        return remainder == 1
    }

    /// Where the text holds an IBAN that passes its check (`isValid`), however its groups
    /// are spaced: in one piece, in groups of four, with a space or a dash between any of its
    /// characters after the first four. It starts a word with a listed country's letters and
    /// its two check digits ("RO49"), and is taken at that country's length (`lengths`), so
    /// a word that happens to be two letters ("de", "cu") never starts one.
    public static func ranges(in text: String) -> [Range<String.Index>] {
        let positions = Array(text.indices)
        func character(_ offset: Int) -> Character? {
            offset >= 0 && offset < positions.count ? text[positions[offset]] : nil
        }
        func isWordCharacter(_ offset: Int) -> Bool {
            character(offset).map { $0.isLetter || $0.isNumber } ?? false
        }
        func isCode(_ offset: Int) -> Bool {
            character(offset).map { $0.isASCII && ($0.isLetter || $0.isNumber) } ?? false
        }
        func isSeparator(_ offset: Int) -> Bool {
            character(offset).map { $0 == " " || $0 == "-" } ?? false
        }
        // The offset just after the IBAN that starts at `start`, if one does.
        func end(from start: Int) -> Int? {
            guard let first = character(start), let second = character(start + 1),
                  let length = lengths[String([first, second]).uppercased()],
                  let check = character(start + 2), let checkEnd = character(start + 3),
                  check.isASCII, check.isNumber, checkEnd.isASCII, checkEnd.isNumber else { return nil }
            var compact = ""
            var offset = start
            while compact.count < length {
                if isCode(offset) {
                    compact.append(text[positions[offset]])
                    offset += 1
                } else if compact.count >= 4, isSeparator(offset), isCode(offset + 1) {
                    offset += 1
                } else {
                    break
                }
            }
            guard compact.count == length, !isWordCharacter(offset), isValid(compact) else { return nil }
            return offset
        }
        var found: [Range<String.Index>] = []
        var start = 0
        while start + 1 < positions.count {
            let startsWord = !isWordCharacter(start - 1) && isCode(start) && text[positions[start]].isLetter
            if startsWord, let after = end(from: start) {
                found.append(positions[start]..<(after < positions.count ? positions[after] : text.endIndex))
                start = after
            } else {
                start += 1
            }
        }
        return found
    }
}
