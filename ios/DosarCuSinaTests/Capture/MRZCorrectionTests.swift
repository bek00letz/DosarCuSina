import Foundation
import Testing
@testable import DosarCuSina

/// OCR-B confusions repaired only where a check digit proves the repair. Synthetic zones
/// with placeholder data (`MRZFixtures`).
@Suite("Machine-readable zone correction")
struct MRZCorrectionTests {

    let now = Date(timeIntervalSince1970: 1_793_577_600)

    @Test("Placeholder zones read with every check passing")
    func fixturesAreValid() throws {
        let passport = try #require(MRZParser.parse(text: MRZFixtures.passport(), referenceDate: now))
        #expect(passport.allChecksValid)
        #expect(passport.documentNumber == "X04512378")
        #expect(passport.optionalData == "1800101990006")

        let card = try #require(MRZParser.parse(text: MRZFixtures.identityCard(), referenceDate: now))
        #expect(card.format == .td1)
        #expect(card.allChecksValid)
        #expect(card.documentNumber == "XT1234567")
    }

    @Test("A letter O read for a zero in the document number is repaired by its check digit")
    func repairsDocumentNumber() throws {
        // "X04512378" read as "XO4512378".
        let misread = MRZFixtures.replacing(MRZFixtures.passport(), line: 1, at: 1, with: "O")
        let result = try #require(MRZParser.parse(text: misread, referenceDate: now))
        #expect(result.documentNumber == "X04512378")
        #expect(result.documentNumberValid)
        #expect(result.allChecksValid)
    }

    @Test("Look-alike letters in dates and check digits are digits")
    func repairsDates() throws {
        var text = MRZFixtures.passport(birth: "900520", expiry: "310412")
        text = MRZFixtures.replacing(text, line: 1, at: 13, with: "S") // birth "9" stays; "0" → see below
        text = MRZFixtures.replacing(text, line: 1, at: 14, with: "O") // "900520" → "9O0520"
        text = MRZFixtures.replacing(text, line: 1, at: 22, with: "I") // expiry "310412" → "3I0412"
        let result = try #require(MRZParser.parse(text: text, referenceDate: now))
        // "S" where a "9" was printed is not a look-alike of 9: the birth date stays unverified.
        #expect(!result.birthDateValid)
        #expect(result.expiryDateValid)
        #expect(result.expiryDate == CaptureDay(year: 2031, month: 4, day: 12))
    }

    @Test("Fillers read as K or « are fillers")
    func fillers() throws {
        var text = MRZFixtures.passport()
        // Line 1: "P<UTOEXEMPLU<<ANA<<<…" — a K among the trailing fillers.
        text = MRZFixtures.replacing(text, line: 0, at: 20, with: "K")
        let result = try #require(MRZParser.parse(text: text, referenceDate: now))
        #expect(result.givenNames == "ANA")
        #expect(result.surname == "EXEMPLU")

        let guillemets = MRZFixtures.passport().replacingOccurrences(of: "ANA<<<<", with: "ANA«<<<<")
        let fromGuillemets = try #require(MRZParser.parse(text: guillemets, referenceDate: now))
        #expect(fromGuillemets.givenNames == "ANA")
    }

    @Test("A digit read as another digit is not guessed")
    func refusesDigitSwaps() throws {
        // "X04512378" read as "X04517378": no look-alike explains it.
        let misread = MRZFixtures.replacing(MRZFixtures.passport(), line: 1, at: 5, with: "7")
        let result = try #require(MRZParser.parse(text: misread, referenceDate: now))
        #expect(!result.documentNumberValid)
        #expect(result.documentNumber == "X04517378")
    }

    @Test("Two repairs that both pass are a guess, and the field stays unverified")
    func refusesAmbiguousRepairs() {
        // "X04512378" read as "X045I2378": both "1" and "L" make the check digit pass.
        let checked = MRZParser.checked("X045I2378", check: "5", as: .alphanumeric)
        #expect(!checked.valid)
        #expect(checked.value == "X045I2378")

        let unique = MRZParser.checked("XO4512378", check: "5", as: .alphanumeric)
        #expect(unique.valid)
        #expect(unique.value == "X04512378")
    }

    @Test("A repair the composite check digit doesn't confirm is undone")
    func compositeConfirmsRepairs() throws {
        // Corrupt the document number and its composite: the field-level repair alone isn't enough.
        var text = MRZFixtures.replacing(MRZFixtures.passport(), line: 1, at: 1, with: "O")
        let lastDigit = Array(text.components(separatedBy: "\n")[1])[43]
        let wrong: Character = lastDigit == "0" ? "1" : "0"
        text = MRZFixtures.replacing(text, line: 1, at: 43, with: wrong)
        let result = try #require(MRZParser.parse(text: text, referenceDate: now))
        #expect(!result.compositeValid)
        #expect(!result.documentNumberValid)
        #expect(result.documentNumber == "XO4512378")
    }

    @Test("Identity card back (TD1): a misread document number is repaired")
    func identityCardBack() throws {
        // "XT1234567" read as "XT123456Z"? Z isn't 7. Read "XT1Z34567" for "XT1234567".
        let misread = MRZFixtures.replacing(MRZFixtures.identityCard(), line: 0, at: 8, with: "Z")
        let result = try #require(MRZParser.parse(text: misread, referenceDate: now))
        #expect(result.documentNumber == "XT1234567")
        #expect(result.allChecksValid)
    }
}
