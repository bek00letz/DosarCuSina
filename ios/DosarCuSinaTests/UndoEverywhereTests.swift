import Foundation
import SwiftData
import Testing
@testable import DosarCuSina

/// "Anulează" for every step: what a delete takes comes back whole, and so does everything
/// outside the database that follows the save (reminders, the badge, the widget, the
/// iPhone's search). The records themselves are pinned step by step in `UndoReceiptTests`.
/// Placeholder data only.
@MainActor
@Suite("Undo everywhere")
struct UndoEverywhereTests {
    typealias Step = UndoReceiptTests.Step

    // MARK: What a delete takes

    @Test("What goes with a deleted record is read from the schema's own delete rules")
    func ownershipFollowsTheSchema() {
        let owned = UndoableRecords.ownedRelationships.filter { !$0.value.isEmpty }
        #expect(owned == [
            "Asset": ["obligations", "attachments", "history", "measurements"],
            "HistoryEntry": ["items"],
            "Attachment": ["pages"],
        ])
    }

    @Test("A deleted section's receipt names everything it took and everything that lost a link")
    func aDeletedSectionsReceiptNamesEverything() throws {
        let house = try UndoReceiptTests.Household.make()
        let receipt = try AssetActions(context: house.context, calendar: .bucharest, now: { noon("2026-11-03") }).delete(house.corina, children: .keep)
        #expect(receipt.touched.contains(RecordRef(house.card)), "What was filed under it moves to the top, and comes back under it")

        let home = try UndoReceiptTests.Household.make()
        let homeReceipt = try AssetActions(context: home.context, calendar: .bucharest, now: { noon("2026-11-03") }).delete(home.home)
        let invoicePages = try home.context.fetch(FetchDescriptor<AttachmentPage>())
        #expect(invoicePages.isEmpty, "The invoice's pages went with the home")
        try homeReceipt.undo()
        let back = try home.context.fetch(FetchDescriptor<AttachmentPage>())
        #expect(back.compactMap(\.imageData) == [Data([5, 6, 7])], "The page's picture is back")
        #expect(back.first?.attachment?.historyEntry?.asset?.name == "Apartament", "And so is every link up to the home")
    }

    // MARK: Outside the database

    /// What the coordinator leaves outside the app after a pass.
    struct Outside: Equatable {
        var reminders: [String: String?]
        var badge: Int?
        var widget: WidgetFeed?
        var spotlight: [String: SpotlightEntry]
    }

    @MainActor
    final class World {
        let house: UndoReceiptTests.Household
        let center = FakeNotificationCenter(status: .authorized)
        let index = FakeSpotlightIndex()
        let folder: URL
        let coordinator: SideEffectsCoordinator

        init() throws {
            house = try UndoReceiptTests.Household.make()
            folder = URL.temporaryDirectory.appending(path: "undo-\(UUID().uuidString)")
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let defaults = try #require(UserDefaults(suiteName: "tests.\(UUID().uuidString)"))
            coordinator = SideEffectsCoordinator(
                container: house.context.container,
                notificationClient: center,
                widgetWriter: WidgetSnapshotWriter(directory: folder),
                inboxNotices: FakeInboxNoticeCenter(allowed: false),
                waitingInboxItems: { nil },
                preferences: AppPreferences(defaults: defaults),
                calendar: .bucharest,
                now: { noon("2026-11-03") }
            )
            coordinator.register(SpotlightIndexer(
                index: index,
                ledger: SpotlightLedgerStore(url: folder.appending(path: "spotlight/ledger.json")),
                isEnabled: { true }
            ))
        }

        func outside() async throws -> Outside {
            await coordinator.reconcileNow()
            let pending = await center.pending()
            let widget = try? Data(contentsOf: folder.appending(path: WidgetFeed.fileName))
            return Outside(
                reminders: Dictionary(uniqueKeysWithValues: pending.map { ($0.identifier, $0.fingerprint) }),
                badge: await center.badge,
                widget: widget.flatMap(WidgetFeed.decode),
                spotlight: index.items
            )
        }
    }

    @Test("After Anulează, reminders, badge, widget and the iPhone's search are as before",
          arguments: [Step.deleteADeadline, .deleteACarWithItsDeadlinesVisitsAndReadings, .deleteAPersonWithTheirDocuments,
                      .deleteADocumentWithItsPages, .pauseADeadline, .archiveADeadline, .fileAReviewOfANewPhoto])
    func sideEffectsFollowTheUndo(_ step: Step) async throws {
        let world = try World()
        try await step.setUp(in: world.house)
        let before = try await world.outside()
        #expect(!before.reminders.isEmpty && !before.spotlight.isEmpty, "The household reminds and is searchable")

        let receipt = try await step.run(in: world.house)
        let after = try await world.outside()
        #expect(after != before, "The step changed what is outside the app")

        try receipt.undo()
        let undone = try await world.outside()
        #expect(undone.reminders == before.reminders, "The same reminders are planned again")
        #expect(undone.badge == before.badge)
        #expect(undone.widget == before.widget)
        #expect(undone.spotlight == before.spotlight)
    }

    // MARK: The toasts

    @Test("A deletion's toast offers Anulează, stays longer, and says what went")
    func aDeletionsToast() throws {
        let house = try UndoReceiptTests.Household.make()
        let receipt = try ObligationActions(context: house.context, calendar: .bucharest).delete(house.kit)
        let toast = DSToast.undoDeletion("Am șters termenul „Trusă medicală”.", receipt: receipt)
        #expect(toast.offersAction)
        #expect(toast.duration == DSToast.deletionDuration)
        #expect(DSToast.deletionDuration > DSToast.undo("", receipt: receipt).duration)
        try receipt.undo()
        #expect(!toast.offersAction, "Once used, it offers nothing")
    }

    @Test("The review's Salvează closes with a toast that takes the filing back")
    func theReviewsToastTakesTheFilingBack() async throws {
        let house = try UndoReceiptTests.Household.make()
        let before = try UndoReceiptTests.database(house.context)
        let receipt = try await Step.fileAReviewOfANewPhoto.run(in: house)

        guard case .filed(let toast, let assetID) = CaptureFlowResult.filing(in: house.car.name, assetID: house.car.id, receipt: receipt) else {
            Issue.record("A filing")
            return
        }
        #expect(assetID == house.car.id)
        #expect(String(localized: toast.title) == "Salvat în VW Golf 2018.")
        #expect(toast.offersAction)
        try #require(toast.receipt).undo()
        #expect(UndoReceiptTests.differences(before, try UndoReceiptTests.database(house.context)).isEmpty)

        guard case .filed(let plain, _) = CaptureFlowResult.filing(in: nil, assetID: nil, receipt: nil) else { return }
        #expect(String(localized: plain.title) == "Actul e salvat.")
        #expect(!plain.offersAction, "Without a receipt there is nothing to take back")
    }

    // MARK: The share inbox

    @Test("An item filed or dismissed from De verificat waits, hidden, until its toast is gone, and Anulează brings it back")
    func anItemLeavingTheInboxWaitsForItsToast() throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: "undo-inbox-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let inbox = ShareInbox(directory: folder)
        let staging = try inbox.makeStagingFolder()
        let file = try inbox.stage(data: Data("placeholder".utf8), fileExtension: "pdf", into: staging, index: 0)
        let item = try inbox.commit(staging: staging, payload: .pdf, files: [file], originalName: "factura.pdf", receivedAt: noon("2026-11-09"))
        let intake = IntakeInbox(inbox: inbox, reader: nil)
        #expect(intake.count == 1)

        intake.setAside(item)
        #expect(intake.waiting.isEmpty && intake.count == 0, "Hidden at once")
        #expect(inbox.contents().items.map(\.id) == [item.id], "But still kept, while Anulează can bring it back")
        intake.refresh()
        #expect(intake.waiting.isEmpty, "Reading the folder again doesn't bring it back")

        intake.keep(item)
        #expect(intake.waiting.map(\.id) == [item.id], "Anulează brings it back")

        intake.setAside(item)
        intake.remove(item)
        #expect(intake.waiting.isEmpty)
        #expect(inbox.contents().items.isEmpty, "Once the toast is gone, it leaves for good")
        #expect(intake.leaving.isEmpty)
    }

    /// One shared PDF waiting in De verificat, and the inbox that shows it.
    private func sharedItem() throws -> (inbox: ShareInbox, intake: IntakeInbox, item: InboxItem) {
        let folder = FileManager.default.temporaryDirectory.appending(path: "undo-visit-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let inbox = ShareInbox(directory: folder)
        let staging = try inbox.makeStagingFolder()
        let file = try inbox.stage(data: Data("placeholder".utf8), fileExtension: "pdf", into: staging, index: 0)
        let item = try inbox.commit(staging: staging, payload: .pdf, files: [file], originalName: "factura-service.pdf", receivedAt: noon("2026-11-09"))
        return (inbox, IntakeInbox(inbox: inbox, reader: nil), item)
    }

    @Test("A visit saved through capture closes with Anulează, and the item it came from waits for it")
    func aVisitThroughCaptureCanBeTakenBack() async throws {
        let house = try UndoReceiptTests.Household.make()
        let before = try UndoReceiptTests.database(house.context)
        let receipt = try await Step.fileAVisitWithANewPhoto.run(in: house)
        let shared = try sharedItem()

        let result = CaptureFlowResult.visit(receipt: receipt).leaving(shared.item, inbox: shared.intake)
        guard case .visitSaved(let toast) = result else { Issue.record("A visit"); return }
        #expect(String(localized: toast.title) == "Vizita e în istoric.")
        #expect(toast.offersAction, "Anulează is there once the capture has closed")
        #expect(shared.intake.waiting.isEmpty, "The shared invoice is hidden from De verificat")
        #expect(shared.inbox.contents().items.map(\.id) == [shared.item.id], "But kept while Anulează can bring it back")

        try #require(toast.receipt).undo()
        toast.afterUndo?()
        #expect(UndoReceiptTests.differences(before, try UndoReceiptTests.database(house.context)).isEmpty,
                "The visit, its invoice, its firm and its reading are gone")
        #expect(shared.intake.waiting.map(\.id) == [shared.item.id], "And the invoice waits in De verificat again")
    }

    @Test("A visit kept: its item leaves once the toast is gone; nothing saved leaves it there")
    func aVisitKeptLetsItsItemGo() async throws {
        let house = try UndoReceiptTests.Household.make()
        let receipt = try await Step.fileAVisitWithANewPhoto.run(in: house)
        let shared = try sharedItem()
        let result = CaptureFlowResult.visit(receipt: receipt).leaving(shared.item, inbox: shared.intake)
        result.toast?.whenGone?()
        #expect(shared.inbox.contents().items.isEmpty, "Gone for good once the undo can't come")

        let other = try sharedItem()
        _ = CaptureFlowResult.dismissed.leaving(other.item, inbox: other.intake)
        #expect(other.intake.waiting.map(\.id) == [other.item.id], "Closed without saving: still waiting")
    }

    @Test("Onboarding's own capture offers Anulează, and taking it back offers the photo again")
    func onboardingsCaptureCanBeTakenBack() async throws {
        let house = try UndoReceiptTests.Household.make()
        let before = try UndoReceiptTests.database(house.context)
        let receipt = try await Step.fileAReviewOfANewPhoto.run(in: house)
        final class Flag { var isOn = false }
        let takenBack = Flag()
        let filed = try #require(OnboardingFlow.photoFiled(.filing(in: house.car.name, assetID: house.car.id, receipt: receipt)) { takenBack.isOn = true })
        #expect(String(localized: filed.message) == "Salvat în VW Golf 2018.")
        #expect(filed.toast.offersAction)

        try #require(filed.toast.receipt).undo()
        filed.toast.afterUndo?()
        #expect(takenBack.isOn, "The photo step offers the photo again")
        #expect(UndoReceiptTests.differences(before, try UndoReceiptTests.database(house.context)).isEmpty)
        #expect(OnboardingFlow.photoFiled(.dismissed) {} == nil, "Nothing saved, nothing to say")
    }

    @Test("Deleting a firm, a category of one's own and the examples each offer Anulează")
    func theLastDeletionsOfferAnuleaza() async throws {
        for step in [Step.deleteAFirm, .deleteACategoryOfOnesOwn, .removeTheExamples] {
            let house = try UndoReceiptTests.Household.make()
            try await step.setUp(in: house)
            let receipt = try await step.run(in: house)
            let toast = DSToast.undoDeletion("Am șters.", receipt: receipt)
            #expect(toast.offersAction, "\(step.rawValue)")
            #expect(toast.duration == DSToast.deletionDuration)
        }
    }
}
