import Foundation
import SwiftData

/// A document the person has confirmed, ready to file. Capture produces drafts
/// for review; only confirmed ones reach here.
public struct DocumentDraft: Sendable {
    public var title: String?
    public var fileName: String
    public var kind: DocumentKind
    /// Type of `originalData`, such as `com.adobe.pdf`.
    public var contentType: String
    public var originalData: Data?
    /// Scanned pages as HEIC, in order.
    public var pageImages: [Data]
    public var thumbnail: Data?
    public var extractedText: String?
    public var documentDate: CalendarDay?
    /// Capture's document store identifier for the source, when it came from there.
    public var documentID: String?

    public init(
        title: String? = nil,
        fileName: String,
        kind: DocumentKind,
        contentType: String = "public.data",
        originalData: Data? = nil,
        pageImages: [Data] = [],
        thumbnail: Data? = nil,
        extractedText: String? = nil,
        documentDate: CalendarDay? = nil,
        documentID: String? = nil
    ) {
        self.documentID = documentID
        self.title = title
        self.fileName = fileName
        self.kind = kind
        self.contentType = contentType
        self.originalData = originalData
        self.pageImages = pageImages
        self.thumbnail = thumbnail
        self.extractedText = extractedText
        self.documentDate = documentDate
    }

    /// The fingerprint `Attachment.sha256` will have.
    public var sha256: String? {
        if let originalData { return Hashing.sha256(originalData) }
        guard !pageImages.isEmpty else { return nil }
        return Hashing.sha256(pageImages.reduce(into: Data()) { $0.append($1) })
    }
}

/// Filing documents. Nothing is thrown away implicitly: replacing a document
/// archives the old one and links it to the new one.
@MainActor
public final class AttachmentActions {
    public let context: ModelContext
    private let calendar: Calendar

    public init(context: ModelContext, calendar: Calendar = .current) {
        self.context = context
        self.calendar = calendar
    }

    /// An already filed document with the same content, if any.
    public func existing(matching draft: DocumentDraft) throws -> Attachment? {
        guard let sha = draft.sha256 else { return nil }
        var descriptor = FetchDescriptor<Attachment>(predicate: #Predicate { $0.sha256 == sha })
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).first
    }

    @discardableResult
    public func file(
        _ draft: DocumentDraft,
        asset: Asset? = nil,
        obligation: Obligation? = nil,
        historyEntry: HistoryEntry? = nil,
        provider: Provider? = nil
    ) throws -> Attachment {
        let attachment = Attachment(fileName: draft.fileName, contentType: draft.contentType, data: draft.originalData, kind: draft.kind)
        attachment.title = draft.title
        attachment.thumbnailData = draft.thumbnail
        attachment.extractedText = draft.extractedText
        attachment.documentDate = draft.documentDate?.noonDate(in: calendar)
        attachment.documentID = draft.documentID
        attachment.sha256 = draft.sha256
        attachment.byteCount = (draft.originalData?.count ?? 0) + draft.pageImages.reduce(0) { $0 + $1.count }
        attachment.isExample = asset?.isExample ?? false
        context.insert(attachment)
        for (index, image) in draft.pageImages.enumerated() {
            let page = AttachmentPage(index: index, imageData: image)
            context.insert(page)
            page.attachment = attachment
        }
        attachment.asset = asset ?? obligation?.asset ?? historyEntry?.asset
        attachment.obligation = obligation
        attachment.historyEntry = historyEntry
        attachment.provider = provider
        try save()
        return attachment
    }

    /// Marks `old` as replaced by `new` (last year's policy by this year's) and archives it.
    public func supersede(_ old: Attachment, with new: Attachment) throws {
        guard old.id != new.id else { return }
        old.supersededBy = new
        old.isArchived = true
        try save()
    }

    public func setArchived(_ attachment: Attachment, _ isArchived: Bool) throws {
        attachment.isArchived = isArchived
        try save()
    }

    /// Deletes a document. Only for an explicit request from the person.
    public func delete(_ attachment: Attachment) throws {
        context.delete(attachment)
        try save()
    }

    private func save() throws {
        do {
            try context.save()
        } catch {
            context.rollback()
            throw error
        }
    }
}
