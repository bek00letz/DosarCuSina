import Foundation
import SwiftData
import Testing
@testable import DosarCuSina

private func temporaryFolder() throws -> URL {
    let url = FileManager.default.temporaryDirectory.appending(path: "dosar-tests-\(UUID().uuidString)", directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

@Suite("Share inbox handoff")
struct ShareInboxTests {
    @Test func photosTravelTogetherAndEachPDFStandsAlone() {
        let plan = ShareInbox.plan([.image, .pdf, .image, .text, .pdf, .text])
        #expect(plan == [
            .init(payload: .images, indices: [0, 2]),
            .init(payload: .pdf, indices: [1]),
            .init(payload: .text, indices: [3, 5]),
            .init(payload: .pdf, indices: [4]),
        ])
    }

    @Test func aHugeShareIsCapped() {
        let plan = ShareInbox.plan(Array(repeating: .image, count: 50))
        #expect(plan.count == 1)
        #expect(plan[0].indices.count == ShareInbox.maxFiles)
    }

    @Test func oversizedFilesAndSharesAreRefused() throws {
        #expect(throws: ShareInbox.InboxError.tooLarge) {
            try ShareInbox.checkRoom(for: ShareInbox.maxFileBytes + 1, sharedSoFar: 0)
        }
        #expect(throws: ShareInbox.InboxError.tooLarge) {
            try ShareInbox.checkRoom(for: 1_000, sharedSoFar: ShareInbox.maxShareBytes)
        }
        try ShareInbox.checkRoom(for: ShareInbox.maxFileBytes, sharedSoFar: 0)

        let folder = try temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let inbox = ShareInbox(directory: folder)
        let staging = try inbox.makeStagingFolder()
        #expect(throws: ShareInbox.InboxError.tooLarge) {
            try inbox.stage(data: Data("x".utf8), fileExtension: "txt", into: staging, index: 0, sharedSoFar: ShareInbox.maxShareBytes)
        }
        #expect(try FileManager.default.contentsOfDirectory(atPath: staging.path()).isEmpty, "Nothing is written when refused")
    }

    @Test func committedItemsAreListedReadAndRemoved() throws {
        let folder = try temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let inbox = ShareInbox(directory: folder.appending(path: ShareInbox.folderName))
        try FileManager.default.createDirectory(at: inbox.directory, withIntermediateDirectories: true)

        let source = folder.appending(path: "incoming.PDF")
        try Data("%PDF-1.4 test".utf8).write(to: source)
        let staging = try inbox.makeStagingFolder()
        let name = try inbox.stage(copyOf: source, into: staging, index: 0)
        #expect(name == "file-1.pdf", "Names are ours, never the sender's")
        #expect(inbox.items().isEmpty, "Nothing shows while it is still being copied")

        let older = try inbox.commit(staging: staging, payload: .pdf, files: [name], originalName: "Factura.pdf", receivedAt: Date(timeIntervalSince1970: 1_000))
        let textStaging = try inbox.makeStagingFolder()
        let textName = try inbox.stage(data: Data("Plata pana pe 20 noiembrie".utf8), fileExtension: "txt", into: textStaging, index: 0)
        let newer = try inbox.commit(staging: textStaging, payload: .text, files: [textName], originalName: nil, receivedAt: Date(timeIntervalSince1970: 2_000))

        #expect(inbox.items().map(\.id) == [newer.id, older.id], "Newest first")
        #expect(try Data(contentsOf: inbox.fileURLs(of: older)[0]) == Data("%PDF-1.4 test".utf8))

        try inbox.remove(older.id)
        try inbox.remove(older.id)
        #expect(inbox.items().map(\.id) == [newer.id])
    }

    @Test func anEmptyShareLeavesNothingBehind() throws {
        let folder = try temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let inbox = ShareInbox(directory: folder)
        let staging = try inbox.makeStagingFolder()
        #expect(throws: ShareInbox.InboxError.nothingToSave) {
            try inbox.commit(staging: staging, payload: .images, files: [], originalName: nil)
        }
        #expect(!FileManager.default.fileExists(atPath: staging.path()))
    }

    @Test func thePracticeInvoiceIsRecognizedByName() {
        #expect(ShareInbox.isPracticeName(ShareInbox.practiceFileName))
        #expect(ShareInbox.isPracticeName("Factura exemplu - Dosar cu Sina"))
        #expect(!ShareInbox.isPracticeName("Factura ENGIE.pdf"))
        #expect(!ShareInbox.isPracticeName(nil))
    }

    @Test func theAppGroupIsTheOneTheWidgetSnapshotUses() {
        #expect(AppGroup.identifier == WidgetSnapshot.appGroupIdentifier)
        #expect(WidgetFeed.fileName == WidgetSnapshot.fileName)
    }
}

@Suite("Widget content")
struct WidgetContentTests {
    let car = (UUID(), "VW Golf")

    private func feed(_ snapshots: [ObligationSnapshot], now: Date) throws -> WidgetFeed {
        let data = try WidgetSnapshot.encoder().encode(WidgetSnapshot.make(from: snapshots, now: now, calendar: .bucharest))
        return try #require(WidgetFeed.decode(data), "The widget reads exactly what the app writes")
    }

    @Test func theWidgetReadsTheAppsSnapshot() throws {
        let itp = snapshot("ITP", kind: .legal, due: "2026-11-07", asset: car)
        let decoded = try feed([itp], now: noon("2026-11-02"))
        #expect(decoded.version == WidgetSnapshot.currentVersion)
        #expect(decoded.items.first?.obligationId == itp.id)
        #expect(decoded.items.first?.dueDate == "2026-11-07")
        #expect(decoded.items.first?.deepLink == DeepLink.url(for: .obligation(itp.id)))
    }

    @Test func rowsCountDaysAndKeepProtectedItemsGeneric() throws {
        let itp = snapshot("ITP", kind: .legal, due: "2026-11-07", asset: car)
        let passport = snapshot("Pașaport", kind: .renewal, due: "2026-11-05", isSensitive: true)
        let rows = WidgetContent.rows(feed: try feed([itp, passport], now: noon("2026-11-02")), completed: [],
                                      now: noon("2026-11-02"), calendar: .bucharest, protectedTitle: "Scadență protejată", limit: 3)
        let protected = try #require(rows.first { $0.id == passport.id })
        #expect(protected.title == "Scadență protejată")
        #expect(protected.subtitle == nil)
        #expect(protected.canComplete == false, "No Gata for protected sections outside the app")
        let open = try #require(rows.first { $0.id == itp.id })
        #expect(open.daysRemaining == 5)
        #expect(open.subtitle == "VW Golf")
        #expect(open.canComplete)
    }

    @Test func examplesNeverReachTheWidget() throws {
        let example = snapshot("RCA", kind: .insurance, due: "2026-11-04", asset: car, isExample: true)
        let rows = WidgetContent.rows(feed: try feed([example], now: noon("2026-11-02")), completed: [],
                                      now: noon("2026-11-02"), calendar: .bucharest, protectedTitle: "", limit: 3)
        #expect(rows.isEmpty)
    }

    @Test func aTapOnGataHidesThatCycleOnly() throws {
        let itp = snapshot("ITP", kind: .legal, due: "2026-11-07", asset: car)
        let rca = snapshot("RCA", kind: .insurance, due: "2026-11-09", asset: car)
        let decoded = try feed([itp, rca], now: noon("2026-11-02"))
        let tapped = WidgetCompletion(obligationId: itp.id, dueDay: "2026-11-07")
        let oldCycle = WidgetCompletion(obligationId: rca.id, dueDay: "2025-11-09")
        let rows = WidgetContent.rows(feed: decoded, completed: [tapped, oldCycle], now: noon("2026-11-02"), calendar: .bucharest, protectedTitle: "", limit: 3)
        #expect(rows.map(\.id) == [rca.id])
    }

    @Test func daysCountDownAtMidnightAndTheLimitHolds() throws {
        let items = (1...5).map { snapshot("Termen \($0)", kind: .legal, due: "2026-11-0\($0 + 2)") }
        let decoded = try feed(items, now: noon("2026-11-02"))
        let tomorrow = Calendar.bucharest.startOfDay(for: noon("2026-11-03"))
        let rows = WidgetContent.rows(feed: decoded, completed: [], now: tomorrow, calendar: .bucharest, protectedTitle: "", limit: 2)
        #expect(rows.count == 2)
        #expect(rows.first?.daysRemaining == 0)
        #expect(WidgetContent.needsActionCount(rows) == 1)
        #expect(WidgetContent.rows(feed: nil, completed: [], now: tomorrow, protectedTitle: "", limit: 3).isEmpty)
    }

    @Test func theQueueKeepsEachCycleOnceAndForgetsHandledOnes() throws {
        let folder = try temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let queue = WidgetCompletionQueue(fileURL: folder.appending(path: WidgetCompletionQueue.fileName))
        let id = UUID()
        let first = WidgetCompletion(obligationId: id, dueDay: "2026-11-07", requestedAt: noon("2026-11-02"))
        queue.enqueue(first)
        queue.enqueue(WidgetCompletion(obligationId: id, dueDay: "2026-11-07", requestedAt: noon("2026-11-03")))
        #expect(queue.pending() == [first])
        queue.remove([first], now: noon("2026-11-03"))
        #expect(queue.pending().isEmpty)

        let stale = WidgetCompletion(obligationId: UUID(), dueDay: "2026-01-01", requestedAt: noon("2026-01-01"))
        queue.enqueue(stale)
        queue.remove([], now: noon("2026-11-02"))
        #expect(queue.pending().isEmpty, "Requests older than a month are dropped")
    }
}

@MainActor
@Suite("Widget taps through the engine")
struct WidgetEngineTests {
    @Test func aQueuedTapCompletesTheCycleItWasMadeFor() throws {
        let context = try makeContext()
        let actions = ObligationActions(context: context, calendar: .bucharest, now: { noon("2026-11-02") })
        let rent = try actions.create(title: "Chirie", kind: .payment, dueDay: CalendarDay("2026-11-05"), for: nil,
                                      recurrence: .interval(.months(1), anchor: .dueDate))
        let folder = try temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let queue = WidgetCompletionQueue(fileURL: folder.appending(path: WidgetCompletionQueue.fileName))
        queue.enqueue(WidgetCompletion(obligationId: rent.id, dueDay: "2026-11-05"))
        queue.enqueue(WidgetCompletion(obligationId: rent.id, dueDay: "2026-10-05"))

        let completed = IntentEngine.applyQueuedWidgetCompletions(queue: queue, in: context, calendar: .bucharest)
        #expect(completed == 1, "The October tap is for a cycle that's already gone")
        #expect(rent.dueDay(in: .bucharest) == CalendarDay("2026-12-05"))
        #expect(rent.history.count == 1)
        #expect(queue.pending().isEmpty)
    }

    @Test func aTapForAnotherCycleChangesNothing() throws {
        let context = try makeContext()
        let rent = try ObligationActions(context: context, calendar: .bucharest).create(
            title: "Chirie", kind: .payment, dueDay: CalendarDay("2026-11-05"), for: nil)
        let outcome = try IntentEngine.complete(obligationID: rent.id, cycle: CalendarDay("2026-12-05"), in: context, calendar: .bucharest)
        #expect(outcome == .skipped)
        #expect(rent.status == .active)
        #expect(try IntentEngine.complete(obligationID: UUID(), in: context) == .skipped)
    }
}
