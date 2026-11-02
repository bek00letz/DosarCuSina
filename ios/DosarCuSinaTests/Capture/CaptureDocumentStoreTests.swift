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

    private func makeStore() -> (CaptureDocumentStore, URL) {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("capture-store-\(UUID().uuidString)", isDirectory: true)
        return (CaptureDocumentStore(rootURL: root), root)
    }

    @Test("Pages are kept with a thumbnail, sized for reading")
    func storesPagesAndThumbnail() async throws {
        let (store, root) = makeStore()
        defer { try? FileManager.default.removeItem(at: root) }

        let (document, isDuplicate) = try await store.store(.init(pages: [Self.page()], kind: .rcaPolicy))
        #expect(!isDuplicate)
        #expect(document.pages.count == 1)
        let page = try #require(document.pages.first)
        #expect(max(page.pixelWidth ?? 0, page.pixelHeight ?? 0) == CaptureDocumentStore.pageMaxLongEdge)
        let thumbnail = try #require(document.thumbnail)
        #expect(max(thumbnail.pixelWidth ?? 0, thumbnail.pixelHeight ?? 0) == CaptureDocumentStore.thumbnailMaxLongEdge)
        #expect(FileManager.default.fileExists(atPath: await store.fileURL(of: page, in: document.id).path))
    }

    @Test("The same document captured twice is stored once")
    func deduplicates() async throws {
        let (store, root) = makeStore()
        defer { try? FileManager.default.removeItem(at: root) }

        let original = Data("same photo bytes".utf8)
        let first = try await store.store(.init(pages: [Self.page(seed: 1)], sourceData: original))
        let second = try await store.store(.init(pages: [Self.page(seed: 2)], sourceData: original))
        #expect(second.isDuplicate)
        #expect(second.document.id == first.document.id)
        #expect(try await store.allDocuments().count == 1)

        let pdf = Data("%PDF-1.7 placeholder".utf8)
        let third = try await store.store(.init(pages: [], originalPDF: pdf))
        let fourth = try await store.store(.init(pages: [], originalPDF: pdf))
        #expect(!third.isDuplicate)
        #expect(fourth.isDuplicate)
    }

    @Test("Replaced documents are archived, never deleted")
    func archiving() async throws {
        let (store, root) = makeStore()
        defer { try? FileManager.default.removeItem(at: root) }

        let old = try await store.store(.init(pages: [Self.page(width: 400, height: 600, seed: 3)], kind: .rcaPolicy)).document
        let new = try await store.store(.init(pages: [Self.page(width: 400, height: 600, seed: 4)], kind: .rcaPolicy)).document
        try await store.archive(documentID: old.id, supersededBy: new.id)

        let archived = try #require(try await store.document(id: old.id))
        #expect(archived.isArchived)
        #expect(archived.supersededBy == new.id)
        #expect(try await store.allDocuments().count == 2)

        // Records survive a fresh store reading the same folder.
        let reopened = CaptureDocumentStore(rootURL: root)
        #expect(try await reopened.document(id: old.id)?.supersededBy == new.id)
    }

    @Test("The report adds up space by owner and kind")
    func report() async throws {
        let (store, root) = makeStore()
        defer { try? FileManager.default.removeItem(at: root) }

        let car = try await store.store(.init(pages: [Self.page(width: 400, height: 600, seed: 5)], kind: .serviceInvoice, ownerID: "car")).document
        let home = try await store.store(.init(pages: [Self.page(width: 400, height: 600, seed: 6)], kind: .utilityInvoice, ownerID: "home")).document
        let report = try await store.report()

        #expect(report.total.documents == 2)
        #expect(report.total.bytes == car.totalBytes + home.totalBytes)
        #expect(report.byOwner["car"]?.bytes == car.totalBytes)
        #expect(report.byKind[.utilityInvoice]?.documents == 1)
    }

    @Test("Old, large scans can be shrunk")
    func compaction() async throws {
        let (store, root) = makeStore()
        defer { try? FileManager.default.removeItem(at: root) }

        let longAgo = Date(timeIntervalSince1970: 1_600_000_000)
        let document = try await store.store(.init(pages: [Self.page(seed: 7)], capturedAt: longAgo)).document
        let policy = CompactionPolicy(olderThanDays: 365, maxLongEdge: 1200, quality: 0.5, minimumPageBytes: 0)

        #expect(try await store.report(policy: policy).compactionCandidates == [document.id])
        let saved = try await store.compact(policy: policy)
        #expect(saved > 0)
        let compacted = try #require(try await store.document(id: document.id))
        #expect(compacted.compactedAt != nil)
        #expect(max(compacted.pages[0].pixelWidth ?? 0, compacted.pages[0].pixelHeight ?? 0) == 1200)
        #expect(try await store.report(policy: policy).compactionCandidates.isEmpty)
    }
}
