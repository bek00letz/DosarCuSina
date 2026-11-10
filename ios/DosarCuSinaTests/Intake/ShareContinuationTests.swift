import Foundation
import PDFKit
import SwiftData
import Testing
import UIKit
@testable import DosarCuSina

// What happens after a share (the notice, opening at De verificat) and how waiting items
// read in De verificat. Placeholder data only.

private func temporaryInbox() throws -> ShareInbox {
    let url = FileManager.default.temporaryDirectory.appending(path: "dosar-continue-\(UUID().uuidString)", directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return ShareInbox(directory: url)
}

/// Commits one item the way the share extension does.
@discardableResult
private func share(_ inbox: ShareInbox, _ payload: InboxItem.Payload, name: String?, pages: Int = 1, at date: Date = Date()) throws -> InboxItem {
    let staging = try inbox.makeStagingFolder()
    var files: [String] = []
    for index in 0..<pages {
        let ext = payload == .pdf ? "pdf" : (payload == .text ? "txt" : "jpg")
        files.append(try inbox.stage(data: Data("placeholder \(index)".utf8), fileExtension: ext, into: staging, index: index))
    }
    return try inbox.commit(staging: staging, payload: payload, files: files, originalName: name, receivedAt: date)
}

private func item(_ payload: InboxItem.Payload = .pdf, name: String? = nil, files: Int = 1, at date: Date = noon("2026-11-09"), practice: Bool = false) -> InboxItem {
    InboxItem(receivedAt: date, payload: payload, files: (1...files).map { "file-\($0)" }, originalName: name, isPractice: practice)
}

/// Records what the inbox notice asks of the notification center.
actor FakeInboxNoticeCenter: InboxNoticeCenter {
    var allowed: Bool
    private(set) var posted: [InboxNotice.Content] = []
    private(set) var current: InboxNotice.Content?
    private(set) var withdrawals = 0

    init(allowed: Bool) { self.allowed = allowed }

    func isAllowed() -> Bool { allowed }

    func post(_ content: InboxNotice.Content) -> Bool {
        posted.append(content)
        current = content
        return true
    }

    func announced() -> [UUID]? { current?.itemIDs }

    func withdraw() {
        withdrawals += 1
        current = nil
    }
}

@Suite("After a share: the notice")
struct InboxNoticeTests {
    @Test func aNoticeOnlyWhenNotificationsAreAlreadyAllowed() async throws {
        let inbox = try temporaryInbox()
        defer { try? FileManager.default.removeItem(at: inbox.directory) }
        let bill = try share(inbox, .pdf, name: "Factura ENGIE.pdf")
        let photos = try share(inbox, .images, name: "IMG_2041.HEIC", pages: 3)

        let refused = FakeInboxNoticeCenter(allowed: false)
        #expect(await !InboxNotice.announce(waiting: inbox.waitingItems(), center: refused))
        #expect(await refused.posted.isEmpty, "Never asks and never posts without permission")

        let allowed = FakeInboxNoticeCenter(allowed: true)
        #expect(await InboxNotice.announce(waiting: inbox.waitingItems(), center: allowed))
        let notice = try #require(await allowed.posted.first)
        // Three photos shared together are one document.
        #expect(notice.title == "Am primit 2 acte")
        #expect(notice.body == "Deschide aplicația ca să le pui la locul lor.")
        #expect(Set(notice.itemIDs) == [bill.id, photos.id])
    }

    @Test func oneDocumentIsAWord() throws {
        let notice = try #require(InboxNotice.content(waiting: [item()]))
        #expect(notice.title == "Am primit un act")
        #expect(notice.body == "Deschide aplicația ca să-l pui la locul lui.")
        #expect(InboxNotice.content(waiting: [item(), item(), item(), item(), item()])?.title == "Am primit 5 acte")
    }

    @Test func thePracticeNeverNotifiesAndTheShareSheetSaysWhatComesNext() {
        let practice = item(practice: true)
        #expect(InboxNotice.content(waiting: [practice]) == nil)
        #expect(InboxNotice.content(waiting: [practice, item()])?.itemIDs.count == 1)
        #expect(InboxNotice.nextStep(saved: [practice], notified: false) == .practice)
        #expect(InboxNotice.nextStep(saved: [item()], notified: true) == .tapNotice)
        #expect(InboxNotice.nextStep(saved: [item()], notified: false) == .openApp)
    }

    @Test func itIsWithdrawnOnlyWhenNothingItAnnouncedStillWaits() {
        let a = UUID(), b = UUID()
        #expect(!InboxNotice.shouldWithdraw(announced: [a, b], waiting: [a, b]))
        #expect(!InboxNotice.shouldWithdraw(announced: [a, b], waiting: [b]))
        #expect(InboxNotice.shouldWithdraw(announced: [a, b], waiting: []))
        #expect(InboxNotice.shouldWithdraw(announced: [a], waiting: [UUID()]), "Only what it announced counts")
        // The reconciler only owns reminders: it never removes the notice by itself.
        #expect(!InboxNotice.identifier.hasPrefix(ReminderPlanner.identifierPrefix))
    }

    @MainActor
    @Test func theCoordinatorWithdrawsItOnceItsItemsAreFiledOrDismissed() async throws {
        let inbox = try temporaryInbox()
        let folder = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(at: inbox.directory)
            try? FileManager.default.removeItem(at: folder)
        }
        let bill = try share(inbox, .pdf, name: "Factura ENGIE.pdf")
        let policy = try share(inbox, .pdf, name: "Polita RCA.pdf")
        let notices = FakeInboxNoticeCenter(allowed: true)
        await InboxNotice.announce(waiting: inbox.waitingItems(), center: notices)

        let defaults = try #require(UserDefaults(suiteName: "tests.\(UUID().uuidString)"))
        let coordinator = SideEffectsCoordinator(
            container: try makeInMemoryContainer(),
            notificationClient: FakeNotificationCenter(status: .authorized),
            widgetWriter: WidgetSnapshotWriter(directory: folder),
            inboxNotices: notices,
            waitingInboxItems: { Set(inbox.waitingItems().map(\.id)) },
            preferences: AppPreferences(defaults: defaults),
            calendar: .bucharest,
            now: { noon("2026-11-09") }
        )
        await coordinator.reconcileNow()
        #expect(await notices.withdrawals == 0, "Both still wait")

        // One filed: the other still waits, so the notice stays.
        let intake = IntakeInbox(inbox: inbox, reader: nil)
        intake.remove(bill)
        await coordinator.reconcileNow()
        #expect(await notices.withdrawals == 0)

        // The last one dismissed: the notice has done its job.
        intake.remove(policy)
        await coordinator.reconcileNow()
        #expect(await notices.withdrawals == 1)
        #expect(await notices.current == nil)
        await coordinator.reconcileNow()
        #expect(await notices.withdrawals == 1, "Nothing left to withdraw")
    }

    @MainActor
    @Test func leavingTheInboxTellsTheCoordinator() throws {
        let inbox = try temporaryInbox()
        defer { try? FileManager.default.removeItem(at: inbox.directory) }
        let bill = try share(inbox, .pdf, name: "Factura ENGIE.pdf")
        let intake = IntakeInbox(inbox: inbox, reader: nil)
        let heard = Flag(false)
        let observer = NotificationCenter.default.addObserver(forName: ShareInbox.didChangeNotification, object: nil, queue: nil) { _ in heard.value = true }
        defer { NotificationCenter.default.removeObserver(observer) }
        intake.remove(bill)
        #expect(heard.value)
        #expect(inbox.waitingItems().isEmpty)
    }
}

@Suite("After a share: the share sheet's confirmation")
struct ShareConfirmationTests {
    @Test func itStaysUntilGata() {
        #expect(!ShareConfirmation.closesByItself, "Nobody misses what happens next: it closes only on „Gata”")
        let saved: [ShareConfirmation.Phase] = [.saved(count: 1, next: .tapNotice), .saved(count: 2, next: .openApp), .saved(count: 1, next: .practice)]
        for phase in saved + [.unsupported, .failed, .tooLarge] {
            #expect(ShareConfirmation(phase).action == .done, "Every outcome waits for „Gata”")
        }
        #expect(ShareConfirmation(.working).action == .cancel)
    }

    @Test func itSaysWhatHappensNext() {
        let notice = ShareConfirmation(.saved(count: 2, next: .tapNotice))
        #expect(notice.title == "Am primit 2 acte")
        #expect(notice.message == "Atinge notificarea ca să continui. Te așteaptă în aplicație, la De verificat.")
        let open = ShareConfirmation(.saved(count: 1, next: .openApp))
        #expect(open.title == "Am primit un act")
        #expect(open.message == "Deschide Dosar cu Șină ca să continui. Te așteaptă la De verificat.")
        #expect(ShareConfirmation(.saved(count: 1, next: .practice)).message == "Te întorci în aplicație și vezi unde a ajuns.")
        #expect(ShareConfirmation(.working).message == nil)
        #expect(ShareConfirmation(.tooLarge).message == "Trimite actele câte unul, sau ca poze în loc de un PDF mare.")
    }
}

@Suite("After a share: opening at De verificat")
@MainActor
struct InboxLandingTests {
    /// A landing whose opening ends at once, unless a test gives it one that never would.
    private func landing(opening: Duration = .zero) throws -> InboxLanding {
        InboxLanding(defaults: try #require(UserDefaults(suiteName: "tests.\(UUID().uuidString)")), opening: opening)
    }

    /// Waits until the landing (or anything) waits on the navigator for a route.
    private func untilWaiting(_ navigator: AppNavigator) async {
        while !navigator.isWaitingForRoute { await Task.yield() }
    }

    @Test("A route that comes with the opening wins, the moment it comes", .timeLimit(.minutes(1)))
    func aRouteThatComesWithTheOpeningWinsAtOnce() async throws {
        // An opening that would never end: only the route can end the wait.
        let landing = try landing(opening: .seconds(3600))
        let navigator = AppNavigator(isAppLocked: { false })
        let waiting = [item()]
        landing.didEnterBackground(navigator: navigator)
        let landed = Task { @MainActor in
            await landing.didBecomeActive(waiting: { waiting }, navigator: navigator, isBusy: { false })
        }
        await untilWaiting(navigator)
        let reminder = AppRoute.obligation(UUID())
        navigator.open(reminder)
        #expect(await !landed.value)
        #expect(navigator.consume() == reminder, "De verificat didn't take its place")
        #expect(!navigator.isWaitingForRoute)
    }

    @Test("A wait cut short leaves the landing for the next time", .timeLimit(.minutes(1)))
    func aWaitCutShortLeavesItForNextTime() async throws {
        let landing = try landing(opening: .seconds(3600))
        let navigator = AppNavigator(isAppLocked: { false })
        let waiting = [item()]
        let cut = Task { @MainActor in
            await landing.didBecomeActive(waiting: { waiting }, navigator: navigator, isBusy: { false })
        }
        await untilWaiting(navigator)
        // The app went inactive again (a Face ID prompt): the wait ends at once.
        cut.cancel()
        #expect(await !cut.value)
        #expect(navigator.pendingRoute == nil)
        #expect(!navigator.isWaitingForRoute)

        // Active again: it is still owed, so it waits for the opening again instead of giving up.
        let again = Task { @MainActor in
            await landing.didBecomeActive(waiting: { waiting }, navigator: navigator, isBusy: { false })
        }
        await untilWaiting(navigator)
        again.cancel()
        #expect(await !again.value)
    }

    @Test func theNoticeOpensDeVerificatAfterUnlocking() {
        let locked = Flag(true)
        let navigator = AppNavigator(isAppLocked: { locked.value })
        let responder = NotificationResponder(containerProvider: { nil }, navigator: navigator)
        responder.openInbox()
        #expect(navigator.consume() == nil, "Waits while the app is locked")
        locked.value = false
        #expect(navigator.consume() == .intake)
        // De verificat is the top of the Adaugă tab, with nothing pushed over it.
        #expect(ShellRouting.plan(for: InboxLanding.route) == ShellRoutePlan(tab: .add, path: []))
        #expect(InboxNotice.isNotice(InboxNotice.identifier))
    }

    @Test func openingTheAppWithSomethingNewLandsOnDeVerificatOnce() async throws {
        let landing = try landing()
        let navigator = AppNavigator(isAppLocked: { false })
        let first = [item(at: noon("2026-11-09"))]

        #expect(await landing.didBecomeActive(waiting: { first }, navigator: navigator, isBusy: { false }))
        #expect(navigator.consume() == .intake)
        // De verificat showed it.
        landing.markSeen(first)

        // Back from the background with nothing new: stays where it was.
        landing.didEnterBackground(navigator: navigator)
        #expect(await !landing.didBecomeActive(waiting: { first }, navigator: navigator, isBusy: { false }))

        // Something new arrived meanwhile: lands again.
        let second = first + [item(at: noon("2026-11-10"))]
        landing.didEnterBackground(navigator: navigator)
        #expect(await landing.didBecomeActive(waiting: { second }, navigator: navigator, isBusy: { false }))
        #expect(navigator.consume() == .intake)

        // Becoming active without having left (Control Center, a Face ID prompt): nothing moves.
        #expect(await !landing.didBecomeActive(waiting: { second }, navigator: navigator, isBusy: { false }))
    }

    @Test func aRouteThePersonOpensWins() async throws {
        let landing = try landing()
        let navigator = AppNavigator(isAppLocked: { false })
        let waiting = [item()]
        landing.didEnterBackground(navigator: navigator)
        let reminder = AppRoute.obligation(UUID())
        navigator.open(reminder)
        #expect(navigator.consume() == reminder)
        #expect(await !landing.didBecomeActive(waiting: { waiting }, navigator: navigator, isBusy: { false }))
        #expect(navigator.consume() == nil)

        // Still owed: the next plain return lands.
        landing.didEnterBackground(navigator: navigator)
        #expect(await landing.didBecomeActive(waiting: { waiting }, navigator: navigator, isBusy: { false }))
    }

    @Test func nothingMovesUnderSomethingOpenOrForThePractice() async throws {
        let landing = try landing()
        let navigator = AppNavigator(isAppLocked: { false })
        #expect(await !landing.didBecomeActive(waiting: { [item()] }, navigator: navigator, isBusy: { true }))
        landing.didEnterBackground(navigator: navigator)
        #expect(await !landing.didBecomeActive(waiting: { [item(practice: true)] }, navigator: navigator, isBusy: { false }))
        landing.didEnterBackground(navigator: navigator)
        #expect(await !landing.didBecomeActive(waiting: { [] }, navigator: navigator, isBusy: { false }))
        #expect(navigator.pendingRoute == nil)
    }

    @Test func aLockedAppLandsAfterUnlocking() async throws {
        let landing = try landing()
        let locked = Flag(true)
        let navigator = AppNavigator(isAppLocked: { locked.value })
        #expect(await landing.didBecomeActive(waiting: { [item()] }, navigator: navigator, isBusy: { false }))
        #expect(navigator.consume() == nil)
        locked.value = false
        #expect(navigator.consume() == .intake)
    }

    @Test func seenIsTheNewestRealArrival() throws {
        let landing = try landing()
        landing.markSeen([item(at: noon("2026-11-09")), item(at: noon("2026-11-12"), practice: true)])
        #expect(landing.seenThrough == noon("2026-11-09"))
        landing.markSeen([item(at: noon("2026-11-01"))])
        #expect(landing.seenThrough == noon("2026-11-09"), "Never goes back")
        #expect(InboxLanding.owesLanding(waiting: [item(at: noon("2026-11-10"))], seenThrough: landing.seenThrough))
        #expect(!InboxLanding.owesLanding(waiting: [item(at: noon("2026-11-09"))], seenThrough: landing.seenThrough))
    }
}

@Suite("De verificat: telling items apart")
struct InboxWordingTests {
    let now = noon("2026-11-09")
    let calendar = Calendar.bucharest

    private func row(_ item: InboxItem, _ preview: InboxPreview? = nil, locked: Set<String> = [], unlocked: Bool = false) -> InboxWording.Row {
        InboxWording.row(for: item, preview: preview, lockedCategories: locked, isSessionUnlocked: unlocked, now: now, calendar: calendar)
    }

    @Test func fileNamesWithoutExtensionsAndNoise() {
        #expect(InboxWording.cleanedName("Factura_ENGIE_octombrie.pdf") == "Factura ENGIE octombrie")
        #expect(InboxWording.cleanedName("Contract Digi (1).pdf") == "Contract Digi")
        #expect(InboxWording.cleanedName("Polita RCA copy.pdf") == "Polita RCA")
        #expect(InboxWording.cleanedName("IMG_2041.HEIC") == nil)
        #expect(InboxWording.cleanedName("IMG-20261102-WA0001.jpg") == nil)
        #expect(InboxWording.cleanedName("WhatsApp Image 2026-11-02 at 10.15.32.jpeg") == nil)
        #expect(InboxWording.cleanedName("document (1).pdf") == nil)
        #expect(InboxWording.cleanedName("Scan 2 nov. 2026.pdf") == nil)
        #expect(InboxWording.cleanedName("6F1D2C3B-0000-4000-8000-000000000001.pdf") == nil)
        #expect(InboxWording.cleanedName("   ") == nil)
        #expect(InboxWording.sender(of: "WhatsApp Image 2026-11-02 at 10.15.32.jpeg") == "WhatsApp")
        #expect(InboxWording.sender(of: "IMG-20261102-WA0001.jpg") == "WhatsApp")
        #expect(InboxWording.sender(of: "IMG_2041.HEIC") == nil)
    }

    @Test func namesNeverShowACNPOrACardNumber() throws {
        let cnp = try #require(InboxWording.cleanedName("Buletin 1800101990006.jpg"))
        #expect(cnp == "Buletin")
        let card = try #require(InboxWording.cleanedName("Card 4111 1111 1111 1111.jpg"))
        #expect(!card.contains("1111"))
        #expect(InboxWording.cleanedName("1800101990006.pdf") == nil)
        let shown = row(item(name: "Factura 4111 1111 1111 1111.pdf"))
        #expect(!shown.title.contains("1111") && !shown.detail.contains("1111"))
    }

    @Test func titlesFromTheFileTheAppOrWhatItIsMadeOf() {
        #expect(row(item(name: "Factura_ENGIE_octombrie.pdf")).title == "Factura ENGIE octombrie")
        #expect(row(item(name: nil)).title == "Un PDF")
        #expect(row(item(.text, name: nil)).title == "Un text")
        #expect(row(item(.images, name: "IMG_2041.HEIC")).title == "O poză")
        #expect(row(item(.images, name: "WhatsApp Image 2026-11-02 at 10.15.32.jpeg")).title == "O poză din WhatsApp")
        #expect(row(item(.pdf, name: "IMG-20261102-WA0001.pdf")).title == "Un PDF din WhatsApp")
        #expect(row(item(practice: true)).title == "Factură de probă")
        #expect(row(item(name: "Factura.pdf", at: noon("2026-11-09"))).detail.hasPrefix("Primit azi la "))
    }

    @Test func onceReadTheTitleSaysWhatItIs() {
        let read = InboxPreview(kind: CaptureDocumentKind.utilityInvoice.rawValue, title: "Factură ENGIE Romania S.A.", categoryKey: "subscription", pageCount: 2, hasThumbnail: true)
        let shown = row(item(name: "factura_oct.pdf"), read)
        #expect(shown.title == "Factură ENGIE Romania S.A.")
        // The file's own name is still there, under it, with the pages and the time.
        #expect(shown.detail.hasPrefix("factura oct · 2 pagini · Primit azi la "))
        #expect(shown.showsThumbnail)
        // A name that says the same as the reading isn't repeated.
        let same = InboxPreview(kind: CaptureDocumentKind.rcaPolicy.rawValue, title: "Poliță RCA", categoryKey: "vehicle", pageCount: 1)
        #expect(row(item(name: "Polita RCA.pdf"), same).detail.hasPrefix("Primit azi"))
        // From WhatsApp, with no name of its own.
        #expect(row(item(.images, name: "IMG-20261102-WA0001.jpg"), same).detail.hasPrefix("Din WhatsApp · "))
    }

    @Test func severalPhotosSharedTogetherAreOneItemWithPages() throws {
        let plan = ShareInbox.plan([.image, .image, .image])
        #expect(plan.count == 1 && plan[0].indices == [0, 1, 2])
        let photos = item(.images, name: "IMG_2041.HEIC", files: 3)
        let shown = row(photos)
        #expect(shown.title == "Poze")
        #expect(shown.detail.hasPrefix("3 pagini · "))
        #expect(InboxNotice.content(waiting: [photos])?.title == "Am primit un act")
        // A PDF's pages come from reading it.
        let pdf = row(item(name: "Contract.pdf"), InboxPreview(kind: nil, title: nil, categoryKey: nil, pageCount: 12))
        #expect(pdf.detail.hasPrefix("12 pagini · "))
        #expect(row(item(name: "Contract.pdf"), InboxPreview(kind: nil, title: nil, categoryKey: nil, pageCount: 1)).detail.hasPrefix("Primit"))
    }

    @Test func aLockedKindNamesNothingUntilUnlock() {
        let card = InboxPreview(kind: CaptureDocumentKind.identityCard.rawValue, title: "Carte de identitate", categoryKey: BuiltInTemplates.Key.documents, pageCount: 2, hasThumbnail: true)
        let shared = item(.images, name: "Buletin Manole Corina.jpg", files: 2)
        let closed = row(shared, card, locked: [BuiltInTemplates.Key.documents], unlocked: false)
        #expect(closed.title == "Act protejat")
        #expect(closed.isProtected && !closed.showsThumbnail)
        #expect(!closed.detail.contains("Manole") && !closed.detail.contains("Buletin"))
        #expect(closed.symbol == "lock.fill")

        let open = row(shared, card, locked: [BuiltInTemplates.Key.documents], unlocked: true)
        #expect(open.title == "Carte de identitate")
        #expect(!open.isProtected && open.showsThumbnail)

        // Another category's lock doesn't hide it.
        #expect(row(shared, card, locked: [BuiltInTemplates.Key.health], unlocked: false).title == "Carte de identitate")
        // Not read yet while a lock is closed: it could be a locked one, so no file name.
        let unread = row(shared, nil, locked: [BuiltInTemplates.Key.documents], unlocked: false)
        #expect(unread.title == "Poze" && !unread.detail.contains("Manole"))
        #expect(!unread.showsThumbnail)
    }
}

@Suite("De verificat: reading what waits")
struct InboxPreviewTests {
    private func reading(_ kind: CaptureDocumentKind, _ fields: [(CaptureFieldKey, CaptureValue)], text: String = "") -> CaptureResult {
        CaptureResult(kind: kind, kindConfidence: 0.9,
                      fields: fields.map { CaptureField(key: $0.0, value: $0.1, confidence: 0.9, sourceText: nil, tier: .heuristic) },
                      suggestions: [], reminder: nil, recognizedText: text, barcodes: [], document: nil, notices: [])
    }

    @Test func whatTheReadingSaysItIs() {
        let bill = InboxPreviewer.summary(of: reading(.utilityInvoice, [(.provider, .text("ENGIE Romania S.A."))]))
        #expect(bill.title == "Factură ENGIE Romania S.A.")
        #expect(bill.categoryKey == BuiltInTemplates.Key.subscription)
        let card = InboxPreviewer.summary(of: reading(.identityCard, [(.holderName, .text("Manole Corina"))]))
        #expect(card.title == "Carte de identitate", "A personal document is named by its type, never its holder")
        #expect(card.categoryKey == BuiltInTemplates.Key.documents)
        let unknown = InboxPreviewer.summary(of: reading(.other, []))
        #expect(unknown.kind == nil && unknown.title == nil)
    }

    @Test func aReadingNeverKeepsACNPOrACardNumber() {
        let receipt = InboxPreviewer.summary(of: reading(.fiscalReceipt, [(.productName, .text("Telefon 1800101990006"))]))
        #expect(receipt.title == "Telefon")
        let card = InboxPreviewer.summary(of: reading(.fiscalReceipt, [(.productName, .text("Card 4111 1111 1111 1111"))]))
        #expect(card.title?.contains("1111") == false)
    }

    @Test func noPictureOfWhatMayBeABankCard() {
        #expect(InboxPreviewer.mayKeepPicture(of: reading(.utilityInvoice, [])))
        #expect(!InboxPreviewer.mayKeepPicture(of: reading(.bankCard, [])))
        #expect(!InboxPreviewer.mayKeepPicture(of: reading(.other, [], text: "VALID THRU 08/28")))
        #expect(!InboxPreviewer.mayKeepPicture(of: reading(.other, [], text: "4111 1111 1111 1111")))
    }

    @Test func aPDFsFirstPageIsReadAndItsPagesCounted() throws {
        let inbox = try temporaryInbox()
        defer { try? FileManager.default.removeItem(at: inbox.directory) }
        let renderer = UIGraphicsPDFRenderer(bounds: CGRect(x: 0, y: 0, width: 595, height: 842))
        let pdf = renderer.pdfData { context in
            for page in 1...3 {
                context.beginPage()
                ("Factura ENGIE Romania S.A. pagina \(page)" as NSString).draw(at: CGPoint(x: 40, y: 40), withAttributes: nil)
            }
        }
        let staging = try inbox.makeStagingFolder()
        let name = try inbox.stage(data: pdf, fileExtension: "pdf", into: staging, index: 0)
        let shared = try inbox.commit(staging: staging, payload: .pdf, files: [name], originalName: "Factura.pdf")

        let first = InboxPreviewer.firstPage(of: shared, files: inbox.fileURLs(of: shared))
        #expect(first.count == 3)
        #expect(first.picture != nil)
        guard case .pdf(let data)? = first.payload else {
            Issue.record("A PDF is read as a PDF")
            return
        }
        #expect(PDFDocument(data: data)?.pageCount == 1, "Only the first page is read")
    }
}

@Suite("De verificat: what the app keeps beside an item")
@MainActor
struct InboxPreviewStorageTests {
    @Test func oldManifestsStillReadAndGetAPreview() throws {
        let inbox = try temporaryInbox()
        defer { try? FileManager.default.removeItem(at: inbox.directory) }
        // A first-version manifest (no version) and a second-version one, as earlier builds wrote them.
        let manifests = [
            #"{"id":"6F1D2C3B-0000-4000-8000-000000000001","receivedAt":"2026-11-01T10:00:00Z","payload":"pdf","files":["file-1.pdf"],"originalName":"Factura ENGIE.pdf","isPractice":false}"#,
            #"{"version":2,"id":"6F1D2C3B-0000-4000-8000-000000000002","receivedAt":"2026-11-02T10:00:00Z","payload":"images","files":["file-1.jpg","file-2.jpg"],"isPractice":false}"#,
        ]
        for (index, manifest) in manifests.enumerated() {
            let folder = inbox.directory.appending(path: "6f1d2c3b-0000-4000-8000-00000000000\(index + 1)")
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try Data(manifest.utf8).write(to: folder.appending(path: "manifest.json"))
            for file in ["file-1.pdf", "file-1.jpg", "file-2.jpg"] { try Data("x".utf8).write(to: folder.appending(path: file)) }
        }
        let items = inbox.contents().items
        #expect(items.map(\.version) == [2, 1])
        #expect(inbox.waitingItems().map(\.id) == items.map(\.id))
        #expect(inbox.unreadable().isEmpty)
        let old = try #require(items.last)
        #expect(inbox.preview(of: old) == nil, "Not read yet")
        #expect(InboxWording.row(for: old, preview: nil, lockedCategories: [], isSessionUnlocked: false).title == "Factura ENGIE")

        let preview = InboxPreview(kind: CaptureDocumentKind.utilityInvoice.rawValue, title: "Factură ENGIE Romania S.A.", categoryKey: "subscription", pageCount: 1)
        try inbox.savePreview(preview, thumbnail: Data("jpg".utf8), for: old)
        #expect(inbox.preview(of: old)?.title == "Factură ENGIE Romania S.A.")
        #expect(inbox.preview(of: old)?.hasThumbnail == true)
        #expect(inbox.thumbnailURL(of: old) != nil)
        #expect(inbox.contents().items.count == 2, "A preview beside the manifest changes nothing about reading it")
    }

    @Test func aPreviewItCantUseIsMadeAgainNeverSetAside() throws {
        let inbox = try temporaryInbox()
        defer { try? FileManager.default.removeItem(at: inbox.directory) }
        let shared = try share(inbox, .pdf, name: "Factura.pdf")
        let previewURL = inbox.folder(for: shared.id).appending(path: "preview.json")
        try Data("{ damaged".utf8).write(to: previewURL)
        #expect(inbox.preview(of: shared) == nil)
        let newer = InboxPreview(version: InboxPreview.currentVersion + 1, kind: nil, title: "Din viitor", categoryKey: nil, pageCount: 1)
        try ShareInbox.encoder.encode(newer).write(to: previewURL)
        #expect(inbox.preview(of: shared) == nil)
        #expect(inbox.contents().items.map(\.id) == [shared.id])
        #expect(inbox.unreadable().isEmpty)
    }

    @Test func eachArrivalIsReadOnceAndKept() async throws {
        let inbox = try temporaryInbox()
        defer { try? FileManager.default.removeItem(at: inbox.directory) }
        let shared = try share(inbox, .pdf, name: "factura.pdf")
        let picture = UIGraphicsImageRenderer(size: CGSize(width: 8, height: 8)).jpegData(withCompressionQuality: 0.7) { context in
            UIColor.gray.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 8, height: 8))
        }
        let reads = Counter()
        let intake = IntakeInbox(inbox: inbox, reader: { _, _ in
            reads.count += 1
            return (InboxPreview(kind: CaptureDocumentKind.utilityInvoice.rawValue, title: "Factură ENGIE Romania S.A.", categoryKey: "subscription", pageCount: 2), picture)
        })
        await intake.previewsSettled()
        #expect(intake.previews[shared.id]?.title == "Factură ENGIE Romania S.A.")
        #expect(intake.thumbnails[shared.id] != nil)
        #expect(inbox.preview(of: shared)?.hasThumbnail == true, "Kept beside the item")

        // Read again by a new look (the app opened again): taken from what was kept.
        let again = IntakeInbox(inbox: inbox, reader: { _, _ in
            reads.count += 1
            return (InboxPreview(kind: nil, title: nil, categoryKey: nil, pageCount: 1), nil)
        })
        await again.previewsSettled()
        #expect(reads.count == 1)
        #expect(again.row(for: shared, lockedCategories: [], isSessionUnlocked: false).title == "Factură ENGIE Romania S.A.")
    }
}
