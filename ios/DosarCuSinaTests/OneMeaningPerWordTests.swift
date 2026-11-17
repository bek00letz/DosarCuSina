import Foundation
import SwiftData
import SwiftUI
import Testing
@testable import DosarCuSina

/// One meaning per word (docs/COPY_GUIDE.md, "Words with one meaning"): „Gata” marks a deadline
/// done, „Anulează” takes back the step just taken, „De verificat” is the share inbox. The
/// architecture check keeps the literals in their homes; these pin what the homes say, and that
/// completing a deadline starts the same way from its page and from Urmează (`CompletionEntry`).
@MainActor
@Suite("One meaning per word")
struct OneMeaningPerWordTests {
    /// Every kind but a chore asks something before it is done.
    nonisolated static let kindsThatAsk = ObligationKind.allCases.filter { !CompletionKind.own($0).shape.isOneTap }

    // MARK: The repair list, the inbox and a check worth a look

    @Test func theRepairListIsDeCorectat() {
        #expect(SettingsPage.repairs.title == "De corectat")
        #expect(SettingsStatus.repairs(0) == "Nimic de corectat")
        #expect(SettingsStatus.repairs(1) == "Un lucru de corectat")
        #expect(SettingsStatus.repairs(2) == "2 lucruri de corectat")
        #expect(SettingsStatus.repairs(20) == "20 de lucruri de corectat")
    }

    @Test func aReadinessCheckWorthALookIsNotTheInbox() {
        #expect(ReadinessStatus.warning.spokenTitle == "Merită o privire")
        for status in ReadinessStatus.allCases {
            #expect(status.spokenTitle != "De verificat", "\(status) reads like the share inbox")
        }
    }

    @Test func backupsAreCopiiDeSiguranta() {
        #expect(SettingsPage.iCloudAndBackups.title == "iCloud și copii de siguranță")
    }

    // MARK: Gata and Anulează

    @Test func gataIsOnlyForAChoreDoneInOneTap() {
        for kind in CompletionKind.allCases {
            let shape = kind.shape
            if shape.isOneTap {
                #expect(shape.actionTitle == "Gata", "\(kind)")
                #expect(shape.menuTitle == "Gata", "\(kind)")
            } else {
                #expect(shape.actionTitle == "Am rezolvat", "\(kind): the page's button")
                #expect(shape.menuTitle == "Am rezolvat…", "\(kind): Urmează's menu opens the same sheet")
            }
        }
        #expect(CompletionKind.chore.shape.isOneTap && CompletionKind.own(.routine) == .chore)
    }

    @Test func theShareSheetClosesAndNeverSaysGataOrAnuleaza() {
        #expect(ShareConfirmation.Action.close.title == "Închide")
        #expect(ShareConfirmation.Action.cancel.title == "Renunță")
    }

    @Test func scriuEuOffersOnlyWhatIsTyped() {
        #expect(!ManualAddFlow.offersDocumentPhoto, "A photo is never behind „Scriu eu”")
    }

    // MARK: One completion entry

    @Test func aChoreIsDoneAtOnceFromEitherPlace() throws {
        let context = try makeContext()
        let watering = try ObligationActions(context: context)
            .create(title: "Udat", kind: .routine, dueDay: CalendarDay(Date()), for: nil, recurrence: .interval(.days(7), anchor: .completion))

        let start = try CompletionEntry(context: context).start(watering) { _, _ in }

        guard case .done(let toast) = start else {
            Issue.record("A chore is done in one tap")
            return
        }
        #expect(watering.history.count == 1)
        #expect(toast.receipt?.canUndo == true, "Its toast takes it back")
    }

    @Test("Any other kind opens „Am rezolvat”, and nothing is done until it saves",
          arguments: Self.kindsThatAsk)
    func anyOtherKindAsksFirst(_ kind: ObligationKind) throws {
        let context = try makeContext()
        let deadline = try ObligationActions(context: context)
            .create(title: "Termen", kind: kind, dueDay: CalendarDay(Date()), for: nil)
        let due = deadline.dueDay

        let start = try CompletionEntry(context: context).start(deadline) { _, _ in }

        guard case .asks(let request) = start else {
            Issue.record("\(kind) asks before it is done")
            return
        }
        #expect(request.obligationID == deadline.id)
        #expect(deadline.history.isEmpty, "Nothing done yet")
        #expect(deadline.dueDay == due)
    }
}
