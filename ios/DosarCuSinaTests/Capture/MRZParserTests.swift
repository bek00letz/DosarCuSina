import Foundation
import Testing
@testable import DosarCuSina

/// Machine-readable zone parsing, using the fictional "UTOPIA" specimens published in ICAO Doc 9303.
@Suite("Machine-readable zone")
struct MRZParserTests {

    /// 2 November 2026, so century decisions are stable.
    let today = Date(timeIntervalSince1970: 1_793_577_600)

    @Test("Check digits follow ICAO weights 7, 3, 1")
    func checkDigits() {
        #expect(MRZParser.checkDigit(for: "L898902C3") == 6)
        #expect(MRZParser.checkDigit(for: "740812") == 2)
        #expect(MRZParser.checkDigit(for: "120415") == 9)
        #expect(MRZParser.checkDigit(for: "ZE184226B<<<<<") == 1)
        #expect(MRZParser.checkDigit(for: "<<<") == 0)
    }

    @Test("Passport (TD3) specimen reads with every check passing")
    func passportSpecimen() throws {
        let text = """
        P<UTOERIKSSON<<ANNA<MARIA<<<<<<<<<<<<<<<<<<<
        L898902C36UTO7408122F1204159ZE184226B<<<<<10
        """
        let result = try #require(MRZParser.parse(text: text, referenceDate: today))
        #expect(result.format == .td3)
        #expect(result.isPassport)
        #expect(result.allChecksValid)
        #expect(result.documentNumber == "L898902C3")
        #expect(result.issuingCountry == "UTO")
        #expect(result.surname == "ERIKSSON")
        #expect(result.givenNames == "ANNA MARIA")
        #expect(result.birthDate == CalendarDay(printedYear: 1974, month: 8, day: 12))
        #expect(result.expiryDate == CalendarDay(printedYear: 2012, month: 4, day: 15))
        #expect(result.sex == "F")
    }

    @Test("A future expiry stays in this century")
    func futureExpiry() throws {
        let text = """
        P<UTOERIKSSON<<ANNA<MARIA<<<<<<<<<<<<<<<<<<<
        L898902C36UTO7408122F3104150ZE184226B<<<<<16
        """
        let result = try #require(MRZParser.parse(text: text, referenceDate: today))
        #expect(result.allChecksValid)
        #expect(result.expiryDate == CalendarDay(printedYear: 2031, month: 4, day: 15))
    }

    @Test("ID card (TD1) specimen")
    func identityCardTD1() throws {
        let text = """
        I<UTOD231458907<<<<<<<<<<<<<<<
        7408122F1204159UTO<<<<<<<<<<<6
        ERIKSSON<<ANNA<MARIA<<<<<<<<<<
        """
        let result = try #require(MRZParser.parse(text: text, referenceDate: today))
        #expect(result.format == .td1)
        #expect(!result.isPassport)
        #expect(result.allChecksValid)
        #expect(result.documentNumber == "D23145890")
        #expect(result.givenNames == "ANNA MARIA")
    }

    @Test("Older ID card (TD2) specimen")
    func identityCardTD2() throws {
        let text = """
        I<UTOERIKSSON<<ANNA<MARIA<<<<<<<<<<<
        D231458907UTO7408122F1204159<<<<<<<6
        """
        let result = try #require(MRZParser.parse(text: text, referenceDate: today))
        #expect(result.format == .td2)
        #expect(result.allChecksValid)
        #expect(result.surname == "ERIKSSON")
    }

    @Test("A wrong check digit is reported, not hidden")
    func corruptedExpiryCheckDigit() throws {
        let text = """
        P<UTOERIKSSON<<ANNA<MARIA<<<<<<<<<<<<<<<<<<<
        L898902C36UTO7408122F1204158ZE184226B<<<<<10
        """
        let result = try #require(MRZParser.parse(text: text, referenceDate: today))
        #expect(!result.expiryDateValid)
        #expect(!result.allChecksValid)
    }

    @Test("Letters read in place of digits are repaired only when the check digit agrees")
    func ocrLookalikeRepair() throws {
        // "O" for "0" in the birth and expiry dates, spaces from recognition.
        let text = """
        P<UTOERIKSSON<<ANNA<MARIA<<<<<<<<<<<<<<<<<<<
        L898902C36UTO74O8122F12O4159ZE184226B<<<<< 10
        """
        let result = try #require(MRZParser.parse(text: text, referenceDate: today))
        #expect(result.birthDateValid)
        #expect(result.expiryDateValid)
        #expect(result.expiryDate == CalendarDay(printedYear: 2012, month: 4, day: 15))
    }

    @Test("Ordinary text has no machine-readable zone")
    func noMRZ() {
        #expect(MRZParser.parse(text: "Factura fiscală nr. 123\nTotal de plată 348,50 lei", referenceDate: today) == nil)
    }
}
