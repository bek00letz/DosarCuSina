import Foundation
import SwiftData
import Testing
@testable import DosarCuSina

/// "Adaugă poza actului" on a document's page: the photo ends up on that document.
@Suite("A document's photo")
@MainActor
struct DocumentPhotoTests {

    private func setup() throws -> (ModelContext, Asset) {
        let context = try makeContext()
        let store = TemplateStore(context: context)
        let member = try #require(try store.template(forKey: BuiltInTemplates.Key.member))
        let documents = try #require(try store.template(forKey: BuiltInTemplates.Key.documents))
        let person = try AssetActions(context: context).create(name: "Exemplu Ion", template: member, values: FieldValues())
        var values = FieldValues()
        values[DocumentType.typeFieldKey] = .text(DocumentType.passport)
        let passport = try AssetActions(context: context).create(name: "Pașaport – Exemplu Ion", template: documents, values: values, parent: person)
        return (context, passport)
    }

    private func review(_ documentID: UUID, notices: [CaptureNotice] = [], on document: Asset, context: ModelContext) -> CaptureReview {
        var review = CaptureReview(
            result: CaptureResult(kind: .passport, kindConfidence: 0.95, fields: [
                CaptureField(key: .surname, value: .text("EXEMPLU"), confidence: 0.9, tier: .deterministic),
            ], suggestions: [], reminder: nil, recognizedText: "", barcodes: [], documentID: documentID, notices: notices),
            assets: [document], context: context
        )
        review.destination = .asset(document.id)
        return review
    }

    @Test func aNewPhotoLandsOnTheDocument() async throws {
        let (context, passport) = try setup()
        let store = CaptureDocumentStore()
        let captured = try await store.store(.init(pages: [CaptureDocumentStoreTests.page(width: 900, height: 640, seed: 3)], kind: .passport)).document
        let outcome = try await CaptureFiler(context: context, store: store).save(review(captured.id, on: passport, context: context))
        #expect(outcome.attachment?.asset?.id == passport.id)
        #expect((passport.attachments ?? []).count == 1)
    }

    @Test func aPhotoAlreadyFiledElsewhereIsBroughtToThisDocument() async throws {
        let (context, passport) = try setup()
        let store = CaptureDocumentStore()
        let first = try await store.store(.init(pages: [CaptureDocumentStoreTests.page(width: 900, height: 640, seed: 4)], kind: .passport)).document
        // Filed once with no section, as an earlier test of the same library photo would.
        let earlier = try #require(try await AttachmentActions(context: context).fileCaptured(documentID: first.id, from: store, title: "Pașaport"))
        #expect(earlier.asset == nil)

        // The same photo again: capture recognises it and points at the filed copy.
        let outcome = try await CaptureFiler(context: context, store: store)
            .save(review(earlier.id, notices: [.duplicateDocument(documentID: earlier.id)], on: passport, context: context))
        #expect(outcome.attachment?.id == earlier.id)
        #expect(earlier.asset?.id == passport.id, "The copy already kept is filed on this document, not lost")
        #expect(try context.fetchCount(FetchDescriptor<DosarCuSina.Attachment>()) == 1, "No second copy")
    }
}
