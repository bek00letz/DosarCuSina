import Foundation
import SwiftData

extension DocumentKind {
    /// The binder's kind for what capture recognized.
    public init(capturedKind: CaptureDocumentKind) {
        switch capturedKind {
        case .passport, .identityCard, .drivingLicence, .vehicleRegistration: self = .identity
        case .rcaPolicy, .insurancePolicy: self = .policy
        case .utilityInvoice, .serviceInvoice: self = .invoice
        case .fiscalReceipt: self = .receipt
        case .warrantyCertificate: self = .warranty
        case .itpReport, .medicalResult, .veterinaryRecord: self = .report
        case .contract: self = .contract
        case .other: self = .other
        }
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

extension AttachmentActions {
    /// Files a capture the person confirmed. The processed pages move from the
    /// capture store into an `Attachment`; nothing stays behind in capture.
    /// The pages leave the capture store only once the save succeeded (after the
    /// enclosing unit of work commits, when there is one), so a failed save can
    /// be retried with everything still there.
    @discardableResult
    public func fileCaptured(
        documentID: UUID,
        from store: CaptureDocumentStore = .shared(),
        title: String?,
        kind: DocumentKind? = nil,
        extractedText: String? = nil,
        documentDate: CalendarDay? = nil,
        asset: Asset? = nil,
        obligation: Obligation? = nil,
        historyEntry: HistoryEntry? = nil,
        provider: Provider? = nil
    ) async throws -> Attachment? {
        guard let processed = await store.processed(id: documentID) else {
            // The same photo was filed before: capture pointed at that copy instead of
            // keeping a second one. File the copy where the person is filing now.
            return try refile(documentID, title: title, asset: asset, obligation: obligation, historyEntry: historyEntry, provider: provider)
        }
        let draft = processed.draft(title: title, kind: kind, extractedText: extractedText, documentDate: documentDate)
        let attachment = try file(draft, asset: asset, obligation: obligation, historyEntry: historyEntry, provider: provider)
        await UnitOfWork.afterCommit(in: context) { await store.discard(id: documentID) }
        return attachment
    }

    /// Moves an already filed document to where it's being filed now, keeping its pages.
    /// Nil when there is no such document.
    private func refile(_ id: UUID, title: String?, asset: Asset?, obligation: Obligation?, historyEntry: HistoryEntry?, provider: Provider?) throws -> Attachment? {
        var descriptor = FetchDescriptor<Attachment>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        guard let attachment = try context.fetch(descriptor).first else { return nil }
        if let destination = asset ?? obligation?.asset ?? historyEntry?.asset { attachment.asset = destination }
        if let obligation { attachment.obligation = obligation }
        if let historyEntry { attachment.historyEntry = historyEntry }
        if let provider { attachment.provider = provider }
        if (attachment.title ?? "").isEmpty, let title { attachment.title = title }
        attachment.isArchived = false
        try UnitOfWork.save(context)
        return attachment
    }

    /// The id of a filed document with this fingerprint, for capture's duplicate check.
    public func attachmentID(withFingerprint sha256: String) -> UUID? {
        var descriptor = FetchDescriptor<Attachment>(predicate: #Predicate { $0.sha256 == sha256 })
        descriptor.fetchLimit = 1
        return (try? context.fetch(descriptor))?.first?.id
    }
}
