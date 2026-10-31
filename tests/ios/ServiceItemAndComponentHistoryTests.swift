import Foundation
import SwiftData

/// Test suite verifying granular service components, component replacement history,
/// mileage deltas, cost differences, and Romanian insurance catalog data structures.
public final class ServiceItemAndComponentHistoryTests: Sendable {
    
    public static func testServiceItemModelInitialization() throws {
        let item = ServiceItem(
            name: "Plăcuțe Frână Față",
            category: "Frâne & Siguranță",
            partBrand: "Brembo",
            partSerialNumber: "P85020",
            cost: 280.0,
            serviceDate: Date(),
            mileageAtService: 120000.0,
            notes: "Înlocuire plăcuțe și curățare etrier"
        )
        
        try assertEqual(item.name, "Plăcuțe Frână Față")
        try assertEqual(item.partBrand, "Brembo")
        try assertEqual(item.partSerialNumber, "P85020")
        try assertEqual(item.cost, 280.0)
        try assertEqual(item.mileageAtService, 120000.0)
    }
    
    public static func testComponentHistoryMileageAndCostDelta() throws {
        let calendar = Calendar.current
        let today = Date()
        let pastDate = calendar.date(byAdding: .year, value: -2, to: today) ?? today
        
        let olderReplacement = ServiceItem(
            name: "Plăcuțe Frână Față",
            category: "Frâne & Siguranță",
            partBrand: "Brembo",
            cost: 280.0,
            serviceDate: pastDate,
            mileageAtService: 120000.0
        )
        
        let newerReplacement = ServiceItem(
            name: "Plăcuțe Frână Față",
            category: "Frâne & Siguranță",
            partBrand: "ATE Ceramic",
            cost: 340.0,
            serviceDate: today,
            mileageAtService: 165000.0
        )
        
        // Compute Deltas
        guard let newerKm = newerReplacement.mileageAtService,
              let olderKm = olderReplacement.mileageAtService else {
            try assertTrue(false, "Mileage values must be present")
            return
        }
        
        let deltaKm = newerKm - olderKm
        try assertEqual(deltaKm, 45000.0, "Delta km must be exactly 45,000 km")
        
        guard let newerCost = newerReplacement.cost,
              let olderCost = olderReplacement.cost else {
            try assertTrue(false, "Cost values must be present")
            return
        }
        
        let deltaCost = newerCost - olderCost
        try assertEqual(deltaCost, 60.0, "Delta cost must be +60 RON")
        
        let daysBetween = calendar.dateComponents([.day], from: olderReplacement.serviceDate, to: newerReplacement.serviceDate).day ?? 0
        try assertTrue(daysBetween >= 700, "Days between replacements should be approx 2 years (~730 days)")
    }
    
    public static func testRomanianInsuranceCatalog() throws {
        let insurers = RomanianInsuranceCatalog.recommendedInsurers
        try assertTrue(!insurers.isEmpty, "Insurers catalog must not be empty")
        
        let groupama = insurers.first { $0.id == "groupama" }
        try assertTrue(groupama != nil, "Groupama must be in catalog")
        try assertEqual(groupama?.name, "Groupama Asigurări")
        
        let allianz = insurers.first { $0.id == "allianz" }
        try assertTrue(allianz != nil, "Allianz must be in catalog")
        try assertEqual(allianz?.name, "Allianz-Țiriac Asigurări")
        
        // Coverage types
        try assertTrue(RomanianInsuranceCatalog.coverageTypes.contains("RCA"))
        try assertTrue(RomanianInsuranceCatalog.coverageTypes.contains("CASCO Complet"))
        try assertTrue(RomanianInsuranceCatalog.coverageTypes.contains("PAD Obligatoriu"))
        
        // Bonus Malus
        try assertTrue(RomanianInsuranceCatalog.bonusMalusClasses.contains("B0"))
        try assertTrue(RomanianInsuranceCatalog.bonusMalusClasses.contains("B8"))
        try assertTrue(RomanianInsuranceCatalog.bonusMalusClasses.contains("M8"))
        
        // Detection helper
        try assertTrue(RomanianInsuranceCatalog.isInsuranceTitle("Asigurare RCA Auto"))
        try assertTrue(RomanianInsuranceCatalog.isInsuranceTitle("Poliță PAD Locuință"))
        try assertFalse(RomanianInsuranceCatalog.isInsuranceTitle("Schimb Ulei Motor"))
    }
    
    public static func testVehicleAssetTailoredFields() throws {
        let car = Asset(
            name: "VW Passat B8",
            subtitle: "2.0 TDI Highline",
            category: .vehicle,
            currentMetricValue: 185000.0,
            metricUnit: "km"
        )
        
        car.licensePlate = "B-777-VWW"
        car.vinNumber = "WVWZZZ3CZJE123456"
        car.manufactureYear = 2018
        car.fuelType = "Motorină"
        car.engineDisplacementCm3 = 1968
        car.enginePowerHp = 190
        
        try assertEqual(car.licensePlate, "B-777-VWW")
        try assertEqual(car.vinNumber, "WVWZZZ3CZJE123456")
        try assertEqual(car.manufactureYear, 2018)
        try assertEqual(car.fuelType, "Motorină")
        try assertEqual(car.engineDisplacementCm3, 1968)
        try assertEqual(car.enginePowerHp, 190)
        try assertEqual(car.currentMetricValue, 185000.0)
    }
    
    public static func testHomeAssetTailoredFields() throws {
        let home = Asset(
            name: "Apartament Floreasca",
            subtitle: "3 Camere",
            category: .home
        )
        
        home.fullAddress = "Str. Aviatorilor Nr. 12, Bloc B2, Ap. 15, Sector 1, București"
        home.surfaceAreaM2 = 82.5
        home.constructionYear = 2016
        home.heatingBoilerModel = "Viessmann Vitodens 100-W 26kW"
        home.heatingBoilerSerial = "7570691234567"
        home.gasMeterSerial = "G4-98765432"
        home.electricityMeterSerial = "EL-00129845"
        home.waterMeterSerial = "AP-445566"
        
        try assertEqual(home.surfaceAreaM2, 82.5)
        try assertEqual(home.heatingBoilerModel, "Viessmann Vitodens 100-W 26kW")
        try assertEqual(home.gasMeterSerial, "G4-98765432")
        try assertEqual(home.electricityMeterSerial, "EL-00129845")
    }
    
    public static func testPetAndHealthTailoredFields() throws {
        let pet = Asset(
            name: "Max",
            subtitle: "Golden Retriever",
            category: .pet
        )
        pet.petSpecies = "Câine"
        pet.petBreed = "Golden Retriever"
        pet.petMicrochipNumber = "642098100123456"
        pet.veterinarianClinic = "SpeedVet București"
        pet.veterinarianPhone = "0722123456"
        
        try assertEqual(pet.petSpecies, "Câine")
        try assertEqual(pet.petMicrochipNumber, "642098100123456")
        try assertEqual(pet.veterinarianPhone, "0722123456")
        
        let health = Asset(
            name: "Dosar Medical Andrei",
            category: .health
        )
        health.bloodType = "A+"
        health.familyDoctorName = "Dr. Popescu Maria"
        health.allergiesNotes = "Alergie sezonieră ambrozie"
        
        try assertEqual(health.bloodType, "A+")
        try assertEqual(health.familyDoctorName, "Dr. Popescu Maria")
        try assertEqual(health.allergiesNotes, "Alergie sezonieră ambrozie")
    }
    
    // MARK: - Suite Runner
    public static func runAll() -> TestSuiteResult {
        let startTime = Date()
        var passed = 0
        var failed = 0
        var failures: [TestFailure] = []
        
        let tests: [(String, () throws -> Void)] = [
            ("testServiceItemModelInitialization", testServiceItemModelInitialization),
            ("testComponentHistoryMileageAndCostDelta", testComponentHistoryMileageAndCostDelta),
            ("testRomanianInsuranceCatalog", testRomanianInsuranceCatalog),
            ("testVehicleAssetTailoredFields", testVehicleAssetTailoredFields),
            ("testHomeAssetTailoredFields", testHomeAssetTailoredFields),
            ("testPetAndHealthTailoredFields", testPetAndHealthTailoredFields)
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
            suiteName: "ServiceItemAndComponentHistoryTests",
            passed: passed,
            failed: failed,
            failures: failures,
            duration: duration
        )
    }
}
