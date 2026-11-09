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
/// with `CaptureDocumentStore` until `CaptureFiler` turns them into an
/// `Attachment`, the one record of every document.
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
    /// HEIC (or JPEG where HEIC isn't available) page images, in order, as taken.
    public let pageData: [Data]
    /// A small picture of the first page as it is shown.
    public let thumbnailData: Data?
    public let originalPDF: Data?
    /// How the pages are shown: the document found in each photo and which way up it goes.
    public let framing: DocumentFraming

    public init(document: StoredDocument, pageData: [Data], thumbnailData: Data?, originalPDF: Data?, framing: DocumentFraming = DocumentFraming()) {
        self.document = document
        self.pageData = pageData
        self.thumbnailData = thumbnailData
        self.originalPDF = originalPDF
        self.framing = framing
    }
}

/// Which document a capture is about: pages it just read, or a document the binder
/// already keeps (the same photo was filed before). The one way capture, the review
/// and filing name a document, so a capture's id and a kept document's id are never
/// mixed up.
public enum CapturedDocumentRef: Hashable, Codable, Sendable {
    /// Pages waiting in `CaptureDocumentStore` under `id`. `claim` is this capture's
    /// own hold on them: the pages stay while any capture still holds them.
    case pending(id: UUID, claim: UUID)
    /// The same photo is already in the binder as this `Attachment`.
    case kept(attachmentID: UUID)

    /// The pages waiting in capture's store, when there are any.
    public var pendingID: UUID? {
        if case .pending(let id, _) = self { return id }
        return nil
    }

    /// The document already in the binder, when it is one.
    public var keptAttachmentID: UUID? {
        if case .kept(let id) = self { return id }
        return nil
    }
}

/// Turns captured pages into what the binder keeps: pages sized for reading
/// small print, a thumbnail and a fingerprint, with duplicates recognized.
///
/// It keeps nothing on disk. A processed document waits here, in memory, until
/// the person confirms the capture and `CaptureFiler` stores it as an `Attachment`;
/// a discarded capture leaves no trace.
///
/// Every capture that reads a document holds its own claim on the pages, even when
/// two captures read the same photo (shared twice, from two apps). The pages go
/// once no capture holds them: closing one review never takes pages another still needs.
public actor CaptureDocumentStore {
    /// Pages are kept sharp enough to read small print on a policy or an invoice.
    public static let pageMaxLongEdge = 2560
    public static let pageQuality = 0.7
    public static let thumbnailMaxLongEdge = 360
    public static let thumbnailQuality = 0.6

    /// Finds an already filed document by its fingerprint; returns its id.
    public typealias DuplicateLookup = @Sendable (String) async -> UUID?

    private struct Waiting {
        var processed: ProcessedDocument
        var claims: Set<UUID>
    }

    private var duplicateLookup: DuplicateLookup?
    private var pending: [UUID: Waiting] = [:]

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
        /// Page images as taken (a scan's already flat), in order. Empty for a PDF, which is kept whole.
        public var pages: [CGImage]
        /// How each page is shown: the document found in the photo and the turn it was read with.
        public var framing: DocumentFraming
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

        public init(pages: [CGImage], framing: DocumentFraming = DocumentFraming(), originalPDF: Data? = nil, thumbnailSource: CGImage? = nil, sourceData: Data? = nil, kind: CaptureDocumentKind = .other, ownerID: String? = nil, title: String? = nil, capturedAt: Date = Date()) {
            self.pages = pages
            self.framing = framing
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

    /// What storing a capture gave: the reference the capture holds, and the
    /// processed document when its pages wait here.
    public struct Stored: Sendable {
        public let ref: CapturedDocumentRef
        /// Nil when the same photo is already in the binder.
        public let document: StoredDocument?
        /// The same content was captured before: it waits for another capture, or is already kept.
        public let isDuplicate: Bool
    }

    /// Processes a document, or points at the existing one (still waiting, or already
    /// in the binder) when the same content was captured before. Each call is a new
    /// claim: release it with `release(_:)` when the capture ends.
    public func store(_ request: StoreRequest) async throws -> Stored {
        guard !request.pages.isEmpty || request.originalPDF != nil else { throw StoreError.nothingToStore }

        // Hash the original bytes when we have them, so a duplicate costs no encoding.
        let originalHash = (request.originalPDF ?? request.sourceData).map(Hashing.sha256)
        if let originalHash, let duplicate = await existing(originalHash) { return duplicate }

        let encodedPages = try request.pages.map { page in
            try ImageEncoding.encode(page, maxLongEdge: Self.pageMaxLongEdge, quality: Self.pageQuality)
        }
        let contentHash = originalHash ?? Hashing.sha256(encodedPages.reduce(into: Data()) { $0.append($1.data) })
        if originalHash == nil, let duplicate = await existing(contentHash) { return duplicate }

        var pages: [StoredFile] = []
        for (offset, page) in encodedPages.enumerated() {
            pages.append(StoredFile(name: "page-\(offset + 1).\(page.fileExtension)", byteSize: page.data.count, pixelWidth: page.width, pixelHeight: page.height))
        }
        var thumbnailData: Data?
        var thumbnail: StoredFile?
        // The thumbnail is the first page as it is shown: cut out and turned.
        if let first = request.thumbnailSource ?? request.pages.first.map({ DocumentPicture.shown($0, framing: request.framing[page: 0]) }) {
            let encoded = try ImageEncoding.encode(first, maxLongEdge: Self.thumbnailMaxLongEdge, quality: Self.thumbnailQuality)
            thumbnailData = encoded.data
            thumbnail = StoredFile(name: "thumbnail.\(encoded.fileExtension)", byteSize: encoded.data.count, pixelWidth: encoded.width, pixelHeight: encoded.height)
        }
        let original = request.originalPDF.map { StoredFile(name: "original.pdf", byteSize: $0.count, pixelWidth: nil, pixelHeight: nil) }

        let document = StoredDocument(
            id: UUID(), contentHash: contentHash, kind: request.kind, ownerID: request.ownerID, title: request.title,
            capturedAt: request.capturedAt, pages: pages, thumbnail: thumbnail, original: original
        )
        let claim = UUID()
        pending[document.id] = Waiting(
            processed: ProcessedDocument(document: document, pageData: encodedPages.map(\.data), thumbnailData: thumbnailData,
                                         originalPDF: request.originalPDF, framing: request.framing),
            claims: [claim]
        )
        return Stored(ref: .pending(id: document.id, claim: claim), document: document, isDuplicate: false)
    }

    // MARK: Pending documents

    /// A processed document still waiting to be filed.
    public func processed(id: UUID) -> ProcessedDocument? {
        pending[id]?.processed
    }

    /// Ends one capture's hold on its pages: once filed, or when the capture is
    /// closed without saving. The pages go when no capture holds them any more.
    /// Releasing twice, or a reference to a kept document, does nothing.
    public func release(_ ref: CapturedDocumentRef) {
        guard case .pending(let id, let claim) = ref, var waiting = pending[id] else { return }
        waiting.claims.remove(claim)
        pending[id] = waiting.claims.isEmpty ? nil : waiting
    }

    public var pendingCount: Int { pending.count }

    // MARK: Private

    /// The same content, captured before: still waiting (a new claim on it), or in the binder.
    private func existing(_ contentHash: String) async -> Stored? {
        if let (id, waiting) = pending.first(where: { $0.value.processed.document.contentHash == contentHash }) {
            let claim = UUID()
            pending[id]?.claims.insert(claim)
            return Stored(ref: .pending(id: id, claim: claim), document: waiting.processed.document, isDuplicate: true)
        }
        guard let lookup = duplicateLookup, let id = await lookup(contentHash) else { return nil }
        return Stored(ref: .kept(attachmentID: id), document: nil, isDuplicate: true)
    }
}

// MARK: - Image encoding

/// Encodes page images, made smaller by `ImageScaling` first. HEIC first, JPEG when HEIC isn't available.
enum ImageEncoding {
    struct Encoded {
        let data: Data
        let fileExtension: String
        let width: Int
        let height: Int
    }

    static func encode(_ image: CGImage, maxLongEdge: Int, quality: Double) throws -> Encoded {
        let scaled = ImageScaling.scaled(image, toLongEdge: maxLongEdge, .down) ?? image
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
}
