import Foundation
import SwiftData
import Testing
@testable import DosarCuSina

/// The golden fixtures in `shared/fixtures`, zipped the way any platform would.
enum Fixtures {
    static var root: URL {
        URL(filePath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appending(path: "shared/fixtures")
    }

    static func archive(_ relativePath: String, editing edit: ((inout [String: Data]) -> Void)? = nil) throws -> Data {
        let base = root.appending(path: relativePath)
        var files: [String: Data] = [:]
        let enumerator = FileManager.default.enumerator(at: base, includingPropertiesForKeys: [.isRegularFileKey])
        while let url = enumerator?.nextObject() as? URL {
            guard (try url.resourceValues(forKeys: [.isRegularFileKey])).isRegularFile == true else { continue }
            let relative = String(url.standardizedFileURL.path().dropFirst(base.standardizedFileURL.path().count)).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            files[relative] = try Data(contentsOf: url)
        }
        edit?(&files)
        let entries = files.keys.sorted().map { DosarZipEngine.Entry(path: $0, data: files[$0]!) }
        return try DosarZipEngine.createArchive(entries: entries)
    }
}

@MainActor
@Suite("Archive v3")
struct ArchiveTests {
    let calendar = Calendar.bucharest

    @Test func goldenV3FixtureImportsCompletely() throws {
        let container = try makeInMemoryContainer()
        let service = DossierArchiveService(container: container, calendar: calendar)
        let data = try Fixtures.archive("dosar-v3/household")

        let summary = try service.inspect(data)
        #expect(summary.schemaVersion == 3)
        #expect(summary.counts.assets == 2)

        try service.importArchive(data, mode: .replace)
        let context = ModelContext(container)
        let assets = try context.fetch(FetchDescriptor<Asset>(sortBy: [SortDescriptor(\.name)]))
        #expect(assets.map(\.name) == ["Barca de pe lac", "VW Golf"])

        let car = try #require(assets.last)
        #expect(car.value("vehicle.plate") == .text("B-123-ABC"))
        let itp = try #require(car.obligations?.first { $0.title == "ITP" })
        #expect(itp.recurrence == .legal(.vehicleITP))
        #expect(itp.dueDay(in: calendar) == CalendarDay("2028-03-01"))
        #expect(itp.history.first?.cost == Money(Decimal(string: "175.5")!))
        #expect(itp.history.first?.serviceItems?.first?.name == "Plăcuțe de frână față")
        #expect(itp.history.first?.attachments?.first?.fileData.map { String(decoding: $0, as: UTF8.self) }?.hasPrefix("Inspecție") == true)

        let rca = try #require(car.obligations?.first { $0.title == "RCA" })
        #expect(rca.reminderMinuteOfDay == 480)
        #expect(rca.reference == "POL-000001")

        let templates = try TemplateStore(context: context).templatesByKey()
        let boats = try #require(templates["custom.0b6c6f43-6c1e-4d1a-9c55-7d3b4f1f2a10"])
        #expect(boats.isCustom)
        #expect(boats.sections.first?.fields.count == 2)
        #expect(boats.blueprints.first?.recurrence == .metric(every: 100, unit: "h", fallback: .years(1)))
        let vehicle = try #require(templates[BuiltInTemplates.Key.vehicle])
        #expect(vehicle.isOnHome == false, "Household preferences travel with the archive")
        #expect(!vehicle.sections.isEmpty, "Built-in definitions come from this app's catalog")
        #expect(templates.count == BuiltInTemplates.all.count + 1, "Built-ins missing from the archive are installed")
    }

    @Test func exportThenImportReproducesTheHousehold() throws {
        let source = try makeInMemoryContainer()
        let context = ModelContext(source)
        try TemplateStore(context: context).installBuiltIns()
        try ExampleDataService(context: context, calendar: calendar, now: { noon("2026-11-02") }).loadExamples()
        let custom = try TemplateStore(context: context).createCustom(
            name: "Bărci", symbol: "sailboat.fill", tint: .teal,
            sections: [FieldSection(key: "boat", title: "Barcă", fields: [FieldDefinition(key: "boat.name", label: "Nume", type: .text)])]
        )
        let boat = Asset(name: "Barca", templateKey: custom.key)
        boat.photoData = Data([0xFF, 0xD8, 0xFF])
        context.insert(boat)
        let attachment = Attachment(fileName: "factura.pdf", contentType: "com.adobe.pdf", data: Data("%PDF-1.7 test".utf8))
        context.insert(attachment)
        attachment.asset = boat
        try context.save()

        let data = try DossierArchiveService(container: source, calendar: calendar).exportData(exportedAt: noon("2026-11-02"))

        let target = try makeInMemoryContainer()
        try DossierArchiveService(container: target, calendar: calendar).importArchive(data, mode: .replace)
        let copy = ModelContext(target)

        func signature(_ context: ModelContext) throws -> [String] {
            try context.fetch(FetchDescriptor<Obligation>()).map {
                "\($0.id)|\($0.title)|\($0.dueDay(in: calendar))|\($0.statusRaw)|\(String(describing: $0.recurrence))|\(String(describing: $0.estimatedCost))|\($0.asset?.id.uuidString ?? "-")"
            }.sorted()
        }
        #expect(try signature(copy) == signature(context))
        #expect(try copy.fetchCount(FetchDescriptor<Asset>()) == context.fetchCount(FetchDescriptor<Asset>()))
        #expect(try copy.fetchCount(FetchDescriptor<MeasurementLog>()) == context.fetchCount(FetchDescriptor<MeasurementLog>()))
        #expect(try copy.fetchCount(FetchDescriptor<Completion>()) == context.fetchCount(FetchDescriptor<Completion>()))
        let copiedBoat = try #require(try copy.fetch(FetchDescriptor<Asset>()).first { $0.name == "Barca" })
        #expect(copiedBoat.photoData == Data([0xFF, 0xD8, 0xFF]))
        #expect(copiedBoat.attachments?.first?.fileData == Data("%PDF-1.7 test".utf8))
        #expect(try TemplateStore(context: copy).template(forKey: custom.key)?.name == "Bărci")
    }

    @Test func exportedFilesFollowTheContract() throws {
        let container = try makeInMemoryContainer()
        let context = ModelContext(container)
        try TemplateStore(context: context).installBuiltIns()
        try ExampleDataService(context: context, calendar: calendar, now: { noon("2026-11-02") }).loadExamples()
        let data = try DossierArchiveService(container: container, calendar: calendar).exportData(exportedAt: noon("2026-11-02"))
        let entries = Dictionary(uniqueKeysWithValues: try DosarZipEngine.unpackArchive(data).map { ($0.path, $0.data) })

        let manifest = try #require(entries["manifest.json"]).utf8String
        #expect(manifest.contains("\"schemaVersion\" : 3"))
        #expect(manifest.contains("\"exportedAt\" : \"2026-11-02T10:00:00Z\""))
        let obligations = try #require(entries["data/obligations.json"]).utf8String
        #expect(obligations.range(of: #""dueDate" : "\d{4}-\d{2}-\d{2}""#, options: .regularExpression) != nil, "Due dates are calendar days")
        #expect(obligations.range(of: #""id" : "[0-9a-f-]{36}""#, options: .regularExpression) != nil, "Identifiers are lowercase")
        #expect(obligations.range(of: #""amount" : "\d+(\.\d+)?""#, options: .regularExpression) != nil, "Money is a decimal string")
        for path in DossierV3.Path.dataFiles {
            #expect(entries[path] != nil, "\(path) is always written")
        }
    }

    @Test func mergeKeepsTheNewerEdit() throws {
        let container = try makeInMemoryContainer()
        let service = DossierArchiveService(container: container, calendar: calendar)
        try service.importArchive(try Fixtures.archive("dosar-v3/household"), mode: .replace)

        let context = ModelContext(container)
        let car = try #require(try context.fetch(FetchDescriptor<Asset>()).first { $0.name == "VW Golf" })
        car.name = "VW Golf editat"
        car.updatedAt = noon("2026-10-01")
        let local = Asset(name: "Doar aici", templateKey: BuiltInTemplates.Key.other)
        context.insert(local)
        try context.save()

        let result = try service.importArchive(try Fixtures.archive("dosar-v3/household"), mode: .merge)
        #expect(result.skipped > 0)
        let names = Set(try ModelContext(container).fetch(FetchDescriptor<Asset>()).map(\.name))
        #expect(names == ["VW Golf editat", "Barca de pe lac", "Doar aici"])
    }

    @Test func aFailedImportLeavesEverythingAsItWas() throws {
        let container = try makeInMemoryContainer()
        let context = ModelContext(container)
        try TemplateStore(context: context).installBuiltIns()
        try ExampleDataService(context: context, calendar: calendar, now: { noon("2026-11-02") }).loadExamples()
        let before = try context.fetchCount(FetchDescriptor<Asset>())
        let service = DossierArchiveService(container: container, calendar: calendar)

        // A record that can't be read surfaces only after the replace has started deleting.
        let broken = try Fixtures.archive("dosar-v3/household") { files in
            let text = files["data/assets.json"]!.utf8String.replacingOccurrences(of: "8a2b3c4d-5e6f-4a7b-8c9d-0e1f2a3b4c52", with: "not-an-id")
            files["data/assets.json"] = Data(text.utf8)
            var manifest = try! JSONSerialization.jsonObject(with: files["manifest.json"]!) as! [String: Any]
            var checksums = manifest["checksums"] as! [String: String]
            checksums["data/assets.json"] = DossierArchiveReader.sha256(files["data/assets.json"]!)
            manifest["checksums"] = checksums
            files["manifest.json"] = try! JSONSerialization.data(withJSONObject: manifest)
        }
        #expect(throws: ArchiveError.brokenReference("data/assets.json")) {
            try service.importArchive(broken, mode: .replace)
        }
        #expect(try ModelContext(container).fetchCount(FetchDescriptor<Asset>()) == before)
    }

    @Test func checksumsAreEnforced() throws {
        let service = DossierArchiveService(container: try makeInMemoryContainer(), calendar: calendar)
        let tampered = try Fixtures.archive("dosar-v3/household") { files in
            files["data/obligations.json"] = Data(files["data/obligations.json"]!.utf8String.replacingOccurrences(of: "\"180\"", with: "\"18\"").utf8)
        }
        #expect(throws: ArchiveError.checksumMismatch("data/obligations.json")) { try service.inspect(tampered) }

        let extra = try Fixtures.archive("dosar-v3/household") { files in
            files["vault/extra.bin"] = Data([1, 2, 3])
        }
        #expect(throws: ArchiveError.unlistedFile("vault/extra.bin")) { try service.inspect(extra) }

        let missing = try Fixtures.archive("dosar-v3/household") { files in
            files["vault/6b7c8d9e-0f1a-4b2c-9d4e-5f6a7b8c9db8.txt"] = nil
        }
        #expect(throws: ArchiveError.missingFile("vault/6b7c8d9e-0f1a-4b2c-9d4e-5f6a7b8c9db8.txt")) { try service.inspect(missing) }
    }

    @Test func newerSchemaVersionsAreRefusedWithAClearReason() throws {
        let future = try DosarZipEngine.createArchive(entries: [
            .init(path: "manifest.json", data: Data(#"{"format":"com.ar.dosarcusina.dossier","schemaVersion":9}"#.utf8)),
        ])
        #expect(throws: ArchiveError.unsupportedVersion(9)) { try DossierArchiveReader.read(future) }
        let other = try DosarZipEngine.createArchive(entries: [.init(path: "readme.txt", data: Data("hi".utf8))])
        #expect(throws: ArchiveError.notADossier) { try DossierArchiveReader.read(other) }
    }
}

@MainActor
@Suite("Archive v2 compatibility")
struct ArchiveV2Tests {
    @Test func firstGenerationBackupsStillImport() throws {
        let container = try makeInMemoryContainer()
        try DossierArchiveService(container: container, calendar: .bucharest).importArchive(try Fixtures.archive("dosar-v2/ios-export"), mode: .replace)
        let context = ModelContext(container)
        let assets = try context.fetch(FetchDescriptor<Asset>(sortBy: [SortDescriptor(\.name)]))
        #expect(assets.map(\.name) == ["Dacia Logan", "Mașina de spălat"])

        let car = assets[0]
        #expect(car.templateKey == BuiltInTemplates.Key.vehicle)
        #expect(car.value("vehicle.plate") == .text("CJ-12-XYZ"))
        #expect(car.value("vehicle.powerHp") == .number(110))
        #expect(car.notes?.contains("Hotel roți: Service exemplu") == true, "Custom fields are kept in the notes")

        let rca = try #require(car.obligations?.first { $0.title == "RCA" })
        #expect(rca.kind == .insurance)
        #expect(rca.recurrence == .interval(.years(1), anchor: .dueDate))
        let itp = try #require(car.obligations?.first { $0.title == "ITP" })
        #expect(itp.status == .done)
        #expect(itp.history.first?.cost == Money(160))
        #expect(itp.attachments?.count == 1)

        let washer = assets[1]
        #expect(washer.templateKey == BuiltInTemplates.Key.warranty)
        #expect(washer.value("warranty.expiry") == .date(CalendarDay("2027-06-15")))
        #expect(car.measurements?.first?.kind == .odometer)
    }
}

@Suite("Zip engine")
struct ZipEngineTests {
    @Test func roundTripsStoredAndCompressedEntries() throws {
        let entries = [
            DosarZipEngine.Entry(path: "manifest.json", data: Data(String(repeating: "{\"a\":1}", count: 500).utf8)),
            DosarZipEngine.Entry(path: "vault/photo.jpg", data: Data((0..<4_096).map { UInt8($0 % 251) })),
        ]
        let unpacked = try DosarZipEngine.unpackArchive(try DosarZipEngine.createArchive(entries: entries))
        #expect(unpacked.map(\.path) == entries.map(\.path))
        #expect(unpacked.map(\.data) == entries.map(\.data))
    }

    @Test("Entry paths must stay inside the archive", arguments: ["../x", "a/../../x", "/abs", "a\\b", "C:/x", "a//b", "./a", ""])
    func rejectsUnsafePaths(path: String) {
        #expect(!DosarZipEngine.isSafeEntryPath(path))
        #expect(throws: DosarZipEngine.ZipError.self) {
            try DosarZipEngine.createArchive(entries: [.init(path: path, data: Data())])
        }
    }

    @Test func acceptsNormalPaths() {
        for path in ["manifest.json", "data/assets.json", "vault/photos/a.jpg", "vault/"] {
            #expect(DosarZipEngine.isSafeEntryPath(path))
        }
    }

    @Test func enforcesSizeLimits() throws {
        let archive = try DosarZipEngine.createArchive(entries: [
            .init(path: "a.bin", data: Data(count: 10_000)),
            .init(path: "b.bin", data: Data(count: 10_000)),
        ])
        let tight = DosarZipEngine.Limits(maxEntries: 10, maxEntryBytes: 5_000, maxTotalBytes: 100_000)
        #expect(throws: DosarZipEngine.ZipError.sizeLimitExceeded) { try DosarZipEngine.unpackArchive(archive, limits: tight) }
        let total = DosarZipEngine.Limits(maxEntries: 10, maxEntryBytes: 20_000, maxTotalBytes: 15_000)
        #expect(throws: DosarZipEngine.ZipError.sizeLimitExceeded) { try DosarZipEngine.unpackArchive(archive, limits: total) }
        let few = DosarZipEngine.Limits(maxEntries: 1, maxEntryBytes: 20_000, maxTotalBytes: 100_000)
        #expect(throws: DosarZipEngine.ZipError.sizeLimitExceeded) { try DosarZipEngine.unpackArchive(archive, limits: few) }
    }

    @Test func detectsDamagedData() throws {
        var archive = try DosarZipEngine.createArchive(entries: [.init(path: "a.txt", data: Data(repeating: 65, count: 64))])
        // Flip a byte inside the stored payload (after the 30-byte local header and the name).
        archive[30 + 5 + 2] ^= 0xFF
        #expect(throws: DosarZipEngine.ZipError.self) { try DosarZipEngine.unpackArchive(archive) }
        #expect(throws: DosarZipEngine.ZipError.invalidZipArchive) { try DosarZipEngine.unpackArchive(Data(count: 10)) }
    }
}

private extension Data {
    var utf8String: String { String(decoding: self, as: UTF8.self) }
}
