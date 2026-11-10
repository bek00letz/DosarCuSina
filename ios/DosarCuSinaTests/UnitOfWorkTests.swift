import Foundation
import LocalAuthentication
import SwiftData
import Testing
@testable import DosarCuSina

private struct ForcedFailure: Error {}

/// One step for the person is one unit of work: everything is kept, or nothing.
@Suite("Unit of work")
@MainActor
struct UnitOfWorkTests {

    private func count<T: PersistentModel>(_ type: T.Type, in context: ModelContext) throws -> Int {
        try context.fetchCount(FetchDescriptor<T>())
    }

    @Test("Actions inside a unit don't save on their own, and a failure keeps none of them")
    func failureRollsBackEverything() async throws {
        let context = try makeContext()
        let template = try #require(try TemplateStore(context: context).template(forKey: BuiltInTemplates.Key.vehicle))
        let assetsBefore = try count(Asset.self, in: context)
        let obligationsBefore = try count(Obligation.self, in: context)
        var afterCommitRan = false

        #expect(throws: ForcedFailure.self) {
            try UnitOfWork.perform(in: context) {
                let car = try AssetActions(context: context).create(name: "VW Golf", template: template, values: FieldValues())
                _ = try ObligationActions(context: context).create(title: "RCA", kind: .insurance, dueDay: CalendarDay("2027-01-10"), for: car)
                UnitOfWork.afterCommit(in: context) { afterCommitRan = true }
                throw ForcedFailure()
            }
        }
        #expect(try count(Asset.self, in: context) == assetsBefore)
        #expect(try count(Obligation.self, in: context) == obligationsBefore)
        await Task.yield()
        #expect(!afterCommitRan, "Nothing that waits for the save runs when it fails")
        #expect(!UnitOfWork.isOpen(in: context))
    }

    @Test("A failed final save rolls everything back too; a later unit works normally")
    func failedCommitRollsBack() async throws {
        let context = try makeContext()
        let template = try #require(try TemplateStore(context: context).template(forKey: BuiltInTemplates.Key.vehicle))
        let before = try count(Asset.self, in: context)

        UnitOfWork.failNextCommitForTesting(ForcedFailure(), in: context)
        #expect(throws: ForcedFailure.self) {
            try UnitOfWork.perform(in: context) {
                _ = try AssetActions(context: context).create(name: "VW Golf", template: template, values: FieldValues())
            }
        }
        #expect(try count(Asset.self, in: context) == before)

        try UnitOfWork.perform(in: context) {
            _ = try AssetActions(context: context).create(name: "VW Golf", template: template, values: FieldValues())
        }
        #expect(try count(Asset.self, in: context) == before + 1)
    }

    @Test("A unit opened inside another joins it")
    func nestedUnitsJoin() throws {
        let context = try makeContext()
        let template = try #require(try TemplateStore(context: context).template(forKey: BuiltInTemplates.Key.vehicle))
        let before = try count(Asset.self, in: context)

        #expect(throws: ForcedFailure.self) {
            try UnitOfWork.perform(in: context) {
                try UnitOfWork.perform(in: context) {
                    _ = try AssetActions(context: context).create(name: "VW Golf", template: template, values: FieldValues())
                }
                #expect(context.hasChanges, "The inner unit didn't save on its own")
                throw ForcedFailure()
            }
        }
        #expect(try count(Asset.self, in: context) == before)
    }

    @Test("A unit's rollback takes back only its own changes, never what another screen left unsaved")
    func rollbackKeepsOthersChanges() throws {
        let context = try makeContext()
        let template = try #require(try TemplateStore(context: context).template(forKey: BuiltInTemplates.Key.vehicle))
        let car = try AssetActions(context: context).create(name: "VW Golf", template: template, values: FieldValues())
        car.notes = "Schimb de ulei la 15 000 km"
        let obligationsBefore = try count(Obligation.self, in: ModelContext(context.container))
        #expect(throws: ForcedFailure.self) {
            try UnitOfWork.perform(in: context) {
                _ = try ObligationActions(context: context).create(title: "RCA", kind: .insurance, dueDay: CalendarDay("2027-01-10"), for: car)
                throw ForcedFailure()
            }
        }
        #expect(car.notes == "Schimb de ulei la 15 000 km")
        if #available(iOS 27, *) {
            #expect(car.obligations?.isEmpty ?? true)
        } else {
            // iOS 26 keeps a rolled-back record in a relationship already loaded in
            // memory until the next fetch; nothing of it was saved (checked below).
            withKnownIssue("iOS 26 keeps a rolled-back record in a loaded relationship", isIntermittent: true) {
                #expect(car.obligations?.isEmpty ?? true)
            }
        }
        #expect(try count(Obligation.self, in: ModelContext(context.container)) == obligationsBefore, "The deadline was never saved")
        let fresh = ModelContext(context.container)
        #expect(try fresh.fetch(FetchDescriptor<Asset>()).first { $0.id == car.id }?.notes == "Schimb de ulei la 15 000 km", "It was saved, not lost")
    }

    @Test("A filing that waits doesn't take another screen's save with it when it fails")
    func waitingFilingKeepsAnUnrelatedSave() async throws {
        let context = try makeContext()
        let store = CaptureDocumentStore()
        // A document in Acte (locked), so filing into it waits for Face ID.
        let documents = try #require(try TemplateStore(context: context).template(forKey: BuiltInTemplates.Key.documents))
        let passport = try AssetActions(context: context).create(name: "Pașaport", template: documents, values: FieldValues())
        let vehicles = try #require(try TemplateStore(context: context).template(forKey: BuiltInTemplates.Key.vehicle))
        let car = try AssetActions(context: context).create(name: "VW Golf", template: vehicles, values: FieldValues())
        let captured = try await store.store(.init(pages: [CaptureDocumentStoreTests.page(width: 900, height: 640, seed: 21)], kind: .passport))
        var review = CaptureReview(
            result: CaptureResult(kind: .passport, kindConfidence: 0.9, fields: [], suggestions: [], reminder: nil,
                                  recognizedText: "", barcodes: [], document: captured.ref, notices: []),
            assets: [passport], context: context
        )
        review.destination = .asset(passport.id)
        let gate = GateAuthenticator()
        var filer = CaptureFiler(context: context, store: store)
        filer.vault = BiometricVaultManager(authenticator: gate, appLockEnabled: { false }, observesAppLifecycle: false)
        let attachmentsBefore = try count(Attachment.self, in: context)

        let filing = Task { @MainActor in _ = try await filer.save(review) }
        await gate.waitUntilAsked()
        // Meanwhile, another screen renames the car. It saves at once, on its own.
        try AssetActions(context: context).update(car, name: "Mașina mea", values: car.values, notes: car.notes)
        #expect(!context.hasChanges, "The rename was saved, not held for the filing")
        UnitOfWork.failNextCommitForTesting(ForcedFailure(), in: context)
        gate.answer(true)
        await #expect(throws: ForcedFailure.self) { try await filing.value }

        #expect(car.name == "Mașina mea", "The rename survived the filing's failure")
        let fresh = ModelContext(context.container)
        #expect(try fresh.fetch(FetchDescriptor<Asset>()).first { $0.id == car.id }?.name == "Mașina mea")
        #expect(try count(Attachment.self, in: context) == attachmentsBefore, "The failed filing kept nothing")
        #expect(await store.processed(id: try #require(captured.ref.pendingID)) != nil, "The pages wait for a retry")
    }

    @Test("Salvează after a failed save: nothing was kept, the photo is still there, and a retry files everything")
    func filingFailureKeepsThePagesForARetry() async throws {
        let context = try makeContext()
        let store = CaptureDocumentStore()
        let captured = try await store.store(.init(pages: [CaptureDocumentStoreTests.page(width: 800, height: 520, seed: 9)], kind: .identityCard))
        let id = try #require(captured.ref.pendingID)
        let expiry = try #require(CalendarDay(printedYear: 2032, month: 3, day: 15))
        let fields = [
            CaptureField(key: .surname, value: .text("EXEMPLU"), confidence: 0.8, tier: .heuristic),
            CaptureField(key: .givenNames, value: .text("ION"), confidence: 0.8, tier: .heuristic),
            CaptureField(key: .expiryDate, value: .day(expiry), confidence: 0.8, tier: .heuristic),
        ]
        let review = CaptureReview(
            result: CaptureResult(kind: .identityCard, kindConfidence: 0.9, fields: fields, suggestions: [], reminder: nil,
                                  recognizedText: "", barcodes: [], document: captured.ref, notices: []),
            assets: [], context: context
        )
        let filer = CaptureFiler(context: context, store: store)
        let assetsBefore = try count(Asset.self, in: context)
        let attachmentsBefore = try count(Attachment.self, in: context)
        let obligationsBefore = try count(Obligation.self, in: context)

        UnitOfWork.failNextCommitForTesting(ForcedFailure(), in: context)
        await #expect(throws: ForcedFailure.self) { _ = try await filer.save(review) }
        #expect(try count(Asset.self, in: context) == assetsBefore, "No person, no section")
        #expect(try count(Obligation.self, in: context) == obligationsBefore, "No deadline")
        #expect(try count(Attachment.self, in: context) == attachmentsBefore, "No document")
        #expect(await store.processed(id: id) != nil, "The pages wait for the retry")

        let outcome = try await filer.save(review)
        #expect(outcome.attachment?.orderedPages.count == 1)
        #expect(outcome.asset?.parent?.name.isEmpty == false, "Filed under the person")
        #expect(try count(Attachment.self, in: context) == attachmentsBefore + 1)
        #expect(await store.processed(id: id) == nil, "The pages left capture once kept")
    }

    // MARK: Saved only through the unit

    @Test("Every context the app makes saves only through the unit of work, never by itself")
    func contextsNeverSaveByThemselves() throws {
        let container = try makeInMemoryContainer()
        #expect(!container.mainContext.autosaveEnabled, "The main context, which every screen and action uses")
        #expect(!PersistenceController.context(in: container).autosaveEnabled, "A context of its own: a backup, a reader")
        #expect(!(try makeContext()).autosaveEnabled, "Tests make theirs the same way")
    }

    @Test("A change left on the context is never written until the unit of work saves it, with its card numbers masked")
    func aChangeLeftUnsavedIsNotWritten() async throws {
        let container = try makeInMemoryContainer()
        let context = container.mainContext
        try TemplateStore(context: context).installBuiltIns()
        let boat = Asset(name: "Barca de pe lac", templateKey: BuiltInTemplates.Key.other)
        boat.notes = "Card 4111 1111 1111 1111"
        context.insert(boat)

        // The main run loop turns, as it would between two taps; nothing saves by itself.
        try await Task.sleep(for: .milliseconds(100))
        let store = PersistenceController.context(in: container)
        #expect(try store.fetchCount(FetchDescriptor<Asset>()) == 0, "Nothing written yet")

        try UnitOfWork.save(context)
        let kept = try #require(Asset.find(boat.recordKey, in: PersistenceController.context(in: container)))
        #expect(kept.notes == "Card \(PaymentCardNumbers.mask) 1111", "Saved through the unit, so only the last four digits stay")
    }
}

/// A Face ID prompt that waits until the test answers it.
final class GateAuthenticator: BiometricAuthenticating, @unchecked Sendable {
    private let lock = NSLock()
    private var asked: CheckedContinuation<Void, Never>?
    private var wasAsked = false
    private var answer: CheckedContinuation<Bool, Never>?

    func biometryType() -> LABiometryType { .faceID }

    func evaluate(localizedReason: String) async throws -> Bool {
        await withCheckedContinuation { (continuation: CheckedContinuation<Bool, Never>) in
            let waiter = lock.withLock { () -> CheckedContinuation<Void, Never>? in
                answer = continuation
                wasAsked = true
                defer { asked = nil }
                return asked
            }
            waiter?.resume()
        }
    }

    func waitUntilAsked() async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            let already = lock.withLock { () -> Bool in
                if wasAsked { return true }
                asked = continuation
                return false
            }
            if already { continuation.resume() }
        }
    }

    func answer(_ value: Bool) {
        let continuation = lock.withLock { () -> CheckedContinuation<Bool, Never>? in
            defer { answer = nil }
            return answer
        }
        continuation?.resume(returning: value)
    }
}

@Suite("Save failure wording")
struct SaveFailureTests {

    @Test func aFullPhoneSaysSoAtAnyDepth() {
        let full = NSError(domain: NSCocoaErrorDomain, code: NSFileWriteOutOfSpaceError)
        let wrapped = NSError(domain: "NSSQLiteErrorDomain", code: 1, userInfo: [NSUnderlyingErrorKey: full])
        #expect(SaveFailure.isOutOfSpace(wrapped))
        #expect(SaveFailure.message(for: wrapped, formKept: true).contains("spațiu liber"))
        #expect(SaveFailure.message(for: wrapped, formKept: true).hasSuffix("Ce ai completat e încă aici."))
    }

    @Test func systemTextNeverReachesThePerson() {
        let system = NSError(domain: NSCocoaErrorDomain, code: NSFileWriteUnknownError, userInfo: [NSLocalizedDescriptionKey: "The operation couldn’t be completed."])
        let message = SaveFailure.message(for: system, formKept: false)
        #expect(!message.contains("operation"))
        #expect(message.hasPrefix("Nu am putut salva."))
    }

    @Test func theAppsOwnErrorsKeepTheirWords() {
        let error = CaptureFiler.FilingError.missingSection
        #expect(SaveFailure.message(for: error, formKept: true) == error.errorDescription)
    }
}
