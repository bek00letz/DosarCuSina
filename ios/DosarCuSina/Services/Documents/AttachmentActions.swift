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
    /// How the pages are shown: the document found in each photo, which way up it goes.
    public var framing = DocumentFraming()

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

    /// A fingerprint worked out by capture (from the camera bytes or the PDF);
    /// when set it is used as is, so the same photo is recognized next time.
    public var contentHash: String?

    /// The fingerprint `Attachment.sha256` will have.
    public var sha256: String? {
        if let contentHash { return contentHash }
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
    let calendar: Calendar

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
        let isExample = try ExampleOwnership.requireReal(asset ?? obligation?.asset ?? historyEntry?.asset)
        let attachment = Self.insert(draft, asset: asset, obligation: obligation, historyEntry: historyEntry, provider: provider, isExample: isExample, calendar: calendar, in: context)
        try save()
        if let storeURL = context.container.configurations.first?.url, storeURL.isFileURL, storeURL.path() != "/dev/null" {
            DocumentFileProtection.apply(toStoreAt: storeURL)
        }
        return attachment
    }

    /// Inserts a filed document without saving, for actions that save once for several records.
    static func insert(
        _ draft: DocumentDraft,
        asset: Asset?,
        obligation: Obligation?,
        historyEntry: HistoryEntry?,
        provider: Provider?,
        isExample: Bool,
        calendar: Calendar,
        in context: ModelContext
    ) -> Attachment {
        let attachment = Attachment(fileName: draft.fileName, contentType: draft.contentType, data: draft.originalData, kind: draft.kind)
        attachment.title = draft.title
        attachment.thumbnailData = draft.thumbnail
        // No card number is kept in a document's text, whoever wrote it (`PaymentCardNumbers`).
        attachment.extractedText = draft.extractedText.map { PaymentCardNumbers.redact($0) }
        attachment.documentDate = draft.documentDate?.noonDate(in: calendar)
        attachment.documentID = draft.documentID
        attachment.framing = draft.framing
        attachment.sha256 = draft.sha256
        attachment.byteCount = (draft.originalData?.count ?? 0) + draft.pageImages.reduce(0) { $0 + $1.count }
        attachment.isExample = isExample
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
        return attachment
    }

    /// Marks `old` as replaced by `new` (last year's policy by this year's) and archives it.
    public func supersede(_ old: Attachment, with new: Attachment) throws {
        guard old.id != new.id else { return }
        old.supersededBy = new
        old.isArchived = true
        try save()
    }

    @discardableResult
    public func setArchived(_ attachment: Attachment, _ isArchived: Bool) throws -> UndoReceipt {
        try UnitOfWork.performUndoable(in: context) {
            attachment.isArchived = isArchived
            try save()
        }.receipt
    }

    /// Deletes a document with its pages. Only for an explicit request from the person.
    /// Undoable: the receipt brings it back where it was, pages and links included.
    @discardableResult
    public func delete(_ attachment: Attachment) throws -> UndoReceipt {
        try UnitOfWork.performUndoable(in: context) {
            context.delete(attachment)
            try save()
        }.receipt
    }

    private func save() throws {
        try UnitOfWork.save(context)
    }
}
