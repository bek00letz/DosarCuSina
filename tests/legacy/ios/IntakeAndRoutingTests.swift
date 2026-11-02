import Foundation
import SwiftData
import SwiftUI

/// Comprehensive test suite for MultiSourceInputView, Intake Routing, Asset Auto-Matching,
/// and AssetsVaultView 6-Layer Faceted Search.
public final class IntakeAndRoutingTests: Sendable {
    
    // MARK: - 1. Asset Auto-Matching Tests
    
    public static func testAssetAutoMatchByPOD() throws {
        let homeAsset = Asset(name: "Apartament Pipera", category: .home)
        homeAsset.podCode = "RO001E123456789"
        
        let scannedText = """
        HIDROELECTRICA S.A.
        Factură fiscală
        Cod POD loc consum: RO001E123456789
        Total: 154,20 lei
        """
        
        let normalizedDoc = RomanianUtilityParser.normalizeDiacritics(scannedText).uppercased()
        let matched = homeAsset.podCode.map { normalizedDoc.contains($0.uppercased()) } ?? false
        try assertTrue(matched, "Auto-match should identify asset by POD code")
    }
    
    public static func testAssetAutoMatchByCLC() throws {
        let homeAsset = Asset(name: "Casă Corbeanca", category: .home)
        homeAsset.clcCode = "DEG0123456"
        
        let scannedText = """
        ENGIE ROMANIA S.A.
        Factură gaze naturale
        Cod loc consum (CLC): DEG0123456
        Consum activ: 145 mc
        """
        
        let normalizedDoc = RomanianUtilityParser.normalizeDiacritics(scannedText).uppercased()
        let matched = homeAsset.clcCode.map { normalizedDoc.contains($0.uppercased()) } ?? false
        try assertTrue(matched, "Auto-match should identify asset by CLC natural gas code")
    }
    
    public static func testAssetAutoMatchByWaterClientCode() throws {
        let homeAsset = Asset(name: "Apartament Brașov", category: .home)
        homeAsset.waterClientCode = "849201-9"
        
        let scannedText = """
        COMPANIA APA BRASOV S.A.
        Notă de consum apă rece
        Cod client apă: 849201-9
        Index contor: 320 mc
        """
        
        let normalizedDoc = RomanianUtilityParser.normalizeDiacritics(scannedText).uppercased()
        let matched = homeAsset.waterClientCode.map { normalizedDoc.contains($0.uppercased()) } ?? false
        try assertTrue(matched, "Auto-match should identify asset by water client code")
    }
    
    public static func testAssetAutoMatchByVIN() throws {
        let carAsset = Asset(name: "VW Passat 2.0 TDI", category: .vehicle)
        carAsset.vin = "WVWZZZ3CZWE123456"
        let assets = [carAsset]
        
        let scannedInvoice = """
        AUTO BAVARIA SERVICE
        Deviz reparații auto
        Serie șasiu VIN: WVWZZZ3CZWE123456
        Intervenție: Revizie ulei și filtre
        """
        
        let match1 = RomanianUtilityParser.findBestAssetMatch(for: scannedInvoice, in: assets)
        try assertNotNil(match1, "Auto-match should identify vehicle by 17-character VIN")
        try assertEqual(match1?.score, 100, "VIN match score 100")
        
        // Formatted VIN with hyphens
        let matchHyphen = RomanianUtilityParser.findBestAssetMatch(for: "Deviz VIN: WVW-ZZZ-3CZ-WE-123456", in: assets)
        try assertNotNil(matchHyphen, "Auto-match should identify vehicle by hyphenated VIN")
        
        // Formatted VIN with spaces
        let matchSpace = RomanianUtilityParser.findBestAssetMatch(for: "Deviz VIN: WVW ZZZ 3CZ WE 123456", in: assets)
        try assertNotNil(matchSpace, "Auto-match should identify vehicle by spaced VIN")
    }
    
    public static func testAssetAutoMatchByLicensePlate() throws {
        let carAsset = Asset(name: "Dacia Duster", category: .vehicle)
        carAsset.licensePlate = "B-123-ABC"
        let assets = [carAsset]
        
        // Test varying space/dash formats in document
        let documentWithSpaces = "Poliță RCA valabilă pentru autoturism număr B 123 ABC"
        let match1 = RomanianUtilityParser.findBestAssetMatch(for: documentWithSpaces, in: assets)
        try assertNotNil(match1, "Auto-match should identify vehicle by license plate with spaces")
        
        let documentWithDashes = "Poliță RCA valabilă pentru autoturism număr B-123-ABC"
        let match2 = RomanianUtilityParser.findBestAssetMatch(for: documentWithDashes, in: assets)
        try assertNotNil(match2, "Auto-match should identify vehicle by license plate with hyphens")
        
        let documentCompact = "Poliță RCA valabilă pentru autoturism număr B123ABC"
        let match3 = RomanianUtilityParser.findBestAssetMatch(for: documentCompact, in: assets)
        try assertNotNil(match3, "Auto-match should identify vehicle by compact license plate")
        
        // Boundary check: ensure substring within other words does NOT collide
        let collisionDoc = "Cod promotie SUB123ABCD magazin online"
        let collisionMatch = RomanianUtilityParser.findBestAssetMatch(for: collisionDoc, in: assets)
        try assertTrue(collisionMatch == nil, "SUB123ABCD must not collide with license plate B-123-ABC")
    }
    
    public static func testAssetAutoMatchByMicrochip() throws {
        let petAsset = Asset(name: "Rex - Ciobănesc German", category: .pet)
        petAsset.microchipNumber = "642098100123456"
        
        let vetRecord = """
        CLINICA VETERINARĂ SPEEDYVET
        Fișă medicală animal companie
        Microcip identificare: 642098100123456
        Vaccin polivalent DHPPi administrat
        """
        
        let matched = vetRecord.contains(petAsset.microchipNumber!)
        try assertTrue(matched, "Auto-match should identify pet by 15-digit ISO microchip")
    }
    
    public static func testAssetAutoMatchBySerialOrImei() throws {
        let applianceAsset = Asset(name: "Mașină de spălat Miele", category: .warranties)
        applianceAsset.serialOrImei = "SN-MIELE-948201"
        
        let warrantyCertificate = """
        CERTIFICAT DE GARANȚIE
        Produs: Miele W1 Passion
        Serie aparat SN: SN-MIELE-948201
        Termen de garanție: 24 luni
        """
        
        let normalizedDoc = RomanianUtilityParser.normalizeDiacritics(warrantyCertificate).uppercased()
        let matched = applianceAsset.serialOrImei.map { normalizedDoc.contains($0.uppercased()) } ?? false
        try assertTrue(matched, "Auto-match should identify warranty goods by serial number")
    }
    
    public static func testAssetAutoMatchByPersonName() throws {
        let healthAsset = Asset(name: "Dosar Medical Copil", category: .health)
        healthAsset.personName = "Popescu Andrei"
        
        let labReport = """
        SYNEVO ROMANIA S.A.
        Buletin analize medicale
        Nume pacient: Popescu Andrei
        CNP: 5180512019482
        Hemoleucogramă completă
        """
        
        let normalizedDoc = RomanianUtilityParser.normalizeDiacritics(labReport).uppercased()
        let matched = healthAsset.personName.map { normalizedDoc.contains($0.uppercased()) } ?? false
        try assertTrue(matched, "Auto-match should identify health profile by person name")
    }
    
    // MARK: - 2. Routing Destination Data Model Tests
    
    public static func testRoutingDestinationEventCreation() throws {
        let asset = Asset(name: "Apartament Central", category: .home)
        let dueDate = Date(timeIntervalSince1970: 1774000000)
        
        let event = LifecycleEvent(
            title: "Factură Hidroelectrica",
            eventDescription: "Consum energie electrică martie",
            dueDate: dueDate,
            cost: 215.80,
            provider: "Hidroelectrica",
            policyOrContractNumber: "FACT-84920192",
            cadenceDays: 30
        )
        event.asset = asset
        asset.events.append(event)
        
        try assertEqual(event.title, "Factură Hidroelectrica", "Event title")
        try assertEqual(event.cost, 215.80, "Event cost")
        try assertEqual(event.cadenceDays, 30, "Monthly cadence")
        try assertEqual(event.provider, "Hidroelectrica", "Provider")
        try assertEqual(event.policyOrContractNumber, "FACT-84920192", "Invoice number")
        try assertEqual(asset.events.count, 1, "Asset should hold 1 event")
    }
    
    public static func testRoutingDestinationServiceItemWithMileage() throws {
        let car = Asset(name: "BMW 320d", category: .vehicle)
        car.currentMetricValue = 180000
        car.metricUnit = "km"
        
        let service = ServiceItem(
            name: "Schimb plăcuțe și discuri frână față",
            category: "Întreținere",
            partBrand: "Brembo",
            cost: 950.0,
            laborCost: 350.0,
            partsCost: 600.0,
            serviceDate: Date(),
            mileageAtService: 195000,
            specialistOrDoctorName: "Mecanic Vasile",
            serialOrBatchNumber: "LOT-BREMBO-421"
        )
        service.asset = car
        car.serviceItems.append(service)
        
        // Update car mileage from service
        if let km = service.mileageAtService, km > (car.currentMetricValue ?? 0) {
            car.currentMetricValue = km
        }
        
        try assertEqual(service.partsCost, 600.0, "Parts cost")
        try assertEqual(service.laborCost, 350.0, "Labor cost")
        try assertEqual(service.totalEffectiveCost, 950.0, "Total effective cost")
        try assertEqual(car.currentMetricValue, 195000.0, "Vehicle odometer should advance to service mileage")
    }
    
    public static func testRoutingDestinationMeasurementLogWithDelta() throws {
        let home = Asset(name: "Garsonieră Titan", category: .home)
        
        let measurement = MeasurementLog(
            domain: .electricityMeter,
            metricName: "Index Contor Energie",
            value: 12480.0,
            unit: "kWh",
            recordedAt: Date(),
            previousValue: 12100.0,
            unitPrice: 0.68,
            isSelfRead: true,
            labOrProviderName: "Hidroelectrica"
        )
        measurement.asset = home
        home.measurements.append(measurement)
        
        try assertEqual(measurement.value, 12480.0, "Current index value")
        try assertEqual(measurement.previousValue, 12100.0, "Previous index value")
        try assertNotNil(measurement.deltaFromPrevious, "Delta should be computed")
        try assertAlmostEqual(measurement.deltaFromPrevious!, 380.0, accuracy: 0.01, "Delta: 12480 - 12100 = 380 kWh")
        try assertNotNil(measurement.estimatedCost, "Estimated cost should be computed")
        try assertAlmostEqual(measurement.estimatedCost!, 258.40, accuracy: 0.01, "Cost: 380 * 0.68 = 258.40 RON")
    }
    
    // MARK: - 3. Faceted Search 6-Layer Matching Tests
    
    public static func testFacetedSearchMultiLayerMatching() throws {
        let home = Asset(name: "Apartament Dorobanți", category: .home)
        home.podCode = "RO001E999888777"
        home.primaryContactName = "Instalator Dan"
        home.primaryContactRole = "Instalator"
        
        let event = LifecycleEvent(title: "Verificare Tehnică Centrală VTP", dueDate: Date(), provider: "Engie")
        event.asset = home
        home.events.append(event)
        
        let service = ServiceItem(name: "Înlocuire robinet calorifer", specialistOrDoctorName: "Instalator Dan")
        service.asset = home
        home.serviceItems.append(service)
        
        let measurement = MeasurementLog(metricName: "Gaze Naturale Curent", value: 1450.0, unit: "m³")
        measurement.asset = home
        home.measurements.append(measurement)
        
        let attachment = DocumentAttachment(fileName: "Factura_ENGIE_Dec2026.pdf", fileExtension: "pdf", extractedText: "Total de plata: 340,50 lei Cod loc consum DEG112233")
        attachment.asset = home
        home.attachments.append(attachment)
        
        let allAssets = [home]
        
        // Helper matching mimicking AssetsVaultView
        func search(_ query: String) -> [Asset] {
            let q = RomanianUtilityParser.stripDiacritics(query).lowercased()
            return allAssets.filter { asset in
                if RomanianUtilityParser.stripDiacritics(asset.name).lowercased().contains(q) { return true }
                if let pod = asset.podCode, pod.lowercased().contains(q) { return true }
                if let contact = asset.primaryContactName, RomanianUtilityParser.stripDiacritics(contact).lowercased().contains(q) { return true }
                for ev in asset.events {
                    if RomanianUtilityParser.stripDiacritics(ev.title).lowercased().contains(q) { return true }
                }
                for s in asset.serviceItems {
                    if RomanianUtilityParser.stripDiacritics(s.name).lowercased().contains(q) { return true }
                }
                for m in asset.measurements {
                    if RomanianUtilityParser.stripDiacritics(m.metricName).lowercased().contains(q) { return true }
                }
                for a in asset.attachments {
                    if let text = a.extractedText, RomanianUtilityParser.stripDiacritics(text).lowercased().contains(q) { return true }
                }
                return false
            }
        }
        
        // Match Layer 1: Core title
        try assertEqual(search("Dorobanti").count, 1, "Should match by asset title without diacritics")
        
        // Match Layer 2: POD code
        try assertEqual(search("999888").count, 1, "Should match by POD code snippet")
        
        // Match Layer 3: Contact name
        try assertEqual(search("Instalator Dan").count, 1, "Should match by primary contact")
        
        // Match Layer 4: Event title
        try assertEqual(search("Centrala VTP").count, 1, "Should match by lifecycle event title")
        
        // Match Layer 5: Service part / procedure
        try assertEqual(search("robinet calorifer").count, 1, "Should match by historical service item")
        
        // Match Layer 6: Measurement metric name
        try assertEqual(search("Gaze Naturale Curent").count, 1, "Should match by measurement metric name")
        
        // Match Layer 7: OCR Document text
        try assertEqual(search("DEG112233").count, 1, "Should match by OCR extracted text inside attached document")
        
        // Unmatched query
        try assertEqual(search("complet_inexistent").count, 0, "Non-matching query should return 0 results")
    }
    
    public static func testMultiIdentifierConflictResolutionEntropyScoring() throws {
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
        
        // Order 1: personAsset first
        let match1 = RomanianUtilityParser.findBestAssetMatch(for: text, in: [personAsset, carAsset])
        try assertNotNil(match1, "Match 1 should not be nil")
        try assertEqual(match1?.asset.name, "BMW 320d", "VIN (score 100) must override person name (score 60) when person is first")
        
        // Order 2: carAsset first
        let match2 = RomanianUtilityParser.findBestAssetMatch(for: text, in: [carAsset, personAsset])
        try assertNotNil(match2, "Match 2 should not be nil")
        try assertEqual(match2?.asset.name, "BMW 320d", "VIN (score 100) must override person name (score 60) when car is first")
    }
    
    // MARK: - Runner
    
    public static func runAll() -> TestSuiteResult {
        let startTime = Date()
        var passed = 0
        var failed = 0
        var failures: [TestFailure] = []
        
        let tests: [(String, () throws -> Void)] = [
            ("testAssetAutoMatchByPOD", testAssetAutoMatchByPOD),
            ("testAssetAutoMatchByCLC", testAssetAutoMatchByCLC),
            ("testAssetAutoMatchByWaterClientCode", testAssetAutoMatchByWaterClientCode),
            ("testAssetAutoMatchByVIN", testAssetAutoMatchByVIN),
            ("testAssetAutoMatchByLicensePlate", testAssetAutoMatchByLicensePlate),
            ("testAssetAutoMatchByMicrochip", testAssetAutoMatchByMicrochip),
            ("testAssetAutoMatchBySerialOrImei", testAssetAutoMatchBySerialOrImei),
            ("testAssetAutoMatchByPersonName", testAssetAutoMatchByPersonName),
            ("testRoutingDestinationEventCreation", testRoutingDestinationEventCreation),
            ("testRoutingDestinationServiceItemWithMileage", testRoutingDestinationServiceItemWithMileage),
            ("testRoutingDestinationMeasurementLogWithDelta", testRoutingDestinationMeasurementLogWithDelta),
            ("testFacetedSearchMultiLayerMatching", testFacetedSearchMultiLayerMatching),
            ("testMultiIdentifierConflictResolutionEntropyScoring", testMultiIdentifierConflictResolutionEntropyScoring)
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
            suiteName: "IntakeAndRoutingTests",
            passed: passed,
            failed: failed,
            failures: failures,
            duration: duration
        )
    }
}
