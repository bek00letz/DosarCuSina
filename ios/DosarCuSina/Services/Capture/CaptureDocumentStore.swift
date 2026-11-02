import CoreGraphics
import CryptoKit
import Foundation
import ImageIO
import UniformTypeIdentifiers

// MARK: - Stored records

/// One file on disk belonging to a stored document.
public struct StoredFile: Codable, Hashable, Sendable {
    public let name: String
    public let byteSize: Int
    public let pixelWidth: Int?
    public let pixelHeight: Int?
}

/// A captured document kept on file: its pages, a thumbnail and the original PDF if there was one.
///
/// Model-independent on purpose: Core's `Attachment` keeps the document's `id`, and the
/// store owns the bytes. Documents are never deleted when replaced, only archived, because an
/// old policy is exactly what you need when you make a claim.
public struct StoredDocument: Codable, Hashable, Sendable, Identifiable {
    public let id: UUID
    /// SHA-256 of the original bytes, used to spot the same document captured twice.
    public let contentHash: String
    public var kind: CaptureDocumentKind
    /// The asset (or other owner) this document belongs to, as an opaque identifier.
    public var ownerID: String?
    public var title: String?
    public let capturedAt: Date
    public var archivedAt: Date?
    /// The document that replaced this one, e.g. this year's policy replacing last year's.
    public var supersededBy: UUID?
    public var pages: [StoredFile]
    public var thumbnail: StoredFile?
    public var original: StoredFile?
    public var compactedAt: Date?

    public var isArchived: Bool { archivedAt != nil }

    public var totalBytes: Int {
        pages.reduce(0) { $0 + $1.byteSize } + (thumbnail?.byteSize ?? 0) + (original?.byteSize ?? 0)
    }
}

/// How much space documents take, so the app can explain it and offer to shrink old scans.
public struct StorageReport: Sendable, Hashable {
    public struct Totals: Sendable, Hashable {
        public var documents: Int = 0
        public var bytes: Int = 0
    }

    public let total: Totals
    /// Keyed by owner identifier; `nil` collects documents not yet filed under an asset.
    public let byOwner: [String?: Totals]
    public let byKind: [CaptureDocumentKind: Totals]
    public let archived: Totals
    /// Documents whose pages are old and large enough to be worth shrinking.
    public let compactionCandidates: [UUID]
}

/// When and how far to shrink old scans. Original PDFs are never touched.
public struct CompactionPolicy: Sendable, Hashable {
    public var olderThanDays: Int
    public var maxLongEdge: Int
    public var quality: Double
    /// Pages smaller than this are left alone; shrinking them saves too little.
    public var minimumPageBytes: Int

    public init(olderThanDays: Int = 365, maxLongEdge: Int = 1800, quality: Double = 0.55, minimumPageBytes: Int = 350_000) {
        self.olderThanDays = olderThanDays
        self.maxLongEdge = maxLongEdge
        self.quality = quality
        self.minimumPageBytes = minimumPageBytes
    }
}

// MARK: - Store

/// Keeps captured documents on disk for years.
///
/// Layout, one folder per document under the root:
/// `<root>/<id>/page-1.heic`, `thumbnail.heic`, `original.pdf`, `document.json`.
/// The JSON records are the source of truth; the in-memory index is rebuilt from them.
/// Lives in the App Group container so a Share Extension can file documents too.
public actor CaptureDocumentStore {

    public static let appGroupIdentifier = "group.com.ar.dosarcusina.shared"

    /// Pages are kept sharp enough to read small print on a policy or an invoice.
    public static let pageMaxLongEdge = 2560
    public static let pageQuality = 0.7
    public static let thumbnailMaxLongEdge = 360
    public static let thumbnailQuality = 0.6

    public let rootURL: URL
    private var index: [UUID: StoredDocument]?
    private let fileManager = FileManager.default

    public init(rootURL: URL) {
        self.rootURL = rootURL
    }

    /// The shared store in the App Group container, falling back to Application Support
    /// when the container isn't available (for example in a unit test host).
    public static func shared() -> CaptureDocumentStore {
        let base = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupIdentifier)
            ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return CaptureDocumentStore(rootURL: base.appendingPathComponent("Documents/Capture", isDirectory: true))
    }

    // MARK: Writing

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

    /// Saves a document, or returns the existing one if the same bytes were stored before.
    public func store(_ request: StoreRequest) throws -> (document: StoredDocument, isDuplicate: Bool) {
        guard !request.pages.isEmpty || request.originalPDF != nil else { throw StoreError.nothingToStore }

        func hash(_ data: Data) -> String {
            SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        }
        func existing(_ contentHash: String) throws -> StoredDocument? {
            try loadIndex().values.first { $0.contentHash == contentHash }
        }

        // Hash the original bytes when we have them, so a duplicate costs no encoding.
        let originalHash = (request.originalPDF ?? request.sourceData).map(hash)
        if let originalHash, let duplicate = try existing(originalHash) { return (duplicate, true) }

        let encodedPages = try request.pages.map { page in
            try ImageEncoding.encode(page, maxLongEdge: Self.pageMaxLongEdge, quality: Self.pageQuality)
        }
        let contentHash = originalHash ?? hash(encodedPages.reduce(into: Data()) { $0.append($1.data) })
        if originalHash == nil, let duplicate = try existing(contentHash) { return (duplicate, true) }

        let id = UUID()
        let folder = folderURL(for: id)
        try fileManager.createDirectory(at: folder, withIntermediateDirectories: true)

        var pages: [StoredFile] = []
        for (offset, page) in encodedPages.enumerated() {
            let name = "page-\(offset + 1).\(page.fileExtension)"
            try write(page.data, to: folder.appendingPathComponent(name))
            pages.append(StoredFile(name: name, byteSize: page.data.count, pixelWidth: page.width, pixelHeight: page.height))
        }

        var thumbnail: StoredFile?
        if let first = request.thumbnailSource ?? request.pages.first {
            let encoded = try ImageEncoding.encode(first, maxLongEdge: Self.thumbnailMaxLongEdge, quality: Self.thumbnailQuality)
            let name = "thumbnail.\(encoded.fileExtension)"
            try write(encoded.data, to: folder.appendingPathComponent(name))
            thumbnail = StoredFile(name: name, byteSize: encoded.data.count, pixelWidth: encoded.width, pixelHeight: encoded.height)
        }

        var original: StoredFile?
        if let pdf = request.originalPDF {
            try write(pdf, to: folder.appendingPathComponent("original.pdf"))
            original = StoredFile(name: "original.pdf", byteSize: pdf.count, pixelWidth: nil, pixelHeight: nil)
        }

        let document = StoredDocument(
            id: id, contentHash: contentHash, kind: request.kind, ownerID: request.ownerID, title: request.title,
            capturedAt: request.capturedAt, archivedAt: nil, supersededBy: nil,
            pages: pages, thumbnail: thumbnail, original: original, compactedAt: nil
        )
        try save(document)
        return (document, false)
    }

    // MARK: Reading

    public func document(id: UUID) throws -> StoredDocument? {
        try loadIndex()[id]
    }

    public func allDocuments() throws -> [StoredDocument] {
        try loadIndex().values.sorted { $0.capturedAt > $1.capturedAt }
    }

    public func fileURL(of file: StoredFile, in documentID: UUID) -> URL {
        folderURL(for: documentID).appendingPathComponent(file.name)
    }

    // MARK: Updating

    public func assign(documentID: UUID, toOwner ownerID: String?) throws {
        try update(documentID) { $0.ownerID = ownerID }
    }

    public func setKind(_ kind: CaptureDocumentKind, for documentID: UUID) throws {
        try update(documentID) { $0.kind = kind }
    }

    /// Moves a document out of the way without deleting it, e.g. last year's policy.
    public func archive(documentID: UUID, supersededBy replacement: UUID? = nil, at date: Date = Date()) throws {
        try update(documentID) {
            $0.archivedAt = date
            $0.supersededBy = replacement
        }
    }

    public func unarchive(documentID: UUID) throws {
        try update(documentID) {
            $0.archivedAt = nil
            $0.supersededBy = nil
        }
    }

    /// Deletes a document's files. Only for when the person explicitly deletes it.
    public func remove(documentID: UUID) throws {
        var current = try loadIndex()
        guard current[documentID] != nil else { return }
        try fileManager.removeItem(at: folderURL(for: documentID))
        current[documentID] = nil
        index = current
    }

    // MARK: Space

    public func report(policy: CompactionPolicy = CompactionPolicy(), now: Date = Date()) throws -> StorageReport {
        var total = StorageReport.Totals()
        var archived = StorageReport.Totals()
        var byOwner: [String?: StorageReport.Totals] = [:]
        var byKind: [CaptureDocumentKind: StorageReport.Totals] = [:]
        var candidates: [UUID] = []

        for document in try loadIndex().values {
            let bytes = document.totalBytes
            total.documents += 1
            total.bytes += bytes
            byOwner[document.ownerID, default: .init()].documents += 1
            byOwner[document.ownerID, default: .init()].bytes += bytes
            byKind[document.kind, default: .init()].documents += 1
            byKind[document.kind, default: .init()].bytes += bytes
            if document.isArchived {
                archived.documents += 1
                archived.bytes += bytes
            }
            if isCompactionCandidate(document, policy: policy, now: now) { candidates.append(document.id) }
        }
        return StorageReport(total: total, byOwner: byOwner, byKind: byKind, archived: archived, compactionCandidates: candidates)
    }

    /// Re-encodes old, large page images at a smaller size. Returns the bytes saved.
    @discardableResult
    public func compact(policy: CompactionPolicy = CompactionPolicy(), now: Date = Date()) throws -> Int {
        var saved = 0
        for document in try loadIndex().values where isCompactionCandidate(document, policy: policy, now: now) {
            var updated = document
            var pages: [StoredFile] = []
            for page in document.pages {
                let url = fileURL(of: page, in: document.id)
                guard page.byteSize >= policy.minimumPageBytes,
                      let source = CGImageSourceCreateWithURL(url as CFURL, nil),
                      let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
                    pages.append(page)
                    continue
                }
                let encoded = try ImageEncoding.encode(image, maxLongEdge: policy.maxLongEdge, quality: policy.quality)
                guard encoded.data.count < page.byteSize else {
                    pages.append(page)
                    continue
                }
                let name = (page.name as NSString).deletingPathExtension + "." + encoded.fileExtension
                let newURL = folderURL(for: document.id).appendingPathComponent(name)
                try write(encoded.data, to: newURL)
                if newURL != url { try? fileManager.removeItem(at: url) }
                saved += page.byteSize - encoded.data.count
                pages.append(StoredFile(name: name, byteSize: encoded.data.count, pixelWidth: encoded.width, pixelHeight: encoded.height))
            }
            updated.pages = pages
            updated.compactedAt = now
            try save(updated)
        }
        return saved
    }

    // MARK: Private

    private func isCompactionCandidate(_ document: StoredDocument, policy: CompactionPolicy, now: Date) -> Bool {
        guard document.compactedAt == nil else { return false }
        let age = now.timeIntervalSince(document.capturedAt) / 86_400
        guard age >= Double(policy.olderThanDays) else { return false }
        return document.pages.contains { page in
            page.byteSize >= policy.minimumPageBytes || max(page.pixelWidth ?? 0, page.pixelHeight ?? 0) > policy.maxLongEdge
        }
    }

    private func folderURL(for id: UUID) -> URL {
        rootURL.appendingPathComponent(id.uuidString, isDirectory: true)
    }

    private func update(_ id: UUID, _ change: (inout StoredDocument) -> Void) throws {
        guard var document = try loadIndex()[id] else { return }
        change(&document)
        try save(document)
    }

    private func save(_ document: StoredDocument) throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try write(try encoder.encode(document), to: folderURL(for: document.id).appendingPathComponent("document.json"))
        var current = try loadIndex()
        current[document.id] = document
        index = current
    }

    private func loadIndex() throws -> [UUID: StoredDocument] {
        if let index { return index }
        var loaded: [UUID: StoredDocument] = [:]
        if fileManager.fileExists(atPath: rootURL.path) {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            for folder in try fileManager.contentsOfDirectory(at: rootURL, includingPropertiesForKeys: nil) {
                let record = folder.appendingPathComponent("document.json")
                guard let data = try? Data(contentsOf: record),
                      let document = try? decoder.decode(StoredDocument.self, from: data) else { continue }
                loaded[document.id] = document
            }
        }
        index = loaded
        return loaded
    }

    private func write(_ data: Data, to url: URL) throws {
        try fileManager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        #if os(iOS)
        try data.write(to: url, options: [.atomic, .completeFileProtection])
        #else
        try data.write(to: url, options: [.atomic])
        #endif
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
