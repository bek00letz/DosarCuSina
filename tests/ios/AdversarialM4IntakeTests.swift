import Foundation
import SwiftData

/// Comprehensive Adversarial Stress Test Suite for Milestone M4:
/// - RomanianUtilityParser (Currency, Comma Decimals, Thousands Separators, Roman Dates, Diacritics, Identifiers)
/// - MultiSourceInputView Auto-Matching Engine (VIN matching, Plate formatting, False Positive Collisions, Multi-Identifier Conflicts)
public final class AdversarialM4IntakeTests: Sendable {
    
    // MARK: - 1. Currency & Thousands Separators Stress Tests
    
    public static func testThousandsSeparatorsWithAndWithoutDecimals() throws {
        // Standard comma decimal with thousand period: "1.450,50 lei"
        let val1 = RomanianUtilityParser.normalizeRomanianAmount("1.450,50 lei")
        try assertNotNil(val1, "1.450,50 lei should parse")
        try assertAlmostEqual(val1!, 1450.50, accuracy: 0.01, "1.450,50 lei -> 1450.50")
        
        // Comma decimal without thousands: "1450,50 RON"
        let val2 = RomanianUtilityParser.normalizeRomanianAmount("1450,50 RON")
        try assertNotNil(val2, "1450,50 RON should parse")
        try assertAlmostEqual(val2!, 1450.50, accuracy: 0.01, "1450,50 RON -> 1450.50")
        
        // Space as thousands separator: "1 450,50"
        let val3 = RomanianUtilityParser.normalizeRomanianAmount("1 450,50")
        try assertNotNil(val3, "1 450,50 should parse")
        try assertAlmostEqual(val3!, 1450.50, accuracy: 0.01, "1 450,50 -> 1450.50")
        
        // Non-breaking space \u{00A0}
        let val4 = RomanianUtilityParser.normalizeRomanianAmount("1\u{00A0}450,50 lei")
        try assertNotNil(val4, "1\\u{00A0}450,50 lei should parse")
        try assertAlmostEqual(val4!, 1450.50, accuracy: 0.01, "Non-breaking space amount")
        
        // Thin non-breaking space \u{202F} with Euro
        let val5 = RomanianUtilityParser.normalizeRomanianAmount("14\u{202F}500,00 €")
        try assertNotNil(val5, "14\\u{202F}500,00 € should parse")
        try assertAlmostEqual(val5!, 14500.00, accuracy: 0.01, "Thin space EUR amount")
        
        // Multi-thousand group: "1.250.450,75 lei"
        let val6 = RomanianUtilityParser.normalizeRomanianAmount("1.250.450,75 lei")
        try assertNotNil(val6, "1.250.450,75 lei should parse")
        try assertAlmostEqual(val6!, 1250450.75, accuracy: 0.01, "Multi-thousand parsing")
        
        // Thousands separator without decimals: "1.450 lei"
        let val7 = RomanianUtilityParser.normalizeRomanianAmount("1.450 lei")
        try assertNotNil(val7, "1.450 lei should parse")
        try assertAlmostEqual(val7!, 1450.0, accuracy: 0.01, "1.450 lei -> 1450.0")
        
        // Thousands separator without decimals: "14.500 lei"
        let val8 = RomanianUtilityParser.normalizeRomanianAmount("14.500 lei")
        try assertNotNil(val8, "14.500 lei should parse")
        try assertAlmostEqual(val8!, 14500.0, accuracy: 0.01, "14.500 lei -> 14500.0")
    }
    
    public static func testFullBillContextAmountExtraction() throws {
        let parser = RomanianUtilityParser.shared
        
        // 1. Bill with period thousands and comma decimal
        let bill1 = parser.parseUtilityBill(text: "ENGIE ROMANIA S.A.\nTotal de plată: 1.450,50 lei\nScadență: 20.12.2026")
        try assertNotNil(bill1.totalAmount, "Total amount should be extracted for 1.450,50 lei")
        try assertAlmostEqual(bill1.totalAmount!, 1450.50, accuracy: 0.01, "Amount: 1450.50")
        try assertEqual(bill1.currency, "RON", "Currency should be RON")
        
        // 2. Bill with space thousands and comma decimal: "Total de plată: 1 450,50 lei"
        let bill2 = parser.parseUtilityBill(text: "ENGIE ROMANIA S.A.\nTotal de plată: 1 450,50 lei\nScadență: 20.12.2026")
        try assertNotNil(bill2.totalAmount, "Total amount should be extracted for 1 450,50 lei")
        try assertAlmostEqual(bill2.totalAmount!, 1450.50, accuracy: 0.01, "Amount: 1450.50")
        try assertEqual(bill2.currency, "RON", "Currency should be RON")
        
        // 3. Bill with non-breaking space: "Total de plată: 1\u{00A0}450,50 lei"
        let bill3 = parser.parseUtilityBill(text: "DIGI ROMANIA\nTotal de plată: 1\u{00A0}450,50 lei\nScadență: 20.12.2026")
        try assertNotNil(bill3.totalAmount, "Total amount should be extracted for 1\\u{00A0}450,50 lei")
        try assertAlmostEqual(bill3.totalAmount!, 1450.50, accuracy: 0.01, "Amount: 1450.50")
        try assertEqual(bill3.currency, "RON", "Currency should be RON")
        
        // 4. Bill with EUR currency: "Total de plată: 14.500,00 €"
        let bill4 = parser.parseUtilityBill(text: "FACTURĂ SERVICII\nTotal de plată: 14.500,00 €\nScadență: 20.12.2026")
        try assertNotNil(bill4.totalAmount, "Euro amount extraction")
        try assertAlmostEqual(bill4.totalAmount!, 14500.00, accuracy: 0.01, "Euro amount value")
        try assertEqual(bill4.currency, "EUR", "Currency should be EUR")
    }
    
    // MARK: - 2. Roman Numeral Date Variants Stress Tests
    
    public static func testRomanNumeralDateVariants() throws {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(secondsFromGMT: 0)!
        
        func checkDate(_ str: String, expectedY: Int, expectedM: Int, expectedD: Int) throws {
            guard let d = RomanianUtilityParser.parseDate(str) else {
                throw TestAssertionError(message: "Failed to parse date '\(str)'", file: #file, line: #line)
            }
            let comps = cal.dateComponents([.year, .month, .day], from: d)
            try assertEqual(comps.year, expectedY, "Year for '\(str)'")
            try assertEqual(comps.month, expectedM, "Month for '\(str)'")
            try assertEqual(comps.day, expectedD, "Day for '\(str)'")
        }
        
        // 15.XI.2024
        try checkDate("15.XI.2024", expectedY: 2024, expectedM: 11, expectedD: 15)
        
        // 01.IV.2026
        try checkDate("01.IV.2026", expectedY: 2026, expectedM: 4, expectedD: 1)
        
        // 28/II/2025
        try checkDate("28/II/2025", expectedY: 2025, expectedM: 2, expectedD: 28)
        
        // 12-VIII-2026
        try checkDate("12-VIII-2026", expectedY: 2026, expectedM: 8, expectedD: 12)
        
        // Invalid Roman numerals: must return nil
        try assertTrue(RomanianUtilityParser.parseDate("15.XXXX.2024") == nil, "15.XXXX.2024 should be rejected")
        try assertTrue(RomanianUtilityParser.parseDate("15.IIII.2024") == nil, "15.IIII.2024 should be rejected")
        try assertTrue(RomanianUtilityParser.parseDate("15.VX.2024") == nil, "15.VX.2024 should be rejected")
        try assertTrue(RomanianUtilityParser.parseDate("15.XIII.2024") == nil, "15.XIII.2024 should be rejected")
    }
    
    public static func testRomanDatesInsideBillExtraction() throws {
        let parser = RomanianUtilityParser.shared
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(secondsFromGMT: 0)!
        
        let billText = """
        S.P.E.E.H. HIDROELECTRICA S.A.
        Factura seria HID nr. 998877
        Data emiterii: 15.XI.2024
        Data scadenta: 01.IV.2026
        Total de achitat: 180,00 LEI
        """
        
        let result = parser.parseUtilityBill(text: billText)
        try assertNotNil(result.issueDate, "Issue date 15.XI.2024 should be extracted")
        try assertNotNil(result.dueDate, "Due date 01.IV.2026 should be extracted")
        
        let issueComps = cal.dateComponents([.year, .month, .day], from: result.issueDate!)
        try assertEqual(issueComps.year, 2024, "Issue year 2024")
        try assertEqual(issueComps.month, 11, "Issue month 11")
        try assertEqual(issueComps.day, 15, "Issue day 15")
        
        let dueComps = cal.dateComponents([.year, .month, .day], from: result.dueDate!)
        try assertEqual(dueComps.year, 2026, "Due year 2026")
        try assertEqual(dueComps.month, 4, "Due month 4")
        try assertEqual(dueComps.day, 1, "Due day 1")
    }
    
    // MARK: - 3. Diacritics Normalization & Legacy Cedilla Stress Tests
    
    public static func testDiacriticsNormalizationAndMixing() throws {
        // Mixed cedillas and commas: "leşi", "Bucureşti", "plăcuțe", "asigurare"
        let sample = "Chitanţă emisă la Bucureşti şi leşi pentru plăcuțe şi asigurare auto"
        let normalized = RomanianUtilityParser.normalizeDiacritics(sample)
        
        // Assert no cedillas remain
        try assertFalse(normalized.contains("\u{015F}"), "No small cedilla s")
        try assertFalse(normalized.contains("\u{015E}"), "No capital cedilla S")
        try assertFalse(normalized.contains("\u{0163}"), "No small cedilla t")
        try assertFalse(normalized.contains("\u{0162}"), "No capital cedilla T")
        
        // Assert proper standard comma-below diacritics are present
        try assertTrue(normalized.contains("București"), "București with comma-below")
        try assertTrue(normalized.contains("leși"), "leși with comma-below")
        try assertTrue(normalized.contains("plăcuțe"), "plăcuțe preserved")
        
        // Stripped diacritics for indexing/search
        let stripped = RomanianUtilityParser.stripDiacritics(normalized)
        try assertTrue(stripped.contains("Chitanta"), "Chitanta stripped")
        try assertTrue(stripped.contains("Bucuresti"), "Bucuresti stripped")
        try assertTrue(stripped.contains("lesi"), "lesi stripped")
        try assertTrue(stripped.contains("placute"), "placute stripped")
        try assertTrue(stripped.contains("asigurare"), "asigurare untouched")
    }
    
    // MARK: - 4. POD, CLC & Water Identifiers with Noise Stress Tests
    
    public static func testPodClcWaterExtractionWithNoise() throws {
        let parser = RomanianUtilityParser.shared
        
        // POD with parentheses: "Punct de delimitare (POD): RO001E123456789"
        let text1 = "Punct de delimitare (POD): RO001E123456789"
        let pod1 = parser.extractPodCode(in: text1)
        try assertEqual(pod1, "RO001E123456789", "POD with parentheses")
        
        // CLC with spaces and prefix noise
        let text2 = "FACTURĂ GAZE\nCod loc consum (CLC): DEG0123456\nIndex: 120"
        let clc1 = parser.extractClcCode(in: text2)
        try assertEqual(clc1, "DEG0123456", "CLC code DEG0123456")
        
        // Water client codes
        let text3 = "APA NOVA BUCURESTI\nApa Nova cod: 1234567\nTotal: 45 lei"
        let water1 = parser.extractWaterClientCode(in: text3)
        try assertEqual(water1, "1234567", "Water client code Apa Nova")
        
        let text4 = "COMPANIA DE APA\nApa-Canal cod client: AC-98765\nTotal: 85 lei"
        let water2 = parser.extractWaterClientCode(in: text4)
        try assertEqual(water2, "AC-98765", "Water client code Apa-Canal")
    }
    
    // MARK: - 5. Auto-Matching Engine Stress Tests
    
    public static func testAutoMatchLicensePlateVariantsAndCollisions() throws {
        let car = Asset(name: "Dacia Logan", category: .vehicle)
        car.licensePlate = "B-123-ABC"
        
        let assets = [car]
        
        // Hyphens: B-123-ABC
        let mHyphen = RomanianUtilityParser.findBestAssetMatch(for: "Polita RCA pentru B-123-ABC", in: assets)
        try assertNotNil(mHyphen?.asset, "Hyphenated plate match")
        
        // Spaces: B 123 ABC
        let mSpaces = RomanianUtilityParser.findBestAssetMatch(for: "Polita RCA pentru B 123 ABC", in: assets)
        try assertNotNil(mSpaces?.asset, "Spaced plate match")
        
        // Compact: B123ABC
        let mCompact = RomanianUtilityParser.findBestAssetMatch(for: "Polita RCA pentru B123ABC", in: assets)
        try assertNotNil(mCompact?.asset, "Compact plate match")
        
        // Lowercase: b 123 abc
        let mLower = RomanianUtilityParser.findBestAssetMatch(for: "Polita RCA pentru b 123 abc", in: assets)
        try assertNotNil(mLower?.asset, "Lowercase plate match")
        
        // Substring collision risk check:
        // Must NOT match "SUB123ABCD" or "B123ABCD" or "SUB123ABC"
        let collisionMatch = RomanianUtilityParser.findBestAssetMatch(for: "Cod promotie SUB123ABCD magazin", in: assets)
        try assertTrue(collisionMatch == nil, "SUB123ABCD must not trigger collision for B-123-ABC")
        
        let collisionMatch2 = RomanianUtilityParser.findBestAssetMatch(for: "Cod promotie B123ABCD magazin", in: assets)
        try assertTrue(collisionMatch2 == nil, "B123ABCD must not trigger collision for B-123-ABC")
        
        let collisionMatch3 = RomanianUtilityParser.findBestAssetMatch(for: "Cod promotie SUB123ABC magazin", in: assets)
        try assertTrue(collisionMatch3 == nil, "SUB123ABC must not trigger collision for B-123-ABC")
    }
    
    public static func testAutoMatchVINFormatsAndPartials() throws {
        let car = Asset(name: "VW Passat", category: .vehicle)
        car.vin = "WVWZZZ3CZWE123456"
        
        let assets = [car]
        
        // Exact VIN: WVWZZZ3CZWE123456
        let resExact = RomanianUtilityParser.findBestAssetMatch(for: "Deviz service auto VIN: WVWZZZ3CZWE123456", in: assets)
        try assertNotNil(resExact?.asset, "Exact 17-char VIN should match")
        
        // Formatted VIN with hyphens: WVW-ZZZ-3CZ-WE-123456
        let resHyphens = RomanianUtilityParser.findBestAssetMatch(for: "Deviz service auto VIN: WVW-ZZZ-3CZ-WE-123456", in: assets)
        try assertNotNil(resHyphens?.asset, "VIN with hyphens should match")
        
        // Formatted VIN with spaces: WVW ZZZ 3CZ WE 123456
        let resSpaces = RomanianUtilityParser.findBestAssetMatch(for: "Deviz service auto VIN: WVW ZZZ 3CZ WE 123456", in: assets)
        try assertNotNil(resSpaces?.asset, "VIN with spaces should match")
        
        // Partial VIN in document: WE123456
        let resPartial = RomanianUtilityParser.findBestAssetMatch(for: "Deviz service auto Serie sasiu: WE123456", in: assets)
        try assertNotNil(resPartial?.asset, "Partial VIN (last 8 chars) should match")
    }
    
    public static func testAutoMatchConflictingIdentifiers() throws {
        let personAsset = Asset(name: "Dosar Medical Copil", category: .health)
        personAsset.personName = "Popescu Andrei"
        
        let carAsset = Asset(name: "BMW 320d", category: .vehicle)
        carAsset.vin = "WBA3A5C50DF123456"
        carAsset.licensePlate = "CJ-01-XYZ"
        
        // Document has both: person name and vehicle VIN
        let text = """
        AUTO BAVARIA SERVICE CLUJ
        Nume client: Popescu Andrei
        Serie sasiu VIN: WBA3A5C50DF123456
        Deviz reparatii
        """
        
        let match1 = RomanianUtilityParser.findBestAssetMatch(for: text, in: [personAsset, carAsset])
        try assertNotNil(match1, "Match 1 should not be nil")
        try assertEqual(match1?.asset.name, "BMW 320d", "Conflicting document [personAsset first] should resolve to BMW 320d by VIN entropy (100 > 60)")
        try assertEqual(match1?.score, 100, "VIN match score should be 100")
        
        let match2 = RomanianUtilityParser.findBestAssetMatch(for: text, in: [carAsset, personAsset])
        try assertNotNil(match2, "Match 2 should not be nil")
        try assertEqual(match2?.asset.name, "BMW 320d", "Conflicting document [carAsset first] should resolve to BMW 320d by VIN entropy (100 > 60)")
        try assertEqual(match2?.score, 100, "VIN match score should be 100")
    }
    
    // MARK: - Runner
    
    public static func runAll() -> TestSuiteResult {
        let startTime = Date()
        var passed = 0
        var failed = 0
        var failures: [TestFailure] = []
        
        let tests: [(String, () throws -> Void)] = [
            ("testThousandsSeparatorsWithAndWithoutDecimals", testThousandsSeparatorsWithAndWithoutDecimals),
            ("testFullBillContextAmountExtraction", testFullBillContextAmountExtraction),
            ("testRomanNumeralDateVariants", testRomanNumeralDateVariants),
            ("testRomanDatesInsideBillExtraction", testRomanDatesInsideBillExtraction),
            ("testDiacriticsNormalizationAndMixing", testDiacriticsNormalizationAndMixing),
            ("testPodClcWaterExtractionWithNoise", testPodClcWaterExtractionWithNoise),
            ("testAutoMatchLicensePlateVariantsAndCollisions", testAutoMatchLicensePlateVariantsAndCollisions),
            ("testAutoMatchVINFormatsAndPartials", testAutoMatchVINFormatsAndPartials),
            ("testAutoMatchConflictingIdentifiers", testAutoMatchConflictingIdentifiers)
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
            suiteName: "AdversarialM4IntakeTests",
            passed: passed,
            failed: failed,
            failures: failures,
            duration: duration
        )
    }
}
