import Foundation
import SwiftData

/// Test suite verifying quantitative telemetry (MeasurementLog), lab biomarker reference intervals,
/// 8-domain tailored asset schemas, and rich starter template catalogs (Solar Prosumer & Landlord).
public final class MeasurementLogAndDomainTests: Sendable {
    
    // MARK: - Test 1: Utility Meter Differential & Estimated Cost
    public static func testUtilityMeterDifferentialAndCost() throws {
        let reading = MeasurementLog(
            domain: .electricityMeter,
            metricName: "Index Contor Zi",
            value: 4710.0,
            unit: "kWh",
            previousValue: 4520.0,
            unitPrice: 0.68,
            isSelfRead: true
        )
        
        try assertEqual(reading.value, 4710.0)
        try assertEqual(reading.previousValue, 4520.0)
        
        // Delta = 4710 - 4520 = 190 kWh
        guard let delta = reading.deltaFromPrevious else {
            throw TestAssertionError(message: "deltaFromPrevious must be computed", file: #file, line: #line)
        }
        try assertAlmostEqual(delta, 190.0, accuracy: 0.001)
        
        // Estimated Cost = 190 * 0.68 = 129.20 RON
        guard let cost = reading.estimatedCost else {
            throw TestAssertionError(message: "estimatedCost must be computed", file: #file, line: #line)
        }
        try assertAlmostEqual(cost, 129.20, accuracy: 0.01)
        try assertTrue(reading.isSelfRead, "Reading should be self-read")
    }
    
    // MARK: - Test 2: Lab Biomarker Reference Range & Out-of-Range Flags
    public static func testLabBiomarkerReferenceRangeFlags() throws {
        // High glucose test (125 mg/dL vs normal 70-99 mg/dL)
        let highGlucose = MeasurementLog(
            domain: .healthBiomarker,
            metricName: "Glicemie serică",
            value: 125.0,
            unit: "mg/dL",
            referenceMin: 70.0,
            referenceMax: 99.0,
            labOrProviderName: "Synevo România"
        )
        try assertTrue(highGlucose.isOutOfRange, "125 mg/dL should be flagged out of range (> 99)")
        
        // Normal glucose test (85 mg/dL vs normal 70-99 mg/dL)
        let normalGlucose = MeasurementLog(
            domain: .healthBiomarker,
            metricName: "Glicemie serică",
            value: 85.0,
            unit: "mg/dL",
            referenceMin: 70.0,
            referenceMax: 99.0
        )
        try assertFalse(normalGlucose.isOutOfRange, "85 mg/dL should be within normal range")
        
        // Low biomarker test (hypoglycemia: 58 mg/dL vs normal 70-99 mg/dL)
        let lowGlucose = MeasurementLog(
            domain: .healthBiomarker,
            metricName: "Glicemie serică",
            value: 58.0,
            unit: "mg/dL",
            referenceMin: 70.0,
            referenceMax: 99.0
        )
        try assertTrue(lowGlucose.isOutOfRange, "58 mg/dL should be flagged out of range (< 70)")
    }
    
    // MARK: - Test 3: 8 Household Domain Schema Completeness
    public static func testEightDomainSchemaCompleteness() throws {
        // 1. Vehicle
        let vehicle = Asset(name: "Dacia Duster", category: .vehicle)
        vehicle.vin = "UU1HSDJ8651234567"
        vehicle.licensePlate = "B-123-ABC"
        vehicle.civSeries = "M-123456"
        vehicle.make = "Dacia"
        vehicle.modelName = "Duster"
        vehicle.manufactureYear = 2022
        vehicle.fuelType = "Motorină"
        vehicle.engineDisplacementCc = 1461
        vehicle.enginePowerKw = 85
        try assertEqual(vehicle.vin, "UU1HSDJ8651234567")
        try assertEqual(vehicle.licensePlate, "B-123-ABC")
        try assertEqual(vehicle.civSeries, "M-123456")
        
        // 2. Home
        let home = Asset(name: "Apartament Floreasca", category: .home)
        home.address = "Str. Banu Antonache 12"
        home.cadastralNumber = "214567-C1-U15"
        home.surfaceAreaSqm = 78.5
        home.constructionYear = 2019
        home.podCode = "RO001E123456789"
        home.clcCode = "DEG1234567"
        home.waterClientCode = "APA-9988"
        home.meterReadWindowStartDay = 20
        home.meterReadWindowEndDay = 25
        try assertEqual(home.podCode, "RO001E123456789")
        try assertEqual(home.clcCode, "DEG1234567")
        try assertEqual(home.meterReadWindowStartDay, 20)
        try assertEqual(home.meterReadWindowEndDay, 25)
        
        // 3. Health
        let health = Asset(name: "Dosar Medical Andrei", category: .health)
        health.personName = "Andrei Popescu"
        health.bloodType = "A II, Rh+"
        health.allergies = "Ambrozie, Penicilină"
        health.chronicConditions = "Hipertensiune esențială"
        health.familyDoctorName = "Dr. Elena Ionescu"
        health.familyDoctorPhone = "+40 721 112 233"
        try assertEqual(health.bloodType, "A II, Rh+")
        try assertEqual(health.allergies, "Ambrozie, Penicilină")
        
        // 4. Pet
        let pet = Asset(name: "Max", category: .pet)
        pet.microchipNumber = "642098100123456"
        pet.petPassportNumber = "RO 123456"
        pet.speciesAndBreed = "Câine — Golden Retriever"
        pet.weightKg = 32.5
        pet.veterinarianClinic = "Speed Vet"
        pet.veterinarianPhone = "+40 733 999 888"
        try assertEqual(pet.microchipNumber, "642098100123456")
        try assertEqual(pet.weightKg, 32.5)
        
        // 5. Warranties
        let warranty = Asset(name: "MacBook Pro M3", category: .warranties)
        warranty.serialOrImei = "C02XYZ123456"
        warranty.retailerOrIssuer = "iStyle România"
        warranty.purchasePrice = 11999.0
        warranty.warrantyMonths = 24
        warranty.extendedWarrantyMonths = 12
        try assertEqual(warranty.serialOrImei, "C02XYZ123456")
        try assertEqual(warranty.warrantyMonths, 24)
        try assertEqual(warranty.extendedWarrantyMonths, 12)
        
        // 6. Subscriptions
        let sub = Asset(name: "Digi Fiber & TV", category: .subscriptions)
        sub.providerName = "RCS & RDS (Digi)"
        sub.billingCycle = "Lunar"
        sub.recurringAmount = 65.0
        sub.currencyCode = "RON"
        sub.paymentCardLast4 = "4321"
        sub.cancellationUrl = "https://digi.ro/contul-meu"
        try assertEqual(sub.providerName, "RCS & RDS (Digi)")
        try assertEqual(sub.paymentCardLast4, "4321")
        
        // 7. Documents
        let doc = Asset(name: "Pașaport Simplu Electronic", category: .documents)
        doc.serialOrImei = "08123456"
        doc.retailerOrIssuer = "SPCP București"
        try assertEqual(doc.serialOrImei, "08123456")
        try assertEqual(doc.retailerOrIssuer, "SPCP București")
        
        // 8. Custom / Landlord
        let rental = Asset(name: "Garsonieră Închiriată", category: .custom)
        rental.primaryContactName = "Mihai Georgescu"
        rental.primaryContactRole = "Chiriaș"
        rental.primaryContactPhone = "+40 744 555 666"
        rental.recurringAmount = 1800.0
        try assertEqual(rental.primaryContactName, "Mihai Georgescu")
        try assertEqual(rental.primaryContactRole, "Chiriaș")
        try assertEqual(rental.recurringAmount, 1800.0)
    }
    
    // MARK: - Test 4: All 10 DynamicField Types Display Formatting
    public static func testAllTenDynamicFieldTypes() throws {
        let fText = DynamicField(key: "notes", label: "Note", fieldType: .text, stringValue: "Text descriptiv")
        try assertEqual(fText.displayValue, "Text descriptiv")
        
        let fNum = DynamicField(key: "area", label: "Suprafață", fieldType: .number, numberValue: 85.0)
        try assertEqual(fNum.displayValue, "85")
        
        let fCurr = DynamicField(key: "rent", label: "Chirie", fieldType: .currency, numberValue: 2450.50)
        try assertEqual(fCurr.displayValue, "2450.50 RON")
        
        let now = Date()
        let fDate = DynamicField(key: "renewal", label: "Reînnoire", fieldType: .date, dateValue: now)
        try assertTrue(fDate.displayValue != "—", "Date displayValue should format date")
        
        let fBool = DynamicField(key: "active", label: "Activ", fieldType: .boolean, boolValue: true)
        try assertEqual(fBool.displayValue, "Da")
        
        let fSingle = DynamicField(key: "tier", label: "Plan", fieldType: .singleSelect, stringValue: "Premium")
        try assertEqual(fSingle.displayValue, "Premium")
        
        let fMulti = DynamicField(key: "addons", label: "Opțiuni", fieldType: .multiSelect, stringValue: "4K, HDR, Dolby")
        try assertEqual(fMulti.displayValue, "4K, HDR, Dolby")
        
        let fUrl = DynamicField(key: "portal", label: "Portal", fieldType: .url, stringValue: "https://example.com")
        try assertEqual(fUrl.displayValue, "https://example.com")
        
        let fPhone = DynamicField(key: "support", label: "Suport", fieldType: .phone, stringValue: "+40 722 000 111")
        try assertEqual(fPhone.displayValue, "+40 722 000 111")
        
        let fLong = DynamicField(key: "terms", label: "Termeni", fieldType: .longText, stringValue: "Linia 1\nLinia 2")
        try assertEqual(fLong.displayValue, "Linia 1\nLinia 2")
    }
    
    // MARK: - Test 5: ServiceItem Days in Service RMA Extension
    public static func testServiceItemRmaStatutoryExtension() throws {
        let asset = Asset(name: "Laptop Asus ROG", category: .warranties)
        asset.warrantyMonths = 24
        let purchaseDate = Date()
        asset.purchaseOrIssueDate = purchaseDate
        
        let rma = ServiceItem(
            name: "Înlocuire Tastatură & Placă Bază",
            category: "Garanție / RMA",
            cost: 0.0,
            daysInService: 12
        )
        rma.asset = asset
        asset.serviceItems.append(rma)
        
        try assertEqual(rma.daysInService, 12)
        let totalRmaDays = asset.serviceItems.compactMap { $0.daysInService }.reduce(0, +)
        try assertEqual(totalRmaDays, 12, "Statutory RMA days should accumulate")
    }
    
    // MARK: - Test 6: Starter Templates Prosumer Solar and Landlord Catalog
    public static func testStarterTemplateGalleryProsumerSolarAndLandlord() throws {
        let templates = StarterTemplate.allTemplates
        
        // Check Landlord Template
        guard let landlord = templates.first(where: { $0.id == "landlord" }) else {
            throw TestAssertionError(message: "Landlord template must exist in catalog", file: #file, line: #line)
        }
        try assertEqual(landlord.id, "landlord")
        try assertTrue(landlord.suggestedEvents.contains { $0.title.contains("Declarația Unică") }, "Landlord must include ANAF Declarația Unică reminder")
        try assertTrue(landlord.suggestedFields.contains { $0.key == "nume_chirias" }, "Landlord must have tenant name field")
        
        // Check Prosumer Solar Template
        guard let solar = templates.first(where: { $0.id == "solar" }) else {
            throw TestAssertionError(message: "Solar prosumer template must exist in catalog", file: #file, line: #line)
        }
        try assertEqual(solar.id, "solar")
        try assertEqual(solar.metricUnit, "kWh")
        try assertTrue(solar.suggestedFields.contains { $0.key == "putere_instalata" }, "Solar must include installed power (kWp)")
        try assertTrue(solar.suggestedFields.contains { $0.key == "model_invertor" }, "Solar must include inverter model")
        try assertTrue(solar.suggestedEvents.contains { $0.title.contains("PRAM") || $0.title.contains("curățare") }, "Solar must include maintenance cadences")
    }
    
    // MARK: - Suite Runner
    public static func runAll() -> TestSuiteResult {
        let startTime = Date()
        var passed = 0
        var failed = 0
        var failures: [TestFailure] = []
        
        let tests: [(String, () throws -> Void)] = [
            ("testUtilityMeterDifferentialAndCost", testUtilityMeterDifferentialAndCost),
            ("testLabBiomarkerReferenceRangeFlags", testLabBiomarkerReferenceRangeFlags),
            ("testEightDomainSchemaCompleteness", testEightDomainSchemaCompleteness),
            ("testAllTenDynamicFieldTypes", testAllTenDynamicFieldTypes),
            ("testServiceItemRmaStatutoryExtension", testServiceItemRmaStatutoryExtension),
            ("testStarterTemplateGalleryProsumerSolarAndLandlord", testStarterTemplateGalleryProsumerSolarAndLandlord)
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
            suiteName: "MeasurementLogAndDomainTests",
            passed: passed,
            failed: failed,
            failures: failures,
            duration: duration
        )
    }
}
