import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

// MARK: - Processed documents

/// The size of one encoded image or file in a processed document.
public struct StoredFile: Codable, Hashable, Sendable {
    public let name: String
    public let byteSize: Int
    public let pixelWidth: Int?
    public let pixelHeight: Int?
}

/// What capture made of a document: its pages, a thumbnail, the original PDF if
/// there was one, and a fingerprint. It is a description only; the bytes stay
/// with `CaptureDocumentStore` until `AttachmentActions.fileCaptured` turns them
/// into an `Attachment`, the one record of every document.
public struct StoredDocument: Codable, Hashable, Sendable, Identifiable {
    public let id: UUID
    /// SHA-256 of the original bytes (or of the pages), used to spot the same document twice.
    public let contentHash: String
    public var kind: CaptureDocumentKind
    /// The asset (or other owner) suggested for this document, as an opaque identifier.
    public var ownerID: String?
    public var title: String?
    public let capturedAt: Date
    public var pages: [StoredFile]
    public var thumbnail: StoredFile?
    public var original: StoredFile?

    public var totalBytes: Int {
        pages.reduce(0) { $0 + $1.byteSize } + (thumbnail?.byteSize ?? 0) + (original?.byteSize ?? 0)
    }
}

/// A processed document with its bytes, waiting to be filed.
public struct ProcessedDocument: Sendable {
    public let document: StoredDocument
    /// HEIC (or JPEG where HEIC isn't available) page images, in order.
    public let pageData: [Data]
    public let thumbnailData: Data?
    public let originalPDF: Data?
}

/// Turns captured pages into what the binder keeps: pages sized for reading
/// small print, a thumbnail and a fingerprint, with duplicates recognized.
///
/// It keeps nothing on disk. A processed document waits here, in memory, until
/// the person confirms the capture and `AttachmentActions.fileCaptured` stores
/// it as an `Attachment`; a discarded capture leaves no trace.
public actor CaptureDocumentStore {
    /// Pages are kept sharp enough to read small print on a policy or an invoice.
    public static let pageMaxLongEdge = 2560
    public static let pageQuality = 0.7
    public static let thumbnailMaxLongEdge = 360
    public static let thumbnailQuality = 0.6

    /// Finds an already filed document by its fingerprint; returns its id.
    public typealias DuplicateLookup = @Sendable (String) async -> UUID?

    private var duplicateLookup: DuplicateLookup?
    private var pending: [UUID: ProcessedDocument] = [:]

    public init(duplicateLookup: DuplicateLookup? = nil) {
        self.duplicateLookup = duplicateLookup
    }

    private static let sharedStore = CaptureDocumentStore()

    /// The store the app and capture share.
    public static func shared() -> CaptureDocumentStore { sharedStore }

    /// Tells the store how to recognize documents already in the binder.
    public func setDuplicateLookup(_ lookup: DuplicateLookup?) {
        duplicateLookup = lookup
    }

    public struct StoreRequest: Sendable {
        /// Perspective-corrected page images, in order. Empty for a PDF, which is kept whole.
        public var pages: [CGImage]
        /// The original PDF, kept as is.
        public var originalPDF: Data?
        /// The image the thumbnail is made from, when it isn't the first page (e.g. a rendered PDF page).
        public var thumbnailSource: CGImage?
        /// The original image bytes (camera or Photos), used only to recognize duplicates.
        public var sourceData: Data?
        public var kind: CaptureDocumentKind
        public var ownerID: String?
        public var title: String?
        public var capturedAt: Date

        public init(pages: [CGImage], originalPDF: Data? = nil, thumbnailSource: CGImage? = nil, sourceData: Data? = nil, kind: CaptureDocumentKind = .other, ownerID: String? = nil, title: String? = nil, capturedAt: Date = Date()) {
            self.pages = pages
            self.originalPDF = originalPDF
            self.thumbnailSource = thumbnailSource
            self.sourceData = sourceData
            self.kind = kind
            self.ownerID = ownerID
            self.title = title
            self.capturedAt = capturedAt
        }
    }

    public enum StoreError: Error, Equatable {
        case nothingToStore
        case encodingFailed
    }

    /// Processes a document, or returns the existing one (filed or still pending)
    /// when the same content was captured before.
    public func store(_ request: StoreRequest) async throws -> (document: StoredDocument, isDuplicate: Bool) {
        guard !request.pages.isEmpty || request.originalPDF != nil else { throw StoreError.nothingToStore }

        // Hash the original bytes when we have them, so a duplicate costs no encoding.
        let originalHash = (request.originalPDF ?? request.sourceData).map(Hashing.sha256)
        if let originalHash, let duplicate = await existing(originalHash, kind: request.kind) { return (duplicate, true) }

        let encodedPages = try request.pages.map { page in
            try ImageEncoding.encode(page, maxLongEdge: Self.pageMaxLongEdge, quality: Self.pageQuality)
        }
        let contentHash = originalHash ?? Hashing.sha256(encodedPages.reduce(into: Data()) { $0.append($1.data) })
        if originalHash == nil, let duplicate = await existing(contentHash, kind: request.kind) { return (duplicate, true) }

        var pages: [StoredFile] = []
        for (offset, page) in encodedPages.enumerated() {
            pages.append(StoredFile(name: "page-\(offset + 1).\(page.fileExtension)", byteSize: page.data.count, pixelWidth: page.width, pixelHeight: page.height))
        }
        var thumbnailData: Data?
        var thumbnail: StoredFile?
        if let first = request.thumbnailSource ?? request.pages.first {
            let encoded = try ImageEncoding.encode(first, maxLongEdge: Self.thumbnailMaxLongEdge, quality: Self.thumbnailQuality)
            thumbnailData = encoded.data
            thumbnail = StoredFile(name: "thumbnail.\(encoded.fileExtension)", byteSize: encoded.data.count, pixelWidth: encoded.width, pixelHeight: encoded.height)
        }
        let original = request.originalPDF.map { StoredFile(name: "original.pdf", byteSize: $0.count, pixelWidth: nil, pixelHeight: nil) }

        let document = StoredDocument(
            id: UUID(), contentHash: contentHash, kind: request.kind, ownerID: request.ownerID, title: request.title,
            capturedAt: request.capturedAt, pages: pages, thumbnail: thumbnail, original: original
        )
        pending[document.id] = ProcessedDocument(document: document, pageData: encodedPages.map(\.data), thumbnailData: thumbnailData, originalPDF: request.originalPDF)
        return (document, false)
    }

    // MARK: Pending documents

    /// A processed document still waiting to be filed.
    public func processed(id: UUID) -> ProcessedDocument? {
        pending[id]
    }

    /// Hands a processed document over for filing and forgets it.
    public func take(id: UUID) -> ProcessedDocument? {
        pending.removeValue(forKey: id)
    }

    /// Drops a capture the person didn't keep.
    public func discard(id: UUID) {
        pending.removeValue(forKey: id)
    }

    public var pendingCount: Int { pending.count }

    // MARK: Private

    private func existing(_ contentHash: String, kind: CaptureDocumentKind) async -> StoredDocument? {
        if let waiting = pending.values.first(where: { $0.document.contentHash == contentHash }) {
            return waiting.document
        }
        guard let lookup = duplicateLookup, let id = await lookup(contentHash) else { return nil }
        // Already in the binder: report it by its attachment id.
        return StoredDocument(id: id, contentHash: contentHash, kind: kind, ownerID: nil, title: nil, capturedAt: Date(), pages: [], thumbnail: nil, original: nil)
    }
}

// MARK: - Image encoding

/// Scales and encodes page images. HEIC first, JPEG when HEIC isn't available.
enum ImageEncoding {
    struct Encoded {
        let data: Data
        let fileExtension: String
        let width: Int
        let height: Int
    }

    static func encode(_ image: CGImage, maxLongEdge: Int, quality: Double) throws -> Encoded {
        let scaled = scaled(image, maxLongEdge: maxLongEdge) ?? image
        for (type, fileExtension) in [(UTType.heic, "heic"), (UTType.jpeg, "jpg")] {
            let data = NSMutableData()
            guard let destination = CGImageDestinationCreateWithData(data, type.identifier as CFString, 1, nil) else { continue }
            let options: [CFString: Any] = [kCGImageDestinationLossyCompressionQuality: quality]
            CGImageDestinationAddImage(destination, scaled, options as CFDictionary)
            if CGImageDestinationFinalize(destination), data.length > 0 {
                return Encoded(data: data as Data, fileExtension: fileExtension, width: scaled.width, height: scaled.height)
            }
        }
        throw CaptureDocumentStore.StoreError.encodingFailed
    }

    /// Decodes encoded image data back to an image, for re-encoding.
    static func decode(_ data: Data) -> CGImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        return CGImageSourceCreateImageAtIndex(source, 0, nil)
    }

    /// Downscales so the long edge fits, keeping the aspect ratio. Returns `nil` when no scaling is needed.
    static func scaled(_ image: CGImage, maxLongEdge: Int) -> CGImage? {
        let longEdge = max(image.width, image.height)
        guard longEdge > maxLongEdge else { return nil }
        let scale = Double(maxLongEdge) / Double(longEdge)
        let width = max(1, Int((Double(image.width) * scale).rounded()))
        let height = max(1, Int((Double(image.height) * scale).rounded()))
        guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: colorSpace, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { return nil }
        context.interpolationQuality = .high
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return context.makeImage()
    }
}
