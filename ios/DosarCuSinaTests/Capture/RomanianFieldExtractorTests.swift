import Foundation
import Testing
@testable import DosarCuSina

@Suite("Romanian field extraction")
struct RomanianFieldExtractorTests {

    @Test("Amounts in Romanian and international formats", arguments: [
        ("1.234,56", Decimal(string: "1234.56")),
        ("1 234,56", Decimal(string: "1234.56")),
        ("1,234.56", Decimal(string: "1234.56")),
        ("348,50", Decimal(string: "348.5")),
        ("50.00", Decimal(string: "50")),
        ("1.450", Decimal(string: "1450")),
        ("350", Decimal(string: "350")),
    ])
    func amounts(raw: String, expected: Decimal?) {
        #expect(RomanianFieldExtractor.amount(raw)?.value == expected)
    }

    @Test("Amounts on a line skip the dates")
    func amountsSkipDates() {
        let found = RomanianFieldExtractor.amounts(inLine: "data 15.11.2026 total 1.240,00 lei")
        #expect(found.map(\.amount) == [Decimal(string: "1240")!])
    }

    @Test("Dates in numeric, written and Roman-numeral forms")
    func dates() {
        let line = RomanianText.fold("Emisă la 15.11.2026, scadentă pe 3 decembrie 2026, recepție 01/XII/2026, ISO 2026-12-20")
        let days = RomanianFieldExtractor.dates(inLine: line, index: 0).map(\.day)
        #expect(days == [
            CaptureDay(year: 2026, month: 11, day: 15)!,
            CaptureDay(year: 2026, month: 12, day: 3)!,
            CaptureDay(year: 2026, month: 12, day: 1)!,
            CaptureDay(year: 2026, month: 12, day: 20)!,
        ])
    }

    @Test("Impossible dates are rejected")
    func impossibleDates() {
        #expect(CaptureDay(year: 2026, month: 2, day: 30) == nil)
        #expect(RomanianFieldExtractor.dates(inLine: "31.02.2026", index: 0).isEmpty)
    }

    @Test("A labelled date wins over other dates on the page")
    func labelledDate() throws {
        let text = CaptureText("""
        Data facturii: 01.11.2026
        Data scadenței: 21.11.2026
        """)
        let due = try #require(RomanianFieldExtractor.labelledDate(["scadent"], in: text))
        #expect(due.day == CaptureDay(year: 2026, month: 11, day: 21))
    }

    @Test("Company tax ID checksum (CUI)")
    func taxIDChecksum() {
        #expect(RomanianFieldExtractor.isValidCUI("12345674"))
        #expect(RomanianFieldExtractor.isValidCUI("98765438"))
        #expect(!RomanianFieldExtractor.isValidCUI("12345675"))
        #expect(!RomanianFieldExtractor.isValidCUI("1"))
    }

    @Test("Registration plates are normalized and checked against county codes")
    func plates() {
        #expect(RomanianFieldExtractor.licensePlate(in: CaptureText("Nr. înmatriculare: B-123-ABC"))?.value == "B 123 ABC")
        #expect(RomanianFieldExtractor.licensePlate(in: CaptureText("Auto CJ 12 XYZ"))?.value == "CJ 12 XYZ")
        // "ZZ" isn't a county, and only Bucharest uses three digits.
        #expect(RomanianFieldExtractor.licensePlate(in: CaptureText("ZZ 12 ABC")) == nil)
        #expect(RomanianFieldExtractor.licensePlate(in: CaptureText("CJ 123 ABC")) == nil)
    }

    @Test("VIN is found and its check digit evaluated")
    func vin() throws {
        // The textbook example VIN with a valid position-9 check digit.
        let valid = try #require(RomanianFieldExtractor.vin(in: CaptureText("Serie șasiu: 1M8GDM9AXKP042788")))
        #expect(valid.value == "1M8GDM9AXKP042788")
        #expect(valid.checksumValid)
        let european = try #require(RomanianFieldExtractor.vin(in: CaptureText("VIN WVWZZZAUZJW000000")))
        #expect(!european.checksumValid)
    }

    @Test("Claims phone is read next to a claims label")
    func claimsPhone() {
        let text = CaptureText("""
        Polița RCA
        Avizare daune nonstop:
        0800 123 456
        """)
        #expect(RomanianFieldExtractor.claimsPhone(in: text)?.value == "0800123456")
    }

    @Test("Odometer prefers a labelled value")
    func odometer() throws {
        let text = CaptureText("""
        Recomandare: următoarea revizie la 15.000 km
        Km bord: 86.420
        """)
        let reading = try #require(RomanianFieldExtractor.odometer(in: text))
        #expect(reading.km == 86_420)
        #expect(reading.labelled)
    }

    @Test("Warranty length in months or years")
    func warranty() {
        #expect(RomanianFieldExtractor.warrantyMonths(in: CaptureText("Termen de garanție: 24 luni"))?.months == 24)
        #expect(RomanianFieldExtractor.warrantyMonths(in: CaptureText("Garanție 3 ani"))?.months == 36)
    }

    @Test("Invoice series and number")
    func invoiceNumber() {
        #expect(RomanianFieldExtractor.invoiceNumber(in: CaptureText("FACTURĂ FISCALĂ seria AUT nr. 004512"))?.value == "AUT 004512")
    }

    @Test("Component keys come from the templates' catalogs")
    func components() {
        let resolver = CatalogComponentResolver()
        #expect(resolver.componentKey(for: "Plăcuțe frână față ATE") == "brakes.padsFront")
        #expect(resolver.componentKey(for: "Pastile frana spate") == "brakes.padsRear")
        #expect(resolver.componentKey(for: "Disc frana spate") == "brakes.discsRear")
        #expect(resolver.componentKey(for: "Filtru ulei Mann") == "engine.oil")
        #expect(resolver.componentKey(for: "Ulei motor 5W30 4L") == "engine.oil")
        #expect(resolver.componentKey(for: "Kit distribuție") == "engine.timing")
        #expect(resolver.componentKey(for: "Baterie lavoar") == "plumbing.taps")
        #expect(resolver.componentKey(for: "Odorizant") == nil)
    }

    @Test("Labour lines are labour, not parts")
    func labour() {
        let line = CaptureLineItem(description: "Manoperă 1,5 ore")
        #expect(line.isLabour)
        #expect(CatalogComponentResolver().componentKey(for: line.description) == nil)
        #expect(!CaptureLineItem(description: "Filtru ulei").isLabour)
    }
}
