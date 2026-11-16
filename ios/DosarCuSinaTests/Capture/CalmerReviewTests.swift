import Foundation
import SwiftData
import Testing
@testable import DosarCuSina

// The capture review asks less and says one thing at a time: closing asks only after a change
// of the person's, the notices come one by one by one rule, "Unde îl pun" offers what fits,
// De verificat's item can be taken out from its review, and a visit ends once. Placeholder data only.

private func field(_ key: CaptureFieldKey, _ value: CaptureValue, confidence: Double = 0.95) -> CaptureField {
    CaptureField(key: key, value: value, confidence: confidence, sourceText: nil, tier: .heuristic)
}

private func day(_ iso: String) -> CaptureValue {
    let parts = iso.split(separator: "-").compactMap { Int($0) }
    return .day(CalendarDay(printedYear: parts[0], month: parts[1], day: parts[2])!)
}

/// A reading routed the way the engine routes it.
private func capture(_ kind: CaptureDocumentKind, _ fields: [CaptureField], notices: [CaptureNotice] = []) -> CaptureResult {
    let routing = CaptureRouter.route(kind: kind, kindConfidence: 0.95, fields: fields)
    return CaptureResult(kind: kind, kindConfidence: 0.95, fields: fields, suggestions: routing.suggestions, reminder: routing.reminder,
                         recognizedText: "", barcodes: [], document: nil, notices: notices)
}

/// An ENGIE gas bill with placeholder codes.
private func gasBill() -> CaptureResult {
    capture(.utilityInvoice, [
        field(.provider, .text("ENGIE Romania S.A.")),
        field(.serviceKind, .text(ServiceKind.gas)),
        field(.clcCode, .text("DEG0000000000001")),
        field(.invoiceNumber, .text("EX 20261005")),
        field(.issueDate, day("2026-10-05")),
        field(.dueDate, day("2026-11-20")),
        field(.total, .money(Money(Decimal(string: "245.30")!, currency: "RON"))),
    ])
}

@MainActor
private func assets(_ context: ModelContext) throws -> [Asset] {
    try context.fetch(FetchDescriptor<Asset>())
}

@MainActor
private func create(_ name: String, _ key: String, _ context: ModelContext) throws -> Asset {
    let template = try #require(try TemplateStore(context: context).template(forKey: key))
    return try AssetActions(context: context).create(name: name, template: template, values: FieldValues())
}

// MARK: - Closing the review

@Suite("The review asks before closing only after a change of the person's")
@MainActor
struct ReviewDiscardRuleTests {
    @Test func aReviewLeftAsReadClosesAtOnce() throws {
        let context = try makeContext()
        let review = CaptureReview(result: gasBill(), assets: try assets(context), context: context)
        #expect(!review.hasPersonsChanges, "Nothing typed or chosen: closing loses nothing, so it doesn't ask")

        var empty = review
        empty.addField(.contractNumber)
        #expect(!empty.hasPersonsChanges, "An empty field added and left empty changes nothing")
    }

    @Test func everyKindOfEditCounts() throws {
        let context = try makeContext()
        let home = try create("Apartament", BuiltInTemplates.Key.home, context)
        let review = CaptureReview(result: gasBill(), assets: try assets(context), context: context)

        var value = review
        let index = try #require(value.fields.firstIndex { $0.key == .total })
        value.fields[index].confirm(.money(Money(Decimal(string: "250.00")!, currency: "RON")))
        #expect(value.hasPersonsChanges, "A value typed")

        var same = review
        same.fields[index].confirm(review.fields[index].value)
        #expect(!same.hasPersonsChanges, "Typed back as it was read: nothing to lose")

        var cleared = review
        cleared.fields[index].confirm(nil)
        #expect(cleared.hasPersonsChanges, "A value cleared")

        var title = review
        title.title = "Factură gaz octombrie"
        #expect(title.hasPersonsChanges, "The title")

        var place = review
        place.choosePlace(place.destination)
        #expect(!place.hasPersonsChanges, "The place shown, chosen again")
        let other: CaptureReview.Destination = place.destination == .asset(home.id) ? .none : .asset(home.id)
        place.choosePlace(other)
        #expect(place.hasPersonsChanges, "Another place")

        var reminder = review
        reminder.remindsToPay.toggle()
        #expect(reminder.hasPersonsChanges, "The reminder to pay")

        var another = review
        another.isAnotherBill = true
        #expect(another.hasPersonsChanges, "„E altă factură”")

        var turned = review
        turned.pageChoices[0] = PageChoice()
        #expect(turned.hasPersonsChanges, "A page turned or framed")
    }

    @Test func aReadingAgainIsNotAChangeButKeepsTheirs() throws {
        let context = try makeContext()
        let all = try assets(context)
        let review = CaptureReview(result: gasBill(), assets: all, context: context)
        let again = CaptureReview(result: gasBill(), assets: all, context: context).carryingEdits(from: review, assets: all)
        #expect(!again.hasPersonsChanges, "Read again with nothing of theirs: still nothing to lose")

        var edited = review
        edited.title = "Factură gaz octombrie"
        let keptEdit = CaptureReview(result: gasBill(), assets: all, context: context).carryingEdits(from: edited, assets: all)
        #expect(keptEdit.hasPersonsChanges, "Their title survives the new reading, and closing still asks")
    }
}

// MARK: - Notices

@Suite("The review's notices: one at a time, by one rule")
struct ReviewNoticeTests {
    private let filed = FiledPaper(entryID: UUID(), match: .number, sectionID: nil, section: "Gaz", day: CalendarDay("2026-10-05"))

    @Test func theMostImportantComesFirstAndNothingIsLost() {
        let notices = ReviewNotice.present(
            asksToSend: true, filedBill: filed, samePhoto: nil, asksForBackPage: true, readingBackPage: false,
            backPageError: nil, resultNotices: [.pagesTruncated(readPages: 10, totalPages: 40), .littleTextRecognized, .machineReadableZoneUnverified],
            cloudMessage: "Nu ești conectat la internet."
        )
        #expect(notices == [
            .askToSend, .alreadyFiled(filed), .checkNumbers, .cloudFailed(message: "Nu ești conectat la internet."),
            .backPage(isReading: false, error: nil), .hardToRead, .pagesTruncated(read: 10),
        ], "A question first, then a paper already filed, values to check, what failed, a better reading, what is only worth knowing")
    }

    @Test func theBackBeingReadComesFirst() {
        let notices = ReviewNotice.present(
            asksToSend: false, filedBill: nil, samePhoto: UUID(), asksForBackPage: true, readingBackPage: true,
            backPageError: "Încearcă o poză mai clară.", resultNotices: [.littleTextRecognized], cloudMessage: nil
        )
        #expect(notices.first == .backPage(isReading: true, error: nil), "What is happening now shows, without the last error")
        #expect(notices.count == 3)
    }

    @Test func aBillAlreadyFiledIsSaidOnceAndQuietReadingsSayNothing() {
        let both = ReviewNotice.present(
            asksToSend: false, filedBill: filed, samePhoto: UUID(), asksForBackPage: false, readingBackPage: false,
            backPageError: nil, resultNotices: [.littleTextRecognized, .littleTextRecognized, .onDeviceModelFailed, .valueFailedCheck], cloudMessage: nil
        )
        #expect(both == [.alreadyFiled(filed), .hardToRead], "The same photo is part of the bill already filed; each notice once; what the review marks on the values isn't a notice")

        let quiet = ReviewNotice.present(
            asksToSend: false, filedBill: nil, samePhoto: nil, asksForBackPage: false, readingBackPage: false,
            backPageError: nil, resultNotices: [], cloudMessage: nil
        )
        #expect(quiet.isEmpty)
    }

    @Test func tiesKeepTheirOrder() {
        let sorted = ReviewNotice.byImportance([.pagesTruncated(read: 2), .hardToRead, .pagesTruncated(read: 3)])
        #expect(sorted == [.hardToRead, .pagesTruncated(read: 2), .pagesTruncated(read: 3)])
    }
}

// MARK: - Where it goes

@Suite("„Unde îl pun” offers what fits the document")
@MainActor
struct CaptureDestinationsTests {
    @MainActor
    private struct Binder {
        let behaviors: [String: CategoryBehavior]
        let car = CaptureDestinations.Place(id: UUID(), templateKey: BuiltInTemplates.Key.vehicle)
        let home = CaptureDestinations.Place(id: UUID(), templateKey: BuiltInTemplates.Key.home)
        let gas = CaptureDestinations.Place(id: UUID(), templateKey: BuiltInTemplates.Key.subscription)
        let person = CaptureDestinations.Place(id: UUID(), templateKey: BuiltInTemplates.Key.member)
        let idCard = CaptureDestinations.Place(id: UUID(), templateKey: BuiltInTemplates.Key.documents)
        let cat = CaptureDestinations.Place(id: UUID(), templateKey: BuiltInTemplates.Key.pet)

        var places: [CaptureDestinations.Place] { [car, home, gas, person, idCard, cat] }

        init() throws {
            behaviors = try TemplateStore(context: try makeContext()).behaviorsByKey()
        }

        func offer(_ kind: CaptureDocumentKind, current: CaptureReview.Destination = .none, fromAPerson: Bool = false) -> CaptureDestinations.Offer {
            CaptureDestinations.offer(kind: kind, cover: nil, suggestedKeys: [], holdsPersonalDocuments: fromAPerson,
                                      current: current, places: places, behaviors: behaviors)
        }
    }

    @Test func anInspectionReportGoesToACar() throws {
        let binder = try Binder()
        let offer = binder.offer(.itpReport)
        #expect(offer.fitting == [binder.car.id])
        #expect(offer.newSectionKey == BuiltInTemplates.Key.vehicle, "„Secțiune nouă în Mașini” through AddSectionFlow")
    }

    @Test func aBillGoesToASubscriptionOrAHome() throws {
        let binder = try Binder()
        #expect(binder.offer(.utilityInvoice).fitting == [binder.home.id, binder.gas.id])
    }

    @Test func aPersonalDocumentGoesToAPersonNeverToAnotherDocument() throws {
        let binder = try Binder()
        let offer = binder.offer(.identityCard)
        #expect(offer.fitting == [binder.person.id], "Each person's documents are reached through the person")
        #expect(offer.newSectionKey == nil, "A new person is „Persoană nouă”, named after the holder")

        let fromAPerson = binder.offer(.fiscalReceipt, fromAPerson: true)
        #expect(fromAPerson.fitting?.contains(binder.person.id) == true, "Started from a person's documents: people fit")
    }

    @Test func theChoiceShownIsNeverHidden() throws {
        let binder = try Binder()
        let offer = binder.offer(.itpReport, current: .asset(binder.cat.id))
        #expect(offer.fitting == [binder.car.id, binder.cat.id])
    }

    @Test func aDocumentThatFitsNothingInParticularListsEverything() throws {
        let binder = try Binder()
        #expect(binder.offer(.other) == CaptureDestinations.Offer(fitting: nil, newSectionKey: nil))
    }

    @Test func theNameOnlyShortcutIsSwitchedOff() {
        #expect(!CaptureDestinations.makesSectionFromAName, "A new section is made by AddSectionFlow")
    }
}

// MARK: - De verificat

@Suite("Taking an item out of De verificat from its review")
@MainActor
struct InboxRemovalTests {
    private func sharedItem() throws -> (inbox: ShareInbox, intake: IntakeInbox, item: InboxItem) {
        let folder = FileManager.default.temporaryDirectory.appending(path: "dosar-remove-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let inbox = ShareInbox(directory: folder)
        let staging = try inbox.makeStagingFolder()
        let file = try inbox.stage(data: Data("placeholder".utf8), fileExtension: "pdf", into: staging, index: 0)
        let item = try inbox.commit(staging: staging, payload: .pdf, files: [file], originalName: "factura-engie.pdf", receivedAt: noon("2026-11-09"))
        return (inbox, IntakeInbox(inbox: inbox, reader: nil), item)
    }

    @Test func itLeavesWithAnulezaAndComesBack() throws {
        let shared = try sharedItem()
        defer { try? FileManager.default.removeItem(at: shared.inbox.directory) }
        let toast = shared.intake.dismissal(of: shared.item, title: "Factură ENGIE")
        #expect(String(localized: toast.title) == "Am scos „Factură ENGIE” din De verificat.")
        #expect(toast.offersAction)
        #expect(shared.intake.waiting.isEmpty, "Hidden at once")
        #expect(shared.inbox.contents().items.map(\.id) == [shared.item.id], "Kept while Anulează can bring it back")

        toast.action?()
        #expect(shared.intake.waiting.map(\.id) == [shared.item.id], "Anulează brings it back")
    }

    @Test func itGoesForGoodOnceTheToastIsGone() throws {
        let shared = try sharedItem()
        defer { try? FileManager.default.removeItem(at: shared.inbox.directory) }
        let toast = shared.intake.dismissal(of: shared.item, title: "Factură ENGIE")
        toast.whenGone?()
        #expect(shared.inbox.contents().items.isEmpty)
    }

    @Test func theReviewClosesWithItsOwnToast() throws {
        let shared = try sharedItem()
        defer { try? FileManager.default.removeItem(at: shared.inbox.directory) }
        let toast = shared.intake.dismissal(of: shared.item, title: "Factură ENGIE")
        let result = CaptureFlowResult.removedFromInbox(toast: toast).leaving(shared.item, inbox: shared.intake)
        guard case .removedFromInbox(let shown) = result else { Issue.record("Still the removal"); return }
        #expect(shown.id == toast.id, "Leaving the capture changes nothing: the removal's toast says when it goes")
        #expect(shared.inbox.contents().items.map(\.id) == [shared.item.id])

        // Closed without saving: it stays where it was.
        let kept = try sharedItem()
        defer { try? FileManager.default.removeItem(at: kept.inbox.directory) }
        _ = CaptureFlowResult.dismissed.leaving(kept.item, inbox: kept.intake)
        #expect(kept.intake.waiting.map(\.id) == [kept.item.id])
    }
}

// MARK: - A visit ends once

@Suite("A visit ends once, with the toast every save shows")
@MainActor
struct VisitEndingTests {
    @Test func theFormClosesWithTheUndoToast() async throws {
        #expect(!VisitEnding.showsWhatChanged, "„Ce s-a schimbat” with its own Gata and Anulează vizita is switched off")
        let house = try UndoReceiptTests.Household.make()
        let before = try UndoReceiptTests.database(house.context)
        let receipt = try await UndoReceiptTests.Step.fileAVisitWithANewPhoto.run(in: house)

        let toast = VisitEnding.toast(receipt)
        #expect(String(localized: toast.title) == "Vizita e în istoric.")
        #expect(toast.offersAction, "Anulează, from Istoric as from capture and „Scriu eu”")
        guard case .visitSaved(let fromCapture) = CaptureFlowResult.visit(receipt: receipt) else { Issue.record("A visit"); return }
        #expect(String(localized: fromCapture.title) == String(localized: toast.title), "One toast for every way in")

        try #require(toast.receipt).undo()
        #expect(UndoReceiptTests.differences(before, try UndoReceiptTests.database(house.context)).isEmpty, "Anulează takes the whole visit back")
    }
}
