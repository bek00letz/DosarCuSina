import Foundation
import SwiftData

extension DocumentKind {
    /// The binder's kind for what capture recognized: the kind profile's, the one place it is written.
    public init(capturedKind: CaptureDocumentKind) {
        self = capturedKind.profile.documentKind
    }
}

extension ProcessedDocument {
    /// The confirmed document to file. Title and kind come from what the person
    /// confirmed; the fingerprint is capture's, so a re-capture is recognized.
    public func draft(title: String?, kind: DocumentKind? = nil, extractedText: String? = nil, documentDate: CalendarDay? = nil) -> DocumentDraft {
        var draft = DocumentDraft(
            title: title ?? document.title,
            fileName: (title ?? document.title ?? String(localized: "Document")) + (originalPDF == nil ? ".heic" : ".pdf"),
            kind: kind ?? DocumentKind(capturedKind: document.kind),
            contentType: originalPDF == nil ? "public.heic" : "com.adobe.pdf",
            originalData: originalPDF,
            pageImages: pageData,
            thumbnail: thumbnailData,
            extractedText: extractedText,
            documentDate: documentDate,
            documentID: document.id.uuidString
        )
        draft.contentHash = document.contentHash
        return draft
    }
}

/// A capture's document, ready to file: new pages, or the copy the binder already
/// keeps. `AttachmentActions.resolve` makes one from a `CapturedDocumentRef`.
public enum CapturedDocument {
    case new(ProcessedDocument, ref: CapturedDocumentRef)
    case kept(Attachment)
}

/// Why a captured document can't be filed.
public enum CapturedDocumentError: LocalizedError, Equatable {
    /// The pages are no longer in capture's memory and the binder doesn't have them.
    case pagesGone

    public var errorDescription: String? {
        String(localized: "Poza actului nu mai e aici. Adaug-o din nou, apoi salvează.")
    }
}

extension AttachmentActions {
    /// What a capture's document is now: its pages waiting in `store`, or the copy the
    /// binder keeps. A pending capture whose same photo another capture filed meanwhile
    /// (shared twice, saved once) is that kept copy, so the second filing moves it
    /// instead of saving without it. Throws `pagesGone` when neither is there.
    public func resolve(_ ref: CapturedDocumentRef, from store: CaptureDocumentStore) async throws -> CapturedDocument {
        switch ref {
        case .kept(let id):
            guard let kept = attachment(id: id) else { throw CapturedDocumentError.pagesGone }
            return .kept(kept)
        case .pending(let id, _):
            if let kept = attachment(fromCapture: id) { return .kept(kept) }
            let processed = await store.processed(id: id)
            // The store answered after a wait: another filing may have kept it meanwhile.
            if let kept = attachment(fromCapture: id) { return .kept(kept) }
            guard let processed else { throw CapturedDocumentError.pagesGone }
            return .new(processed, ref: ref)
        }
    }

    /// Files a captured document the person confirmed, linked to everything it belongs to.
    /// New pages become an `Attachment`. A kept copy moves here: it now belongs here only,
    /// so every old link (another place's deadline, history entry or firm) is replaced,
    /// its archived state stays as it was, and it takes what was read now (kind, text,
    /// date, title). The pages leave capture's memory once the filing is kept (see
    /// `CaptureFiler`), so a failed save can be retried with everything still there.
    /// The filing's undo receipt puts a moved copy back where it was.
    @discardableResult
    public func fileCaptured(
        _ document: CapturedDocument,
        title: String?,
        kind: DocumentKind? = nil,
        extractedText: String? = nil,
        documentDate: CalendarDay? = nil,
        validUntil: CalendarDay? = nil,
        asset: Asset? = nil,
        obligation: Obligation? = nil,
        historyEntry: HistoryEntry? = nil,
        provider: Provider? = nil
    ) throws -> Attachment {
        let filed: Attachment
        switch document {
        case .new(let processed, _):
            let draft = processed.draft(title: title, kind: kind, extractedText: extractedText, documentDate: documentDate)
            filed = try file(draft, asset: asset, obligation: obligation, historyEntry: historyEntry, provider: provider)
        case .kept(let attachment):
            try refile(attachment, title: title, kind: kind, extractedText: extractedText, documentDate: documentDate,
                       asset: asset, obligation: obligation, historyEntry: historyEntry, provider: provider)
            filed = attachment
        }
        // How long the paper itself is valid, as read now: its deadline moving on later never changes it.
        if let validUntil {
            filed.validUntil = validUntil.noonDate(in: calendar)
            try UnitOfWork.save(context)
        }
        return filed
    }

    /// Moves a kept document to where it's being filed now, keeping its pages.
    private func refile(_ attachment: Attachment, title: String?, kind: DocumentKind?, extractedText: String?, documentDate: CalendarDay?,
                        asset: Asset?, obligation: Obligation?, historyEntry: HistoryEntry?, provider: Provider?) throws {
        let destination = asset ?? obligation?.asset ?? historyEntry?.asset
        // A document that becomes the person's never stays an example: only the loader makes those.
        let isExample = try ExampleOwnership.requireReal(destination)
        attachment.asset = destination
        attachment.obligation = obligation
        attachment.historyEntry = historyEntry
        attachment.provider = provider
        attachment.isExample = isExample
        if let title, !title.isEmpty { attachment.title = title }
        if let kind { attachment.kind = kind }
        if let extractedText { attachment.extractedText = PaymentCardNumbers.redact(extractedText) }
        if let documentDate { attachment.documentDate = documentDate.noonDate(in: calendar) }
        try UnitOfWork.save(context)
    }

    /// The id of a filed document with this fingerprint, for capture's duplicate check.
    public func attachmentID(withFingerprint sha256: String) -> UUID? {
        var descriptor = FetchDescriptor<Attachment>(predicate: #Predicate { $0.sha256 == sha256 })
        descriptor.fetchLimit = 1
        return (try? context.fetch(descriptor))?.first?.id
    }

    func attachment(id: UUID) -> Attachment? {
        fetchOne(FetchDescriptor<Attachment>(predicate: #Predicate { $0.id == id }))
    }

    /// The document a capture's pages were filed as, if they were.
    func attachment(fromCapture id: UUID) -> Attachment? {
        let documentID = id.uuidString
        return fetchOne(FetchDescriptor<Attachment>(predicate: #Predicate { $0.documentID == documentID }))
    }

    private func fetchOne<T: PersistentModel>(_ descriptor: FetchDescriptor<T>) -> T? {
        var descriptor = descriptor
        descriptor.fetchLimit = 1
        return (try? context.fetch(descriptor))?.first
    }
}
