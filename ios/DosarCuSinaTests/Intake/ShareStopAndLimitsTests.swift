import Foundation
import Testing
import UniformTypeIdentifiers
@testable import DosarCuSina

// The share sheet's limits and its „Renunță”: a file too large is refused without its bytes
// ever being read whole, a stopped share leaves nothing and announces nothing, and what a
// share ended mid-copy left behind goes once no share can own it. Placeholder files only.

private func temporaryFolder() throws -> URL {
    let url = FileManager.default.temporaryDirectory.appending(path: "dosar-share-stop-\(UUID().uuidString)", directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

private let pdfBytes = Data("%PDF-1.4 Factura ENGIE Romania S.A.".utf8)

/// A PDF of `bytes` that takes no room on the disk (its end only is written), so a test can
/// share a file far larger than the inbox takes.
private func largePDF(bytes: Int, in folder: URL) throws -> URL {
    let url = folder.appending(path: "Contract ENGIE.pdf")
    try pdfBytes.write(to: url)
    let handle = try FileHandle(forWritingTo: url)
    defer { try? handle.close() }
    try handle.truncate(atOffset: UInt64(bytes))
    return url
}

/// Counts how often a sender was asked for its item, from whichever queue asks.
private final class Asked: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0
    func add() { lock.withLock { count += 1 } }
    var times: Int { lock.withLock { count } }
}

/// A sender that keeps `file` for a PDF and counts every time it is asked for it: asking for
/// its bytes reads that same file, so a count of one means its bytes were never asked for.
@MainActor private func sender(of file: URL?, error: (any Error)? = nil, asked: Asked) -> NSItemProvider {
    let provider = NSItemProvider()
    provider.registerFileRepresentation(forTypeIdentifier: UTType.pdf.identifier, fileOptions: [], visibility: .all) { completion in
        asked.add()
        completion(file, false, error)
        return nil
    }
    return provider
}

@Suite("Share: a file too large never comes whole into memory")
@MainActor
struct ShareTooLargeTests {
    @Test func aFileTooLargeIsRefusedAndItsBytesAreNeverAskedFor() async throws {
        let folder = try temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let large = try largePDF(bytes: ShareInbox.maxFileBytes * 5, in: folder)
        #expect(ShareInbox.statedSize(of: large) == ShareInbox.maxFileBytes * 5, "Its size is known without reading it")
        let asked = Asked()
        let holding = folder.appending(path: "holding", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: holding, withIntermediateDirectories: true)

        let outcome = await ShareReceiving.receive(sender(of: large, asked: asked), into: holding, index: 0, room: ShareInbox.maxFileBytes)
        guard case .failed(let failure, let attempts) = outcome else { Issue.record("Not refused: \(outcome)"); return }
        #expect(failure == .tooLarge)
        #expect(attempts.map(\.way) == ["file"], "Too large is final: no link, no bytes")
        #expect(asked.times == 1, "Its bytes were never asked for")
        #expect(try FileManager.default.contentsOfDirectory(atPath: holding.path()).isEmpty, "Nothing was copied")
    }

    @Test func aLinkToAFileTooLargeIsRefusedBeforeAnythingIsRead() async throws {
        let folder = try temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let large = try largePDF(bytes: ShareInbox.maxShareBytes * 2, in: folder)
        let holding = folder.appending(path: "holding", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: holding, withIntermediateDirectories: true)
        let provider = NSItemProvider(item: large as NSURL, typeIdentifier: UTType.fileURL.identifier)

        let outcome = await ShareReceiving.receive(provider, into: holding, index: 0, room: ShareInbox.maxFileBytes)
        guard case .failed(let failure, _) = outcome else { Issue.record("Not refused: \(outcome)"); return }
        #expect(failure == .tooLarge)
        #expect(try FileManager.default.contentsOfDirectory(atPath: holding.path()).isEmpty)
        #expect(throws: ShareInbox.InboxError.tooLarge) {
            try ShareInbox.coordinatedCopy(of: large, to: holding.appending(path: "copy.pdf"), limit: ShareInbox.maxFileBytes)
        }
    }

    @Test func onceTheShareHasNoRoomLeftAnItemIsNotAskedForAtAll() async throws {
        let folder = try temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let small = folder.appending(path: "Factura.pdf")
        try pdfBytes.write(to: small)
        let asked = Asked()

        let outcome = await ShareReceiving.receive(sender(of: small, asked: asked), into: folder, index: 0, room: ShareInbox.room(sharedSoFar: ShareInbox.maxShareBytes))
        guard case .failed(let failure, let attempts) = outcome else { Issue.record("Not refused: \(outcome)"); return }
        #expect(failure == .tooLarge)
        #expect(attempts.map(\.way) == ["room"])
        #expect(asked.times == 0, "Past the share's limit, the sender is never asked")
    }

    @Test func aFileThatIsThereButCantBeCopiedIsNeverAskedForAsBytes() async throws {
        let folder = try temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let asked = Asked()
        let outcome = await ShareReceiving.receive(sender(of: nil, error: CocoaError(.fileReadNoPermission), asked: asked), into: folder, index: 0,
                                                   room: ShareInbox.maxFileBytes)
        guard case .failed(let failure, let attempts) = outcome else { Issue.record("Not failed: \(outcome)"); return }
        #expect(failure == .noAccess)
        #expect(attempts.map(\.way) == ["file"], "Its bytes would be the same file, read whole")
        #expect(asked.times == 1)
    }

    @Test func textThatIsAFileIsAskedForAsAFileFirst() throws {
        let plan = try #require(ShareReceiving.plan(identifiers: [UTType.utf8PlainText.identifier, UTType.fileURL.identifier]))
        #expect(plan.kind == .text)
        #expect(plan.ways == [.file(UTType.utf8PlainText.identifier), .link, .data(UTType.utf8PlainText.identifier)])
    }
}

/// A notice center that stops the share while it is asked whether notifications are allowed:
/// „Renunță” tapped as the share is about to announce.
private actor StoppingNoticeCenter: InboxNoticeCenter {
    let stop: ShareCancellation
    private(set) var posted = 0

    init(stopping stop: ShareCancellation) { self.stop = stop }

    func isAllowed() -> Bool {
        stop.stop()
        return true
    }

    func post(_ content: InboxNotice.Content) -> Bool {
        posted += 1
        return true
    }

    func announced() -> [UUID]? { nil }
    func withdraw() {}
}

@Suite("Share: „Renunță” stops the share", .serialized)
@MainActor
struct ShareStopTests {
    /// A note shared as text; `stop` stops the share as its sender hands it over.
    private static func note(asked: Asked? = nil, stopping stop: ShareCancellation? = nil) -> NSItemProvider {
        let provider = NSItemProvider()
        provider.registerDataRepresentation(forTypeIdentifier: UTType.plainText.identifier, visibility: .all) { completion in
            asked?.add()
            stop?.stop()
            completion(Data("Notă despre factura ENGIE Romania S.A.".utf8), nil)
            return nil
        }
        return provider
    }

    private static func stagingFolders(in inbox: ShareInbox) throws -> [String] {
        try FileManager.default.contentsOfDirectory(atPath: inbox.directory.path()).filter { $0.hasPrefix(ShareInbox.stagingPrefix) }
    }

    @Test func theTokenCancelsWhatWaitsOnceAndAtOnceForWhatComesLate() throws {
        let stop = ShareCancellation()
        let asked = Asked()
        stop.onStop { asked.add() }
        #expect(!stop.isStopped)
        #expect(throws: Never.self) { try stop.check() }
        stop.stop()
        stop.stop()
        #expect(asked.times == 1, "What waited runs once")
        stop.onStop { asked.add() }
        #expect(asked.times == 2, "What comes after runs at once")
        #expect(throws: CancellationError.self) { try stop.check() }
    }

    @Test func aStoppedCopyStopsAndLeavesNothing() throws {
        let folder = try temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let source = folder.appending(path: "Contract.pdf")
        try (pdfBytes + Data(repeating: 0x20, count: ShareInbox.chunkLength * 3)).write(to: source)
        let target = folder.appending(path: "copy.pdf")
        let stop = ShareCancellation()
        stop.stop()
        #expect(throws: CancellationError.self) {
            try ShareInbox.copyStreaming(from: source, to: target, limit: ShareInbox.maxFileBytes, stop: stop)
        }
        #expect(throws: CancellationError.self) {
            try ShareInbox.coordinatedCopy(of: source, to: target, limit: ShareInbox.maxFileBytes, stop: stop)
        }
        #expect(!FileManager.default.fileExists(atPath: target.path()))
    }

    @Test func afterStoppingNoOtherItemIsAskedForAndNothingIsLogged() async throws {
        let folder = try temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let inbox = ShareInbox(directory: folder)
        let holding = try inbox.makeStagingFolder()
        let stop = ShareCancellation()
        let later = Asked()

        let share = await ShareReceiving.receiveAll([Self.note(stopping: stop), Self.note(asked: later), Self.note(asked: later)],
                                                    into: holding, log: inbox, stop: stop)
        #expect(share.stopped)
        #expect(share.received.isEmpty, "What was being copied as it stopped isn't kept")
        #expect(later.times == 0, "No item after is asked for")
        #expect(inbox.failureLog().isEmpty, "Stopping is no failure")
    }

    @Test func aShareStoppedWhileCopyingLeavesNothingAndAnnouncesNothing() async throws {
        let folder = try temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let inbox = ShareInbox(directory: folder)
        let stop = ShareCancellation()
        let center = FakeInboxNoticeCenter(allowed: true)

        let phase = await ShareDelivery.deliver([Self.note(), Self.note(stopping: stop), Self.note()], into: inbox, center: center,
                                                notificationsOn: true, stop: stop)
        #expect(phase == nil)
        #expect(inbox.contents().items.isEmpty, "Nothing lands in the inbox")
        #expect(try Self.stagingFolders(in: inbox).isEmpty, "What was staged for it is gone")
        #expect(await center.posted.isEmpty, "No notice")
    }

    @Test func aShareStoppedAsItAnnouncesTakesBackWhatItKeptAndPostsNothing() async throws {
        let folder = try temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let inbox = ShareInbox(directory: folder)
        let stop = ShareCancellation()
        let center = StoppingNoticeCenter(stopping: stop)

        let phase = await ShareDelivery.deliver([Self.note(), Self.note()], into: inbox, center: center, notificationsOn: true, stop: stop)
        #expect(phase == nil)
        #expect(inbox.contents().items.isEmpty, "What it had committed is taken out again")
        #expect(try Self.stagingFolders(in: inbox).isEmpty)
        #expect(await center.posted == 0, "No notice")
    }

    @Test func aShareNobodyStopsArrivesAndIsAnnounced() async throws {
        let folder = try temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let inbox = ShareInbox(directory: folder)
        let center = FakeInboxNoticeCenter(allowed: true)

        let phase = await ShareDelivery.deliver([Self.note(), Self.note()], into: inbox, center: center, notificationsOn: true, stop: ShareCancellation())
        #expect(phase == .saved(count: 1, next: .tapNotice, notArrived: nil), "Two notes are one document")
        #expect(inbox.contents().items.map(\.payload) == [.text])
        #expect(try Self.stagingFolders(in: inbox).isEmpty)
        #expect(await center.posted.count == 1)
    }
}

@Suite("Share: what a share ended mid-copy left behind")
struct ShareAbandonedStagingTests {
    private static func staging(in inbox: ShareInbox, made: Date, touched: Date) throws -> URL {
        let folder = try inbox.makeStagingFolder()
        try pdfBytes.write(to: folder.appending(path: "received-1.pdf"))
        try FileManager.default.setAttributes([.creationDate: made, .modificationDate: touched], ofItemAtPath: folder.path())
        return folder
    }

    @Test func onlyStagingNoShareCanStillOwnGoes() throws {
        let folder = try temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let inbox = ShareInbox(directory: folder)
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let longAgo = now.addingTimeInterval(-ShareInbox.longestShare - 60)
        let abandoned = try Self.staging(in: inbox, made: longAgo, touched: longAgo)
        let running = try Self.staging(in: inbox, made: now.addingTimeInterval(-60), touched: now.addingTimeInterval(-60))
        let stillCopying = try Self.staging(in: inbox, made: longAgo, touched: now.addingTimeInterval(-5))

        inbox.removeAbandonedStaging(now: now)
        #expect(!FileManager.default.fileExists(atPath: abandoned.path()), "Untouched for longer than a share takes: no share owns it")
        #expect(FileManager.default.fileExists(atPath: running.path()), "A share running now keeps its own")
        #expect(FileManager.default.fileExists(atPath: stillCopying.path()), "A file went in lately: still a share's")
    }

    @Test func readingTheInboxClearsWhatNoShareOwns() throws {
        let folder = try temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let inbox = ShareInbox(directory: folder)
        let now = Date()
        let longAgo = now.addingTimeInterval(-ShareInbox.longestShare - 60)
        let abandoned = try Self.staging(in: inbox, made: longAgo, touched: longAgo)
        _ = inbox.contents(now: now)
        #expect(!FileManager.default.fileExists(atPath: abandoned.path()))
    }
}
