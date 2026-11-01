import Foundation
import SwiftData
import CryptoKit

public final class DossierArchiveServiceTests {
    @MainActor
    public static func runAll() async -> TestSuiteResult {
        let startTime = Date()
        var passed = 0
        var failed = 0
        var failures: [TestFailure] = []
        
        let tests: [(String, () async throws -> Void)] = [
            ("testZipEngine_RoundTrip_DeflateAndStore", testZipEngine_RoundTrip_DeflateAndStore),
            ("testZipEngine_CRC32_Validation", testZipEngine_CRC32_Validation),
            ("testZipEngine_ZipSlipSecurityGuard", testZipEngine_ZipSlipSecurityGuard),
            ("testExportHouseholdArchive_ProducesStandardDosar", testExportHouseholdArchive_ProducesStandardDosar),
            ("testManifestV2_SHA256_IntegrityVerification", testManifestV2_SHA256_IntegrityVerification),
            ("testInspectArchive_DetectsTamperedFile", testInspectArchive_DetectsTamperedFile),
            ("testImportArchive_CleanRestoreMode", testImportArchive_CleanRestoreMode),
            ("testImportArchive_MergeMode_NewerWins", testImportArchive_MergeMode_NewerWins)
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
            suiteName: "DossierArchiveServiceTests",
            passed: passed,
            failed: failed,
            failures: failures,
            duration: duration
        )
    }
    
    // MARK: - Test Cases
    
    public static func testZipEngine_RoundTrip_DeflateAndStore() throws {
        let file1Content = "Manifest schema version 2 in Romanian: Dosar cu Sina arhivă standard.".data(using: .utf8)!
        let file2Content = String(repeating: "Large compressible text block with repetitive content 1234567890 ", count: 200).data(using: .utf8)!
        let file3Content = Data((0..<255).map { UInt8($0) })
        
        let entries = [
            DosarZipEngine.Entry(path: "manifest.json", data: file1Content),
            DosarZipEngine.Entry(path: "data/assets.json", data: file2Content),
            DosarZipEngine.Entry(path: "vault/sample.bin", data: file3Content)
        ]
        
        let zipBytes = try DosarZipEngine.createArchive(entries: entries)
        try assertTrue(!zipBytes.isEmpty, "Zip archive should not be empty")
        
        let extracted = try DosarZipEngine.unpackArchive(zipBytes)
        try assertEqual(extracted.count, 3, "Extracted archive should contain exactly 3 entries")
        
        let map = Dictionary(uniqueKeysWithValues: extracted.map { ($0.path, $0.data) })
        try assertEqual(map["manifest.json"], file1Content, "manifest.json content must match original")
        try assertEqual(map["data/assets.json"], file2Content, "data/assets.json content must match original")
        try assertEqual(map["vault/sample.bin"], file3Content, "vault/sample.bin content must match original")
    }
    
    public static func testZipEngine_CRC32_Validation() throws {
        let text1 = "Hello World".data(using: .utf8)!
        let crc1 = DosarZipEngine.computeCRC32(text1)
        // Standard IEEE 802.3 CRC-32 for "Hello World" is 0x4A17B156
        try assertEqual(crc1, 0x4A17B156, "CRC-32 of 'Hello World' must equal 0x4A17B156")
        
        let textEmpty = Data()
        let crcEmpty = DosarZipEngine.computeCRC32(textEmpty)
        try assertEqual(crcEmpty, 0, "CRC-32 of empty data must equal 0")
    }
    
    public static func testZipEngine_ZipSlipSecurityGuard() throws {
        let maliciousEntry = DosarZipEngine.Entry(path: "../escape.txt", data: "malicious".data(using: .utf8)!)
        do {
            _ = try DosarZipEngine.createArchive(entries: [maliciousEntry])
            throw TestAssertionError(message: "Should have thrown pathTraversalDetected", file: #file, line: #line)
        } catch DosarZipEngine.ZipError.pathTraversalDetected {
            // Expected
        }
    }
    
    @MainActor
    public static func testExportHouseholdArchive_ProducesStandardDosar() async throws {
        let schema = Schema([Asset.self, LifecycleEvent.self, ServiceItem.self, MeasurementLog.self, DocumentAttachment.self, DynamicField.self])
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: config)
        let context = container.mainContext
        
        let asset = Asset(name: "VW Golf 2018", category: .vehicle, iconName: "car.fill", accentColorHex: "#007AFF")
        asset.vin = "WVWZZZAUZJP123456"
        asset.licensePlate = "B-999-DOS"
        context.insert(asset)
        
        let field = DynamicField(key: "serie_sasiu_veche", label: "Serie Veche", fieldType: .text, stringValue: "ABC123456", asset: asset)
        context.insert(field)
        
        let event = LifecycleEvent(
            title: "Poliță Asigurare RCA",
            dueDate: Calendar.current.date(byAdding: .month, value: 6, to: Date())!,
            cost: 850.0,
            provider: "Groupama Asigurări"
        )
        event.asset = asset
        context.insert(event)
        
        let service = ServiceItem(
            name: "Revizie Ulei și Filtre",
            cost: 650.0,
            mileageAtService: 125000.0
        )
        service.asset = asset
        context.insert(service)
        
        let measurement = MeasurementLog(
            domain: .odometer,
            metricName: "Kilometraj",
            value: 125400.0,
            unit: "km"
        )
        measurement.asset = asset
        context.insert(measurement)
        
        let attData = "Continut scanat polita RCA oficiala".data(using: .utf8)!
        let att = DocumentAttachment(fileName: "Polita_RCA_2026.pdf", fileExtension: "pdf", fileData: attData)
        att.asset = asset
        att.event = event
        context.insert(att)
        
        try context.save()
        
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }
        
        let archiveURL = try DossierArchiveService.shared.exportHouseholdArchive(context: context, targetDirectory: tempDir)
        try assertTrue(FileManager.default.fileExists(atPath: archiveURL.path), "Archive file must exist on disk")
        try assertTrue(archiveURL.pathExtension == "dosar", "Archive must have .dosar extension")
        
        let archiveBytes = try Data(contentsOf: archiveURL)
        let entries = try DosarZipEngine.unpackArchive(archiveBytes)
        let paths = Set(entries.map { $0.path })
        
        try assertTrue(paths.contains("manifest.json"), "Archive must contain manifest.json")
        try assertTrue(paths.contains("data/assets.json"), "Archive must contain data/assets.json")
        try assertTrue(paths.contains("data/events.json"), "Archive must contain data/events.json")
        try assertTrue(paths.contains("data/service_history.json"), "Archive must contain data/service_history.json")
        try assertTrue(paths.contains("data/measurements.json"), "Archive must contain data/measurements.json")
        try assertTrue(paths.contains("data/attachments_meta.json"), "Archive must contain data/attachments_meta.json")
        try assertTrue(paths.contains("opis.pdf"), "Archive must contain opis.pdf")
        try assertTrue(paths.contains("vault/\(att.id.uuidString).pdf"), "Archive must contain vault attachment")
    }
    
    @MainActor
    public static func testManifestV2_SHA256_IntegrityVerification() async throws {
        let schema = Schema([Asset.self, LifecycleEvent.self, ServiceItem.self, MeasurementLog.self, DocumentAttachment.self, DynamicField.self])
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: config)
        let context = container.mainContext
        
        let home = Asset(name: "Vila Sinaia", category: .home)
        context.insert(home)
        try context.save()
        
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }
        
        let archiveURL = try DossierArchiveService.shared.exportHouseholdArchive(context: context, targetDirectory: tempDir)
        let summary = try DossierArchiveService.shared.inspectArchive(at: archiveURL)
        
        try assertEqual(summary.manifest.schemaVersion, 2, "Manifest schema version must be 2")
        try assertEqual(summary.manifest.appName, "Dosar cu Șină")
        try assertEqual(summary.manifest.format, "com.ar.dosarcusina.dossier")
        try assertEqual(summary.manifest.entityCounts.assets, 1)
        try assertTrue(summary.isValidIntegrity, "Exported archive must have 100% valid SHA-256 integrity")
    }
    
    @MainActor
    public static func testInspectArchive_DetectsTamperedFile() async throws {
        let schema = Schema([Asset.self, LifecycleEvent.self, ServiceItem.self, MeasurementLog.self, DocumentAttachment.self, DynamicField.self])
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: config)
        let context = container.mainContext
        
        let asset = Asset(name: "Test Asset", category: .custom)
        context.insert(asset)
        try context.save()
        
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }
        
        let archiveURL = try DossierArchiveService.shared.exportHouseholdArchive(context: context, targetDirectory: tempDir)
        
        // Unpack, tamper with data/assets.json, and repack
        let archiveBytes = try Data(contentsOf: archiveURL)
        var entries = try DosarZipEngine.unpackArchive(archiveBytes)
        
        for i in 0..<entries.count {
            if entries[i].path == "data/assets.json" {
                let tamperedString = "[{\"name\": \"TAMPERED_INTRUSION\"}]"
                entries[i] = DosarZipEngine.Entry(path: "data/assets.json", data: tamperedString.data(using: .utf8)!)
            }
        }
        
        let tamperedBytes = try DosarZipEngine.createArchive(entries: entries)
        let tamperedURL = tempDir.appendingPathComponent("tampered.dosar")
        try tamperedBytes.write(to: tamperedURL)
        
        let summary = try DossierArchiveService.shared.inspectArchive(at: tamperedURL)
        try assertFalse(summary.isValidIntegrity, "Tampered file must fail SHA-256 validation")
        
        // Attempting import must throw checksumMismatch
        do {
            _ = try DossierArchiveService.shared.importArchive(at: tamperedURL, mode: .merge, context: context)
            throw TestAssertionError(message: "Should have failed with checksumMismatch", file: #file, line: #line)
        } catch ArchiveError.checksumMismatch {
            // Expected
        }
    }
    
    @MainActor
    public static func testImportArchive_CleanRestoreMode() async throws {
        // Source Container
        let schema = Schema([Asset.self, LifecycleEvent.self, ServiceItem.self, MeasurementLog.self, DocumentAttachment.self, DynamicField.self])
        let sourceContainer = try ModelContainer(for: schema, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let srcContext = sourceContainer.mainContext
        
        let origId = UUID()
        let asset = Asset(id: origId, name: "Apartament Pipera", category: .home)
        asset.address = "Sos. Pipera nr. 42"
        srcContext.insert(asset)
        
        let attData = "Certificat Energetic Clasa A".data(using: .utf8)!
        let att = DocumentAttachment(fileName: "CPE_Pipera.pdf", fileExtension: "pdf", fileData: attData)
        att.asset = asset
        srcContext.insert(att)
        try srcContext.save()
        
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }
        let archiveURL = try DossierArchiveService.shared.exportHouseholdArchive(context: srcContext, targetDirectory: tempDir)
        
        // Destination Container with different obsolete data
        let destContainer = try ModelContainer(for: schema, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let dstContext = destContainer.mainContext
        let obsoleteAsset = Asset(name: "Obsolete House To Delete", category: .custom)
        dstContext.insert(obsoleteAsset)
        try dstContext.save()
        
        let result = try DossierArchiveService.shared.importArchive(at: archiveURL, mode: .cleanRestore, context: dstContext)
        try assertEqual(result.assetsImported, 1)
        try assertEqual(result.attachmentsImported, 1)
        
        let restoredAssets = try dstContext.fetch(FetchDescriptor<Asset>())
        try assertEqual(restoredAssets.count, 1, "Clean restore must wipe previous local assets")
        try assertEqual(restoredAssets[0].id, origId, "Restored asset ID must match original")
        try assertEqual(restoredAssets[0].name, "Apartament Pipera")
        try assertEqual(restoredAssets[0].address, "Sos. Pipera nr. 42")
        
        let restoredAtts = try dstContext.fetch(FetchDescriptor<DocumentAttachment>())
        try assertEqual(restoredAtts.count, 1)
        try assertEqual(restoredAtts[0].fileName, "CPE_Pipera.pdf")
        try assertEqual(restoredAtts[0].fileData, attData, "Binary attachment must be restored bit-for-bit into vault")
    }
    
    @MainActor
    public static func testImportArchive_MergeMode_NewerWins() async throws {
        let schema = Schema([Asset.self, LifecycleEvent.self, ServiceItem.self, MeasurementLog.self, DocumentAttachment.self, DynamicField.self])
        let sourceContainer = try ModelContainer(for: schema, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let srcContext = sourceContainer.mainContext
        
        let sharedId = UUID()
        let olderDate = Date().addingTimeInterval(-3600)
        let assetArchive = Asset(
            id: sharedId,
            name: "Car Old Name",
            category: .vehicle,
            updatedAt: olderDate
        )
        srcContext.insert(assetArchive)
        try srcContext.save()
        
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }
        let archiveURL = try DossierArchiveService.shared.exportHouseholdArchive(context: srcContext, targetDirectory: tempDir)
        
        // Destination Container with newer local edits
        let destContainer = try ModelContainer(for: schema, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let dstContext = destContainer.mainContext
        let newerDate = Date()
        let assetLocal = Asset(
            id: sharedId,
            name: "Car Newer Local Name",
            category: .vehicle,
            updatedAt: newerDate
        )
        dstContext.insert(assetLocal)
        try dstContext.save()
        
        // Execute Merge
        let result = try DossierArchiveService.shared.importArchive(at: archiveURL, mode: .merge, context: dstContext)
        try assertEqual(result.assetsUpdated, 0, "Older archive asset must not overwrite newer local asset")
        
        let currentAssets = try dstContext.fetch(FetchDescriptor<Asset>())
        try assertEqual(currentAssets.count, 1)
        try assertEqual(currentAssets[0].name, "Car Newer Local Name", "Local newer name must be preserved in merge")
    }
}
