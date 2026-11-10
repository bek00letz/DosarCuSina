import Foundation
import Testing
@testable import DosarCuSina

@Suite("Field validation and formatting")
struct FieldFormatterTests {
    @Test("Romanian plates are formatted with dashes", arguments: [
        ("b123abc", "B-123-ABC"),
        ("B 12 XYZ", "B-12-XYZ"),
        ("cj-12-abc", "CJ-12-ABC"),
        ("IF 07 DEV", "IF-07-DEV"),
    ])
    func formatsPlates(raw: String, expected: String) {
        #expect(FieldFormatter.formatPlate(raw) == expected)
        #expect(FieldFormatter.validate(raw, as: .plate) == .valid)
    }

    @Test("Plates that aren't Romanian only warn", arguments: ["XX-12-ABC", "CJ-123-ABC", "B-12-AB", "M AB 1234"])
    func warnsOnForeignPlates(raw: String) {
        #expect(FieldFormatter.formatPlate(raw) == nil)
        let result = FieldFormatter.validate(raw, as: .plate)
        #expect(result.allowsSaving)
        #expect(result.message != nil)
    }

    @Test func vinNeedsSeventeenAllowedCharacters() {
        #expect(FieldFormatter.validate("WVWZZZ1KZ8W123456", as: .vin) == .valid)
        #expect(FieldFormatter.validate("wvwzzz1kz8w12345", as: .vin).message != nil)
        #expect(FieldFormatter.validate("WVWZZZ1KZ8W12345O", as: .vin).message != nil)
        #expect(FieldFormatter.normalize("wvw zzz-1kz8w123456", as: .vin) == "WVWZZZ1KZ8W123456")
    }

    @Test func microchipHasFifteenDigits() {
        #expect(FieldFormatter.validate("642 0000 0000 0001", as: .microchip) == .valid)
        #expect(FieldFormatter.validate("12345", as: .microchip).allowsSaving)
        #expect(FieldFormatter.validate("12345", as: .microchip) != .valid)
    }

    @Test func ibanUsesTheMod97Check() {
        #expect(IBAN.isValid("RO49 AAAA 1B31 0075 9384 0000"))
        #expect(!IBAN.isValid("RO49 AAAA 1B31 0075 9384 0001"))
        #expect(!IBAN.isValid("RO49AAAA1B310075"))
        #expect(FieldFormatter.validate("RO49AAAA1B31007593840001", as: .iban).allowsSaving == false)
        #expect(FieldFormatter.groupIBAN("RO49AAAA1B31007593840000") == "RO49 AAAA 1B31 0075 9384 0000")
    }

    @Test func phoneAndEmailAndURL() {
        #expect(FieldFormatter.normalize("0040 722 123 456", as: .phone) == "+40722123456")
        #expect(FieldFormatter.validate("0722 123 456", as: .phone) == .valid)
        #expect(FieldFormatter.validate("12", as: .phone).allowsSaving == false)
        #expect(FieldFormatter.validate("nume@exemplu.ro", as: .email) == .valid)
        #expect(FieldFormatter.validate("nume@exemplu", as: .email).allowsSaving == false)
        #expect(FieldFormatter.normalize("exemplu.ro/anulare", as: .url) == "https://exemplu.ro/anulare")
        #expect(FieldFormatter.validate("exemplu.ro", as: .url) == .valid)
    }

    @Test func emptyInputIsEmptyNotInvalid() {
        for type in FieldType.allCases {
            #expect(FieldFormatter.validate("   ", as: type) == .empty)
            #expect(FieldFormatter.value(from: "", as: type) == nil)
        }
    }

    @Test func typedTextBecomesTheRightValue() {
        #expect(FieldFormatter.value(from: "142.500", as: .metric) == .number(142_500))
        #expect(FieldFormatter.value(from: "31,5", as: .number) == .number(31.5))
        #expect(FieldFormatter.value(from: "1.250,50", as: .money, currency: "EUR") == .money(Money(Decimal(string: "1250.5")!, currency: "EUR")))
        #expect(FieldFormatter.value(from: "b 123 abc", as: .plate) == .text("B-123-ABC"))
    }

    @Test func displayUsesUnitsAndRomanianFormatting() {
        let locale = Locale(identifier: "ro_RO")
        #expect(FieldFormatter.display(.number(142_500), as: .metric, unit: .kilometres, locale: locale) == "142.500 km")
        #expect(FieldFormatter.display(.bool(true), as: .toggle, locale: locale) == "Da")
        #expect(FieldFormatter.display(.text("RO49AAAA1B31007593840000"), as: .iban, locale: locale) == "RO49 AAAA 1B31 0075 9384 0000")
    }

    @Test func yearsHaveNoThousandsSeparatorAndStayPlausible() {
        let locale = Locale(identifier: "ro_RO")
        #expect(FieldFormatter.display(.number(2018), as: .year, locale: locale) == "2018")
        #expect(FieldFormatter.validate("2018", as: .year) == .valid)
        #expect(FieldFormatter.validate("18", as: .year) != .valid)
        #expect(FieldFormatter.validate("2018,5", as: .year) != .valid)
    }
}

@Suite("Field values")
struct FieldValueTests {
    @Test func everyKindRoundTripsThroughJSON() throws {
        var values = FieldValues()
        values["a"] = .text("B-123-ABC")
        values["b"] = .number(142_500)
        values["c"] = .money(Money(Decimal(string: "350.5")!, currency: "RON"))
        values["d"] = .date(CalendarDay("2027-03-31"))
        values["e"] = .bool(false)
        values["f"] = .choices(["Căpușe", "Purici"])
        let data = try JSONEncoder().encode(values)
        #expect(try JSONDecoder().decode(FieldValues.self, from: data) == values)
    }

    @Test func encodingMatchesTheArchiveContract() throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let money = String(decoding: try encoder.encode(FieldValue.money(Money(350, currency: "RON"))), as: UTF8.self)
        #expect(money == #"{"amount":"350","currency":"RON","type":"money"}"#)
        let day = String(decoding: try encoder.encode(FieldValue.date(CalendarDay("2027-03-31"))), as: UTF8.self)
        #expect(day == #"{"type":"date","value":"2027-03-31"}"#)
    }

    @Test func unknownValuesAreSkippedNotFatal() throws {
        let json = #"{"ok": {"type": "text", "value": "x"}, "future": {"type": "hologram", "value": 1}}"#
        let values = try JSONDecoder().decode(FieldValues.self, from: Data(json.utf8))
        #expect(values["ok"] == .text("x"))
        #expect(values["future"] == nil)
    }

    @Test func emptyValuesAreNotStored() {
        var values = FieldValues()
        values["a"] = .text("   ")
        values["b"] = .choices([])
        #expect(values.isEmpty)
    }
}

@Suite("Money")
struct MoneyTests {
    @Test("Amounts parse in Romanian and plain formats", arguments: [
        ("1.234,56", "1234.56"), ("1234.5", "1234.5"), ("1 234,50", "1234.5"), ("12,5", "12.5"), ("1.250", "1250"), ("350", "350"),
    ])
    func parsesAmounts(raw: String, expected: String) {
        #expect(RomanianNumber.value(raw, as: .money) == Decimal(string: expected))
    }

    @Test func totalsNeverMixCurrencies() {
        let totals = MoneyTotals([Money(100), Money(Decimal(string: "2.99")!, currency: "EUR"), Money(50), Money(1, currency: "eur")])
        #expect(totals.amount(in: "RON") == 150)
        #expect(totals.amount(in: "EUR") == Decimal(string: "3.99"))
        #expect(totals.amounts.map(\.currency) == ["RON", "EUR"])
    }

    @Test func formatsForRomania() {
        let locale = Locale(identifier: "ro_RO")
        let text = Money(Decimal(string: "1234.5")!, currency: "RON").formatted(locale: locale)
        #expect(text.contains("1.234,50"))
        #expect(Money(350).formattedCompact(locale: locale).contains("350"))
        #expect(!Money(350).formattedCompact(locale: locale).contains(","))
    }

    @Test func amountStringRoundsToCents() {
        #expect(Money(Decimal(string: "12.345")!).amountString == "12.34")
        #expect(Money(Decimal(string: "12.5")!).amountString == "12.5")
    }
}

@Suite("Calendar days")
struct CalendarDayTests {
    @Test func noonKeepsTheDayAcrossTimeZones() {
        let day = CalendarDay("2026-03-29")
        let stored = day.noonDate(in: .bucharest)
        var london = Calendar(identifier: .gregorian)
        london.timeZone = TimeZone(identifier: "Europe/London")!
        var newYork = Calendar(identifier: .gregorian)
        newYork.timeZone = TimeZone(identifier: "America/New_York")!
        #expect(CalendarDay(stored, calendar: london) == day)
        #expect(CalendarDay(stored, calendar: newYork) == day)
    }

    @Test func monthDayClampsInShortYears() {
        #expect(MonthDay(month: 2, day: 29).day(inYear: 2027, calendar: .bucharest) == CalendarDay("2027-02-28"))
        #expect(MonthDay(month: 2, day: 29).day(inYear: 2028, calendar: .bucharest) == CalendarDay("2028-02-29"))
    }
}
