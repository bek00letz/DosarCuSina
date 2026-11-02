import Foundation
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

        await #expect(throws: ForcedFailure.self) {
            try await UnitOfWork.perform(in: context) {
                let car = try AssetActions(context: context).create(name: "VW Golf", template: template, values: FieldValues())
                _ = try ObligationActions(context: context).create(title: "RCA", kind: .insurance, dueDay: CalendarDay("2027-01-10"), for: car)
                await UnitOfWork.afterCommit(in: context) { afterCommitRan = true }
                throw ForcedFailure()
            }
        }
        #expect(try count(Asset.self, in: context) == assetsBefore)
        #expect(try count(Obligation.self, in: context) == obligationsBefore)
        #expect(!afterCommitRan, "Nothing that waits for the save runs when it fails")
        #expect(!UnitOfWork.isOpen(in: context))
    }

    @Test("A failed final save rolls everything back too; a later unit works normally")
    func failedCommitRollsBack() async throws {
        let context = try makeContext()
        let template = try #require(try TemplateStore(context: context).template(forKey: BuiltInTemplates.Key.vehicle))
        let before = try count(Asset.self, in: context)

        UnitOfWork.failNextCommitForTesting = ForcedFailure()
        #expect(throws: ForcedFailure.self) {
            try UnitOfWork.perform(in: context) {
                _ = try AssetActions(context: context).create(name: "VW Golf", template: template, values: FieldValues())
            }
        }
        #expect(try count(Asset.self, in: context) == before)

        var afterCommitRan = false
        try await UnitOfWork.perform(in: context) {
            _ = try AssetActions(context: context).create(name: "VW Golf", template: template, values: FieldValues())
            await UnitOfWork.afterCommit(in: context) { afterCommitRan = true }
        }
        #expect(try count(Asset.self, in: context) == before + 1)
        #expect(afterCommitRan)
    }

    @Test("A unit opened inside another joins it")
    func nestedUnitsJoin() async throws {
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

    @Test("Salvează after a failed save: nothing was kept, the photo is still there, and a retry files everything")
    func filingFailureKeepsThePagesForARetry() async throws {
        let context = try makeContext()
        let store = CaptureDocumentStore()
        let captured = try await store.store(.init(pages: [CaptureDocumentStoreTests.page(width: 800, height: 520, seed: 9)], kind: .identityCard)).document
        let expiry = try #require(CaptureDay(year: 2032, month: 3, day: 15))
        let fields = [
            CaptureField(key: .surname, value: .text("EXEMPLU"), confidence: 0.8, tier: .heuristic),
            CaptureField(key: .givenNames, value: .text("ION"), confidence: 0.8, tier: .heuristic),
            CaptureField(key: .expiryDate, value: .day(expiry), confidence: 0.8, tier: .heuristic),
        ]
        let review = CaptureReview(
            result: CaptureResult(kind: .identityCard, kindConfidence: 0.9, fields: fields, suggestions: [], reminder: nil,
                                  recognizedText: "", barcodes: [], documentID: captured.id, notices: []),
            assets: [], context: context
        )
        let filer = CaptureFiler(context: context, store: store)
        let assetsBefore = try count(Asset.self, in: context)
        let attachmentsBefore = try count(Attachment.self, in: context)
        let obligationsBefore = try count(Obligation.self, in: context)

        UnitOfWork.failNextCommitForTesting = ForcedFailure()
        await #expect(throws: ForcedFailure.self) { _ = try await filer.save(review) }
        #expect(try count(Asset.self, in: context) == assetsBefore, "No person, no section")
        #expect(try count(Obligation.self, in: context) == obligationsBefore, "No deadline")
        #expect(try count(Attachment.self, in: context) == attachmentsBefore, "No document")
        #expect(await store.processed(id: captured.id) != nil, "The pages wait for the retry")

        let outcome = try await filer.save(review)
        #expect(outcome.attachment?.orderedPages.count == 1)
        #expect(outcome.asset?.parent?.name.isEmpty == false, "Filed under the person")
        #expect(try count(Attachment.self, in: context) == attachmentsBefore + 1)
        #expect(await store.processed(id: captured.id) == nil, "The pages left capture once kept")
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
