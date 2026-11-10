import Foundation
import Testing
@testable import DosarCuSina

/// Capture reads into the app's own day, money and field-role types, so nothing is turned
/// from one type into another between reading a page and filing it. These pin what the
/// conversions that went away used to do.
@MainActor
@Suite("Capture's shared values")
struct CaptureSharedValuesTests {

    // MARK: Days

    @Test func aPrintedDayIsOneTheCalendarHasInAYearADocumentPrints() {
        #expect(CalendarDay(printedYear: 2031, month: 2, day: 31) == nil)
        #expect(CalendarDay(printedYear: 2031, month: 13, day: 1) == nil)
        #expect(CalendarDay(printedYear: 2031, month: 3, day: 0) == nil)
        #expect(CalendarDay(printedYear: 2027, month: 2, day: 29) == nil)
        #expect(CalendarDay(printedYear: 2028, month: 2, day: 29) == CalendarDay("2028-02-29"))
        #expect(CalendarDay(printedYear: 1899, month: 12, day: 31) == nil, "A misread year, not a day")
        #expect(CalendarDay(printedYear: 2201, month: 1, day: 1) == nil, "A misread year, not a day")
        #expect(CalendarDay(validYear: 1899, month: 12, day: 31) == CalendarDay("1899-12-31"),
                "Only capture knows the years a document prints")
        #expect(CalendarDay(validYear: 2100, month: 2, day: 29) == nil, "2100 isn't a leap year")
    }

    @Test func monthsAfterADayClampToAShorterMonth() {
        #expect(CalendarDay("2027-01-31").printed(addingMonths: 1) == CalendarDay("2027-02-28"))
        #expect(CalendarDay("2028-01-31").printed(addingMonths: 1) == CalendarDay("2028-02-29"))
        #expect(CalendarDay("2028-03-31").printed(addingMonths: -1) == CalendarDay("2028-02-29"))
        #expect(CalendarDay("2026-11-10").printed(addingMonths: -80 * 12) == CalendarDay("1946-11-10"))
        #expect(CalendarDay("2026-11-10").printed(addingMonths: 900) == CalendarDay("2101-11-10"))
        #expect(CalendarDay("2026-11-10").printed(addingMonths: 3_000) == nil, "A length no document states")
        #expect(CalendarDay("2026-11-10").printed(addingMonths: .max) == nil)
        #expect(CalendarDay("2026-11-10").printed(addingMonths: .min) == nil)
    }

    @Test(arguments: ["Pacific/Kiritimati", "Pacific/Pago_Pago", "Europe/Bucharest", "America/Sao_Paulo", "UTC"])
    func aDayReadFilesAsTheSameDayInEveryTimeZone(_ zone: String) throws {
        let day = CalendarDay("2031-03-12")
        let expiry = FieldDefinition(key: "example.expiry", label: "Valabil până la", type: .expiryDate)
        #expect(CaptureMapping.fieldValue(.day(day), for: expiry) == .date(day))

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(identifier: zone))
        var draft = VisitDraft(date: noon("2026-11-02"))
        let issued = CaptureField(key: .issueDate, value: .day(day), confidence: 0.9, sourceText: nil, tier: .heuristic)
        draft.apply(Self.result([issued]), components: [], calendar: calendar)
        #expect(CalendarDay(draft.date, calendar: calendar) == day, "A visit's day is the invoice's, wherever the phone is")
    }

    @Test func aDayTheReviewShowsIsTheDayRead() {
        let day = CalendarDay("2031-03-12")
        #expect(CaptureMapping.displayText(.day(day)) == DosarFormat.longDay(day))
    }

    // MARK: Money

    @Test func moneyKeepsItsCurrencyFromReadingToFiling() throws {
        let price = FieldDefinition(key: "example.price", label: "Preț", type: .money, role: .purchasePrice)
        let euros = Money(try #require(Decimal(string: "12.50")), currency: "eur")
        #expect(euros.currency == "EUR")
        #expect(CaptureMapping.fieldValue(.money(euros), for: price) == .money(Money(try #require(Decimal(string: "12.50")), currency: "EUR")))
        #expect(CaptureMapping.displayText(.money(euros)) == euros.formattedCompact())

        let read = try #require(RomanianFieldExtractor.total(in: CaptureText("Total de plată: 120,00 EUR")))
        #expect(read.money == Money(120, currency: "EUR"), "Never turned into lei")
    }

    @Test func twoReadersAgreeOnAnAmountWhateverTheCaseOfItsCurrency() {
        #expect(CaptureValue.money(Money(695, currency: "ron")) == .money(Money(695, currency: "RON")))
        #expect(CaptureValue.money(Money(695, currency: "EUR")) != .money(Money(695, currency: "RON")))
    }

    // MARK: Roles

    @Test func aFieldWithoutAPlaceOfItsOwnFillsTheTemplatesRole() {
        #expect(CaptureMapping.role(for: .expiryDate) == .expiryDate)
        #expect(CaptureMapping.role(for: .purchaseDate) == .purchaseDate)
        #expect(CaptureMapping.role(for: .purchasePrice) == .purchasePrice)
        #expect(CaptureMapping.role(for: .retailer) == .retailer)
        #expect(CaptureMapping.role(for: .warrantyUntil) == .warrantyUntil)
        #expect(CaptureMapping.role(for: .policyNumber) == nil, "A key fact goes only where the template names it")
        #expect(CaptureMapping.role(for: .productName) == nil)

        #expect(CaptureMapping.fieldKey(for: .expiryDate, kind: .other, in: BuiltInTemplates.tenancy, deadline: nil) == "tenancy.end")
        #expect(CaptureMapping.fieldKey(for: .purchasePrice, kind: .fiscalReceipt, in: BuiltInTemplates.purchase, deadline: nil) == "purchase.price")
    }

    // MARK: Helpers

    private static func result(_ fields: [CaptureField]) -> CaptureResult {
        CaptureResult(kind: .serviceInvoice, kindConfidence: 0.9, fields: fields, suggestions: [], reminder: nil,
                      recognizedText: "", barcodes: [], document: nil, notices: [])
    }
}
