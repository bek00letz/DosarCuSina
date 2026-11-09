import Foundation
import SwiftData

/// A new way of showing a document's pages, with its thumbnail already drawn for it:
/// what a turn or "Folosește poza întreagă" keeps. Made before a unit of work opens,
/// since drawing takes time and a unit never waits.
public struct PictureChange: Sendable {
    public let framing: DocumentFraming
    /// The first page as `framing` shows it, small; nil when there is no page to draw.
    public let thumbnail: Data?

    /// Draws the thumbnail away from the main thread.
    static func make(firstPage: DocumentPageSource?, framing: DocumentFraming) async -> PictureChange {
        guard let firstPage else { return PictureChange(framing: framing, thumbnail: nil) }
        let thumbnail = await Task.detached(priority: .userInitiated) { DocumentPicture.thumbnailData(of: firstPage) }.value
        return PictureChange(framing: framing, thumbnail: thumbnail)
    }
}

/// Pages to go after a filed document's own (the back of a card), as capture prepared
/// them: each as taken, with how it is shown. Made before a unit of work opens.
public struct AddedPages: Sendable, Equatable {
    public let images: [Data]
    public let framing: [PageFraming]

    public init(images: [Data], framing: [PageFraming]) {
        self.images = images
        self.framing = framing
    }

    /// Why pages can't be added.
    public enum Refusal: LocalizedError, Equatable {
        /// The document is kept as one PDF, with its own pages.
        case keptWhole
        /// The document's type keeps no back (`DocumentType.keepsBackSide`): a bank card's
        /// back shows its security code, which the binder never keeps.
        case noBackSide

        public var errorDescription: String? {
            switch self {
            case .keptWhole:
                String(localized: "Actul e păstrat ca PDF, cu paginile lui. Adaugă spatele ca act separat.",
                       comment: "Adding the back to a document kept as a PDF was refused.")
            case .noBackSide:
                String(localized: "Pentru acest tip de act nu se păstrează spatele.",
                       comment: "Adding the back to a document whose type keeps no back (a bank card) was refused.")
            }
        }
    }
}

extension DocumentPages {
    /// A filed document's pages as `framing` would show them.
    @MainActor
    static func sources(of attachment: Attachment, framing: DocumentFraming) -> [DocumentPageSource] {
        sources(pageImages: attachment.orderedPages.compactMap(\.imageData), original: attachment.fileData,
                thumbnail: attachment.thumbnailData, framing: framing)
    }
}

/// Turning a page and choosing between the document cut out of its photo and the whole
/// photo: one undoable step each, for the review's document once it is filed and for any
/// document in the binder. The photo as taken is never changed; only how it is shown.
extension AttachmentActions {

    /// Turns page `page` a quarter turn clockwise (or `turns` of them). The person's turn
    /// wins over the app's guess, now and after any later reading.
    @discardableResult
    public func turnPage(_ attachment: Attachment, page: Int, by turns: Int = 1) async throws -> UndoReceipt {
        var framing = attachment.framing
        framing[page: page] = framing[page: page].turned(by: turns)
        return try await setFraming(attachment, framing)
    }

    /// Shows the whole photo instead of the document cut out of it, or the cut-out again,
    /// on `pages` (every page that has a cut-out when nil).
    @discardableResult
    public func showWholePhoto(_ whole: Bool, of attachment: Attachment, pages: [Int]? = nil) async throws -> UndoReceipt {
        var framing = attachment.framing
        for source in DocumentPages.sources(of: attachment) where source.framing.hasCrop && (pages?.contains(source.index) ?? true) {
            framing[page: source.index] = framing[page: source.index].showingWholePhoto(whole)
        }
        return try await setFraming(attachment, framing)
    }

    /// What a review's choices change for its document; nil when the person chose nothing.
    public func pictureChange(for document: CapturedDocument, choices: [Int: PageChoice]) async -> PictureChange? {
        guard !choices.isEmpty else { return nil }
        switch document {
        case .new(let processed, _):
            let framing = processed.framing.applying(choices)
            return await PictureChange.make(firstPage: DocumentPages.sources(of: processed, choices: choices).first, framing: framing)
        case .kept(let attachment):
            let framing = attachment.framing.applying(choices)
            return await PictureChange.make(firstPage: DocumentPages.sources(of: attachment, framing: framing).first, framing: framing)
        }
    }

    /// Keeps a change already drawn, without saving: for actions that save once.
    func apply(_ change: PictureChange, to attachment: Attachment) {
        attachment.framing = change.framing
        if let thumbnail = change.thumbnail { attachment.thumbnailData = thumbnail }
    }

    /// Adds `pages` after the document's own (the back of a card), as capture prepared
    /// them, with the text read off the whole document now. Its pages as taken never
    /// change, and its fingerprint stays the one capture gave it, so the same front photo
    /// shared again is still known as this document. Saves through the unit it runs in:
    /// the document page saves it with the values in one step (`AssetActions.editDocument`).
    public func addPages(_ pages: AddedPages, to attachment: Attachment) throws {
        guard !pages.images.isEmpty else { return }
        guard attachment.takesMorePages else { throw AddedPages.Refusal.keptWhole }
        // A personal document takes a back only when its type keeps one; the rule holds here,
        // whatever screen asks.
        if let type = attachment.asset?.values[DocumentType.typeFieldKey]?.textValue,
           !DocumentType.keepsBackSide(type) {
            throw AddedPages.Refusal.noBackSide
        }
        let position = attachment.orderedPages.count
        let nextIndex = (attachment.orderedPages.last?.index ?? -1) + 1
        var framing = attachment.framing
        for (offset, image) in pages.images.enumerated() {
            let page = AttachmentPage(index: nextIndex + offset, imageData: image)
            context.insert(page)
            page.attachment = attachment
            framing[page: position + offset] = pages.framing.indices.contains(offset) ? pages.framing[offset] : .plain
        }
        attachment.framing = framing
        attachment.byteCount += pages.images.reduce(0) { $0 + $1.count }
        try UnitOfWork.save(context)
    }

    /// Keeps the text read off a document again (no card number, whoever read it).
    public func setReadText(_ text: String, of attachment: Attachment) throws {
        let text = PaymentCardNumbers.redact(text)
        guard attachment.extractedText != text else { return }
        attachment.extractedText = text
        try UnitOfWork.save(context)
    }

    private func setFraming(_ attachment: Attachment, _ framing: DocumentFraming) async throws -> UndoReceipt {
        let change = await PictureChange.make(firstPage: DocumentPages.sources(of: attachment, framing: framing).first, framing: framing)
        return try UnitOfWork.performUndoable(in: context) {
            apply(change, to: attachment)
            try UnitOfWork.save(context)
        }.receipt
    }
}
