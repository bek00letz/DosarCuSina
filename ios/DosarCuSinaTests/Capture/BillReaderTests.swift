import Foundation
import Testing
@testable import DosarCuSina

/// Bills read by their kind's label table (`BillReader`), `ContractReader` and the known
/// providers (`UtilityProviders`), which replaced the first bill reader
/// (`RomanianUtilityParser`, switched off in ios/Legacy).
///
/// The first half runs that reader's fixtures (tests/legacy/ios/RomanianUtilityParserSuite.swift)
/// through the analyzer and checks every value it read still comes out the same; only
/// the street addresses became placeholders. The second half pins what the shared readers
/// add: a meter index that could read two ways is marked "Verifică", like every other value.
@Suite("Bills read by label tables")
struct BillReaderTests {

    static let referenceDate = Date(timeIntervalSince1970: 1_793_577_600)

    private func analyze(_ text: String, as kind: CaptureDocumentKind? = nil) -> CaptureAnalyzer.Analysis {
        CaptureAnalyzer(specializedParsers: [UtilityInvoiceParser()]).analyze(text: text, referenceDate: Self.referenceDate, as: kind)
    }

    private func field(_ key: CaptureFieldKey, _ analysis: CaptureAnalyzer.Analysis) -> CaptureField? {
        analysis.fields.first { $0.key == key }
    }

    private func day(_ year: Int, _ month: Int, _ day: Int) -> CaptureValue {
        .day(CalendarDay(printedYear: year, month: month, day: day)!)
    }

    private func money(_ amount: String, _ currency: String = "RON") -> CaptureValue {
        .money(Money(Decimal(string: amount)!, currency: currency))
    }

    private func invoiceNumber(_ analysis: CaptureAnalyzer.Analysis) -> String {
        field(.invoiceNumber, analysis)?.value.text ?? ""
    }

    // MARK: - The first reader's fixtures, one per provider

    @Test func digi() {
        let bill = analyze("""
        RCS & RDS S.A.
        Strada Exemplu 1, București
        FACTURA
        Factura seria FCR nr. 29481023
        Data facturii: 10.11.2026
        Data scadenta: 25.11.2026
        Cod client: 19482910
        Cod de plata: 94810293
        Abonament servicii telecomunicații: 125,63
        TVA 19%: 23,87
        Total de plata: 149,50 LEI
        """)
        #expect(bill.kind == .utilityInvoice)
        #expect(field(.provider, bill)?.value == .text("Digi (RCS & RDS)"))
        #expect(field(.clientCode, bill)?.value == .text("19482910"))
        #expect(invoiceNumber(bill).contains("29481023"))
        #expect(field(.issueDate, bill)?.value == day(2026, 11, 10))
        #expect(field(.dueDate, bill)?.value == day(2026, 11, 25))
        #expect(field(.total, bill)?.value == money("149.50"))
        #expect(field(.paymentCode, bill)?.value == .text("94810293"))
    }

    @Test func ppcEnel() {
        let bill = analyze("""
        PPC ENERGIE MUNTENIA S.A.
        Strada Exemplu 1, sector 3, București
        Factura fiscala seria PPC nr. 10928491
        Data emiterii: 01.12.2026
        Data scadentei: 18.12.2026
        Cod client: 304928192
        Cod plata: 948201948201
        Perioada de facturare: 01.11.2026 - 30.11.2026
        Index nou autocitit: 4521
        Index vechi: 4210
        Consum activ: 311 kWh
        Total de plata: 382,14 lei
        """)
        #expect(field(.provider, bill)?.value == .text("PPC / Enel"))
        #expect(field(.clientCode, bill)?.value == .text("304928192"))
        #expect(invoiceNumber(bill).contains("10928491"))
        #expect(field(.dueDate, bill)?.value == day(2026, 12, 18))
        let index = field(.meterIndex, bill)
        #expect(index?.value == .number(4521))
        #expect(index?.needsCheck == false, "Read one way only")
        #expect(field(.total, bill)?.value == money("382.14"))
        #expect(field(.paymentCode, bill)?.value == .text("948201948201"))
    }

    @Test func hidroelectrica() {
        let bill = analyze("""
        S.P.E.E.H. HIDROELECTRICA S.A.
        Strada Exemplu 1, București
        FACTURĂ FISCALĂ
        Factura seria HID nr. 84920192
        Data emiterii: 15.10.2026
        Data scadenta: 30.10.2026
        Cod client: 849201
        Cod loc consum (CLC): 10294819
        1.8.0: 12480
        Total de achitat: 215,80 LEI
        RO10294819283746
        """)
        #expect(field(.provider, bill)?.value == .text("Hidroelectrica"))
        #expect(field(.clientCode, bill)?.value == .text("849201"))
        #expect(invoiceNumber(bill).contains("84920192"))
        #expect(field(.dueDate, bill)?.value == day(2026, 10, 30))
        #expect(field(.meterIndex, bill)?.value == .number(12480), "The active energy register, 1.8.0")
        #expect(field(.total, bill)?.value == money("215.80"))
        #expect(field(.clcCode, bill)?.value == .text("10294819"))
        // The first reader also gave this code as the payment code; it is the consumption
        // point's, so it is the POD and nothing else.
        #expect(field(.podCode, bill)?.value == .text("RO10294819283746"))
        #expect(field(.paymentCode, bill) == nil)
    }

    @Test func eon() {
        let bill = analyze("""
        E.ON ENERGIE ROMANIA S.A.
        Strada Exemplu 1, Târgu Mureș
        Factura seria EON nr. 59281048
        Data emiterii: 01.11.2026
        Scadenta: 15.11.2026
        Cod incasare: 1049281948
        Index nou: 8320
        Total de plata: 540,00 LEI
        """)
        #expect(field(.provider, bill)?.value == .text("E.ON Energie"))
        #expect(field(.clientCode, bill)?.value == .text("1049281948"))
        #expect(field(.paymentCode, bill)?.value == .text("1049281948"), "As before, the collection code is both")
        #expect(invoiceNumber(bill).contains("59281048"))
        #expect(field(.dueDate, bill)?.value == day(2026, 11, 15))
        #expect(field(.meterIndex, bill)?.value == .number(8320))
        #expect(field(.total, bill)?.value == money("540.00"))
    }

    @Test func engie() {
        let bill = analyze("""
        ENGIE ROMANIA S.A.
        Strada Exemplu 1, sector 4, București
        FACTURĂ DE GAZE NATURALE
        Factura seria ENG nr. 78291048
        Data emiterii: 20.10.2026
        Data scadenta: 12.11.2026
        Cod client: 194820192
        Index nou autocitit: 1495 mc
        Index vechi: 1380 mc
        Total de plata: 412,30 LEI
        Cod bare client: 94810294819283
        """)
        #expect(field(.provider, bill)?.value == .text("ENGIE Romania"))
        #expect(field(.clientCode, bill)?.value == .text("194820192"))
        #expect(invoiceNumber(bill).contains("78291048"))
        #expect(field(.dueDate, bill)?.value == day(2026, 11, 12))
        #expect(field(.meterIndex, bill)?.value == .number(1495))
        #expect(field(.total, bill)?.value == money("412.30"))
        #expect(field(.paymentCode, bill)?.value == .text("94810294819283"))
        #expect(field(.serviceKind, bill)?.value == .text(ServiceKind.gas))
    }

    @Test func orange() {
        let bill = analyze("""
        ORANGE ROMANIA S.A.
        Strada Exemplu 1, București
        FACTURĂ FISCALĂ
        Factura seria ORG nr. 48291029
        Data emiterii: 05.11.2026
        Scadenta: 20.11.2026
        Cod abonat: 84920194
        Abonament Orange Me: 75,62
        Servicii suplimentare: 14,37
        Total factura curenta: 89,99 lei
        """)
        #expect(field(.provider, bill)?.value == .text("Orange Romania"))
        #expect(field(.clientCode, bill)?.value == .text("84920194"))
        #expect(invoiceNumber(bill).contains("48291029"))
        #expect(field(.dueDate, bill)?.value == day(2026, 11, 20))
        #expect(field(.total, bill)?.value == money("89.99"))
    }

    @Test func vodafone() {
        let bill = analyze("""
        VODAFONE ROMANIA S.A.
        Strada Exemplu 1, București
        FACTURA
        Factura seria VDF nr. 39281049
        Data emiterii: 02.11.2026
        Data scadenta: 22.11.2026
        Cod client: 29481029
        Total servicii Vodafone: 92,65
        TVA 19%: 17,60
        Total de plata: 110,25 LEI
        """)
        #expect(field(.provider, bill)?.value == .text("Vodafone Romania"))
        #expect(field(.clientCode, bill)?.value == .text("29481029"))
        #expect(invoiceNumber(bill).contains("39281049"))
        #expect(field(.dueDate, bill)?.value == day(2026, 11, 22))
        #expect(field(.total, bill)?.value == money("110.25"))
    }

    // MARK: - The first reader's fixtures: numbers, money and dates

    @Test func amountsAndCurrencies() {
        let cases: [(String, String, String)] = [
            ("Factura Electrica S.A.\nScadenta: 15.12.2026\nTotal de plata: 1.234,56 LEI", "1234.56", "RON"),
            ("Chitanta Salubrizare\nData scadenta: 10.12.2026\nTotal de plata: 123,45 RON", "123.45", "RON"),
            ("Abonament Parcare\nTermen de plata: 01.12.2026\nTotal: 50.00 lei", "50.00", "RON"),
            ("Factura Lucrari Izolatie\nScadenta: 30.12.2026\nTotal de plata: 14.500,75 LEI", "14500.75", "RON"),
            ("Factura Chirie Spatiu\nScadenta: 05.12.2026\nTotal de plata: 2.500,00 EUR", "2500.00", "EUR"),
            ("ENGIE ROMANIA S.A.\nTotal de plată: 1 450,50 lei\nScadență: 20.12.2026", "1450.50", "RON"),
            ("DIGI ROMANIA\nTotal de plată: 1\u{00A0}450,50 lei\nScadență: 20.12.2026", "1450.50", "RON"),
            ("FACTURĂ SERVICII\nTotal de plată: 14.500,00 €\nScadență: 20.12.2026", "14500.00", "EUR"),
        ]
        for (text, amount, currency) in cases {
            let bill = analyze(text, as: .utilityInvoice)
            #expect(field(.total, bill)?.value == money(amount, currency), "\(text)")
        }
        #expect(field(.dueDate, analyze(cases[2].0, as: .utilityInvoice))?.value == day(2026, 12, 1), "Termen de plată")
        #expect(field(.provider, analyze(cases[6].0))?.value == .text("Digi (RCS & RDS)"))
    }

    @Test func amountsAreReadByTheOneNumberReader() {
        let cases: [(String, String)] = [
            ("1.450,50 lei", "1450.50"), ("1 450,50 RON", "1450.50"), ("1\u{00A0}450,50 lei", "1450.50"),
            ("2\u{202F}500,00 EUR", "2500.00"), ("123,45", "123.45"), ("50.00 lei", "50.00"),
            ("1.450 lei", "1450"), ("14.500 lei", "14500"),
        ]
        for (raw, expected) in cases {
            #expect(RomanianNumber.value(raw, as: .money, from: .document) == Decimal(string: expected), "\(raw)")
        }
    }

    @Test func writtenMonths() {
        let bill = analyze("""
        Furnizor General
        Data emiterii: 15 octombrie 2026
        Data scadenta: 15 noiembrie 2026
        Cod client: ABC-12345
        Total de plata: 210,00 LEI
        """, as: .utilityInvoice)
        #expect(field(.issueDate, bill)?.value == day(2026, 10, 15))
        #expect(field(.dueDate, bill)?.value == day(2026, 11, 15))
        #expect(field(.clientCode, bill)?.value == .text("ABC-12345"))
    }

    @Test func romanNumeralMonths() {
        let cases: [(String, CalendarDay)] = [
            ("15.XI.2024", CalendarDay(printedYear: 2024, month: 11, day: 15)!), ("01.IV.2026", CalendarDay(printedYear: 2026, month: 4, day: 1)!),
            ("28/II/2025", CalendarDay(printedYear: 2025, month: 2, day: 28)!), ("12-VIII-2026", CalendarDay(printedYear: 2026, month: 8, day: 12)!),
        ]
        for (raw, expected) in cases {
            #expect(RomanianFieldExtractor.dates(inLine: RomanianText.fold(raw), index: 0).first?.day == expected, "\(raw)")
        }
        let bill = analyze("""
        NOTĂ DE PLATĂ
        Furnizor Apă Ilfov S.A.
        Scadență: 10.XII.2026
        Total: 95,40 lei
        """, as: .utilityInvoice)
        #expect(field(.dueDate, bill)?.value == day(2026, 12, 10))
    }

    @Test func oldAndNewDiacriticsFoldAlike() {
        #expect(RomanianText.fold("şcoală şi ţară de la Ştefan") == RomanianText.fold("școală și țară de la Ștefan"))
        #expect(RomanianText.fold("școală, țară, pâine, mâncare, împărat") == "scoala, tara, paine, mancare, imparat")
    }

    @Test func consumptionPointsWaterCodeAndBothIndexes() throws {
        let text = """
        ENGIE ROMANIA S.A.
        FACTURĂ DE GAZE NATURALE
        Cod loc consum (CLC): DEG0123456
        Punct de delimitare POD: RO001E987654321
        Cod client apa: 849201-9
        Index nou: 4520
        Index vechi: 4210
        Total de plata: 310,00 LEI
        """
        let bill = analyze(text)
        #expect(field(.clcCode, bill)?.value == .text("DEG0123456"))
        #expect(field(.podCode, bill)?.value == .text("RO001E987654321"))
        #expect(field(.clientCode, bill)?.value == .text("849201-9"), "The water code is the client code a home keeps")
        #expect(field(.meterIndex, bill)?.value == .number(4520))
        let layout = BillReader.layout(of: CaptureText(text))
        let previous = try #require(BillReader.previousIndex(in: layout))
        #expect(previous.value == 4210)
        #expect(Decimal(4520) - previous.value == 310, "The consumption between the two")
    }

    @Test func waterCodeAfterTheProvidersName() {
        let bill = analyze("APA NOVA BUCURESTI\nApa Nova cod: 1234567\nTotal: 45 lei", as: .utilityInvoice)
        #expect(field(.clientCode, bill)?.value == .text("1234567"), "Not the town in the provider's name")
    }

    @Test func knownProvidersByWholeWords() {
        #expect(UtilityProviders.named(inFolded: RomanianText.fold("SEMNATURA DIGITALA ROMANIA")) == nil)
        #expect(UtilityProviders.named(inFolded: RomanianText.fold("DIGI ROMANIA S.A. FACTURA"))?.name == "Digi (RCS & RDS)")
        #expect(UtilityProviders.named(inFolded: RomanianText.fold("Str. Leonte nr. 1"))?.name == nil, "EON isn't in Leonte")
        #expect(UtilityProviders.named(inFolded: RomanianText.fold("ENGIE Romania S.A."))?.name == "ENGIE Romania")
    }

    // MARK: - What the shared readers add

    @Test("A meter index that could read two ways is marked for checking")
    func ambiguousMeterIndexIsMarked() {
        let bill = analyze("""
        ENGIE Romania S.A.
        Factură de gaze naturale
        Cod client: 1000000000
        Index nou: 12.345 mc
        Total de plată: 245,30 lei
        """)
        let index = field(.meterIndex, bill)
        #expect(index?.value == .number(12345), "The Romanian rule: a dot groups thousands")
        #expect(index?.needsCheck == true, "Verifică")

        let plain = analyze("ENGIE Romania S.A.\nFactură de gaze naturale\nIndex nou: 12345 mc", as: .utilityInvoice)
        #expect(field(.meterIndex, plain)?.value == .number(12345))
        #expect(field(.meterIndex, plain)?.needsCheck == false)
    }

    @Test func everyBillIsReadTheSameWayWhateverItsProvider() {
        let bill = analyze("""
        Furnizor Exemplu S.A.
        Factură de energie electrică
        Index nou: 3.250
        Cod de plată: EX000123
        """, as: .utilityInvoice)
        #expect(field(.meterIndex, bill)?.value == .number(3250))
        #expect(field(.meterIndex, bill)?.needsCheck == true)
        #expect(field(.paymentCode, bill)?.value == .text("EX000123"))
    }

    @Test func thePreviousIndexIsNeverTheNewOne() {
        let swapped = analyze("ENGIE Romania S.A.\nIndex vechi: 4210\nIndex nou: 4520", as: .utilityInvoice)
        #expect(field(.meterIndex, swapped)?.value == .number(4520))
        #expect(field(.meterIndex, analyze("ENGIE Romania S.A.\nIndex vechi: 4210", as: .utilityInvoice)) == nil)

        let lower = analyze("ENGIE Romania S.A.\nIndex nou: 4100\nIndex vechi: 4210", as: .utilityInvoice)
        #expect(field(.meterIndex, lower)?.value == .number(4100))
        #expect(field(.meterIndex, lower)?.needsCheck == true, "Lower than the previous index")
    }

    @Test func twoDifferentNewIndexesAreMarked() {
        let bill = analyze("PPC Energie S.A.\nIndex nou: 4521\nIndex nou: 1820", as: .utilityInvoice)
        #expect(field(.meterIndex, bill)?.value == .number(4521))
        #expect(field(.meterIndex, bill)?.needsCheck == true)
    }

    @Test func aDueDateWithoutItsLabelIsAGuessMarkedForChecking() {
        let bill = analyze("""
        ENGIE Romania S.A.
        Data emiterii: 01.11.2026
        Perioada de facturare: 01.10.2026 - 31.10.2026
        Vă rugăm să plătiți până pe 20.11.2026
        Următoarea citire: 15.02.2027
        """, as: .utilityInvoice)
        let due = field(.dueDate, bill)
        #expect(due?.value == day(2026, 11, 20), "The latest date in the two months after its issue")
        #expect(due?.needsCheck == true)
    }

    @Test func aPaymentCodeReadOffTheTextProvesNothing() throws {
        let digits = String(repeating: "0", count: 29) + "1"
        let bill = analyze("ENGIE Romania S.A.\nTotal de plată: 245,30 lei\n\(digits)", as: .utilityInvoice)
        let code = try #require(field(.paymentCode, bill))
        #expect(code.value == .text(digits), "The digits printed under the barcode")
        #expect(ReadingArbiter.standing(code) == .pattern, "Only a decoded barcode is checked")

        let scanned = CaptureAnalyzer(specializedParsers: [UtilityInvoiceParser()]).analyze(
            text: "ENGIE Romania S.A.\nCod de plată: EX000123", barcodes: [CaptureBarcode(symbology: "code128", payload: "EX999999")],
            referenceDate: Self.referenceDate, as: .utilityInvoice)
        #expect(scanned.fields.first { $0.key == .paymentCode }?.value == .text("EX999999"), "The decoded barcode wins")
    }

    @Test func theBillsLabelsNameOnlyWhatItCarries() {
        let profile = CaptureDocumentKind.utilityInvoice.profile
        for (key, _) in profile.labels where key != .previousMeterIndex {
            #expect(profile.expectedKeys.contains(key) || key == .paymentCode, "\(key)")
            #expect(CaptureDocumentKind.utilityInvoice.allows(key), "\(key)")
        }
    }
}
