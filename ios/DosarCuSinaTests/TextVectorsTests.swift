import Foundation
import Testing
@testable import DosarCuSina

/// The rules that keep a bank card's number out of everything the binder keeps
/// (`PaymentCardNumbers`, in ios/Shared/CardNumberRule.swift and the app's PaymentCardNumbers.swift,
/// and the text rule `FreeText` masks every save with), with the rules beside them (`IBAN`,
/// `RomanianText`'s comparing, `TextPattern`), run over inputs chosen to bite and written to
/// `shared/test-vectors/text/`, one file per rule: each input with the answer this app gives. The
/// Android app's tests read the same files and must give the same answers
/// (docs/ANDROID_PLAN.md, "How parity is kept"). A sibling of `ValueVectorsTests` rather than more
/// of it: these are the rules every save masks with, a family of their own with a folder of their
/// own, and that test keeps its folder to the files it writes.
///
/// Placeholder data only, and more so here: no number that passes a card's check digit is
/// written in the repository (scripts/privacy-check.sh refuses one) other than the networks'
/// published test numbers, and IBANs are the specifications' examples. A case that needs another
/// is written with a token built when the test runs, the same way on both sides (`Built`), and its
/// answer is written back with the same token.
@Suite("Text vectors")
struct TextVectorsTests {
    static var folder: URL {
        URL(filePath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appending(path: "shared/test-vectors/text")
    }

    /// How to bring the files up to date, said when one isn't.
    static let regenerate = """
    is out of date with the text rules. Bring shared/test-vectors/text up to date: \
    TEST_RUNNER_TEXT_VECTORS_WRITE=1 ./tests/run_tests.sh (or run TextVectorsTests in Xcode with \
    TEXT_VECTORS_WRITE=1 in the scheme's environment), review the diff, run scripts/privacy-check.sh \
    on it and commit it, then run the Android tests (./gradlew :core:test in android/), which read the same files.
    """

    typealias Vectors = ValueVectorsTests.Vectors

    @Test("shared/test-vectors/text is up to date with the text rules")
    func vectorsAreUpToDate() throws {
        let files = try Self.all()
        let writes = ProcessInfo.processInfo.environment["TEXT_VECTORS_WRITE"] == "1"
        let manager = FileManager.default
        if writes { try manager.createDirectory(at: Self.folder, withIntermediateDirectories: true) }
        for file in files {
            let url = Self.folder.appending(path: "\(file.name).json")
            let fresh = try Self.render(file)
            if writes {
                try fresh.write(to: url, atomically: true, encoding: .utf8)
                continue
            }
            let committed = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
            #expect(committed == fresh, Comment(rawValue: "\(file.name).json " + Self.regenerate))
        }
        // A file no rule writes any more goes, so Android never tests against an old answer.
        let names = Set(files.map { "\($0.name).json" })
        let present = (try? manager.contentsOfDirectory(atPath: Self.folder.path(percentEncoded: false))) ?? []
        for stale in present where stale.hasSuffix(".json") && !names.contains(stale) {
            if writes {
                try manager.removeItem(at: Self.folder.appending(path: stale))
            } else {
                Issue.record(Comment(rawValue: "\(stale) is written by no rule any more " + Self.regenerate))
            }
        }
    }

    @Test("A built number passes its check, and is never written as it passes")
    func builtNumbersPass() {
        let card = Built.expand("{luhn:64200000000123}")
        #expect(PaymentCardNumbers.passesLuhn(card))
        #expect(Built.written(card, for: ["{luhn:64200000000123}"]) == "{luhn:64200000000123}")
        #expect(IBAN.isValid(Built.expand("{iban4:RO:AAAA4111111111111111}")))
    }

    static func all() throws -> [Vectors] {
        try [
            cardNumberRedact(), cardNumberLuhn(), cardNumberLastFour(), cardNumberKeepsWhole(), cardNumberKeptWhole(),
            cardNumberSanitizing(), cardNumberRedactingJSON(), freeTextMask(), iban(), romanianTextCompact(),
            romanianTextWords(), romanianTextContainsWord(), textPattern(),
        ]
    }

    static func render(_ file: Vectors) throws -> String {
        let document: JSONValue = .object([
            "rule": .string(file.rule),
            "source": .string(file.source),
            "shape": .string(file.shape),
            "writtenBy": "ios/DosarCuSinaTests/TextVectorsTests.swift",
            "built": .string(Built.explanation),
            "cases": .array(file.cases),
        ])
        return String(decoding: try MachineText.jsonEncoder(.readable).encode(document), as: UTF8.self) + "\n"
    }

    // MARK: Numbers built when the test runs

    /// Numbers a case needs that pass a check, written as a token and built when the test runs,
    /// so the repository never holds one: `{luhn:DIGITS}` is DIGITS as written (spaces and dashes
    /// kept) with the Luhn check digit after them; `{iban:CC:BBAN}` is the IBAN of country CC with
    /// that BBAN, its two check digits worked out (ISO 13616: 98 minus the BBAN, CC and "00" as a
    /// number mod 97, letters as A=10 … Z=35); `{iban4:CC:BBAN}` the same in groups of four;
    /// `{fours:DIGITS}` DIGITS in groups of four (two published test numbers side by side, which
    /// written out would read as another number to the privacy check).
    enum Built {
        static let explanation = """
        A token in a case's text is a number that passes its check, built when the test runs so the \
        repository never holds one. {luhn:DIGITS}: DIGITS as written with the Luhn check digit after them. \
        {iban:CC:BBAN}: CC, the two ISO 13616 check digits (98 minus BBAN + CC + "00" mod 97, letters as \
        A=10 … Z=35), then BBAN. {iban4:CC:BBAN}: the same, in groups of four with a space between. \
        {fours:DIGITS}: DIGITS in groups of four with a space between. Answers name the same tokens.
        """

        static let token = #"\{(luhn|iban|iban4|fours):([^{}]*)\}"#

        /// The text with every token built.
        static func expand(_ template: String) -> String {
            var result = ""
            var rest = template.startIndex
            for match in TextPattern.matches(token, in: template, caseInsensitive: false) {
                result += template[rest..<match.range.lowerBound]
                result += number(kind: match[1] ?? "", content: match[2] ?? "")
                rest = match.range.upperBound
            }
            return result + template[rest...]
        }

        /// An answer with each number the templates built written back as its token.
        static func written(_ answer: String, for templates: [String]) -> String {
            let built = templates.flatMap { template in
                TextPattern.matches(token, in: template, caseInsensitive: false).map { match in
                    (token: String(template[match.range]), number: number(kind: match[1] ?? "", content: match[2] ?? ""))
                }
            }
            return built.sorted { $0.number.count > $1.number.count }.reduce(answer) { text, item in
                text.replacingOccurrences(of: item.number, with: item.token)
            }
        }

        static func number(kind: String, content: String) -> String {
            switch kind {
            case "luhn":
                let digits = content.filter { $0.isASCII && $0.isNumber }
                if (13...19).contains(digits.count) {
                    #expect(!PaymentCardNumbers.passesLuhn(digits), "\(content) passes the card check as written")
                }
                return content + String(checkDigit(digits))
            case "fours":
                return grouped(content)
            default:
                let parts = content.split(separator: ":", maxSplits: 1).map(String.init)
                guard parts.count == 2 else {
                    Issue.record("Not a country and a BBAN: \(content)")
                    return content
                }
                let iban = parts[0] + checkDigits(country: parts[0], bban: parts[1]) + parts[1]
                return kind == "iban4" ? grouped(iban) : iban
            }
        }

        static func checkDigit(_ digits: String) -> Int {
            let sum = digits.compactMap(\.wholeNumberValue).reversed().enumerated().reduce(0) { total, item in
                let doubled = item.offset.isMultiple(of: 2) ? item.element * 2 : item.element
                return total + (doubled > 9 ? doubled - 9 : doubled)
            }
            return (10 - sum % 10) % 10
        }

        static func checkDigits(country: String, bban: String) -> String {
            var remainder = 0
            for character in bban + country + "00" {
                let value = character.wholeNumberValue.map(String.init) ?? String(Int(character.asciiValue ?? 0) - 55)
                for digit in value { remainder = (remainder * 10 + (digit.wholeNumberValue ?? 0)) % 97 }
            }
            let check = 98 - remainder
            return (check < 10 ? "0" : "") + String(check)
        }

        static func grouped(_ text: String) -> String {
            stride(from: 0, to: text.count, by: 4).map { offset in
                String(text.dropFirst(offset).prefix(4))
            }.joined(separator: " ")
        }
    }

    static func optional(_ text: String?) -> JSONValue { text.map(JSONValue.string) ?? .null }

    // MARK: Card numbers

    /// Texts every card-number rule is asked about.
    static let texts = [
        // Masked by shape, the check digit or groups of four.
        "Card 4111 1111 1111 1111 Visa", "5555-5555-5555-4444", "5555555555554444", "4111 1111 1111 1112",
        "378282246310005", "3782 822463 10005", "30569309025904", "3056 930902 5904", "6011111111111117",
        "3566002020360505", "2223003122003222", "{luhn:4111 1111 1111 1111 11}", "{luhn:500000000000000000}",
        // Never a card: a CNP, an IMEI, a health card's 20 digits, a payment code, an invoice, a short card.
        "CNP 1800101990006", "IMEI {luhn:99000086247185}", "80642000000000000001", "1234567890123456789012345678",
        "Factura 1234567", "Visa veche {luhn:422222222222}", "Telefon 0722 123 456", "Suma 1 250 000 lei",
        // A card next to other digits: found inside the longer run.
        "Nr. 12 4111 1111 1111 1111", "Ref 3-5555555555554444", "4111-1111-1111-1111-27 lei", "Rând 2 150 4111 1111 1111 1111",
        "4111 1111 1111 1111 0828", "Plată 7 3782 822463 10005", "CNP 1800101990006 4111111111111111",
        "80642000000000000001 4111111111111111",
        // Two cards in one run.
        "4111 1111 1111 1111-5555555555554444", "4111 1111 1111 1111 {fours:5555555555554444}",
        // A run longer than a card stays as written unless a card is printed apart in it.
        "Index 41111111111111110000", "Contract 124111111111111111", "Cod 4111 1111 1111 1112 0000",
        "2 4 6 8 10 12 14 16 18 20", "8064 {luhn:2221 0000 0000 010}",
        // Digits glued to letters are a code.
        "AB4111111111111111", "4111111111111111RON", "Cod4111111111111111X", "Cod XY-4111111111111111",
        "NR4111111111111111", "Contract X12 4111 1111 1111 1111", "AB12 4111 1111 1111 1111",
        // IBANs: passing their check in any spacing, mistyped, carrying on an IBAN's groups, beside a card.
        "RO49 AAAA 1B31 0075 9384 0000", "RO49AAAA1B31007593840000", "ro49 aaaa 1b31 0075 9384 0000",
        "GB82-WEST-1234-5698-7654-32", "IBAN: DE89 3704 0044 0532 0130 00.", "Cont GB82WEST12345698765432, deschis la ghișeu",
        "FR14 2004 1010 0505 0001 3M02 606", "RO49 AAAA 1B31 0075 9384 0001", "IBAN GB82 WEST 1234 5698 7654 33",
        "{iban:RO:AAAA4111111111111111}", "{iban4:RO:AAAA4111111111111111}", "RO00 AAAA 4111 1111 1111 1111",
        "RO49AAAA1B31007593840000 4111111111111111", "IBAN RO49 AAAA 1B31 0075 9384 0000, card 4111 1111 1111 1111",
        "RO49 AAAA 1B31 0075 9384 0000 4111 1111 1111 1111", "4111 1111 1111 1111 GB82WEST12345698765432",
        // A microchip's 15 digits that would pass as a Maestro card: alone, nothing says what they are.
        "Microcip {luhn:64200000000123}", "Microcip 642093400012345",
        // Romanian text, dots and other separators.
        "Plătită cu cardul 4111 1111 1111 1111 în ședința de vineri; țânțarii știu", "Șofer: 5555 5555 5555 4444, țară România",
        "Nr. 12.4111 1111 1111 1111", "Total 1.250,00 lei, card 4111-1111-1111-1111", "Plătit cu 4111 1111 1111 1111 azi",
        "VISA 4111 1111 1111 1112", "nr. 4111 1111 1111 1111", "Card: 4111111111111111",
        // Groups apart by dots, slashes, several spaces, other spaces or a dash with spaces round it.
        "4111.1111.1111.1111", "4111/1111/1111/1111", "4111  1111  1111  1111", "4111   1111 1111  1111",
        "4111\u{00A0}1111\u{00A0}1111\u{00A0}1111", "4111\t1111\t1111\t1111", "4111\u{202F}1111\u{202F}1111\u{202F}1111",
        "4111 - 1111 - 1111 - 1111", "4111 / 1111 / 1111 / 1111", "Card: 5555.5555.5555.4444 azi", "3782.822463.10005",
        "{luhn:4000.0000.0000.000}", "Ref 12/4111/1111/1111/1111", "Nr. 12.4111.1111.1111.1111 lei", "4111.1111.1111.1111.pdf",
        "4111.1111.1111.1111; 5555.5555.5555.4444", "Plată 4111/1111/1111/1111, 12.03.2026",
        // Apart that way, never a card: the check digit fails, the gaps differ, or the groups aren't a card's.
        "4111.1111.1111.1112", "4111  1111  1111  1112", "4111.1111 1111/1111", "4111.1111-1111.1111",
        "Perioada 01.02.2026 - 28.02.2026", "30.05.2026 31.05.2026", "30.05.2026-30.06.2026", "Data 31/12/2026 12:30",
        "Suma 1.250.000 lei", "4.111.111.111.111.111", "Versiunea 4.1.1.1", "192.168.100.200", "B-123-ABC",
        "4500   4600   4700   4800", "Tel 0722.123.456", "8064.2000.0000.0000.0001", "{luhn:3.0569309.02590}",
        "scan 2026-03-15 10.45.12.pdf", "RO49.AAAA.1B31.0075.9384.0000", "RO00.AAAA.4111.1111.1111.1111",
        "RO00  AAAA  4111  1111  1111  1111", "CNP 1800101990006 / 4111",
        // A date is a number of its own: a card right after it is found as if alone, a long number stays.
        "01.02.2026 4111 1111 1111 1111", "01-02-2026 4111 1111 1111 1111", "01/02/2026 4111 1111 1111 1111",
        "2026-02-01 4111 1111 1111 1111", "Plătit 01.02.2026 12:30 4111 1111 1111 1111", "01.02.2026 14.30 4111 1111 1111 1111",
        "31.12.2026 5555-5555-5555-4444", "01.02.2026 4111 1111 1111 1112", "2/1/2026 4111 1111 1111 1111",
        "01.02.2026 8064 2000 0000 0000 0001", "01.02.2026 1234 5678 9012 3456", "01.02.2026 4111 1111 1111 1111 0828",
        // Digits of other scripts are the digits they are: full-width, Arabic-Indic, Devanagari, mathematical.
        "\u{FF14}\u{FF11}\u{FF11}\u{FF11} \u{FF11}\u{FF11}\u{FF11}\u{FF11} \u{FF11}\u{FF11}\u{FF11}\u{FF11} \u{FF11}\u{FF11}\u{FF11}\u{FF11}",
        "Card \u{FF15}\u{FF15}\u{FF15}\u{FF15}\u{FF15}\u{FF15}\u{FF15}\u{FF15}\u{FF15}\u{FF15}\u{FF15}\u{FF15}\u{FF14}\u{FF14}\u{FF14}\u{FF14}",
        "\u{0664}\u{0661}\u{0661}\u{0661} \u{0661}\u{0661}\u{0661}\u{0661} \u{0661}\u{0661}\u{0661}\u{0661} \u{0661}\u{0661}\u{0661}\u{0661}",
        "\u{096A}\u{0967}\u{0967}\u{0967}-\u{0967}\u{0967}\u{0967}\u{0967}-\u{0967}\u{0967}\u{0967}\u{0967}-\u{0967}\u{0967}\u{0967}\u{0967}",
        "\u{1D7D3}\u{1D7D3}\u{1D7D3}\u{1D7D3} \u{1D7D3}\u{1D7D3}\u{1D7D3}\u{1D7D3} \u{1D7D3}\u{1D7D3}\u{1D7D3}\u{1D7D3} \u{1D7D2}\u{1D7D2}\u{1D7D2}\u{1D7D2}",
        "4111 \u{0661}\u{0661}\u{0661}\u{0661} 1111 \u{FF11}\u{FF11}\u{FF11}\u{FF11}", "\u{FF14}\u{FF11}\u{FF11}\u{FF11}.\u{FF11}\u{FF11}\u{FF11}\u{FF11}.\u{FF11}\u{FF11}\u{FF11}\u{FF11}.\u{FF11}\u{FF11}\u{FF11}\u{FF11}",
        "\u{FF14}\u{FF11}\u{FF11}\u{FF11} \u{FF11}\u{FF11}\u{FF11}\u{FF11} \u{FF11}\u{FF11}\u{FF11}\u{FF11} \u{FF11}\u{FF11}\u{FF11}\u{FF12}",
        "AB\u{FF14}\u{FF11}\u{FF11}\u{FF11}\u{FF11}\u{FF11}\u{FF11}\u{FF11}\u{FF11}\u{FF11}\u{FF11}\u{FF11}\u{FF11}\u{FF11}\u{FF11}\u{FF11}",
        "CNP \u{FF11}\u{FF18}\u{FF10}\u{FF10}\u{FF11}\u{FF10}\u{FF11}\u{FF19}\u{FF19}\u{FF10}\u{FF10}\u{FF10}\u{FF16}",
        "\u{FF14}\u{FF11}\u{FF11}\u{FF11} \u{FF11}\u{FF11}\u{FF11}\u{FF11} \u{FF11}\u{FF11}\u{FF11}\u{FF11} \u{FF11}\u{FF11}\u{FF11}\u{FF11} \u{FF10}\u{FF18}\u{FF12}\u{FF18}",
        // Already masked, and the last digits under a mask.
        "•••• 4444", "**** **** **** 4821", "XXXX-XXXX-XXXX-4821", "•••• 1111 •••• 4444",
        // On a bank card any run of eight digits or more goes; digits of other scripts are digits there.
        "1234 5678 9012 3456", "1234 5678", "VALID THRU 08/28", "Cod \u{0661}\u{0662}\u{0663}\u{0664}\u{0665}\u{0666}\u{0667}\u{0668}\u{0669}\u{0660}\u{0661}\u{0662}",
        "", "fără cifre",
    ]

    static func cardNumberRedact() -> Vectors {
        let cases: [JSONValue] = texts.map { template in
            let text = Built.expand(template)
            let written = { (answer: String) in JSONValue.string(Built.written(answer, for: [template])) }
            return .object([
                "text": .string(template),
                "redacted": written(PaymentCardNumbers.redact(text)),
                "strict": written(PaymentCardNumbers.redact(text, strict: true)),
                "contains": .bool(PaymentCardNumbers.containsCardNumber(text)),
                "lastFour": optional(PaymentCardNumbers.lastFour(in: text)),
                "lastFourStrict": optional(PaymentCardNumbers.lastFour(in: text, strict: true)),
            ])
        }
        return Vectors(
            name: "card-number-redact",
            rule: "PaymentCardNumbers.redact(_:strict:), containsCardNumber(_:) and lastFour(in:strict:): a bank card's number masked wherever text is kept",
            source: "ios/Shared/CardNumberRule.swift",
            shape: "text: a text (with built tokens). redacted: masked by the \"anywhere\" rule; strict: masked as on a bank card. contains: whether it holds a card number by the anywhere rule. lastFour, lastFourStrict: the last four digits of the card number in it, by each rule, else null.",
            cases: cases
        )
    }

    static func cardNumberLuhn() -> Vectors {
        let inputs = [
            "4111111111111111", "4111111111111112", "5555555555554444", "378282246310005", "30569309025904",
            "{luhn:411111111111111111}", "{luhn:64200000000123}", "79927398713", "1234", "", "4111a11111111111",
            "4", "34", "35", "36", "37", "300", "305", "306", "3527", "3528", "3589", "3590", "38", "39", "50", "51",
            "55", "56", "69", "70", "2220", "2221", "2720", "2721", "1", "9", "+4111", " 4111",
        ]
        let cases: [JSONValue] = inputs.map { template in
            let digits = Built.expand(template)
            let brand = PaymentCardNumbers.brand(of: digits)
            return .object([
                "digits": .string(template),
                "passesLuhn": .bool(PaymentCardNumbers.passesLuhn(digits)),
                "network": optional(PaymentCardNumbers.network(ofNumber: digits)),
                "lengths": brand.map { .array([.int($0.lengths.lowerBound), .int($0.lengths.upperBound)]) } ?? .null,
            ])
        }
        return Vectors(
            name: "card-number-luhn",
            rule: "PaymentCardNumbers.passesLuhn(_:), brand(of:) and network(ofNumber:): the check digit and the networks' issuer ranges",
            source: "ios/Shared/CardNumberRule.swift",
            shape: "digits: digits (with built tokens). passesLuhn: whether they pass the Luhn check (twelve digits or more). network: the network key their first digits name, else null. lengths: the lengths that network's numbers have, [shortest, longest], else null.",
            cases: cases
        )
    }

    static func cardNumberLastFour() -> Vectors {
        let inputs = ["4821", "•••• 4821", "4111 1111 1111 1111", "12", "", "Card 1234-5678", "\u{FF14}\u{FF18}\u{FF12}\u{FF11}", "48 21"]
        let cases: [JSONValue] = inputs.map { .object(["value": .string($0), "lastFour": optional(PaymentCardNumbers.lastFour(of: $0))]) }
        return Vectors(
            name: "card-number-last-four",
            rule: "PaymentCardNumbers.lastFour(of:): only the last four digits of what was typed or read",
            source: "ios/Shared/CardNumberRule.swift",
            shape: "value: text typed or read. lastFour: its last four ASCII digits, or null when it has fewer.",
            cases: cases
        )
    }

    static func cardNumberKeepsWhole() -> Vectors {
        let inputs: [(text: String, type: String?)] = [
            ("RO49 AAAA 1B31 0075 9384 0000", "iban"), ("RO49AAAA1B31007593840000", "iban"), ("  GB82 WEST 1234 5698 7654 32 ", "iban"),
            ("RO49 AAAA 1B31 0075 9384 0001", "iban"), ("4111 1111 1111 1111", "iban"), ("{iban4:RO:AAAA4111111111111111}", "iban"),
            ("{luhn:64200000000123}", "microchip"), ("{luhn:642 000 000 001 23}", "microchip"), ("{luhn:642-000-000-001-23}", "microchip"),
            ("642093400012345", "microchip"), ("4111 1111 1111 1111", "microchip"), ("64200000000012A", "microchip"),
            ("", "microchip"), ("   ", "iban"), ("{luhn:64200000000123}", "text"), ("{luhn:64200000000123}", "phone"),
            ("{luhn:64200000000123}", nil), ("RO49 AAAA 1B31 0075 9384 0000", "text"), ("WVWZZZ1KZAW000000", "vin"),
        ]
        let cases: [JSONValue] = inputs.map { input in
            let type = input.type.flatMap(FieldType.init(rawValue:))
            return .object([
                "text": .string(input.text),
                "type": optional(input.type),
                "keepsWhole": .bool(PaymentCardNumbers.keepsWhole(Built.expand(input.text), as: type)),
            ])
        }
        return Vectors(
            name: "card-number-keeps-whole",
            rule: "PaymentCardNumbers.keepsWhole(_:as:): a field's value its type tells apart from a card number (an IBAN, a microchip) and that passes that type's own check",
            source: "ios/DosarCuSina/Services/Security/PaymentCardNumbers.swift",
            shape: "text: a field's value (with built tokens). type: its field's type as stored (FieldType's raw value), or null for no field. keepsWhole: whether it stays whole, never masked.",
            cases: cases
        )
    }

    static func cardNumberKeptWhole() -> Vectors {
        let chip = "{luhn:64200000000123}"
        let inputs: [(values: [(text: String, type: String)], text: String)] = [
            ([(chip, "microchip")], "Microcip \(chip) citit la vaccin"),
            ([(chip, "microchip")], "Microcip \(chip), plătit cu 4111 1111 1111 1111"),
            ([(chip, "microchip")], "\(chip)4"),
            ([("{luhn:642 000 000 001 23}", "microchip")], "Cip \(chip) și {luhn:642 000 000 001 23}"),
            ([(chip, "text")], "Microcip \(chip)"),
            ([(chip, "phone")], "Microcip \(chip)"),
            ([("RO49 AAAA 1B31 0075 9384 0000", "iban"), (chip, "microchip")], "Cont RO49 AAAA 1B31 0075 9384 0000, cip \(chip)"),
            ([("4111 1111 1111 1111", "microchip")], "Card 4111 1111 1111 1111"),
            ([], "Microcip \(chip)"),
        ]
        let cases: [JSONValue] = inputs.map { input in
            let typed = input.values.compactMap { value in FieldType(rawValue: value.type).map { (text: Built.expand(value.text), type: $0) } }
            let kept = PaymentCardNumbers.KeptWhole(typed: typed)
            let text = Built.expand(input.text)
            let templates = [input.text] + input.values.map(\.text)
            let written = { (answer: String) in JSONValue.string(Built.written(answer, for: templates)) }
            return .object([
                "values": .array(input.values.map { .object(["text": .string($0.text), "type": .string($0.type)]) }),
                "text": .string(input.text),
                "isEmpty": .bool(kept.isEmpty),
                "redacted": written(PaymentCardNumbers.redact(text, keeping: kept)),
                "strict": written(PaymentCardNumbers.redact(text, strict: true, keeping: kept)),
                "contains": .bool(PaymentCardNumbers.containsCardNumber(text, keeping: kept)),
            ])
        }
        return Vectors(
            name: "card-number-kept-whole",
            rule: "PaymentCardNumbers.KeptWhole(typed:) and redact(_:strict:keeping:): the digits of a section's own typed values stay whole in all its words",
            source: "ios/DosarCuSina/Services/Security/PaymentCardNumbers.swift",
            shape: "values: a section's values with their fields' types (with built tokens). text: words the section keeps. isEmpty: whether nothing is kept whole. redacted, strict: the text masked keeping them, by the anywhere rule and on a bank card. contains: whether it holds a card number that isn't one of them.",
            cases: cases
        )
    }

    static func cardNumberSanitizing() -> Vectors {
        let chip = "{luhn:64200000000123}"
        let sealed = SecretSealer.prefix + "AAAA4111111111111111"
        let inputs: [[String: (text: String, type: String?)]] = [
            ["x.iban": ("RO49 AAAA 1B31 0075 9384 0000", "iban"), "x.chip": (chip, "microchip"), "x.note": (chip, "text")],
            ["x.chip": (chip, "microchip"), "x.note": ("Cip \(chip), card 4111 1111 1111 1111", "longText")],
            ["x.note": (chip, "text")],
            ["x.note": (chip, nil)],
            ["x.chip": ("4111 1111 1111 1111", "microchip"), "x.iban": ("5555 5555 5555 4444", "iban")],
            ["document.cardLastFour": ("4111 1111 1111 1111", "text")],
            ["document.cardLastFour": ("•••• 4821", nil)],
            ["document.cardLastFour": ("12", "text")],
            ["x.pin": (sealed, "secret"), "x.note": ("Plătit cu 4111-1111-1111-1111", "text")],
            ["x.phone": ("{luhn:64200000000123}", "phone"), "x.text": ("fără cifre", "text")],
            ["x.note": ("Card 4111  1111  1111  1111, din 01.02.2026", "longText"), "x.label": ("5555/5555/5555/4444", "text")],
            [:],
        ]
        let cases: [JSONValue] = inputs.map { input in
            let values = FieldValues(input.mapValues { FieldValue.text(Built.expand($0.text)) })
            let fields = input.sorted { $0.key < $1.key }.compactMap { key, value in
                value.type.flatMap(FieldType.init(rawValue:)).map { FieldDefinition(key: key, label: "Câmp", type: $0) }
            }
            let sanitized = PaymentCardNumbers.sanitizing(values, fields: { fields })
            let templates = input.values.map(\.text)
            return .object([
                "values": .object(input.mapValues { .object(["text": .string($0.text), "type": optional($0.type)]) }),
                "sealed": .array(input.keys.sorted().filter { SecretSealer.isSealed(Built.expand(input[$0]?.text ?? "")) }.map(JSONValue.string)),
                "sanitized": .object(input.mapValues { _ in JSONValue.null }.merging(
                    sanitized.storage.compactMapValues { $0.textValue.map { JSONValue.string(Built.written($0, for: templates)) } },
                    uniquingKeysWith: { _, value in value }
                )),
            ])
        }
        return Vectors(
            name: "card-number-sanitizing",
            rule: "PaymentCardNumbers.sanitizing(_:fields:): a section's text values masked, a bank card's last digits cut to four, a value its field's type keeps whole and its digits elsewhere kept",
            source: "ios/DosarCuSina/Services/Security/PaymentCardNumbers.swift",
            shape: "values: a section's text values by field key, each with its field's type (null for no field; with built tokens). sealed: the keys whose value is a sealed secret, by its own form. sanitized: each key's value after, or null where the value goes.",
            cases: cases
        )
    }

    /// The strings inside a JSON value, in no order.
    static func strings(in value: JSONValue) -> [String] {
        switch value {
        case .string(let text): [text]
        case .array(let values): values.flatMap(strings(in:))
        case .object(let values): values.values.flatMap(strings(in:))
        case .int, .number, .bool, .null: []
        }
    }

    static func cardNumberRedactingJSON() throws -> Vectors {
        let inputs = [
            #"{"title":"Card 4111 1111 1111 1111","number":4111111111111111,"nested":{"list":["5555-5555-5555-4444","RO49 AAAA 1B31 0075 9384 0000",true,null]}}"#,
            #"{"code":"sealed:v1:AAAA4111111111111111","label":"Cod 4111111111111111"}"#,
            #"["Plătit cu 4111 1111 1111 1111 în Iași", 12.5, {"x":"fără cifre"}]"#,
            #""Nr. 12 4111 1111 1111 1111""#,
        ]
        let cases: [JSONValue] = try inputs.map { text in
            let raw = try ValueVectorsTests.json(text)
            return .object([
                "json": raw,
                "sealed": .array(Set(strings(in: raw).filter(SecretSealer.isSealed)).sorted().map(JSONValue.string)),
                "redacted": PaymentCardNumbers.redacting(raw),
            ])
        }
        return Vectors(
            name: "card-number-redacting-json",
            rule: "PaymentCardNumbers.redacting(_:): JSON a newer build wrote, with every card number in its strings masked and sealed codes left alone",
            source: "ios/DosarCuSina/Services/Security/PaymentCardNumbers.swift",
            shape: "json: a JSON value. sealed: the strings in it that are sealed secrets, by their own form. redacted: the same JSON with its strings masked by the anywhere rule, sealed ones left as they are; numbers, keys and the rest unchanged.",
            cases: cases
        )
    }

    static func freeTextMask() -> Vectors {
        let texts = [
            "Card 4111 1111 1111 1111", "Fără card", "RO49 AAAA 1B31 0075 9384 0000", "Microcip {luhn:64200000000123}",
            "•••• 1111", "Nr. 12 4111 1111 1111 1111 și 5555-5555-5555-4444", "",
            "Plătit cu 4111.1111.1111.1111 și 5555/5555/5555/4444", "Card \u{FF14}\u{FF11}\u{FF11}\u{FF11}\u{FF11}\u{FF11}\u{FF11}\u{FF11}\u{FF11}\u{FF11}\u{FF11}\u{FF11}\u{FF11}\u{FF11}\u{FF11}\u{FF11}",
            "Revizie 01.02.2026, 1.250.000 km",
        ]
        let lists = [["Mecanic", "Card 4111 1111 1111 1111"], ["Electrician", "Instalator"], [], ["5555555555554444"]]
        var cases: [JSONValue] = texts.map { template in
            let provider = Provider(name: "Service Exemplu S.R.L.")
            provider.notes = Built.expand(template)
            let masked = FreeText.mask(provider, write: true).contains("notes")
            return .object([
                "kind": "text",
                "before": .string(template),
                "masked": masked ? .string(Built.written(provider.notes ?? "", for: [template])) : .null,
            ])
        }
        cases += lists.map { list in
            let provider = Provider(name: "Service Exemplu S.R.L.")
            provider.trades = list
            let masked = FreeText.mask(provider, write: true).contains("trades")
            return .object([
                "kind": "texts",
                "before": .array(list.map(JSONValue.string)),
                "masked": masked ? .array(provider.trades.map(JSONValue.string)) : .null,
            ])
        }
        return Vectors(
            name: "free-text-mask",
            rule: "FreeText.mask(_:write:): the unit of work's rule for a record's words (a text, a list of words), here on a firm's notes and trades, whose section keeps nothing whole",
            source: "ios/DosarCuSina/Services/Persistence/FreeText.swift",
            shape: "kind: text (one text) or texts (a list of words). before: what the record held (with built tokens). masked: what it holds after the unit masks it, or null when nothing in it was masked and it is left as it was.",
            cases: cases
        )
    }

    // MARK: IBANs

    static func iban() -> Vectors {
        let inputs = [
            "RO49 AAAA 1B31 0075 9384 0000", "RO49AAAA1B31007593840000", "ro49aaaa1b31007593840000", "RO49-AAAA-1B31-0075-9384-0000",
            "GB82 WEST 1234 5698 7654 32", "DE89 3704 0044 0532 0130 00", "FR14 2004 1010 0505 0001 3M02 606", " RO49 AAAA 1B31 0075 9384 0000 ",
            "RO49 AAAA 1B31 0075 9384 0001", "RO49 AAAA 1B31 0075 9384 000Ș", "RO49AAAA1B310075", "{iban:DE:3704004405320130000}",
            "{iban:QQ:12345678901234}", "{iban4:RO:AAAA4111111111111111}", "IBAN: RO49 AAAA 1B31 0075 9384 0000.",
            "RO49 AAAA 1B31 0075 9384 0000 și GB82 WEST 1234 5698 7654 32", "XRO49AAAA1B31007593840000", "RO49AAAA1B31007593840000X",
            "RO49 AAAA1B31-0075 9384 0000", "RO 49 AAAA 1B31 0075 9384 0000", "RO49  AAAA 1B31 0075 9384 0000",
            "Contul în lei: RO49 AAAA 1B31 0075 9384 0000, deschis în Iași.", "de 12 cu 34", "", "ıt60 X054 2811 1010 0000 0123 456",
        ]
        let cases: [JSONValue] = inputs.map { template in
            let text = Built.expand(template)
            let ranges = IBAN.ranges(in: text).map { range -> JSONValue in
                .object([
                    "at": .int(text.utf16.distance(from: text.startIndex, to: range.lowerBound)),
                    "text": .string(Built.written(String(text[range]), for: [template])),
                ])
            }
            return .object(["text": .string(template), "isValid": .bool(IBAN.isValid(text)), "ranges": .array(ranges)])
        }
        return Vectors(
            name: "iban",
            rule: "IBAN.isValid(_:) and IBAN.ranges(in:): the ISO 13616 check, and where a text holds an IBAN that passes it",
            source: "ios/Shared/IBAN.swift",
            shape: "text: a text (with built tokens). isValid: whether the whole text, compacted, is an IBAN that passes its check. ranges: each IBAN found in it, in order: where it starts (in UTF-16 code units) and its text.",
            cases: cases
        )
    }

    // MARK: Comparing text

    static let comparedTexts = [
        "B-123-ABC", "b 123 abc", "Service Exemplu S.R.L.", "SERVICE EXEMPLU SRL", "RO49 AAAA 1B31 0075 9384 0000", "Șțăîâ ŞŢ şţ",
        "Straße", "\u{FB01}nal", "\u{0661}\u{0662}\u{0663}", "½ x²", "e\u{0301}", "İstanbul", "\u{01C5}", "\u{216B}", "\u{FF22}-\u{FF11}\u{FF12}",
        "Plătită, în ședința de vineri: țânțarii știu.", "120kwh", "", "--- ,,, ...", "Nr.12/2026",
        // Case folded the way Foundation folds it, which isn't lowercasing: letters that fold to two.
        "\u{00B5}", "Σίσυφος ς", "\u{017F}", "\u{0149}", "\u{01F0}", "\u{0131}", "\u{1E9E}", "\u{FB00} \u{FB06} \u{FB03}",
        "\u{13A0}\u{AB70}", "\u{01C8}", "\u{03D0}\u{03D1}\u{03D5}\u{03D6}\u{03F0}\u{03F1}\u{03F5}", "\u{FB13}", "\u{1E9B}",
        "\u{1F80}", "\u{0587}",
    ]

    static func romanianTextCompact() -> Vectors {
        let cases: [JSONValue] = comparedTexts.map { .object(["input": .string($0), "compact": .string(RomanianText.compact($0))]) }
        return Vectors(
            name: "romanian-text-compact",
            rule: "RomanianText.compact(_:): a value as compared and checked, the one way codes, numbers, plates and names are compared",
            source: "ios/Shared/RomanianText.swift",
            shape: "input: text. compact: folded, in capitals, letters and digits only.",
            cases: cases
        )
    }

    static func romanianTextWords() -> Vectors {
        let cases: [JSONValue] = comparedTexts.map { text in
            .object(["input": .string(text), "words": .array(RomanianText.words(text).map { .string(String($0)) })])
        }
        return Vectors(
            name: "romanian-text-words",
            rule: "RomanianText.words(_:): the folded words of a text",
            source: "ios/Shared/RomanianText.swift",
            shape: "input: text. words: its folded runs of letters and digits, in order, everything else dropped.",
            cases: cases
        )
    }

    static func romanianTextContainsWord() -> Vectors {
        let inputs: [(phrase: String, text: String, match: RomanianText.WordMatch?)] = [
            ("index", "Indexare anuală", .word), ("index", "Index nou: 12.345", nil), ("rca", "Marca mașinii", nil), ("RCA", "Poliță rca valabilă", nil),
            ("garanti", "Garanția expiră", .stem), ("garanti", "Garanția expiră", .word), ("scadent", "Data scadentă", nil),
            ("achitat", "Neachitat", nil), ("achitat", "Achitată integral", nil), ("kwh", "Consum 120kwh", nil), ("kWh", "120 kWh", nil),
            ("data scadenței", "DATA SCADENȚEI: 12.03.2027", nil), ("factura nr", "Factura, nr. 12", nil), ("factura nr", "Factura-nr12", nil),
            ("factura nr", "Facturanr 12", nil), ("plătit", "Platit cu cardul", nil), ("ședința", "Ședinţa de vineri", nil), ("", "orice", nil),
            ("---", "--- ", nil), ("cod", "Cod2026", nil), ("2026", "Nr.12/2026", nil), ("total de plată", "Total  de   plată: 120 lei", nil),
            ("total de plată", "Totalul de plată", nil), ("vin", "VIN: WVWZZZ1KZAW000000", nil), ("vin", "Vinieta", nil),
        ]
        let cases: [JSONValue] = inputs.map { input in
            let match: JSONValue = switch input.match {
            case .word: "word"
            case .stem: "stem"
            case nil: .null
            }
            let natural: JSONValue = RomanianText.WordMatch.natural(for: RomanianText.fold(input.phrase)) == .word ? "word" : "stem"
            return .object([
                "phrase": .string(input.phrase), "text": .string(input.text), "match": match, "natural": natural,
                "found": .bool(RomanianText.containsWord(input.phrase, in: input.text, as: input.match)),
            ])
        }
        return Vectors(
            name: "romanian-text-contains-word",
            rule: "RomanianText.containsWord(_:in:as:) and WordMatch.natural(for:): a keyword in text, as whole words or with an ending on its last",
            source: "ios/Shared/RomanianText.swift",
            shape: "phrase, text: a keyword and the text it is looked for in. match: word or stem as asked, or null for the natural rule. natural: what the natural rule gives for the folded phrase. found: whether the phrase is in the text.",
            cases: cases
        )
    }

    // MARK: Patterns

    static func textPattern() -> Vectors {
        let inputs: [(pattern: String, text: String, caseInsensitive: Bool)] = [
            (#"(\d{4})"#, "Cod \u{0661}\u{0662}\u{0663}\u{0664} 5678", false),
            (#"[a-z]+"#, "ȘTEFAN abc DEF", true),
            (#"[a-z]+"#, "ȘTEFAN abc DEF", false),
            (#"(ro)(\d{2})?"#, "RO49 ro", true),
            (#"\bde\b"#, "de, deci, de-a", false),
            (#"ș+"#, "Șș ş", true),
            (#"(?<!\d[ -]?)\d(?:[ -]?\d){11,}(?![ -]?\d)"#, "Nr. 12 4111 1111 1111 1111, 0722 123 456", false),
            (#"(\p{L}+)\s*:\s*(\S+)"#, "Total: 120 lei; Data:12.03", false),
            (#"[•*xX]{4}[ -]?(?:[•*xX]{4}[ -]?){0,3}(\d{4})(?!\d)"#, "**** **** **** 4821 și •••• 44445", false),
            (#"\w+"#, "café e\u{0301} naïve_x", false),
            (#"\s+"#, "a\u{00A0}b\u{2009}c\td", false),
        ]
        let cases: [JSONValue] = inputs.map { input in
            let text = input.text
            let matches = TextPattern.matches(input.pattern, in: text, caseInsensitive: input.caseInsensitive).map { match -> JSONValue in
                .object([
                    "at": .int(text.utf16.distance(from: text.startIndex, to: match.range.lowerBound)),
                    "length": .int(text.utf16.distance(from: match.range.lowerBound, to: match.range.upperBound)),
                    "groups": .array(match.groups.map(optional)),
                ])
            }
            return .object([
                "pattern": .string(input.pattern), "text": .string(text), "caseInsensitive": .bool(input.caseInsensitive),
                "matches": .array(matches),
            ])
        }
        return Vectors(
            name: "text-pattern",
            rule: "TextPattern.matches(_:in:caseInsensitive:): the regular expressions the text rules are written in (ICU's, as NSRegularExpression runs them)",
            source: "ios/Shared/TextPattern.swift",
            shape: "pattern, text, caseInsensitive: what is asked. matches: each match in order: where it starts and how long it is (in UTF-16 code units), and its groups, the whole match first, null for a group that took no part.",
            cases: cases
        )
    }
}
