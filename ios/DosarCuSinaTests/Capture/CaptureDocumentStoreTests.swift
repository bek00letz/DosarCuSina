import CoreGraphics
import Foundation
import Testing
@testable import DosarCuSina

@Suite("Document store")
struct CaptureDocumentStoreTests {

    /// A page-sized image with some texture, so encoders produce realistic sizes.
    static func page(width: Int = 2480, height: Int = 3508, seed: UInt8 = 0) -> CGImage {
        let context = CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
        )!
        context.setFillColor(CGColor(gray: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        var value = UInt32(seed) &+ 7
        for row in stride(from: 0, to: height, by: 24) {
            for column in stride(from: 0, to: width, by: 18) {
                value = value &* 1_103_515_245 &+ 12_345
                let shade = CGFloat((value >> 16) & 0xFF) / 255
                context.setFillColor(CGColor(gray: shade, alpha: 1))
                context.fill(CGRect(x: column, y: row, width: 14, height: 10))
            }
        }
        return context.makeImage()!
    }

    @Test("Pages are processed with a thumbnail, sized for reading, and nothing is written to disk")
    func processesPagesAndThumbnail() async throws {
        let store = CaptureDocumentStore()
        let stored = try await store.store(.init(pages: [Self.page()], kind: .rcaPolicy))
        #expect(!stored.isDuplicate)
        let document = try #require(stored.document)
        #expect(document.pages.count == 1)
        let page = try #require(document.pages.first)
        #expect(max(page.pixelWidth ?? 0, page.pixelHeight ?? 0) == CaptureDocumentStore.pageMaxLongEdge)
        let thumbnail = try #require(document.thumbnail)
        #expect(max(thumbnail.pixelWidth ?? 0, thumbnail.pixelHeight ?? 0) == CaptureDocumentStore.thumbnailMaxLongEdge)
        let processed = try #require(await store.processed(id: document.id))
        #expect(processed.pageData.count == 1)
        #expect(processed.thumbnailData != nil)
    }

    @Test("The same document captured twice is processed once")
    func deduplicatesPending() async throws {
        let store = CaptureDocumentStore()
        let original = Data("same photo bytes".utf8)
        let first = try await store.store(.init(pages: [Self.page(width: 400, height: 600, seed: 1)], sourceData: original))
        let second = try await store.store(.init(pages: [Self.page(width: 400, height: 600, seed: 2)], sourceData: original))
        #expect(second.isDuplicate)
        #expect(second.ref.pendingID == first.ref.pendingID)
        #expect(second.ref != first.ref, "Each capture holds its own claim")
        #expect(await store.pendingCount == 1)

        let pdf = Data("%PDF-1.7 placeholder".utf8)
        let third = try await store.store(.init(pages: [], originalPDF: pdf))
        let fourth = try await store.store(.init(pages: [], originalPDF: pdf))
        #expect(!third.isDuplicate)
        #expect(fourth.isDuplicate)
    }

    @Test("Documents already in the binder are recognized by fingerprint")
    func recognizesFiledDocuments() async throws {
        let filedID = UUID()
        let pdf = Data("%PDF-1.7 already filed".utf8)
        let fingerprint = Hashing.sha256(pdf)
        let store = CaptureDocumentStore(duplicateLookup: { $0 == fingerprint ? filedID : nil })
        let result = try await store.store(.init(pages: [], originalPDF: pdf))
        #expect(result.isDuplicate)
        #expect(result.ref == .kept(attachmentID: filedID))
        #expect(await store.pendingCount == 0)
    }

    @Test("Releasing a capture leaves nothing behind, and releasing twice does nothing more")
    func releaseLeavesNothing() async throws {
        let store = CaptureDocumentStore()
        let first = try await store.store(.init(pages: [Self.page(width: 400, height: 600, seed: 3)]))
        let second = try await store.store(.init(pages: [Self.page(width: 400, height: 600, seed: 4)]))
        await store.release(first.ref)
        await store.release(first.ref)
        #expect(await store.pendingCount == 1)
        await store.release(second.ref)
        #expect(await store.pendingCount == 0)
    }

    @Test("Closing one capture of a photo never takes the pages another capture of it still needs")
    func claimsAreCountedPerCapture() async throws {
        let store = CaptureDocumentStore()
        let bytes = Data("the same bill, shared twice".utf8)
        let fromMail = try await store.store(.init(pages: [Self.page(width: 400, height: 600, seed: 5)], sourceData: bytes))
        let fromPhotos = try await store.store(.init(pages: [Self.page(width: 400, height: 600, seed: 5)], sourceData: bytes))
        let id = try #require(fromMail.ref.pendingID)
        await store.release(fromMail.ref)
        #expect(await store.processed(id: id) != nil, "The other capture still has its pages")
        await store.release(fromPhotos.ref)
        #expect(await store.processed(id: id) == nil)
    }

    @MainActor
    @Test("A confirmed capture becomes an Attachment, the one record")
    func filingMovesTheCaptureIntoTheBinder() async throws {
        let context = try makeContext()
        let car = Asset(name: "Mașina", templateKey: BuiltInTemplates.Key.vehicle)
        context.insert(car)
        try context.save()
        let store = CaptureDocumentStore()
        let stored = try await store.store(.init(pages: [Self.page(width: 800, height: 1100, seed: 5)], kind: .rcaPolicy))
        let captured = try #require(stored.document)

        let documents = AttachmentActions(context: context)
        let attachment = try await documents.fileForTest(stored.ref, from: store, title: "Poliță RCA", asset: car)
        #expect(attachment.kind == .policy)
        #expect(attachment.orderedPages.count == 1)
        #expect(attachment.thumbnailData != nil)
        #expect(attachment.sha256 == captured.contentHash)
        #expect(attachment.documentID == captured.id.uuidString)
        #expect(await store.pendingCount == 0, "Nothing stays in capture")
        #expect(documents.attachmentID(withFingerprint: captured.contentHash) == attachment.id)
    }

    @MainActor
    @Test("The report adds up space by asset and kind, over attachments")
    func report() throws {
        let context = try makeContext()
        let car = Asset(name: "Mașina", templateKey: BuiltInTemplates.Key.vehicle)
        context.insert(car)
        try context.save()
        let documents = AttachmentActions(context: context)
        try documents.file(DocumentDraft(fileName: "a.pdf", kind: .invoice, originalData: Data(count: 1_000)), asset: car)
        let old = try documents.file(DocumentDraft(fileName: "b.pdf", kind: .policy, originalData: Data(count: 500)))
        old.isArchived = true
        let report = try DocumentStorage(context: context).report()
        #expect(report.total.documents == 2)
        #expect(report.total.bytes == 1_500)
        #expect(report.byAsset[car.id]?.bytes == 1_000)
        #expect(report.byKind[.policy]?.documents == 1)
        #expect(report.archived.bytes == 500)
    }

    @MainActor
    @Test("Old, large scans can be shrunk; originals are never touched")
    func compaction() async throws {
        let context = try makeContext()
        let store = CaptureDocumentStore()
        let captured = try await store.store(.init(pages: [Self.page(seed: 7)]))
        let attachment = try await AttachmentActions(context: context).fileForTest(captured.ref, from: store, title: "Scan vechi")
        attachment.createdAt = Date(timeIntervalSince1970: 1_600_000_000)
        let policy = CompactionPolicy(olderThanDays: 365, maxLongEdge: 1200, quality: 0.5, minimumPageBytes: 0)
        let storage = DocumentStorage(context: context)

        #expect(try storage.report(policy: policy).compactionCandidates == [attachment.id])
        let before = attachment.byteCount
        let saved = try storage.compact(policy: policy)
        #expect(saved > 0)
        #expect(attachment.byteCount == before - saved)
        #expect(attachment.compactedAt != nil)
        let image = try #require(attachment.orderedPages.first?.imageData.flatMap { ImageScaling.decoded($0, maxLongEdge: nil) })
        #expect(max(image.width, image.height) == 1200)
        #expect(try storage.report(policy: policy).compactionCandidates.isEmpty)
    }
}
