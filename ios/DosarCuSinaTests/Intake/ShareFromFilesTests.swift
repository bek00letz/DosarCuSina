import Foundation
import FileProvider
import Testing
import UniformTypeIdentifiers
@testable import DosarCuSina

// Sharing into the app from Files, iCloud Drive and other apps: every way a sender hands an
// item over, what a file is when its type says nothing, copying a piece at a time, and why a
// share that fails failed. Placeholder files only.

private func temporaryFolder() throws -> URL {
    let url = FileManager.default.temporaryDirectory.appending(path: "dosar-share-\(UUID().uuidString)", directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

private let pdfBytes = Data("%PDF-1.4 Factura ENGIE Romania S.A.".utf8)
private let jpegBytes = Data([0xFF, 0xD8, 0xFF, 0xE0, 0x00, 0x10] + Array("JFIF".utf8))
private let pngBytes = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00, 0x00])
private let heicBytes = Data([0x00, 0x00, 0x00, 0x18] + Array("ftypheic".utf8) + [0x00, 0x00, 0x00, 0x00])

@Suite("Share from Files: what to ask the sender for")
struct SharePlanTests {
    @Test func aPDFFromFilesIsAskedForAsAFileThenThroughItsLinkThenAsBytes() throws {
        let plan = try #require(ShareReceiving.plan(identifiers: [UTType.pdf.identifier, UTType.fileURL.identifier]))
        #expect(plan.kind == .pdf)
        #expect(plan.ways == [.file(UTType.pdf.identifier), .link, .data(UTType.pdf.identifier)], "Bytes come whole into memory: last")
    }

    @Test func aPictureIsAskedForInTheTypeItsSenderRegistered() throws {
        let heic = try #require(ShareReceiving.plan(identifiers: [UTType.heic.identifier, UTType.jpeg.identifier]))
        #expect(heic.kind == .image)
        #expect(heic.ways == [.file(UTType.heic.identifier), .data(UTType.heic.identifier)], "A HEIC conforms to a picture: it is asked for as itself")
        let png = try #require(ShareReceiving.plan(identifiers: [UTType.png.identifier]))
        #expect(png.kind == .image)
        #expect(png.type == .png)
    }

    @Test func aPDFBeatsAPictureAndAPictureBeatsText() throws {
        let plan = try #require(ShareReceiving.plan(identifiers: [UTType.utf8PlainText.identifier, UTType.jpeg.identifier, UTType.pdf.identifier]))
        #expect(plan.kind == .pdf)
    }

    @Test func textIsAskedForAsBytesFirst() throws {
        let plan = try #require(ShareReceiving.plan(identifiers: [UTType.utf8PlainText.identifier]))
        #expect(plan.kind == .text)
        #expect(plan.ways == [.data(UTType.utf8PlainText.identifier), .file(UTType.utf8PlainText.identifier)])
    }

    @Test func plainDataIsLookedAtThroughItsLinkFirst() throws {
        let plan = try #require(ShareReceiving.plan(identifiers: [UTType.data.identifier, UTType.fileURL.identifier]))
        #expect(plan.kind == nil, "Only the file can say what it is")
        #expect(plan.ways == [.link, .file(UTType.data.identifier), .data(UTType.data.identifier)])
        #expect(try #require(ShareReceiving.plan(identifiers: [UTType.fileURL.identifier])).ways == [.link])
    }

    @Test func aTypeWithNoNameIsLookedAt() throws {
        let unnamed = try #require(UTType(filenameExtension: "dosarxyz"))
        #expect(unnamed.isDynamic)
        let plan = try #require(ShareReceiving.plan(identifiers: [unnamed.identifier]))
        #expect(plan.kind == nil)
        #expect(plan.ways == [.file(unnamed.identifier), .data(unnamed.identifier)])
    }

    @Test func whatTheInboxCantTakeIsNotAskedFor() {
        #expect(ShareReceiving.plan(identifiers: [UTType.zip.identifier]) == nil)
        #expect(ShareReceiving.plan(identifiers: [UTType.url.identifier]) == nil, "A web address is no file")
        #expect(ShareReceiving.plan(identifiers: []) == nil)
    }

    @Test func aLinkIsAFileOnlyWhenItPointsAtOne() throws {
        let file = URL(filePath: "/tmp/Factura.pdf")
        #expect(ShareReceiving.fileURL(from: file) == file)
        #expect(ShareReceiving.fileURL(from: file.dataRepresentation) == file)
        #expect(ShareReceiving.fileURL(from: file.absoluteString) == file)
        #expect(ShareReceiving.fileURL(from: URL(string: "https://exemplu.ro/factura.pdf")) == nil)
        #expect(ShareReceiving.fileURL(from: nil) == nil)
    }
}

@Suite("Share from Files: what a file is")
struct ShareFileKindTests {
    @Test func aFileWhoseTypeSaysNothingIsKnownByItsFirstBytes() {
        #expect(ShareInbox.type(sniffing: pdfBytes) == .pdf)
        #expect(ShareInbox.type(sniffing: Data("\r\n".utf8) + pdfBytes) == .pdf, "A PDF's header may follow a little leading junk")
        #expect(ShareInbox.type(sniffing: jpegBytes) == .jpeg)
        #expect(ShareInbox.type(sniffing: pngBytes) == .png)
        #expect(ShareInbox.type(sniffing: heicBytes) == .heic)
        #expect(ShareInbox.type(sniffing: Data("GIF89a....".utf8)) == .gif)
        #expect(ShareInbox.type(sniffing: Data("Plata pana pe 20 noiembrie".utf8)) == nil, "Text is never guessed from bytes")
        #expect(ShareInbox.type(sniffing: Data()) == nil)
    }

    @Test func aFileIsTakenLookedAtOrLeftBeforeItIsCopied() {
        #expect(ShareInbox.verdict(for: .pdf) == .take(.pdf))
        #expect(ShareInbox.verdict(for: .heic) == .take(.image))
        #expect(ShareInbox.verdict(for: .png) == .take(.image))
        #expect(ShareInbox.verdict(for: .zip) == .leave, "Never downloaded only to be refused")
        #expect(ShareInbox.verdict(for: .data) == .look)
        #expect(ShareInbox.verdict(for: nil) == .look)
    }

    @Test func aReceivedFileTakesTheExtensionOfWhatItIs() throws {
        let folder = try temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let inbox = ShareInbox(directory: folder)

        let unnamed = folder.appending(path: "received-1")
        try pdfBytes.write(to: unnamed)
        let settled = try #require(inbox.settle(received: unnamed, declared: nil, hint: nil))
        #expect(settled.kind == .pdf)
        #expect(settled.file.pathExtension == "pdf")
        #expect(try Data(contentsOf: settled.file) == pdfBytes)

        let mislabelled = folder.appending(path: "received-2.bin")
        try jpegBytes.write(to: mislabelled)
        #expect(try #require(inbox.settle(received: mislabelled, declared: nil, hint: .data)).kind == .image)

        let text = folder.appending(path: "received-3.txt")
        try Data("Plata pana pe 20 noiembrie".utf8).write(to: text)
        #expect(inbox.settle(received: text, declared: nil, hint: .plainText)?.kind == .text, "Text is known by its name")

        let other = folder.appending(path: "received-4")
        try Data("PK\u{3}\u{4}".utf8).write(to: other)
        #expect(inbox.settle(received: other, declared: nil, hint: nil) == nil)
        #expect(!FileManager.default.fileExists(atPath: other.path()), "What the inbox can't take is removed")

        let declared = folder.appending(path: "received-5.heic")
        try heicBytes.write(to: declared)
        #expect(inbox.settle(received: declared, declared: .image, hint: nil)?.file == declared)
    }
}

@Suite("Share from Files: copying")
struct ShareCopyTests {
    @Test func aLargeFileIsCopiedWholeAPieceAtATime() throws {
        let folder = try temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let source = folder.appending(path: "Contract.pdf")
        let bytes = pdfBytes + Data(repeating: 0x20, count: ShareInbox.chunkLength * 2 + 123)
        try bytes.write(to: source)
        let target = folder.appending(path: "copy.pdf")
        #expect(try ShareInbox.copyStreaming(from: source, to: target, limit: ShareInbox.maxFileBytes) == bytes.count)
        #expect(try Data(contentsOf: target) == bytes)
    }

    @Test func aFilePastTheRoomLeftIsRefusedAndLeavesNothing() throws {
        let folder = try temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let source = folder.appending(path: "Contract.pdf")
        try pdfBytes.write(to: source)
        let target = folder.appending(path: "copy.pdf")
        #expect(throws: ShareInbox.InboxError.tooLarge) {
            try ShareInbox.copyStreaming(from: source, to: target, limit: pdfBytes.count - 1)
        }
        #expect(!FileManager.default.fileExists(atPath: target.path()))
        #expect(ShareInbox.room(sharedSoFar: 0) == ShareInbox.maxFileBytes)
        #expect(ShareInbox.room(sharedSoFar: ShareInbox.maxShareBytes - 10) == 10)
        #expect(ShareInbox.room(sharedSoFar: ShareInbox.maxShareBytes + 10) == 0)
    }

    @Test func aFileWhereItLivesIsCopiedWithCoordinatedReading() throws {
        let folder = try temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let source = folder.appending(path: "Factura.pdf")
        try pdfBytes.write(to: source)
        let target = folder.appending(path: "copy.pdf")
        #expect(try ShareInbox.coordinatedCopy(of: source, to: target, limit: ShareInbox.maxFileBytes) == pdfBytes.count)
        #expect(try Data(contentsOf: target) == pdfBytes)
        #expect(!ShareInbox.isWaitingInCloud(source), "A file on the phone isn't waiting in iCloud")
    }

    @Test func aReceivedFileMovesIntoItsItemUnderOurName() throws {
        let folder = try temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let inbox = ShareInbox(directory: folder)
        let holding = try inbox.makeStagingFolder()
        let received = holding.appending(path: "received-3.PDF")
        try pdfBytes.write(to: received)
        let staging = try inbox.makeStagingFolder()
        #expect(try inbox.stage(received: received, into: staging, index: 0) == "file-1.pdf")
        let item = try inbox.commit(staging: staging, payload: .pdf, files: ["file-1.pdf"], originalName: "Factura ENGIE.pdf")
        #expect(try Data(contentsOf: inbox.fileURLs(of: item)[0]) == pdfBytes)
    }
}

@Suite("Share from Files: receiving an item every way")
@MainActor
struct ShareReceivingTests {
    private func receive(_ provider: NSItemProvider, room: Int = ShareInbox.maxFileBytes) async throws -> (ShareReceiving.Outcome, URL) {
        let folder = try temporaryFolder()
        return (await ShareReceiving.receive(provider, into: folder, index: 0, room: room), folder)
    }

    @Test func aTypedFileArrives() async throws {
        let source = try temporaryFolder().appending(path: "Factura.pdf")
        try pdfBytes.write(to: source)
        let provider = try #require(NSItemProvider(contentsOf: source))
        let (outcome, folder) = try await receive(provider)
        defer { try? FileManager.default.removeItem(at: folder) }
        guard case .received(let item) = outcome else { Issue.record("Not received: \(outcome)"); return }
        #expect(item.kind == .pdf)
        #expect(item.bytes == pdfBytes.count)
        #expect(try Data(contentsOf: item.file) == pdfBytes)
    }

    @Test func aSenderWithOnlyBytesStillHandsItOver() async throws {
        let provider = NSItemProvider()
        provider.registerDataRepresentation(forTypeIdentifier: UTType.pdf.identifier, visibility: .all) { completion in
            completion(pdfBytes, nil)
            return nil
        }
        let (outcome, folder) = try await receive(provider)
        defer { try? FileManager.default.removeItem(at: folder) }
        guard case .received(let item) = outcome else { Issue.record("Not received: \(outcome)"); return }
        #expect(item.kind == .pdf)
        #expect(try Data(contentsOf: item.file) == pdfBytes)
    }

    @Test func whenTheTypedFileFailsTheLinkStillWorks() async throws {
        let source = try temporaryFolder().appending(path: "IMG_0001.HEIC")
        try heicBytes.write(to: source)
        let provider = NSItemProvider()
        provider.registerFileRepresentation(forTypeIdentifier: UTType.heic.identifier, fileOptions: [], visibility: .all) { completion in
            completion(nil, false, CocoaError(.fileReadUnknown))
            return nil
        }
        provider.registerItem(forTypeIdentifier: UTType.fileURL.identifier) { completion, _, _ in
            completion?(source as NSURL, nil)
        }
        let (outcome, folder) = try await receive(provider)
        defer { try? FileManager.default.removeItem(at: folder) }
        guard case .received(let item) = outcome else { Issue.record("Not received: \(outcome)"); return }
        #expect(item.kind == .image)
        #expect(try Data(contentsOf: item.file) == heicBytes)
    }

    @Test func aLinkedFileWithNoExtensionIsKnownByItsBytes() async throws {
        let source = try temporaryFolder().appending(path: "Factura")
        try pdfBytes.write(to: source)
        let provider = NSItemProvider(item: source as NSURL, typeIdentifier: UTType.fileURL.identifier)
        let (outcome, folder) = try await receive(provider)
        defer { try? FileManager.default.removeItem(at: folder) }
        guard case .received(let item) = outcome else { Issue.record("Not received: \(outcome)"); return }
        #expect(item.kind == .pdf)
        #expect(item.file.pathExtension == "pdf")
        #expect(item.name == "Factura")
    }

    @Test func aLinkedFileTheInboxCantTakeIsNotCopied() async throws {
        let source = try temporaryFolder().appending(path: "Arhiva.zip")
        try Data("PK\u{3}\u{4}".utf8).write(to: source)
        let provider = NSItemProvider(item: source as NSURL, typeIdentifier: UTType.fileURL.identifier)
        let (outcome, folder) = try await receive(provider)
        defer { try? FileManager.default.removeItem(at: folder) }
        guard case .unsupported = outcome else { Issue.record("Not left: \(outcome)"); return }
        #expect(try FileManager.default.contentsOfDirectory(atPath: folder.path()).isEmpty)
    }

    @Test func aFilePastTheRoomLeftSaysItIsTooLarge() async throws {
        let source = try temporaryFolder().appending(path: "Factura.pdf")
        try pdfBytes.write(to: source)
        let provider = try #require(NSItemProvider(contentsOf: source))
        let (outcome, folder) = try await receive(provider, room: 4)
        defer { try? FileManager.default.removeItem(at: folder) }
        guard case .failed(let failure, _) = outcome else { Issue.record("Not refused: \(outcome)"); return }
        #expect(failure == .tooLarge)
    }

    @Test func aSenderThatHandsOverNothingIsToldAsSuch() async throws {
        let provider = NSItemProvider()
        provider.registerFileRepresentation(forTypeIdentifier: UTType.pdf.identifier, fileOptions: [], visibility: .all) { completion in
            completion(nil, false, NSError(domain: NSItemProvider.errorDomain, code: NSItemProvider.ErrorCode.unavailableCoercionError.rawValue))
            return nil
        }
        let (outcome, folder) = try await receive(provider)
        defer { try? FileManager.default.removeItem(at: folder) }
        guard case .failed(let failure, let attempts) = outcome else { Issue.record("Not failed: \(outcome)"); return }
        #expect(failure == .notHandedOver)
        #expect(attempts.map(\.way) == ["file", "data"], "Both ways were tried")
    }
}

@Suite("Share from Files: why a share failed")
struct ShareFailureTests {
    private func error(_ domain: String, _ code: Int, under: NSError? = nil) -> NSError {
        NSError(domain: domain, code: code, userInfo: under.map { [NSUnderlyingErrorKey: $0] } ?? [:])
    }

    @Test func eachKnownCauseIsNamed() {
        #expect(ShareFailure(error(NSCocoaErrorDomain, NSFileWriteOutOfSpaceError)) == .noRoom)
        #expect(ShareFailure(error(NSPOSIXErrorDomain, Int(ENOSPC))) == .noRoom)
        #expect(ShareFailure(error(NSCocoaErrorDomain, NSUbiquitousFileUnavailableError)) == .stillInCloud)
        #expect(ShareFailure(error(NSCocoaErrorDomain, NSFileReadUnknownError, under: error(NSPOSIXErrorDomain, Int(EDEADLK)))) == .stillInCloud,
                "The telling error is often under the one the system gives")
        #expect(ShareFailure(URLError(.notConnectedToInternet)) == .offline)
        #expect(ShareFailure(error(NSFileProviderErrorDomain, NSFileProviderError.Code.serverUnreachable.rawValue)) == .offline)
        #expect(ShareFailure(error(NSCocoaErrorDomain, NSFileReadNoPermissionError)) == .noAccess)
        #expect(ShareFailure(error(NSItemProvider.errorDomain, NSItemProvider.ErrorCode.unavailableCoercionError.rawValue)) == .notHandedOver)
        #expect(ShareFailure(ShareInbox.InboxError.tooLarge) == .tooLarge)
        #expect(ShareFailure(ShareReceivingError.stillInCloud(underlying: CocoaError(.fileReadUnknown))) == .stillInCloud)
        #expect(ShareFailure(error("com.exemplu.altceva", 7)) == .couldNotCopy)
    }

    @Test func theMostTellingReasonIsTold() {
        #expect(ShareFailure.mostTelling([.notHandedOver, .stillInCloud, .couldNotCopy]) == .stillInCloud)
        #expect(ShareFailure.mostTelling([.couldNotCopy, .notHandedOver]) == .notHandedOver, "A known cause before an unnamed one")
        #expect(ShareFailure.mostTelling([]) == nil)
        #expect(Set(ShareFailure.mostTellingFirst) == Set(ShareFailure.allCases), "Every reason has its place")
    }

    @Test func theLogKeepsKindsOnlyAndTheLatestOnes() throws {
        let folder = try temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let inbox = ShareInbox(directory: folder)
        let named = NSError(domain: "com.exemplu.Factura ENGIE", code: 3, userInfo: [
            NSFilePathErrorKey: "Documente/Factura ENGIE.pdf",
            NSUnderlyingErrorKey: NSError(domain: NSPOSIXErrorDomain, code: Int(EDEADLK)),
        ])
        let attempt = ShareFailureLog.Attempt(way: ShareReceiving.Way.link.logName, error: named)
        #expect(attempt.failure == .stillInCloud)
        #expect(attempt.domain == NSPOSIXErrorDomain)
        #expect(attempt.code == Int(EDEADLK))
        #expect(ShareFailureLog.Attempt(way: "file", error: NSError(domain: "com.exemplu.Factura ENGIE", code: 3)).domain == "other",
                "A domain the system doesn't name is never kept")

        for _ in 0 ..< ShareFailureLog.kept + 5 {
            ShareFailureLog.record(ShareFailureLog.Entry(at: Date(timeIntervalSince1970: 1_000), failure: .stillInCloud, attempts: [attempt]), in: inbox)
        }
        #expect(inbox.failureLog().count == ShareFailureLog.kept)
        #expect(inbox.failureLog().last?.failure == .stillInCloud)
        let written = try String(decoding: Data(contentsOf: folder.appending(path: ShareInbox.failureLogName)), as: UTF8.self)
        #expect(!written.contains("Factura"), "No name or path is ever kept")
        #expect(inbox.items().isEmpty, "The log is never read as an item")
    }
}

@Suite("Share from Files: what the confirmation says")
struct ShareFailureWordsTests {
    @Test func eachReasonSaysWhatHappenedAndWhatToDo() {
        let words = ShareFailure.allCases.map { ShareConfirmation(.failed($0)) }
        #expect(Set(words.compactMap(\.message)).count == ShareFailure.allCases.count, "No catch-all message for a known cause")
        for confirmation in words {
            #expect(!confirmation.title.isEmpty)
            #expect(confirmation.message?.hasSuffix(".") == true)
            #expect(confirmation.title.contains("!") == false && confirmation.message?.contains("!") == false)
            #expect(confirmation.action == .close)
        }
        let cloud = ShareConfirmation(.failed(.stillInCloud))
        #expect(cloud.title == "Fișierul e încă în iCloud")
        #expect(cloud.message == "Nu l-am putut descărca acum. Deschide-l o dată în Fișiere, apoi trimite-l din nou.")
        #expect(ShareConfirmation(.failed(.notHandedOver)).message == "Telefonul nu mi-a dat fișierul. Încearcă din nou din aplicația din care l-ai trimis.")
    }
}
