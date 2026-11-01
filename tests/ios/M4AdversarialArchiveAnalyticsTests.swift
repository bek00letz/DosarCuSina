import Foundation
import SwiftData
import CryptoKit

/// Comprehensive Adversarial Test Suite for M4 Archive (.dosar & DosarZipEngine)
/// and Financial Analytics (FinancialPulseCalculator).
public final class M4AdversarialArchiveAnalyticsTests: Sendable {
    
    @MainActor
    public static func runAll() async -> TestSuiteResult {
        let startTime = Date()
        var passed = 0
        var failed = 0
        var failures: [TestFailure] = []
        
        let tests: [(String, () async throws -> Void)] = [
            ("testZipEngine_EmptyZipAndSub22Bytes", testZipEngine_EmptyZipAndSub22Bytes),
            ("testZipEngine_ZipSlipAdversarialPaths", testZipEngine_ZipSlipAdversarialPaths),
            ("testZipEngine_CorruptedSignaturesAndBitFlip", testZipEngine_CorruptedSignaturesAndBitFlip),
            ("testArchive_ManifestAbsenceAndTamperedIntegrity", testArchive_ManifestAbsenceAndTamperedIntegrity),
            ("testArchive_MacOSUnzipStandardToolCompatibility", testArchive_MacOSUnzipStandardToolCompatibility),
            ("testArchive_MergeSemantics_OlderDiscardedNewerApplied", testArchive_MergeSemantics_OlderDiscardedNewerApplied),
            ("testFinancialPulse_ZeroAndNegativeCashFlowGuards", testFinancialPulse_ZeroAndNegativeCashFlowGuards),
            ("testFinancialPulse_ExactDayBoundaries", testFinancialPulse_ExactDayBoundaries),
            ("testFinancialPulse_LeapYearAndBucharestDST", testFinancialPulse_LeapYearAndBucharestDST),
            ("testFinancialPulse_SubscriptionBillingCyclesAndMath", testFinancialPulse_SubscriptionBillingCyclesAndMath),
            ("testFinancialPulse_FreeTrialAlertsAndRetentionWindows", testFinancialPulse_FreeTrialAlertsAndRetentionWindows),
            ("testFinancialPulse_UtilityDeltasMissingPreviousAndWrapAround", testFinancialPulse_UtilityDeltasMissingPreviousAndWrapAround)
        ]
        
        for (testName, testFunc) in tests {
            do {
                try await testFunc()
                passed += 1
                print("  ✅ PASS  \(testName)")
            } catch {
                failed += 1
                let failure = TestFailure(testName: testName, message: "\(error)", file: #file, line: #line)
                failures.append(failure)
                print("  ❌ FAIL  \(testName): \(error)")
            }
        }
        
        let duration = Date().timeIntervalSince(startTime)
        return TestSuiteResult(
            suiteName: "M4AdversarialArchiveAnalyticsTests",
            passed: passed,
            failed: failed,
            failures: failures,
            duration: duration
        )
    }
    
    // MARK: - 1. Empty Zip & Sub-22 Bytes
    
    public static func testZipEngine_EmptyZipAndSub22Bytes() throws {
        // Empty archive creation
        let emptyZip = try DosarZipEngine.createArchive(entries: [])
        try assertEqual(emptyZip.count, 22, "Empty zip archive must be exactly 22 bytes (EOCD record)")
        
        let unpacked = try DosarZipEngine.unpackArchive(emptyZip)
        try assertTrue(unpacked.isEmpty, "Unpacking empty archive must return 0 entries")
        
        // Zero-byte input
        do {
            _ = try DosarZipEngine.unpackArchive(Data())
            throw TestAssertionError(message: "0 bytes must fail with invalidZipArchive", file: #file, line: #line)
        } catch DosarZipEngine.ZipError.invalidZipArchive {
            // Expected
        }
        
        // Sub-22 byte input (15 bytes)
        do {
            _ = try DosarZipEngine.unpackArchive(Data(repeating: 0x42, count: 15))
            throw TestAssertionError(message: "15 bytes must fail with invalidZipArchive", file: #file, line: #line)
        } catch DosarZipEngine.ZipError.invalidZipArchive {
            // Expected
        }
    }
    
    // MARK: - 2. Zip-Slip Path Traversal
    
    public static func testZipEngine_ZipSlipAdversarialPaths() throws {
        let adversarialPaths = [
            "../escape.txt",
            "../../../../etc/passwd",
            "/etc/shadow",
            "/private/var/root",
            "data/../../secret.key",
            "vault/../../../app.bin",
            "foo\\..\\bar",
            "subfolder/../../root.txt"
        ]
        
        for path in adversarialPaths {
            let entry = DosarZipEngine.Entry(path: path, data: "pwn".data(using: .utf8)!)
            do {
                _ = try DosarZipEngine.createArchive(entries: [entry])
                throw TestAssertionError(message: "Path traversal should have been blocked for '\(path)' during createArchive", file: #file, line: #line)
            } catch DosarZipEngine.ZipError.pathTraversalDetected {
                // Expected
            }
        }
    }
    
    // MARK: - 3. Corrupted Headers & Bit-Flips
    
    public static func testZipEngine_CorruptedSignaturesAndBitFlip() throws {
        let payload = "Sample document payload with repetitive content 1234567890".data(using: .utf8)!
        let validEntry = DosarZipEngine.Entry(path: "test.txt", data: payload)
        let validZip = try DosarZipEngine.createArchive(entries: [validEntry])
        
        // Corrupt EOCD signature
        var corruptEOCD = validZip
        let eocdPos = corruptEOCD.count - 22
        corruptEOCD[eocdPos] = 0x00
        do {
            _ = try DosarZipEngine.unpackArchive(corruptEOCD)
            throw TestAssertionError(message: "Corrupted EOCD signature must fail", file: #file, line: #line)
        } catch DosarZipEngine.ZipError.endOfCentralDirectoryNotFound {
            // Expected
        }
        
        // Corrupt Central Directory signature (0x02014b50)
        var corruptCD = validZip
        if let cdRange = corruptCD.range(of: Data([0x50, 0x4b, 0x01, 0x02])) {
            corruptCD[cdRange.lowerBound] = 0xAA
            do {
                _ = try DosarZipEngine.unpackArchive(corruptCD)
                throw TestAssertionError(message: "Corrupted CD signature must fail", file: #file, line: #line)
            } catch DosarZipEngine.ZipError.invalidZipArchive {
                // Expected
            }
        }
        
        // Single bit-flip in payload to trigger CRC-32 / inflation failure
        var bitFlipZip = validZip
        let flipIndex = 42
        bitFlipZip[flipIndex] ^= 0x01
        do {
            _ = try DosarZipEngine.unpackArchive(bitFlipZip)
            throw TestAssertionError(message: "Single bit-flip in payload must trigger integrity error", file: #file, line: #line)
        } catch DosarZipEngine.ZipError.crcMismatch {
            // Expected
        } catch DosarZipEngine.ZipError.zlibError {
            // Expected
        } catch DosarZipEngine.ZipError.fileCorrupted {
            // Expected
        }
    }
    
    // MARK: - 4. Manifest Absence & Tampered Integrity
    
    @MainActor
    public static func testArchive_ManifestAbsenceAndTamperedIntegrity() async throws {
        let schema = Schema([Asset.self, LifecycleEvent.self, ServiceItem.self, MeasurementLog.self, DocumentAttachment.self, DynamicField.self])
        let container = try ModelContainer(for: schema, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let context = container.mainContext
        
        let asset = Asset(name: "Vila Sinaia", category: .home)
        context.insert(asset)
        try context.save()
        
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }
        
        let archiveURL = try DossierArchiveService.shared.exportHouseholdArchive(context: context, targetDirectory: tempDir)
        let archiveBytes = try Data(contentsOf: archiveURL)
        
        // 1. Missing manifest.json
        var entriesNoManifest = try DosarZipEngine.unpackArchive(archiveBytes)
        entriesNoManifest.removeAll(where: { $0.path == "manifest.json" })
        let noManifestZip = try DosarZipEngine.createArchive(entries: entriesNoManifest)
        let noManifestURL = tempDir.appendingPathComponent("no_manifest.dosar")
        try noManifestZip.write(to: noManifestURL)
        
        do {
            _ = try DossierArchiveService.shared.inspectArchive(at: noManifestURL)
            throw TestAssertionError(message: "Missing manifest.json must throw manifestMissing", file: #file, line: #line)
        } catch ArchiveError.manifestMissing {
            // Expected
        }
        
        // 2. Unsupported schema version (99)
        var entriesBadSchema = try DosarZipEngine.unpackArchive(archiveBytes)
        for i in 0..<entriesBadSchema.count {
            if entriesBadSchema[i].path == "manifest.json" {
                let origStr = String(data: entriesBadSchema[i].data, encoding: .utf8)!
                let tamperedStr = origStr.replacingOccurrences(of: "\"schemaVersion\" : 2", with: "\"schemaVersion\" : 99")
                entriesBadSchema[i] = DosarZipEngine.Entry(path: "manifest.json", data: tamperedStr.data(using: .utf8)!)
            }
        }
        let badSchemaZip = try DosarZipEngine.createArchive(entries: entriesBadSchema)
        let badSchemaURL = tempDir.appendingPathComponent("bad_schema.dosar")
        try badSchemaZip.write(to: badSchemaURL)
        
        do {
            _ = try DossierArchiveService.shared.inspectArchive(at: badSchemaURL)
            throw TestAssertionError(message: "Schema version 99 must fail", file: #file, line: #line)
        } catch ArchiveError.unsupportedSchemaVersion(let v) {
            try assertEqual(v, 99)
        }
        
        // 3. Tampered payload: inspectArchive says isValidIntegrity == false, importArchive throws checksumMismatch
        var tamperedEntries = try DosarZipEngine.unpackArchive(archiveBytes)
        for i in 0..<tamperedEntries.count {
            if tamperedEntries[i].path == "data/assets.json" {
                let evilData = "[{\"id\":\"00000000-0000-0000-0000-000000000000\",\"name\":\"TAMPERED\"}]".data(using: .utf8)!
                tamperedEntries[i] = DosarZipEngine.Entry(path: "data/assets.json", data: evilData)
            }
        }
        let tamperedZip = try DosarZipEngine.createArchive(entries: tamperedEntries)
        let tamperedURL = tempDir.appendingPathComponent("tampered.dosar")
        try tamperedZip.write(to: tamperedURL)
        
        let insp = try DossierArchiveService.shared.inspectArchive(at: tamperedURL)
        try assertFalse(insp.isValidIntegrity, "Tampered file must report isValidIntegrity == false")
        
        do {
            _ = try DossierArchiveService.shared.importArchive(at: tamperedURL, mode: .merge, context: context)
            throw TestAssertionError(message: "Importing tampered archive must throw checksumMismatch", file: #file, line: #line)
        } catch ArchiveError.checksumMismatch(let file, _, _) {
            try assertEqual(file, "data/assets.json")
        }
    }
    
    // MARK: - 5. macOS /usr/bin/unzip Standard Tool Compatibility
    
    public static func testArchive_MacOSUnzipStandardToolCompatibility() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }
        
        let textData = "Manifest schema version 2 in Romanian: Dosar cu Sina arhivă standard.".data(using: .utf8)!
        let largeCompressible = String(repeating: "Compresie mare repetitivă PKZip standard ", count: 300).data(using: .utf8)!
        let binaryBytes = Data((0..<256).map { UInt8($0) })
        let romanianText = "Document cu caractere speciale: ș, ț, Ș, Ț, â, î, Â, Î.".data(using: .utf8)!
        let emptyData = Data()
        
        let entries = [
            DosarZipEngine.Entry(path: "manifest.json", data: textData),
            DosarZipEngine.Entry(path: "data/assets.json", data: largeCompressible),
            DosarZipEngine.Entry(path: "vault/sample.bin", data: binaryBytes),
            DosarZipEngine.Entry(path: "data/romanian.txt", data: romanianText),
            DosarZipEngine.Entry(path: "data/empty.txt", data: emptyData)
        ]
        
        let zipBytes = try DosarZipEngine.createArchive(entries: entries)
        let zipURL = tempDir.appendingPathComponent("test_unzip.zip")
        try zipBytes.write(to: zipURL)
        
        // 1. Run /usr/bin/unzip -t (test archive)
        let testProc = Process()
        testProc.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
        testProc.arguments = ["-t", zipURL.path]
        let testPipe = Pipe()
        testProc.standardOutput = testPipe
        testProc.standardError = testPipe
        try testProc.run()
        testProc.waitUntilExit()
        try assertEqual(testProc.terminationStatus, 0, "/usr/bin/unzip -t failed on DosarZipEngine archive!")
        
        // 2. Run /usr/bin/unzip -o -d <dest> and verify content match
        let destDir = tempDir.appendingPathComponent("extracted")
        let extractProc = Process()
        extractProc.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
        extractProc.arguments = ["-o", zipURL.path, "-d", destDir.path]
        try extractProc.run()
        extractProc.waitUntilExit()
        try assertEqual(extractProc.terminationStatus, 0, "/usr/bin/unzip extract failed!")
        
        try assertEqual(try Data(contentsOf: destDir.appendingPathComponent("manifest.json")), textData)
        try assertEqual(try Data(contentsOf: destDir.appendingPathComponent("data/assets.json")), largeCompressible)
        try assertEqual(try Data(contentsOf: destDir.appendingPathComponent("vault/sample.bin")), binaryBytes)
        try assertEqual(try Data(contentsOf: destDir.appendingPathComponent("data/romanian.txt")), romanianText)
        try assertEqual(try Data(contentsOf: destDir.appendingPathComponent("data/empty.txt")), emptyData)
        
        // 3. Reverse: Create zip with /usr/bin/zip, unpack with DosarZipEngine
        let toZipDir = tempDir.appendingPathComponent("to_zip")
        try FileManager.default.createDirectory(at: toZipDir, withIntermediateDirectories: true)
        try "Reverse zip check".write(to: toZipDir.appendingPathComponent("reverse.txt"), atomically: true, encoding: .utf8)
        let sysZipURL = tempDir.appendingPathComponent("system.zip")
        
        let zipProc = Process()
        zipProc.currentDirectoryURL = toZipDir
        zipProc.executableURL = URL(fileURLWithPath: "/usr/bin/zip")
        zipProc.arguments = ["-r", sysZipURL.path, "reverse.txt"]
        try zipProc.run()
        zipProc.waitUntilExit()
        try assertEqual(zipProc.terminationStatus, 0, "/usr/bin/zip failed!")
        
        let sysData = try Data(contentsOf: sysZipURL)
        let unpackedFromSys = try DosarZipEngine.unpackArchive(sysData)
        try assertEqual(unpackedFromSys.count, 1)
        try assertEqual(unpackedFromSys[0].path, "reverse.txt")
        try assertEqual(String(data: unpackedFromSys[0].data, encoding: .utf8), "Reverse zip check")
    }
    
    // MARK: - 6. Merge Semantics & Partial Payloads
    
    @MainActor
    public static func testArchive_MergeSemantics_OlderDiscardedNewerApplied() async throws {
        let schema = Schema([Asset.self, LifecycleEvent.self, ServiceItem.self, MeasurementLog.self, DocumentAttachment.self, DynamicField.self])
        let container = try ModelContainer(for: schema, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let context = container.mainContext
        
        let sharedAssetId = UUID()
        let t0 = Date(timeIntervalSince1970: 1700000000)
        let tLocal = Date(timeIntervalSince1970: 1700010000)
        let tOlder = Date(timeIntervalSince1970: 1700005000)
        let tNewer = Date(timeIntervalSince1970: 1700020000)
        
        // Local asset at tLocal
        let localAsset = Asset(id: sharedAssetId, name: "Local Version (tLocal)", category: .home, createdAt: t0, updatedAt: tLocal)
        context.insert(localAsset)
        try context.save()
        
        let encoder = JSONEncoder.dosarArchiveEncoder()
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }
        
        // 1. Older archive (tOlder < tLocal) -> Local must win
        let olderDTO = AssetDTO(id: sharedAssetId, name: "Older Archive Name", categoryRaw: AssetCategory.home.rawValue, iconName: "house", accentColorHex: "#007AFF", createdAt: t0, updatedAt: tOlder)
        let olderJSON = try encoder.encode([olderDTO])
        let olderManifest = DossierManifestV2(
            entityCounts: DossierManifestV2.EntityCounts(assets: 1, events: 0, serviceItems: 0, measurements: 0, dynamicFields: 0, attachments: 0),
            checksums: ["data/assets.json": DossierArchiveService.computeSHA256(of: olderJSON)]
        )
        let olderManifestJSON = try encoder.encode(olderManifest)
        let olderZip = try DosarZipEngine.createArchive(entries: [
            DosarZipEngine.Entry(path: "manifest.json", data: olderManifestJSON),
            DosarZipEngine.Entry(path: "data/assets.json", data: olderJSON)
        ])
        let olderURL = tempDir.appendingPathComponent("older.dosar")
        try olderZip.write(to: olderURL)
        
        let resOlder = try DossierArchiveService.shared.importArchive(at: olderURL, mode: .merge, context: context)
        try assertEqual(resOlder.assetsUpdated, 0, "Older archive asset must NOT overwrite newer local asset")
        let assetsAfterOlder = try context.fetch(FetchDescriptor<Asset>())
        try assertEqual(assetsAfterOlder.first?.name, "Local Version (tLocal)")
        
        // 2. Newer archive (tNewer > tLocal) -> Archive must win
        let newerDTO = AssetDTO(id: sharedAssetId, name: "Newer Archive Wins Name", categoryRaw: AssetCategory.home.rawValue, iconName: "house", accentColorHex: "#007AFF", createdAt: t0, updatedAt: tNewer)
        let newerJSON = try encoder.encode([newerDTO])
        let newerManifest = DossierManifestV2(
            entityCounts: DossierManifestV2.EntityCounts(assets: 1, events: 0, serviceItems: 0, measurements: 0, dynamicFields: 0, attachments: 0),
            checksums: ["data/assets.json": DossierArchiveService.computeSHA256(of: newerJSON)]
        )
        let newerManifestJSON = try encoder.encode(newerManifest)
        let newerZip = try DosarZipEngine.createArchive(entries: [
            DosarZipEngine.Entry(path: "manifest.json", data: newerManifestJSON),
            DosarZipEngine.Entry(path: "data/assets.json", data: newerJSON)
        ])
        let newerURL = tempDir.appendingPathComponent("newer.dosar")
        try newerZip.write(to: newerURL)
        
        let resNewer = try DossierArchiveService.shared.importArchive(at: newerURL, mode: .merge, context: context)
        try assertEqual(resNewer.assetsUpdated, 1, "Newer archive asset MUST update local asset")
        let assetsAfterNewer = try context.fetch(FetchDescriptor<Asset>())
        try assertEqual(assetsAfterNewer.first?.name, "Newer Archive Wins Name")
    }
    
    // MARK: - 7. Zero & Negative Cash Flow Guards
    
    public static func testFinancialPulse_ZeroAndNegativeCashFlowGuards() {
        let calendar = Calendar.current
        let refDate = Date()
        let startOfRefDate = calendar.startOfDay(for: refDate)
        
        // Empty state
        let emptyPulse = FinancialPulseCalculator.calculatePulse(assets: [], referenceDate: refDate)
        try! assertEqual(emptyPulse.cashFlow.days30Committed, 0.0)
        try! assertEqual(emptyPulse.cashFlow.days60Committed, 0.0)
        try! assertEqual(emptyPulse.cashFlow.days90Committed, 0.0)
        try! assertEqual(emptyPulse.cashFlow.prior30DaysActual, 0.0)
        try! assertEqual(emptyPulse.spendBreakdown.recurringAnnualTotal, 0.0)
        try! assertEqual(emptyPulse.subscriptionPulse.totalMonthlyBurnRate, 0.0)
        try! assertTrue(emptyPulse.rankedTCO.isEmpty)
        try! assertEqual(emptyPulse.utilityCurves.count, 12)
        
        // Negative cost event (-500 RON)
        let asset = Asset(name: "Test Asset", category: .home)
        let negEvent = LifecycleEvent(title: "Refund Event", dueDate: calendar.date(byAdding: .day, value: 5, to: startOfRefDate)!, cost: -500.0)
        negEvent.asset = asset
        
        let cf = FinancialPulseCalculator.computeCashFlowForecast(
            events: [negEvent],
            serviceItems: [],
            measurements: [],
            referenceDate: refDate,
            startOfRefDate: startOfRefDate,
            calendar: calendar
        )
        try! assertEqual(cf.days30Committed, 0.0, "Negative cost must be guarded and excluded from committed spend")
        try! assertTrue(cf.upcomingEventsNext30Days.isEmpty)
    }
    
    // MARK: - 8. Exact Day Boundaries
    
    public static func testFinancialPulse_ExactDayBoundaries() {
        let calendar = Calendar.current
        let refDate = calendar.date(from: DateComponents(year: 2026, month: 6, day: 15, hour: 12, minute: 0))!
        let startOfRefDate = calendar.startOfDay(for: refDate)
        let asset = Asset(name: "Boundary Asset", category: .vehicle)
        
        let evDay0 = LifecycleEvent(title: "Day 0", dueDate: startOfRefDate, cost: 100.0)
        evDay0.asset = asset
        
        let d30Date = calendar.date(byAdding: .day, value: 30, to: startOfRefDate)!
        let evDay30 = LifecycleEvent(title: "Day 30", dueDate: d30Date, cost: 200.0)
        evDay30.asset = asset
        
        let d31Date = calendar.date(byAdding: .day, value: 31, to: startOfRefDate)!
        let evDay31 = LifecycleEvent(title: "Day 31", dueDate: d31Date, cost: 300.0)
        evDay31.asset = asset
        
        let d60Date = calendar.date(byAdding: .day, value: 60, to: startOfRefDate)!
        let evDay60 = LifecycleEvent(title: "Day 60", dueDate: d60Date, cost: 400.0)
        evDay60.asset = asset
        
        let d90Date = calendar.date(byAdding: .day, value: 90, to: startOfRefDate)!
        let evDay90 = LifecycleEvent(title: "Day 90", dueDate: d90Date, cost: 500.0)
        evDay90.asset = asset
        
        let d91Date = calendar.date(byAdding: .day, value: 91, to: startOfRefDate)!
        let evDay91 = LifecycleEvent(title: "Day 91", dueDate: d91Date, cost: 600.0)
        evDay91.asset = asset
        
        let allEvents = [evDay0, evDay30, evDay31, evDay60, evDay90, evDay91]
        let cf = FinancialPulseCalculator.computeCashFlowForecast(
            events: allEvents,
            serviceItems: [],
            measurements: [],
            referenceDate: refDate,
            startOfRefDate: startOfRefDate,
            calendar: calendar
        )
        
        // 30d: Day 0 (100) + Day 30 (200) = 300
        try! assertEqual(cf.days30Committed, 300.0)
        // 60d: Day 0 (100) + Day 30 (200) + Day 31 (300) + Day 60 (400) = 1000
        try! assertEqual(cf.days60Committed, 1000.0)
        // 90d: 1000 + Day 90 (500) = 1500
        try! assertEqual(cf.days90Committed, 1500.0)
        // Day 91 must not be included
        try! assertFalse(cf.upcomingEventsNext90Days.contains(where: { $0.title == "Day 91" }))
    }
    
    // MARK: - 9. Leap Year & Bucharest DST
    
    public static func testFinancialPulse_LeapYearAndBucharestDST() {
        var bucharestCal = Calendar(identifier: .gregorian)
        bucharestCal.timeZone = TimeZone(identifier: "Europe/Bucharest")!
        
        // Leap year 2024: Feb 28 + 30 days = March 29
        let feb28 = bucharestCal.date(from: DateComponents(year: 2024, month: 2, day: 28, hour: 10))!
        let feb28Start = bucharestCal.startOfDay(for: feb28)
        let d30Leap = bucharestCal.date(byAdding: .day, value: 30, to: feb28Start)!
        let leapComps = bucharestCal.dateComponents([.year, .month, .day], from: d30Leap)
        try! assertEqual(leapComps.year, 2024)
        try! assertEqual(leapComps.month, 3)
        try! assertEqual(leapComps.day, 29)
        
        // Spring DST transition (March 29, 2026, 23h day)
        let march1 = bucharestCal.date(from: DateComponents(year: 2026, month: 3, day: 1, hour: 10))!
        let march1Start = bucharestCal.startOfDay(for: march1)
        let d30Spring = bucharestCal.date(byAdding: .day, value: 30, to: march1Start)!
        let springComps = bucharestCal.dateComponents([.year, .month, .day], from: d30Spring)
        try! assertEqual(springComps.year, 2026)
        try! assertEqual(springComps.month, 3)
        try! assertEqual(springComps.day, 31)
        
        // Fall DST transition (October 25, 2026, 25h day)
        let oct1 = bucharestCal.date(from: DateComponents(year: 2026, month: 10, day: 1, hour: 10))!
        let oct1Start = bucharestCal.startOfDay(for: oct1)
        let d30Fall = bucharestCal.date(byAdding: .day, value: 30, to: oct1Start)!
        let fallComps = bucharestCal.dateComponents([.year, .month, .day], from: d30Fall)
        try! assertEqual(fallComps.year, 2026)
        try! assertEqual(fallComps.month, 10)
        try! assertEqual(fallComps.day, 31)
    }
    
    // MARK: - 10. Subscription Cycles & Trimestrial Isolation
    
    public static func testFinancialPulse_SubscriptionBillingCyclesAndMath() {
        let weekly = FinancialPulseCalculator.normalizeToMonthlyRate(amount: 50.0, cycle: "săptămânal")
        try! assertAlmostEqual(weekly, 50.0 * 52.0 / 12.0)
        
        let trim = FinancialPulseCalculator.normalizeToMonthlyRate(amount: 300.0, cycle: "trimestrial")
        try! assertAlmostEqual(trim, 100.0)
        
        let sem = FinancialPulseCalculator.normalizeToMonthlyRate(amount: 600.0, cycle: "semestrial")
        try! assertAlmostEqual(sem, 100.0)
        
        let anual = FinancialPulseCalculator.normalizeToMonthlyRate(amount: 1200.0, cycle: "anual")
        try! assertAlmostEqual(anual, 100.0)
        
        // Trimestrial must not trigger trial
        let trimAsset = Asset(name: "Abonament Trimestrial Fitness", category: .subscriptions)
        trimAsset.recurringAmount = 350.0
        trimAsset.billingCycle = "Trimestrial"
        let isTrial = FinancialPulseCalculator.isFreeTrialSubscription(asset: trimAsset, event: nil, originalAmount: 350.0)
        try! assertFalse(isTrial, "Word 'trimestrial' must not trigger 'trial' classification")
    }
    
    // MARK: - 11. Free Trial Alerts & Retention Windows
    
    public static func testFinancialPulse_FreeTrialAlertsAndRetentionWindows() {
        let calendar = Calendar.current
        let refDate = Date()
        let startOfRefDate = calendar.startOfDay(for: refDate)
        
        // Free trial ending today (day 0)
        let trialToday = Asset(name: "Trial Ending Today", category: .subscriptions)
        trialToday.recurringAmount = 0.0
        trialToday.contractEndDate = startOfRefDate
        
        // Free trial ended yesterday (day -1)
        let trialYesterday = Asset(name: "Trial Ended Yesterday", category: .subscriptions)
        trialYesterday.recurringAmount = 0.0
        trialYesterday.contractEndDate = calendar.date(byAdding: .day, value: -1, to: startOfRefDate)!
        
        // Paid telecom ending in 45 days (retention active)
        let telecom45 = Asset(name: "Abonament Digi Mobil", category: .subscriptions)
        telecom45.recurringAmount = 45.0
        telecom45.contractEndDate = calendar.date(byAdding: .day, value: 45, to: startOfRefDate)!
        
        let pulse = FinancialPulseCalculator.computeSubscriptionBurnRate(
            assets: [trialToday, trialYesterday, telecom45],
            events: [],
            referenceDate: refDate,
            startOfRefDate: startOfRefDate,
            calendar: calendar
        )
        
        let itemToday = pulse.items.first(where: { $0.name == "Trial Ending Today" })!
        try! assertTrue(itemToday.isTrialConvertingSoon, "Trial ending today must flag isTrialConvertingSoon")
        
        let itemYesterday = pulse.items.first(where: { $0.name == "Trial Ended Yesterday" })!
        try! assertFalse(itemYesterday.isTrialConvertingSoon, "Trial ended yesterday must NOT flag isTrialConvertingSoon")
        
        let itemDigi = pulse.items.first(where: { $0.name == "Abonament Digi Mobil" })!
        try! assertTrue(itemDigi.isRetentionWindowActive, "Telecom contract in 45 days must be in retention window")
        try! assertFalse(itemDigi.isFreeTrial, "Paid telecom contract is not free trial")
    }
    
    // MARK: - 12. Utility Deltas Missing Previous & Negative Deltas
    
    public static func testFinancialPulse_UtilityDeltasMissingPreviousAndWrapAround() {
        let calendar = Calendar.current
        let refDate = Date()
        
        // 1. Normal reading: prev 1000, curr 1250 -> delta 250, cost 200
        let mNormal = MeasurementLog(
            domain: .electricityMeter,
            metricName: "Index Contor",
            value: 1250.0,
            recordedAt: refDate,
            previousValue: 1000.0,
            unitPrice: 0.80
        )
        try! assertEqual(mNormal.deltaFromPrevious, 250.0)
        try! assertEqual(mNormal.estimatedCost, 200.0)
        
        // 2. Missing previous reading: prev nil, curr 500 -> delta nil, cost nil
        let mMissing = MeasurementLog(
            domain: .electricityMeter,
            metricName: "Index Contor Initial",
            value: 500.0,
            recordedAt: refDate,
            previousValue: nil,
            unitPrice: 0.80
        )
        try! assertNil(mMissing.deltaFromPrevious)
        try! assertNil(mMissing.estimatedCost)
        
        // 3. Negative delta (meter wrap-around or user typo): prev 500, curr 450 -> delta -50, estimatedCost nil
        let mNegative = MeasurementLog(
            domain: .electricityMeter,
            metricName: "Index Contor Wrap",
            value: 450.0,
            recordedAt: refDate,
            previousValue: 500.0,
            unitPrice: 0.80
        )
        try! assertEqual(mNegative.deltaFromPrevious, -50.0)
        try! assertNil(mNegative.estimatedCost)
        
        // 4. Seasonal curves with these measurements
        let curves = FinancialPulseCalculator.computeSeasonalUtilityCurves(
            measurements: [mNormal, mNegative],
            referenceDate: refDate,
            calendar: calendar
        )
        let currCurve = curves.last!
        try! assertEqual(currCurve.electricityKWh, 200.0, "Net electricity kWh should be 250 + (-50) = 200.0")
    }
}
