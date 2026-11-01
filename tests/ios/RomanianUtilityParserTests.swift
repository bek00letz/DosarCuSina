import Foundation

/// Comprehensive unit test suite for `RomanianUtilityParser`.
///
/// Verifies:
/// 1. Extraction across all 7 supported Romanian utility providers:
///    - Digi (RCS & RDS)
///    - PPC / Enel
///    - Hidroelectrica
///    - E.ON
///    - Engie
///    - Orange
///    - Vodafone
/// 2. Asserts extraction of provider enum, client code, invoice number, due date, index reading, total amount, and barcode/QR string.
/// 3. Romanian currency and number formatting tests: parsing `1.234,56 LEI`, `123,45 RON`, `50.00 lei`, and EUR currency.
/// 4. Romanian date parsing (numeric and written month names, e.g. "15 noiembrie 2026").
/// 5. Ambiguous date resolution: prioritizing due date over issue date.
/// 6. Fallback general provider detection.
public final class RomanianUtilityParserTests: Sendable {
    
    private static let calendar: Calendar = {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(secondsFromGMT: 0)!
        cal.locale = Locale(identifier: "ro_RO")
        return cal
    }()
    
    // MARK: - 1. Digi (RCS & RDS) Tests
    
    public static func testDigiInvoiceExtraction() throws {
        let parser = RomanianUtilityParser()
        let invoiceText = """
        RCS & RDS S.A.
        Calea 13 Septembrie nr. 90, București
        FACTURA
        Factura seria FCR nr. 29481023
        Data facturii: 10.11.2026
        Data scadenta: 25.11.2026
        Cod client: 19482910
        Cod de plata: 94810293
        Abonament servicii telecomunicații: 125,63
        TVA 19%: 23,87
        Total de plata: 149,50 LEI
        """
        
        let result = parser.parseUtilityBill(text: invoiceText)
        
        try assertEqual(result.provider, .digi, "Provider should be detected as .digi")
        try assertEqual(result.clientCode, "19482910", "Digi client code extraction")
        try assertTrue(result.invoiceNumber?.contains("29481023") == true, "Digi invoice number extraction")
        try assertNotNil(result.dueDate, "Due date should not be nil")
        
        let dueComponents = calendar.dateComponents([.year, .month, .day], from: result.dueDate!)
        try assertEqual(dueComponents.year, 2026, "Due date year")
        try assertEqual(dueComponents.month, 11, "Due date month")
        try assertEqual(dueComponents.day, 25, "Due date day")
        
        try assertNotNil(result.totalAmount, "Total amount should not be nil")
        try assertAlmostEqual(result.totalAmount!, 149.50, accuracy: 0.01, "Total amount should be 149.50")
        try assertEqual(result.currency, "RON", "Currency should be RON")
        try assertEqual(result.barcodeRaw, "94810293", "Payment code should match")
    }
    
    // MARK: - 2. PPC / Enel Tests
    
    public static func testPpcEnelInvoiceExtraction() throws {
        let parser = RomanianUtilityParser()
        let invoiceText = """
        PPC ENERGIE MUNTENIA S.A.
        B-dul Mircea Vodă nr. 30, sector 3, București
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
        """
        
        let result = parser.parseUtilityBill(text: invoiceText)
        
        try assertEqual(result.provider, .ppcEnel, "Provider should be detected as .ppcEnel")
        try assertEqual(result.clientCode, "304928192", "PPC client code should start with 30")
        try assertTrue(result.invoiceNumber?.contains("10928491") == true, "PPC invoice number")
        try assertNotNil(result.dueDate, "PPC due date")
        
        let dueComponents = calendar.dateComponents([.year, .month, .day], from: result.dueDate!)
        try assertEqual(dueComponents.year, 2026, "Due date year")
        try assertEqual(dueComponents.month, 12, "Due date month")
        try assertEqual(dueComponents.day, 18, "Due date day")
        
        try assertNotNil(result.indexReading, "Index reading should not be nil")
        try assertAlmostEqual(result.indexReading!, 4521.0, accuracy: 0.1, "Index reading should be 4521")
        try assertEqual(result.meterIndex, "4521", "Meter index string alias")
        
        try assertNotNil(result.totalAmount, "Total amount should not be nil")
        try assertAlmostEqual(result.totalAmount!, 382.14, accuracy: 0.01, "Total amount should be 382.14")
        try assertEqual(result.barcodeRaw, "948201948201", "PPC payment code extraction")
    }
    
    // MARK: - 3. Hidroelectrica Tests
    
    public static func testHidroelectricaInvoiceExtraction() throws {
        let parser = RomanianUtilityParser()
        let invoiceText = """
        S.P.E.E.H. HIDROELECTRICA S.A.
        Bd. Ion Mihalache nr. 15-17, București
        FACTURĂ FISCALĂ
        Factura seria HID nr. 84920192
        Data emiterii: 15.10.2026
        Data scadenta: 30.10.2026
        Cod client: 849201
        Cod loc consum (CLC): 10294819
        1.8.0: 12480
        Total de achitat: 215,80 LEI
        RO10294819283746
        """
        
        let result = parser.parseUtilityBill(text: invoiceText)
        
        try assertEqual(result.provider, .hidroelectrica, "Provider should be detected as .hidroelectrica")
        try assertEqual(result.clientCode, "849201", "Hidroelectrica client code")
        try assertTrue(result.invoiceNumber?.contains("84920192") == true, "Hidroelectrica invoice number")
        try assertNotNil(result.dueDate, "Due date should not be nil")
        
        let dueComponents = calendar.dateComponents([.year, .month, .day], from: result.dueDate!)
        try assertEqual(dueComponents.year, 2026, "Due date year")
        try assertEqual(dueComponents.month, 10, "Due date month")
        try assertEqual(dueComponents.day, 30, "Due date day")
        
        // Active energy 1.8.0 index reading preference
        try assertNotNil(result.indexReading, "1.8.0 active energy reading")
        try assertAlmostEqual(result.indexReading!, 12480.0, accuracy: 0.1, "Index reading 12480")
        
        try assertNotNil(result.totalAmount, "Total amount")
        try assertAlmostEqual(result.totalAmount!, 215.80, accuracy: 0.01, "Total amount should be 215.80")
        try assertEqual(result.barcodeRaw, "RO10294819283746", "POD barcode extraction")
    }
    
    // MARK: - 4. E.ON Tests
    
    public static func testEonInvoiceExtraction() throws {
        let parser = RomanianUtilityParser()
        let invoiceText = """
        E.ON ENERGIE ROMANIA S.A.
        Târgu Mureș, str. Pandurilor nr. 42
        Factura seria EON nr. 59281048
        Data emiterii: 01.11.2026
        Scadenta: 15.11.2026
        Cod incasare: 1049281948
        Index nou: 8320
        Total de plata: 540,00 LEI
        """
        
        let result = parser.parseUtilityBill(text: invoiceText)
        
        try assertEqual(result.provider, .eon, "Provider should be detected as .eon")
        try assertEqual(result.clientCode, "1049281948", "E.ON collection / client code")
        try assertTrue(result.invoiceNumber?.contains("59281048") == true, "E.ON invoice number")
        try assertNotNil(result.dueDate, "E.ON due date")
        
        let dueComponents = calendar.dateComponents([.year, .month, .day], from: result.dueDate!)
        try assertEqual(dueComponents.year, 2026, "Due date year")
        try assertEqual(dueComponents.month, 11, "Due date month")
        try assertEqual(dueComponents.day, 15, "Due date day")
        
        try assertNotNil(result.indexReading, "Index reading")
        try assertAlmostEqual(result.indexReading!, 8320.0, accuracy: 0.1, "Index reading should be 8320")
        
        try assertNotNil(result.totalAmount, "Total amount")
        try assertAlmostEqual(result.totalAmount!, 540.00, accuracy: 0.01, "Total amount should be 540.00")
    }
    
    // MARK: - 5. Engie Tests
    
    public static func testEngieInvoiceExtraction() throws {
        let parser = RomanianUtilityParser()
        let invoiceText = """
        ENGIE ROMANIA S.A.
        B-dul Mărășești nr. 4-6, sector 4, București
        FACTURĂ DE GAZE NATURALE
        Factura seria ENG nr. 78291048
        Data emiterii: 20.10.2026
        Data scadenta: 12.11.2026
        Cod client: 194820192
        Index nou autocitit: 1495 mc
        Index vechi: 1380 mc
        Total de plata: 412,30 LEI
        Cod bare client: 94810294819283
        """
        
        let result = parser.parseUtilityBill(text: invoiceText)
        
        try assertEqual(result.provider, .engie, "Provider should be detected as .engie")
        try assertEqual(result.clientCode, "194820192", "Engie client code")
        try assertTrue(result.invoiceNumber?.contains("78291048") == true, "Engie invoice number")
        try assertNotNil(result.dueDate, "Due date")
        
        let dueComponents = calendar.dateComponents([.year, .month, .day], from: result.dueDate!)
        try assertEqual(dueComponents.year, 2026, "Due date year")
        try assertEqual(dueComponents.month, 11, "Due date month")
        try assertEqual(dueComponents.day, 12, "Due date day")
        
        try assertNotNil(result.indexReading, "Index reading in mc")
        try assertAlmostEqual(result.indexReading!, 1495.0, accuracy: 0.1, "Index reading should be 1495")
        
        try assertNotNil(result.totalAmount, "Total amount")
        try assertAlmostEqual(result.totalAmount!, 412.30, accuracy: 0.01, "Total amount should be 412.30")
        try assertEqual(result.barcodeRaw, "94810294819283", "Barcode client code")
    }
    
    // MARK: - 6. Orange Tests
    
    public static func testOrangeInvoiceExtraction() throws {
        let parser = RomanianUtilityParser()
        let invoiceText = """
        ORANGE ROMANIA S.A.
        B-dul Lascăr Catargiu nr. 51-53, București
        FACTURĂ FISCALĂ
        Factura seria ORG nr. 48291029
        Data emiterii: 05.11.2026
        Scadenta: 20.11.2026
        Cod abonat: 84920194
        Abonament Orange Me: 75,62
        Servicii suplimentare: 14,37
        Total factura curenta: 89,99 lei
        """
        
        let result = parser.parseUtilityBill(text: invoiceText)
        
        try assertEqual(result.provider, .orange, "Provider should be detected as .orange")
        try assertEqual(result.clientCode, "84920194", "Orange subscriber code")
        try assertTrue(result.invoiceNumber?.contains("48291029") == true, "Orange invoice number")
        try assertNotNil(result.dueDate, "Due date")
        
        let dueComponents = calendar.dateComponents([.year, .month, .day], from: result.dueDate!)
        try assertEqual(dueComponents.year, 2026, "Due date year")
        try assertEqual(dueComponents.month, 11, "Due date month")
        try assertEqual(dueComponents.day, 20, "Due date day")
        
        try assertNotNil(result.totalAmount, "Total amount")
        try assertAlmostEqual(result.totalAmount!, 89.99, accuracy: 0.01, "Total amount should be 89.99")
    }
    
    // MARK: - 7. Vodafone Tests
    
    public static func testVodafoneInvoiceExtraction() throws {
        let parser = RomanianUtilityParser()
        let invoiceText = """
        VODAFONE ROMANIA S.A.
        Globalworth Tower, str. Barbu Văcărescu nr. 201, București
        FACTURA
        Factura seria VDF nr. 39281049
        Data emiterii: 02.11.2026
        Data scadenta: 22.11.2026
        Cod client: 29481029
        Total servicii Vodafone: 92,65
        TVA 19%: 17,60
        Total de plata: 110,25 LEI
        """
        
        let result = parser.parseUtilityBill(text: invoiceText)
        
        try assertEqual(result.provider, .vodafone, "Provider should be detected as .vodafone")
        try assertEqual(result.clientCode, "29481029", "Vodafone client code")
        try assertTrue(result.invoiceNumber?.contains("39281049") == true, "Vodafone invoice number")
        try assertNotNil(result.dueDate, "Due date")
        
        let dueComponents = calendar.dateComponents([.year, .month, .day], from: result.dueDate!)
        try assertEqual(dueComponents.year, 2026, "Due date year")
        try assertEqual(dueComponents.month, 11, "Due date month")
        try assertEqual(dueComponents.day, 22, "Due date day")
        
        try assertNotNil(result.totalAmount, "Total amount")
        try assertAlmostEqual(result.totalAmount!, 110.25, accuracy: 0.01, "Total amount should be 110.25")
    }
    
    // MARK: - 8. Romanian Currency and Number Formatting Tests
    
    public static func testRomanianNumberAndCurrencyFormatting() throws {
        let parser = RomanianUtilityParser()
        
        // Format A: European thousand dot and decimal comma "1.234,56 LEI"
        let textA = """
        Factura Electrica S.A.
        Scadenta: 15.12.2026
        Total de plata: 1.234,56 LEI
        """
        let resA = parser.parseUtilityBill(text: textA)
        try assertNotNil(resA.totalAmount, "Amount A should be parsed")
        try assertAlmostEqual(resA.totalAmount!, 1234.56, accuracy: 0.01, "1.234,56 LEI must normalize to 1234.56")
        try assertEqual(resA.currency, "RON", "Currency should be RON")
        
        // Format B: Decimal comma without thousands separator "123,45 RON"
        let textB = """
        Chitanta Salubrizare
        Data scadenta: 10.12.2026
        Total de plata: 123,45 RON
        """
        let resB = parser.parseUtilityBill(text: textB)
        try assertNotNil(resB.totalAmount, "Amount B should be parsed")
        try assertAlmostEqual(resB.totalAmount!, 123.45, accuracy: 0.01, "123,45 RON must normalize to 123.45")
        try assertEqual(resB.currency, "RON", "Currency should be RON")
        
        // Format C: Standard dot decimal "50.00 lei"
        let textC = """
        Abonament Parcare
        Termen de plata: 01.12.2026
        Total: 50.00 lei
        """
        let resC = parser.parseUtilityBill(text: textC)
        try assertNotNil(resC.totalAmount, "Amount C should be parsed")
        try assertAlmostEqual(resC.totalAmount!, 50.00, accuracy: 0.01, "50.00 lei must normalize to 50.00")
        try assertEqual(resC.currency, "RON", "Currency should be RON")
        
        // Format D: Large thousands amount "14.500,75 LEI"
        let textD = """
        Factura Lucrari Izolatie
        Scadenta: 30.12.2026
        Total de plata: 14.500,75 LEI
        """
        let resD = parser.parseUtilityBill(text: textD)
        try assertNotNil(resD.totalAmount, "Amount D should be parsed")
        try assertAlmostEqual(resD.totalAmount!, 14500.75, accuracy: 0.01, "14.500,75 LEI must normalize to 14500.75")
        
        // Format E: EUR currency detection "2.500,00 EUR"
        let textE = """
        Factura Chirie Spatiu
        Scadenta: 05.12.2026
        Total de plata: 2.500,00 EUR
        """
        let resE = parser.parseUtilityBill(text: textE)
        try assertNotNil(resE.totalAmount, "Amount E should be parsed")
        try assertAlmostEqual(resE.totalAmount!, 2500.00, accuracy: 0.01, "2500 EUR")
        try assertEqual(resE.currency, "EUR", "Currency should be detected as EUR")
    }
    
    // MARK: - 9. Written Romanian Months & Date Fallbacks
    
    public static func testWrittenRomanianMonthParsing() throws {
        let parser = RomanianUtilityParser()
        let text = """
        Furnizor General
        Data emiterii: 15 octombrie 2026
        Data scadenta: 15 noiembrie 2026
        Cod client: ABC-12345
        Total de plata: 210,00 LEI
        """
        let res = parser.parseUtilityBill(text: text)
        try assertNotNil(res.dueDate, "Due date with written month should parse")
        
        let comp = calendar.dateComponents([.year, .month, .day], from: res.dueDate!)
        try assertEqual(comp.year, 2026, "Year")
        try assertEqual(comp.month, 11, "Month noiembrie should be 11")
        try assertEqual(comp.day, 15, "Day 15")
    }
    
    // MARK: - 10. Roman Numeral Date Parsing Tests
    
    public static func testRomanNumeralDateParsing() throws {
        // Test A: 15.XI.2024 -> 15 November 2024
        let dateA = RomanianUtilityParser.parseDate("15.XI.2024")
        try assertNotNil(dateA, "15.XI.2024 should parse")
        let compA = calendar.dateComponents([.year, .month, .day], from: dateA!)
        try assertEqual(compA.year, 2024, "Year 2024")
        try assertEqual(compA.month, 11, "Month XI should be 11")
        try assertEqual(compA.day, 15, "Day 15")
        
        // Test B: 01.IV.2026 -> 1 April 2026
        let dateB = RomanianUtilityParser.parseDate("01.IV.2026")
        try assertNotNil(dateB, "01.IV.2026 should parse")
        let compB = calendar.dateComponents([.year, .month, .day], from: dateB!)
        try assertEqual(compB.year, 2026, "Year 2026")
        try assertEqual(compB.month, 4, "Month IV should be 4")
        try assertEqual(compB.day, 1, "Day 1")
        
        // Test C: 28/II/2025 -> 28 February 2025
        let dateC = RomanianUtilityParser.parseDate("28/II/2025")
        try assertNotNil(dateC, "28/II/2025 should parse")
        let compC = calendar.dateComponents([.year, .month, .day], from: dateC!)
        try assertEqual(compC.year, 2025, "Year 2025")
        try assertEqual(compC.month, 2, "Month II should be 2")
        try assertEqual(compC.day, 28, "Day 28")
        
        // Test D: 12-VIII-2026 -> 12 August 2026
        let dateD = RomanianUtilityParser.parseDate("12-VIII-2026")
        try assertNotNil(dateD, "12-VIII-2026 should parse")
        let compD = calendar.dateComponents([.year, .month, .day], from: dateD!)
        try assertEqual(compD.year, 2026, "Year 2026")
        try assertEqual(compD.month, 8, "Month VIII should be 8")
        try assertEqual(compD.day, 12, "Day 12")
        
        // Test E: Invoice with Roman numeral due date in text
        let invoiceText = """
        NOTĂ DE PLATĂ
        Furnizor Apă Ilfov S.A.
        Scadență: 10.XII.2026
        Total: 95,40 lei
        """
        let parsed = RomanianUtilityParser.shared.parseUtilityBill(text: invoiceText)
        try assertNotNil(parsed.dueDate, "Due date with Roman numeral XII should be extracted")
        let compE = calendar.dateComponents([.year, .month, .day], from: parsed.dueDate!)
        try assertEqual(compE.year, 2026, "Year 2026")
        try assertEqual(compE.month, 12, "Month XII should be 12")
        try assertEqual(compE.day, 10, "Day 10")
    }
    
    // MARK: - 11. Romanian Comma Decimal Parsing with Currency and Non-Breaking Spaces
    
    public static func testRomanianCommaDecimalParsingWithCurrencyAndSpaces() throws {
        // "1.450,50 lei" -> 1450.50
        let valA = RomanianUtilityParser.normalizeRomanianAmount("1.450,50 lei")
        try assertNotNil(valA, "1.450,50 lei")
        try assertAlmostEqual(valA!, 1450.50, accuracy: 0.01, "1.450,50 lei -> 1450.50")
        
        // "1 450,50 RON" -> 1450.50
        let valB = RomanianUtilityParser.normalizeRomanianAmount("1 450,50 RON")
        try assertNotNil(valB, "1 450,50 RON")
        try assertAlmostEqual(valB!, 1450.50, accuracy: 0.01, "1 450,50 RON -> 1450.50")
        
        // Non-breaking space \u{00A0}
        let valC = RomanianUtilityParser.normalizeRomanianAmount("1\u{00A0}450,50 lei")
        try assertNotNil(valC, "1\\u{00A0}450,50 lei")
        try assertAlmostEqual(valC!, 1450.50, accuracy: 0.01, "Non-breaking space amount")
        
        // Thin non-breaking space \u{202F}
        let valD = RomanianUtilityParser.normalizeRomanianAmount("2\u{202F}500,00 EUR")
        try assertNotNil(valD, "2\\u{202F}500,00 EUR")
        try assertAlmostEqual(valD!, 2500.00, accuracy: 0.01, "Thin space EUR amount")
        
        // Simple decimal comma without thousands "123,45"
        let valE = RomanianUtilityParser.normalizeRomanianAmount("123,45")
        try assertNotNil(valE, "123,45")
        try assertAlmostEqual(valE!, 123.45, accuracy: 0.01, "123,45")
        
        // Standard dot decimal "50.00 lei"
        let valF = RomanianUtilityParser.normalizeRomanianAmount("50.00 lei")
        try assertNotNil(valF, "50.00 lei")
        try assertAlmostEqual(valF!, 50.00, accuracy: 0.01, "50.00 lei")
    }
    
    // MARK: - 12. Romanian Diacritic Normalization Tests
    
    public static func testRomanianDiacriticNormalization() throws {
        // Cedilla to comma-below replacement
        let legacyText = "şcoală şi ţară de la Ştefan la Ţiriac"
        let normalized = RomanianUtilityParser.normalizeDiacritics(legacyText)
        try assertEqual(normalized, "școală și țară de la Ștefan la Țiriac", "Cedillas replaced by standard comma-below")
        
        // Diacritic stripping for insensitive search
        let stripped = RomanianUtilityParser.stripDiacritics("școală, țară, pâine, mâncare, împărat")
        try assertEqual(stripped, "scoala, tara, paine, mancare, imparat", "Diacritics stripped for indexing")
    }
    
    // MARK: - 13. POD, CLC, Water Client Code & Consumption Delta Extraction
    
    public static func testPodClcWaterAndConsumptionDeltaExtraction() throws {
        let parser = RomanianUtilityParser()
        let invoiceText = """
        ENGIE ROMANIA S.A.
        FACTURĂ DE GAZE NATURALE
        Cod loc consum (CLC): DEG0123456
        Punct de delimitare POD: RO001E987654321
        Cod client apa: 849201-9
        Index nou: 4520
        Index vechi: 4210
        Total de plata: 310,00 LEI
        """
        
        let result = parser.parseUtilityBill(text: invoiceText)
        
        try assertEqual(result.clcCode, "DEG0123456", "CLC natural gas point of consumption")
        try assertEqual(result.podCode, "RO001E987654321", "POD electricity/utility point of delivery")
        try assertEqual(result.waterClientCode, "849201-9", "Water client code")
        try assertEqual(result.indexReading, 4520.0, "Current index reading")
        try assertEqual(result.previousIndexReading, 4210.0, "Previous index reading")
        try assertNotNil(result.consumptionDelta, "Consumption delta should be computed")
        try assertAlmostEqual(result.consumptionDelta!, 310.0, accuracy: 0.1, "Consumption delta: 4520 - 4210 = 310")
    }
    
    // MARK: - 14. Thousands Separators, Euro Symbol & Water Header Guards
    
    public static func testThousandsSeparatorsAndEuroSymbol() throws {
        // Space thousands
        let billSpace = RomanianUtilityParser.shared.parseUtilityBill(text: "ENGIE ROMANIA S.A.\nTotal de plată: 1 450,50 lei\nScadență: 20.12.2026")
        try assertNotNil(billSpace.totalAmount, "Total amount with space thousands")
        try assertAlmostEqual(billSpace.totalAmount!, 1450.50, accuracy: 0.01, "Amount: 1450.50")
        try assertEqual(billSpace.currency, "RON", "Currency: RON")
        
        // NBSP thousands
        let billNbsp = RomanianUtilityParser.shared.parseUtilityBill(text: "DIGI ROMANIA\nTotal de plată: 1\u{00A0}450,50 lei\nScadență: 20.12.2026")
        try assertNotNil(billNbsp.totalAmount, "Total amount with NBSP")
        try assertAlmostEqual(billNbsp.totalAmount!, 1450.50, accuracy: 0.01, "Amount: 1450.50")
        
        // Thousands separator without decimals
        let val1450 = RomanianUtilityParser.normalizeRomanianAmount("1.450 lei")
        try assertNotNil(val1450, "1.450 lei should parse")
        try assertAlmostEqual(val1450!, 1450.0, accuracy: 0.01, "1.450 lei -> 1450.0")
        
        let val14500 = RomanianUtilityParser.normalizeRomanianAmount("14.500 lei")
        try assertNotNil(val14500, "14.500 lei should parse")
        try assertAlmostEqual(val14500!, 14500.0, accuracy: 0.01, "14.500 lei -> 14500.0")
        
        // Euro symbol
        let billEur = RomanianUtilityParser.shared.parseUtilityBill(text: "FACTURĂ SERVICII\nTotal de plată: 14.500,00 €\nScadență: 20.12.2026")
        try assertNotNil(billEur.totalAmount, "Euro bill amount")
        try assertAlmostEqual(billEur.totalAmount!, 14500.00, accuracy: 0.01, "Euro amount 14500.00")
        try assertEqual(billEur.currency, "EUR", "Currency EUR")
    }
    
    public static func testWaterClientCodeApaNovaHeaderGuard() throws {
        let parser = RomanianUtilityParser.shared
        let text = "APA NOVA BUCURESTI\nApa Nova cod: 1234567\nTotal: 45 lei"
        let code = parser.extractWaterClientCode(in: text)
        try assertEqual(code, "1234567", "Water client code should extract 1234567, not company name BUCURESTI")
    }
    
    // MARK: - Runner
    
    public static func runAll() -> TestSuiteResult {
        let startTime = Date()
        var passed = 0
        var failed = 0
        var failures: [TestFailure] = []
        
        let tests: [(String, () throws -> Void)] = [
            ("testDigiInvoiceExtraction", testDigiInvoiceExtraction),
            ("testPpcEnelInvoiceExtraction", testPpcEnelInvoiceExtraction),
            ("testHidroelectricaInvoiceExtraction", testHidroelectricaInvoiceExtraction),
            ("testEonInvoiceExtraction", testEonInvoiceExtraction),
            ("testEngieInvoiceExtraction", testEngieInvoiceExtraction),
            ("testOrangeInvoiceExtraction", testOrangeInvoiceExtraction),
            ("testVodafoneInvoiceExtraction", testVodafoneInvoiceExtraction),
            ("testRomanianNumberAndCurrencyFormatting", testRomanianNumberAndCurrencyFormatting),
            ("testWrittenRomanianMonthParsing", testWrittenRomanianMonthParsing),
            ("testRomanNumeralDateParsing", testRomanNumeralDateParsing),
            ("testRomanianCommaDecimalParsingWithCurrencyAndSpaces", testRomanianCommaDecimalParsingWithCurrencyAndSpaces),
            ("testRomanianDiacriticNormalization", testRomanianDiacriticNormalization),
            ("testPodClcWaterAndConsumptionDeltaExtraction", testPodClcWaterAndConsumptionDeltaExtraction),
            ("testThousandsSeparatorsAndEuroSymbol", testThousandsSeparatorsAndEuroSymbol),
            ("testWaterClientCodeApaNovaHeaderGuard", testWaterClientCodeApaNovaHeaderGuard)
        ]
        
        for (name, test) in tests {
            do {
                try test()
                passed += 1
            } catch let error as TestAssertionError {
                failed += 1
                failures.append(TestFailure(testName: name, message: error.message, file: error.file, line: error.line))
            } catch {
                failed += 1
                failures.append(TestFailure(testName: name, message: "\(error)", file: #file, line: #line))
            }
        }
        
        let duration = Date().timeIntervalSince(startTime)
        return TestSuiteResult(
            suiteName: "RomanianUtilityParserTests",
            passed: passed,
            failed: failed,
            failures: failures,
            duration: duration
        )
    }
}
