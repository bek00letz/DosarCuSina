import Foundation
import SwiftData
import Testing
@testable import DosarCuSina

/// A source that remembers the largest piece read from it.
private final class CountingSource: ArchiveByteSource {
    let inner: ArchiveByteSource
    private(set) var largestRead = 0
    init(_ inner: ArchiveByteSource) { self.inner = inner }
    var size: Int { inner.size }

    func read(at offset: Int, count: Int) throws -> Data {
        largestRead = max(largestRead, count)
        return try inner.read(at: offset, count: count)
    }
}

/// Whatever a backup writes, the same app puts back: one set of limits both ways, a file
/// written and read a piece at a time, whatever the binder's size.
@MainActor
@Suite("Backups that restore")
struct BackupsThatRestoreTests {
    let calendar = Calendar.bucharest

    /// A binder of `documents` documents, each with three pages and a thumbnail of their own.
    private func binder(documents: Int, pageBytes: Int = 2_048) throws -> ModelContainer {
        let container = try makeInMemoryContainer()
        let context = ModelContext(container)
        try TemplateStore(context: context).installBuiltIns()
        for index in 0..<documents {
            let attachment = Attachment(fileName: "pagina-\(index).heic", contentType: "public.heic", data: nil)
            attachment.title = "Act \(index)"
            attachment.thumbnailData = Self.bytes(seed: index, count: 256)
            context.insert(attachment)
            for page in 0..<3 {
                let stored = AttachmentPage(index: page, imageData: Self.bytes(seed: index * 3 + page, count: pageBytes))
                context.insert(stored)
                stored.attachment = attachment
            }
        }
        try context.save()
        return container
    }

    private static func bytes(seed: Int, count: Int) -> Data {
        var state = UInt64(truncatingIfNeeded: seed) &* 0x9E37_79B9_7F4A_7C15 &+ 1
        return Data((0..<count).map { _ in
            state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
            return UInt8(truncatingIfNeeded: state >> 33)
        })
    }

    private func writer(_ container: ModelContainer, limits: DosarZipEngine.Limits = .standard) -> DossierArchiveWriter {
        DossierArchiveWriter(container: container, calendar: calendar, appVersion: "1.0", exportedAt: noon("2026-11-10"), limits: limits)
    }

    // MARK: One set of limits

    @Test func exportAndImportReadTheSameLimits() throws {
        let export = DossierArchiveWriter(container: try makeInMemoryContainer(), calendar: calendar, appVersion: "1.0", exportedAt: Date())
        #expect(export.limits == DosarZipEngine.Limits.standard)
        #expect(DosarZipEngine.Writer(sink: MemoryByteSink()).limits == DosarZipEngine.Limits.standard)
        let zip = try DosarZipEngine.createArchive(entries: [.init(path: "a.txt", data: Data("Dosar".utf8))])
        #expect(try DosarZipEngine.Reader(source: MemoryByteSource(zip)).limits == DosarZipEngine.Limits.standard)
    }

    @Test func aBinderOfManyFilesComesBackWhole() throws {
        // 300 documents, 1 200 files: past what a batch reads, and every file back as it was.
        let container = try binder(documents: 300)
        let archive = try DossierArchiveService(container: container, calendar: calendar).exportData(exportedAt: noon("2026-11-10"))
        let target = try makeInMemoryContainer()
        try DossierArchiveService(container: target, calendar: calendar).importArchive(archive, mode: .replace)

        let context = ModelContext(target)
        let documents = try context.fetch(FetchDescriptor<Attachment>())
        #expect(documents.count == 300)
        #expect(try context.fetchCount(FetchDescriptor<AttachmentPage>()) == 900)
        let sample = try #require(documents.first { $0.title == "Act 217" })
        #expect(sample.orderedPages.map(\.imageData) == (0..<3).map { Self.bytes(seed: 217 * 3 + $0, count: 2_048) as Data? })
        #expect(sample.thumbnailData == Self.bytes(seed: 217, count: 256))
    }

    // MARK: A piece at a time

    @Test func aProtectedBackupIsWrittenAndReadAChunkAtATime() throws {
        let container = try binder(documents: 300)
        let file = MemoryByteSink()
        let sealed = try ArchiveEncryption.EncryptingSink(file, password: "parola-exemplu", iterations: 1_000)
        try writer(container).write(into: sealed)
        try sealed.finish()
        let chunk = ArchiveEncryption.defaultChunkSize + ArchiveEncryption.tagSize
        #expect(file.data.count > 2 * chunk, "Bigger than what is held at once")
        #expect(file.largestWrite <= chunk, "Never more than a chunk written at once")

        let source = CountingSource(MemoryByteSource(file.data))
        let folder = URL.temporaryDirectory.appending(path: "restore-test-\(UUID().uuidString)", directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: folder) }
        let package = try DossierArchiveReader.read(source, password: "parola-exemplu", limits: .standard, keeping: .extract(into: folder))
        #expect(package.attachments.count == 300)
        #expect(source.largestRead <= chunk, "Never more than a chunk read at once")
    }

    @Test func aPlainBackupIsReadAPieceAtATime() throws {
        let container = try binder(documents: 120, pageBytes: 8_192)
        let file = MemoryByteSink()
        try writer(container).write(into: file)
        #expect(file.data.count > 2 * DosarZipEngine.Reader.pieceSize)

        let source = CountingSource(MemoryByteSource(file.data))
        let summary = ArchiveSummary(try DossierArchiveReader.read(source, password: nil, limits: .standard, keeping: .checkOnly))
        #expect(summary.counts.attachments == 120)
        #expect(source.largestRead <= DosarZipEngine.Reader.pieceSize)
    }

    // MARK: What can't be put back is never written

    @Test func aDocumentTooBigForABackupIsNamedAndNoFileIsLeft() throws {
        let container = try makeInMemoryContainer()
        let context = ModelContext(container)
        let attachment = Attachment(fileName: "factura.pdf", contentType: "com.adobe.pdf", data: Data(repeating: 7, count: 2_000))
        attachment.title = "Factura mare"
        context.insert(attachment)
        try context.save()

        let folder = URL.temporaryDirectory.appending(path: "too-big-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appending(path: "copie.dosar")
        let small = DosarZipEngine.Limits(maxEntries: 100, maxEntryBytes: 1_000)
        #expect(throws: ArchiveError.documentTooLarge("Factura mare")) {
            try writer(container, limits: small).write(to: url, password: nil)
        }
        #expect(try FileManager.default.contentsOfDirectory(atPath: folder.path(percentEncoded: false)).isEmpty, "No file, not even half of one")
        #expect(ArchiveError.documentTooLarge("Factura mare").errorDescription?.contains("Factura mare") == true)
    }

    // MARK: Password rounds

    @Test func onlyTheRoundsThisAppWritesAreAccepted() throws {
        #expect(ArchiveEncryption.acceptedIterations.contains(ArchiveEncryption.defaultIterations), "Every protected backup made so far opens")
        #expect(ArchiveEncryption.acceptedIterations.upperBound <= 2 * ArchiveEncryption.defaultIterations)

        let plain = try DosarZipEngine.createArchive(entries: [.init(path: "a.txt", data: Data("Dosar".utf8))])
        var sealed = try ArchiveEncryption.encrypt(plain, password: "parola-exemplu", iterations: 1_000, chunkSize: 1_024)
        // The rounds sit after the 8-byte mark and the two version bytes, big-endian.
        let tooMany = ArchiveEncryption.acceptedIterations.upperBound + 1
        for (offset, byte) in [UInt8(tooMany >> 24 & 0xFF), UInt8(tooMany >> 16 & 0xFF), UInt8(tooMany >> 8 & 0xFF), UInt8(tooMany & 0xFF)].enumerated() {
            sealed[sealed.startIndex + 10 + offset] = byte
        }
        #expect(throws: ArchiveEncryption.Failure.damaged) { try ArchiveEncryption.decrypt(sealed, password: "parola-exemplu") }
        #expect(throws: ArchiveError.notADossier) { try DossierArchiveReader.read(sealed, password: "parola-exemplu") }
    }

    // MARK: What an import reads

    @Test func aStatusFromANewerBuildIsKeptAndGoesBackOut() throws {
        var id = ""
        let archive = try Fixtures.archive("dosar-v3/household") { files in
            NewerVersionTests.rewrite(&files, DossierV3.Path.obligations) { obligations in
                id = obligations[0]["id"]?.string ?? ""
                obligations[0].set("status", "waitingForTheOffice")
            }
        }
        let container = try makeInMemoryContainer()
        let service = DossierArchiveService(container: container, calendar: calendar)
        try service.importArchive(archive, mode: .replace)
        let uuid = try #require(UUID(uuidString: id))
        let obligation = try #require(try ModelContext(container).fetch(FetchDescriptor<Obligation>(predicate: #Predicate { $0.id == uuid })).first)
        #expect(obligation.statusRaw == "waitingForTheOffice")
        #expect(obligation.status == .active, "Read as the loudest: it still reminds")
        #expect(ObligationStatus(stored: "waitingForTheOffice") == ObligationStatus.loudest)

        let again = try DossierArchiveReader.read(try service.exportData(exportedAt: noon("2026-11-10")))
        #expect(again.obligations.first { $0.id == id }?.status == "waitingForTheOffice", "Never written back downgraded")
    }

    @Test func aCategorysTintHeroAndPocketsFromANewerBuildAreKept() throws {
        var key = ""
        let archive = try Fixtures.archive("dosar-v3/household") { files in
            NewerVersionTests.rewrite(&files, DossierV3.Path.templates) { templates in
                guard let index = templates.firstIndex(where: { $0["isBuiltIn"] == .bool(false) }) else { return }
                key = templates[index]["key"]?.string ?? ""
                templates[index].set("tint", "ultraviolet")
                templates[index].set("heroStyle", "hologram")
                templates[index].set("pockets", ["keyFacts", "telepathy"])
            }
        }
        let container = try makeInMemoryContainer()
        let service = DossierArchiveService(container: container, calendar: calendar)
        try service.importArchive(archive, mode: .replace)
        let template = try #require(try TemplateStore(context: ModelContext(container)).template(forKey: key))
        #expect(template.tintRaw == "ultraviolet")
        #expect(template.heroStyleRaw == "hologram")
        #expect(template.pocketsRaw == ["keyFacts", "telepathy"])
        #expect(template.pockets == [.keyFacts], "Shown with what this build knows")

        let again = try DossierArchiveReader.read(try service.exportData(exportedAt: noon("2026-11-10")))
        let written = try #require(again.templates.first { $0.key == key })
        #expect(written.tint == "ultraviolet")
        #expect(written.heroStyle == "hologram")
        #expect(written.pockets == ["keyFacts", "telepathy"])
    }

    @Test func aDayTheCalendarDoesntHaveIsRefused() throws {
        #expect(CalendarDay(isoString: "2026-02-30") == nil)
        #expect(CalendarDay(isoString: "2026-04-31") == nil)
        #expect(CalendarDay(isoString: "2026-02-29") == nil)
        #expect(CalendarDay(isoString: "2028-02-29") == CalendarDay(year: 2028, month: 2, day: 29))
        #expect(CalendarDay(isoString: "2026-12-31T23:00:00Z") == CalendarDay(year: 2026, month: 12, day: 31))

        let archive = try Fixtures.archive("dosar-v3/household") { files in
            NewerVersionTests.rewrite(&files, DossierV3.Path.obligations) { obligations in
                obligations[0].set("dueDate", "2026-02-30")
            }
        }
        let container = try makeInMemoryContainer()
        #expect(throws: ArchiveError.unreadableFile(DossierV3.Path.obligations)) {
            try DossierArchiveService(container: container, calendar: calendar).importArchive(archive, mode: .replace)
        }
        #expect(try ModelContext(container).fetchCount(FetchDescriptor<Obligation>()) == 0, "Nothing written")
    }

    @Test func aDocumentCreatedInTheFutureComesInAsOfNow() throws {
        var id = ""
        let archive = try Fixtures.archive("dosar-v3/household") { files in
            NewerVersionTests.rewrite(&files, DossierV3.Path.attachments) { attachments in
                id = attachments[0]["id"]?.string ?? ""
                attachments[0].set("createdAt", "2099-01-01T00:00:00Z")
            }
        }
        let container = try makeInMemoryContainer()
        try DossierArchiveService(container: container, calendar: calendar).importArchive(archive, mode: .replace)
        let uuid = try #require(UUID(uuidString: id))
        let document = try #require(try ModelContext(container).fetch(FetchDescriptor<Attachment>(predicate: #Predicate { $0.id == uuid })).first)
        #expect(document.createdAt <= Date())
    }

    @Test func anIntervalOfNoneNeverMovesADayInAnyUnit() {
        let start = CalendarDay("2026-05-15")
        for unit in RecurrenceInterval.Unit.allCases {
            for every in [0, -1, -12] {
                var interval = RecurrenceInterval(every: 1, unit: unit)
                interval.every = every
                #expect(RecurrenceEngine.add(interval, to: start) == start, "\(every) \(unit)")
                #expect(RecurrenceEngine.add(interval, to: start, dayOfMonth: 31) == start, "\(every) \(unit), a series on the 31st")
            }
        }
    }
}
