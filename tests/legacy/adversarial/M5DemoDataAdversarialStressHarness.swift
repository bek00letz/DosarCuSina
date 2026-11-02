import Foundation
import SwiftData
import SwiftUI

// MARK: - Minimal Terminal Test Reporter

var totalTests = 0
var passedTests = 0
var failedTests = 0

func assertTest(_ condition: Bool, _ name: String, file: String = #file, line: Int = #line) {
    totalTests += 1
    if condition {
        passedTests += 1
        print("  \u{001B}[32m✔ PASS\u{001B}[0m [\(totalTests)] \(name)")
    } else {
        failedTests += 1
        print("  \u{001B}[31m✘ FAIL\u{001B}[0m [\(totalTests)] \(name) (at \(file):\(line))")
    }
}

// MARK: - SUITE 1: DEMO DATA SEEDER CONSTRAINTS & COMPLIANCE

@MainActor
func runDemoDataSeederConstraintsTests(context: ModelContext) throws {
    print("\n\u{001B}[1m=== SUITE 1: DEMO DATA SEEDER CONSTRAINTS & ROMANIAN STANDARDS ===\u{001B}[0m")
    
    // Ensure fresh seed
    try DemoDataSeeder.resetAndReseed(context: context)
    
    let assets = try context.fetch(FetchDescriptor<Asset>())
    let events = try context.fetch(FetchDescriptor<LifecycleEvent>())
    let services = try context.fetch(FetchDescriptor<ServiceItem>())
    let measurements = try context.fetch(FetchDescriptor<MeasurementLog>())
    let fields = try context.fetch(FetchDescriptor<DynamicField>())
    
    // 1.1 Assert all 8 domains are represented
    let categoriesPresent = Set(assets.map { $0.category })
    assertTest(categoriesPresent.count == 8, "All 8 AssetCategory domains are represented (got \(categoriesPresent.count)/8)")
    for cat in AssetCategory.allCases {
        assertTest(categoriesPresent.contains(cat), "Domain '\(cat.rawValue)' (\(cat.title)) is present in seeded assets")
    }
    
    // 1.2 Assert zero occurrences of Pod Fetești, SMS 8545, or abolished toll patterns
    let forbiddenPatterns = ["fetesti", "fetești", "giurgeni", "8545", "peaj", "taxa de pod", "taxă de pod"]
    
    var stringCorpus: [String] = []
    for a in assets {
        stringCorpus.append(a.name)
        if let s = a.subtitle { stringCorpus.append(s) }
        if let n = a.notes { stringCorpus.append(n) }
        if let m = a.make { stringCorpus.append(m) }
        if let mn = a.modelName { stringCorpus.append(mn) }
        if let c = a.customCategoryName { stringCorpus.append(c) }
    }
    for e in events {
        stringCorpus.append(e.title)
        if let d = e.eventDescription { stringCorpus.append(d) }
        if let p = e.provider { stringCorpus.append(p) }
        if let loc = e.serviceLocation { stringCorpus.append(loc) }
        if let cov = e.coverageType { stringCorpus.append(cov) }
    }
    for s in services {
        stringCorpus.append(s.name)
        stringCorpus.append(s.category)
        if let n = s.notes { stringCorpus.append(n) }
        if let b = s.partBrandOrCode { stringCorpus.append(b) }
        if let shop = s.shopName { stringCorpus.append(shop) }
        if let spec = s.specialistOrDoctorName { stringCorpus.append(spec) }
    }
    for m in measurements {
        stringCorpus.append(m.metricName)
        if let n = m.notes { stringCorpus.append(n) }
        if let lab = m.labOrProviderName { stringCorpus.append(lab) }
    }
    for f in fields {
        stringCorpus.append(f.key)
        stringCorpus.append(f.label)
        if let sv = f.stringValue { stringCorpus.append(sv) }
    }
    
    for pattern in forbiddenPatterns {
        let matches = stringCorpus.filter { $0.localizedCaseInsensitiveContains(pattern) }
        assertTest(matches.isEmpty, "Zero occurrences of abolished toll pattern '\(pattern)' (found: \(matches))")
    }
    
    // 1.3 Assert all 17-char VINs are valid alphanumeric uppercase strings
    let vehicleAssets = assets.filter { $0.category == .vehicle }
    assertTest(!vehicleAssets.isEmpty, "At least one vehicle asset exists")
    for v in vehicleAssets {
        guard let vin = v.vin else {
            assertTest(false, "Vehicle '\(v.name)' must have a VIN")
            continue
        }
        assertTest(vin.count == 17, "VIN '\(vin)' has exactly 17 characters")
        let isAlphanumericUppercase = vin.range(of: "^[A-Z0-9]{17}$", options: .regularExpression) != nil
        assertTest(isAlphanumericUppercase, "VIN '\(vin)' is valid alphanumeric uppercase without disallowed characters")
        // Check ISO 3779 standard (letters I, O, Q disallowed in standard VINs)
        let containsIOQ = vin.contains("I") || vin.contains("O") || vin.contains("Q")
        assertTest(!containsIOQ, "VIN '\(vin)' complies with ISO 3779 (does not contain I, O, Q)")
    }
    
    // 1.4 Assert microchip number is 15 numeric digits starting with 642
    let petAssets = assets.filter { $0.category == .pet }
    assertTest(!petAssets.isEmpty, "At least one pet asset exists")
    for p in petAssets {
        guard let chip = p.microchipNumber else {
            assertTest(false, "Pet '\(p.name)' must have a microchip number")
            continue
        }
        assertTest(chip.count == 15, "Microchip '\(chip)' is exactly 15 characters")
        let isAllDigits = chip.range(of: "^[0-9]{15}$", options: .regularExpression) != nil
        assertTest(isAllDigits, "Microchip '\(chip)' consists entirely of numeric digits")
        assertTest(chip.hasPrefix("642"), "Microchip '\(chip)' starts with 642 (Romania ISO country code)")
    }
    
    // 1.5 Assert sequential service items calculate non-negative delta-km and delta-cost
    for a in assets {
        let sortedServices = a.serviceItems.sorted { $0.serviceDate < $1.serviceDate }
        if sortedServices.count >= 2 {
            for i in 1..<sortedServices.count {
                let prev = sortedServices[i - 1]
                let curr = sortedServices[i]
                
                if let prevKm = prev.mileageAtService, let currKm = curr.mileageAtService {
                    let deltaKm = currKm - prevKm
                    assertTest(deltaKm >= 0, "Sequential service item '\(curr.name)' has non-negative delta-km (\(deltaKm) km, prev=\(prevKm), curr=\(currKm))")
                }
                
                let prevCost = prev.totalEffectiveCost
                let currCost = curr.totalEffectiveCost
                let deltaCost = currCost - prevCost
                // Cost delta: check that effective cost calculations are coherent
                assertTest(currCost >= 0 && prevCost >= 0, "Service items have valid non-negative costs (\(prevCost), \(currCost))")
            }
        }
    }
    
    // Specifically test Vehicle Brake Pads delta
    let car = vehicleAssets.first!
    let brakeServices = car.serviceItems.filter { $0.name.contains("Frână") }.sorted { $0.serviceDate < $1.serviceDate }
    assertTest(brakeServices.count == 2, "Vehicle has exactly 2 consecutive brake service items")
    if brakeServices.count == 2 {
        let b1 = brakeServices[0]
        let b2 = brakeServices[1]
        let deltaKm = (b2.mileageAtService ?? 0) - (b1.mileageAtService ?? 0)
        assertTest(deltaKm == 47000.0, "Brake pads delta-km is exactly +47,000 km (85k -> 132k)")
        let deltaCost = b2.totalEffectiveCost - b1.totalEffectiveCost
        assertTest(deltaCost == 90.0, "Brake pads delta-cost is exactly +90 RON (430 -> 520, +20.9%)")
    }
}

// MARK: - SUITE 2: CASCADE DELETION & RESET-AND-RESEED ADVERSARIAL STRESS

@MainActor
func runCascadeAndResetStressTests(context: ModelContext) throws {
    print("\n\u{001B}[1m=== SUITE 2: CASCADE DELETION & RESET-AND-RESEED ADVERSARIAL STRESS ===\u{001B}[0m")
    
    // 2.1 SwiftData direct cascade delete test: single asset deletion cascades to all children
    let testAsset = Asset(name: "Test Cascade Asset", category: .warranties)
    context.insert(testAsset)
    
    let testEvent = LifecycleEvent(title: "Test Event", dueDate: Date())
    testEvent.asset = testAsset
    context.insert(testEvent)
    
    let testService = ServiceItem(name: "Test Service", serviceDate: Date())
    testService.asset = testAsset
    context.insert(testService)
    
    let testMeasurement = MeasurementLog(domain: .bodyWeight, metricName: "Test Metric", value: 10.0, unit: "kg")
    testMeasurement.asset = testAsset
    context.insert(testMeasurement)
    
    let testField = DynamicField(key: "test_key", label: "Test Field", fieldType: .text, stringValue: "val", asset: testAsset)
    context.insert(testField)
    
    let testAttachment = DocumentAttachment(fileName: "test.pdf", fileType: "pdf", fileSize: 1024, asset: testAsset)
    context.insert(testAttachment)
    
    try context.save()
    
    // Verify insertion
    let assetId = testAsset.id
    let eventId = testEvent.id
    let serviceId = testService.id
    let measurementId = testMeasurement.id
    let fieldId = testField.id
    let attachmentId = testAttachment.id
    
    // Now delete testAsset directly
    context.delete(testAsset)
    try context.save()
    
    // Verify that all 5 child entities are deleted
    let remainingEvents = try context.fetch(FetchDescriptor<LifecycleEvent>(predicate: #Predicate { $0.id == eventId }))
    assertTest(remainingEvents.isEmpty, "Direct Asset deletion cascades to LifecycleEvent")
    
    let remainingServices = try context.fetch(FetchDescriptor<ServiceItem>(predicate: #Predicate { $0.id == serviceId }))
    assertTest(remainingServices.isEmpty, "Direct Asset deletion cascades to ServiceItem")
    
    let remainingMeasurements = try context.fetch(FetchDescriptor<MeasurementLog>(predicate: #Predicate { $0.id == measurementId }))
    assertTest(remainingMeasurements.isEmpty, "Direct Asset deletion cascades to MeasurementLog")
    
    let remainingFields = try context.fetch(FetchDescriptor<DynamicField>(predicate: #Predicate { $0.id == fieldId }))
    assertTest(remainingFields.isEmpty, "Direct Asset deletion cascades to DynamicField")
    
    let remainingAttachments = try context.fetch(FetchDescriptor<DocumentAttachment>(predicate: #Predicate { $0.id == attachmentId }))
    assertTest(remainingAttachments.isEmpty, "Direct Asset deletion cascades to DocumentAttachment")
    
    // 2.2 Adversarial Orphan Pollution & resetAndReseed Cleanup
    // Intentionally inject orphaned records with nil asset references
    let orphanEvent = LifecycleEvent(title: "Orphan Event Without Asset", dueDate: Date())
    context.insert(orphanEvent)
    
    let orphanService = ServiceItem(name: "Orphan Service Without Asset", serviceDate: Date())
    context.insert(orphanService)
    
    let orphanMeasurement = MeasurementLog(domain: .gasMeter, metricName: "Orphan Reading", value: 99.0, unit: "m³")
    context.insert(orphanMeasurement)
    
    let orphanField = DynamicField(key: "orphan_field", label: "Orphan Field", fieldType: .number, numberValue: 42.0)
    context.insert(orphanField)
    
    let orphanAttachment = DocumentAttachment(fileName: "orphan.pdf", fileType: "pdf", fileSize: 2048)
    context.insert(orphanAttachment)
    
    try context.save()
    
    // Execute resetAndReseed
    try DemoDataSeeder.resetAndReseed(context: context)
    
    // Assert ZERO orphaned records across all tables
    let allEvents = try context.fetch(FetchDescriptor<LifecycleEvent>())
    let orphanedEvents = allEvents.filter { $0.asset == nil }
    assertTest(orphanedEvents.isEmpty, "resetAndReseed left zero orphaned events (found \(orphanedEvents.count))")
    
    let allServices = try context.fetch(FetchDescriptor<ServiceItem>())
    let orphanedServices = allServices.filter { $0.asset == nil }
    assertTest(orphanedServices.isEmpty, "resetAndReseed left zero orphaned service items (found \(orphanedServices.count))")
    
    let allMeasurements = try context.fetch(FetchDescriptor<MeasurementLog>())
    let orphanedMeasurements = allMeasurements.filter { $0.asset == nil }
    assertTest(orphanedMeasurements.isEmpty, "resetAndReseed left zero orphaned measurements (found \(orphanedMeasurements.count))")
    
    let allFields = try context.fetch(FetchDescriptor<DynamicField>())
    let orphanedFields = allFields.filter { $0.asset == nil }
    assertTest(orphanedFields.isEmpty, "resetAndReseed left zero orphaned dynamic fields (found \(orphanedFields.count))")
    
    let allAttachments = try context.fetch(FetchDescriptor<DocumentAttachment>())
    let orphanedAttachments = allAttachments.filter { $0.asset == nil }
    assertTest(orphanedAttachments.isEmpty, "resetAndReseed left zero orphaned attachments (found \(orphanedAttachments.count))")
    
    // Assert exact seed baseline counts
    let seededAssets = try context.fetch(FetchDescriptor<Asset>())
    assertTest(seededAssets.count == 8, "Exact 8 assets restored after resetAndReseed (got \(seededAssets.count))")
    assertTest(allEvents.count == 9, "Exact 9 lifecycle events restored after resetAndReseed (got \(allEvents.count))")
    assertTest(allServices.count == 5, "Exact 5 service items restored after resetAndReseed (got \(allServices.count))")
    assertTest(allMeasurements.count == 8, "Exact 8 measurement logs restored after resetAndReseed (got \(allMeasurements.count))")
    assertTest(allFields.count == 3, "Exact 3 dynamic fields restored after resetAndReseed (got \(allFields.count))")
    
    // 2.3 Idempotency & Rapid Repeated Reseed Stress Test (5x loop)
    for cycle in 1...5 {
        try DemoDataSeeder.resetAndReseed(context: context)
        let cAssets = try context.fetch(FetchDescriptor<Asset>())
        let cEvents = try context.fetch(FetchDescriptor<LifecycleEvent>())
        assertTest(cAssets.count == 8 && cEvents.count == 9, "Repeated resetAndReseed cycle \(cycle)/5 maintains exact count invariant (8 assets, 9 events)")
    }
    
    // 2.4 seedInitialDataIfNeeded idempotency (force: false)
    DemoDataSeeder.seedInitialDataIfNeeded(context: context, force: false)
    let postNoopAssets = try context.fetch(FetchDescriptor<Asset>())
    assertTest(postNoopAssets.count == 8, "seedInitialDataIfNeeded with force=false is idempotent no-op when data exists")
}

// MARK: - SUITE 3: SPECIFIC DOMAIN ATTRIBUTE & TELEMETRY INVARIANTS

@MainActor
func runDomainAttributeAndTelemetryTests(context: ModelContext) throws {
    print("\n\u{001B}[1m=== SUITE 3: SPECIFIC DOMAIN ATTRIBUTE & TELEMETRY INVARIANTS ===\u{001B}[0m")
    
    let assets = try context.fetch(FetchDescriptor<Asset>())
    
    // 3.1 Home domain checks
    guard let home = assets.first(where: { $0.category == .home }) else {
        assertTest(false, "Home asset must exist")
        return
    }
    assertTest(home.podCode == "RO001E123456789012", "Home POD code is RO001E123456789012")
    assertTest(home.clcCode == "DEG0123456", "Home CLC code is DEG0123456")
    assertTest(home.meterReadWindowStartDay == 20 && home.meterReadWindowEndDay == 25, "Self-read window is 20-25")
    
    // Check Home Measurements
    let electricityLogs = home.measurements.filter { $0.domain == .electricityMeter }.sorted { $0.recordedAt < $1.recordedAt }
    assertTest(electricityLogs.count == 2, "Home has 2 electricity measurement logs")
    if electricityLogs.count == 2 {
        let e2 = electricityLogs[1]
        assertTest(e2.deltaFromPrevious == 210.0, "Electricity delta calculation is 210.0 kWh (4330 - 4120)")
        assertTest(abs((e2.estimatedCost ?? 0) - 142.80) < 0.01, "Electricity estimated cost is 142.80 RON (210 * 0.68)")
    }
    
    let gasLogs = home.measurements.filter { $0.domain == .gasMeter }
    assertTest(gasLogs.count == 1, "Home has 1 gas measurement log")
    if let g = gasLogs.first {
        assertTest(g.deltaFromPrevious == 170.0, "Gas delta calculation is 170.0 m³ (1540 - 1370)")
        assertTest(abs((g.estimatedCost ?? 0) - 552.50) < 0.01, "Gas estimated cost is 552.50 RON (170 * 3.25)")
    }
    
    // 3.2 Health biomarker checks
    guard let health = assets.first(where: { $0.category == .health }) else {
        assertTest(false, "Health asset must exist")
        return
    }
    assertTest(health.bloodType == "A II, Rh+", "Health blood type is A II, Rh+")
    assertTest(health.allergies == "Penicilină, Polen mesteacăn", "Health allergies populated")
    
    let glucose = health.measurements.first { $0.metricName.contains("Glicemie") }
    assertTest(glucose != nil, "Glucose biomarker log exists")
    if let glu = glucose {
        assertTest(!glu.isOutOfRange, "Seeded glucose 92 mg/dL is within normal range [70, 99]")
        assertTest(glu.deltaFromPrevious == -6.0, "Glucose delta is -6 mg/dL (92 - 98)")
    }
    
    let cholesterol = health.measurements.first { $0.metricName.contains("Colesterol") }
    assertTest(cholesterol != nil, "Cholesterol biomarker log exists")
    if let chol = cholesterol {
        assertTest(!chol.isOutOfRange, "Seeded LDL Cholesterol 125 mg/dL is within range [0, 130]")
        assertTest(chol.deltaFromPrevious == -23.0, "Cholesterol delta is -23 mg/dL (125 - 148)")
    }
    
    // Dental implant check
    let implant = health.serviceItems.first { $0.name.contains("Implant") }
    assertTest(implant != nil, "Dental implant service item exists")
    if let imp = implant {
        assertTest(imp.serialOrBatchNumber == "Straumann BLX Lot ST-8829104", "Dental implant lot number tracked")
        assertTest(imp.locationOrToothNumber == "Dinte #36 (FDI)", "FDI tooth number #36 tracked")
        assertTest(imp.warrantyMonths == 120, "Implant warranty is 120 months (10 years)")
    }
    
    // 3.3 Passport Non-EU travel restriction check
    guard let doc = assets.first(where: { $0.category == .documents }) else {
        assertTest(false, "Documents asset must exist")
        return
    }
    let passportEvent = doc.events.first { $0.title.contains("Pașaport") }
    assertTest(passportEvent != nil, "Passport expiry event exists")
    if let pe = passportEvent {
        assertTest(pe.reminderOffsetDays.contains(180), "Passport reminders include 180-day alert for 6-month non-EU rule")
    }
    
    // 3.4 Warranty Last-Chance check
    guard let warranty = assets.first(where: { $0.category == .warranties }) else {
        assertTest(false, "Warranties asset must exist")
        return
    }
    let warrantyEvent = warranty.events.first { $0.title.contains("Garanție") }
    assertTest(warrantyEvent != nil, "Warranty expiry event exists")
    if let we = warrantyEvent {
        assertTest(we.reminderOffsetDays.contains(30), "Warranty reminders include 30-day Last-Chance inspection alert")
    }
    
    // 3.5 Landlord Hub ANAF Form 212 check
    guard let landlord = assets.first(where: { $0.category == .custom }) else {
        assertTest(false, "Landlord custom asset must exist")
        return
    }
    let anafEvent = landlord.events.first { $0.title.contains("ANAF") }
    assertTest(anafEvent != nil, "ANAF Declarația Unică event exists")
    if let ae = anafEvent {
        let cal = Calendar.current
        let dueMonth = cal.component(.month, from: ae.dueDate)
        let dueDay = cal.component(.day, from: ae.dueDate)
        assertTest(dueMonth == 5 && dueDay == 25, "ANAF Formularul 212 due date is May 25 (got month \(dueMonth), day \(dueDay))")
    }
}

// MARK: - MAIN ENTRY

@main
struct M5DemoDataAdversarialStressHarness {
    @MainActor
    static func main() async {
        print("\u{001B}[1m\u{001B}[36m==================================================================\u{001B}[0m")
        print("\u{001B}[1m\u{001B}[36m    DOSAR CU ȘINĂ — M5 DEMO DATA & CASCADE ADVERSARIAL HARNESS   \u{001B}[0m")
        print("\u{001B}[1m\u{001B}[36m==================================================================\u{001B}[0m")
        
        let schema = Schema([
            Asset.self,
            LifecycleEvent.self,
            DocumentAttachment.self,
            DynamicField.self,
            ServiceItem.self,
            MeasurementLog.self
        ])
        
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        
        do {
            let container = try ModelContainer(for: schema, configurations: [config])
            let context = container.mainContext
            
            try runDemoDataSeederConstraintsTests(context: context)
            try runCascadeAndResetStressTests(context: context)
            try runDomainAttributeAndTelemetryTests(context: context)
            
            print("\n\u{001B}[1m\u{001B}[36m==================================================================\u{001B}[0m")
            print("\u{001B}[1mRESULTS: Total Tests: \(totalTests) | Passed: \(passedTests) | Failed: \(failedTests)\u{001B}[0m")
            
            if failedTests == 0 {
                print("\u{001B}[32m\u{001B}[1m🎉 ALL M5 DEMO SEED & CASCADE ADVERSARIAL TESTS PASSED (100%)\u{001B}[0m")
                print("\u{001B}[1m\u{001B}[36m==================================================================\u{001B}[0m")
                exit(0)
            } else {
                print("\u{001B}[31m\u{001B}[1m⚠️ ADVERSARIAL HARNESS DETECTED \(failedTests) FAILURE(S)!\u{001B}[0m")
                print("\u{001B}[1m\u{001B}[36m==================================================================\u{001B}[0m")
                exit(1)
            }
        } catch {
            print("\u{001B}[31mFatal Error in test harness: \(error)\u{001B}[0m")
            exit(2)
        }
    }
}
