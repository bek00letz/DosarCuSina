import CoreGraphics
import Foundation
import SwiftData

/// "Citește din nou" and "Adaugă spatele" on a filed personal document: its pages, with the
/// back being added, read again by the one engine (`CaptureEngine`) as the document's own
/// kind, and what was read put into the edit form by the filer's rule
/// (`CaptureFiler.values`, `CaptureFiler.merging`). Nothing is saved here: the form keeps
/// it until "Gata", which saves it through `AssetActions.editDocument`.
///
/// It reads on the phone only (Apple's model when there is one), never with the person's
/// AI provider: the person asked to read a document they keep, not to send it.
@MainActor
struct DocumentReading {
    let context: ModelContext
    var engine: CaptureEngine = .standard()
    var store: CaptureDocumentStore = .shared()
    var referenceDate: Date = Date()

    /// A value reading changed in the form, so the person can see it and take it back.
    struct Change: Identifiable, Equatable {
        let key: String
        let label: String
        let before: FieldValue?
        let after: FieldValue
        var id: String { key }
    }

    /// What reading found.
    struct Outcome {
        /// The form's values with what was read.
        var values: FieldValues
        var changes: [Change]
        /// The back read with the document, ready to keep on its picture.
        var addedPages: AddedPages?
        /// The text read off the whole document now.
        var readText: String?
    }

    enum Failure: LocalizedError, Equatable {
        /// The picture has nothing that can be read (only a small thumbnail).
        case nothingToRead

        var errorDescription: String? {
            String(localized: "Poza actului nu se mai poate citi. Adaugă o poză nouă de pe pagina actului.",
                   comment: "Reading a document again found no page to read.")
        }
    }

    /// Reads `picture` (and `adding`, the back) again as `document`'s kind and puts what was
    /// read into `form`, the values the edit form holds now.
    func read(_ document: Asset, picture: Attachment, adding: [CaptureImage] = [], into form: FieldValues,
              definition: TemplateDefinition) async throws -> Outcome {
        let existing = picture.orderedPages.compactMap(\.imageData)
        let original = picture.fileData
        let payload = try await Task.detached(priority: .userInitiated) {
            try Self.payload(pages: existing, original: original, adding: adding)
        }.value
        let options = CaptureOptions(useOnDeviceModel: true, useCloudModel: false, storeDocument: !adding.isEmpty,
                                     ownerID: document.id.uuidString, referenceDate: referenceDate)
        var result = try await engine.capture(CaptureRequest(payload, options: options))

        // The added page, as capture prepared it; the pages already kept stay as they are.
        var added: AddedPages?
        if let ref = result.document {
            if !adding.isEmpty, let id = ref.pendingID, let processed = await store.processed(id: id) {
                let count = existing.count
                added = AddedPages(images: Array(processed.pageData.dropFirst(count)),
                                   framing: (count..<max(count, processed.pageData.count)).map { processed.framing[page: $0] })
            }
            await store.release(ref)
        }
        if !adding.isEmpty, added?.images.isEmpty ?? true { throw CapturedDocumentError.pagesGone }

        // The type the person keeps wins: the pages are read as that kind.
        if let kind = Self.kind(for: form), kind != result.kind {
            result = engine.reinterpret(result, as: kind)
        }
        var review = CaptureReview(result: result, assets: [document], context: context)
        review.destination = .asset(document.id)
        let read = Self.keepingType(of: form, in: CaptureFiler.values(from: review, for: definition))
        let values = CaptureFiler.merging(read, into: form)
        return Outcome(values: values, changes: Self.changes(from: form, to: values, definition: definition), addedPages: added,
                       readText: result.recognizedText.isEmpty ? nil : result.recognizedText)
    }

    // MARK: Rules

    /// What the engine reads: the kept pages as taken (found and turned again, as any
    /// photo is) and the back after them, or the PDF the document is kept as.
    nonisolated static func payload(pages: [Data], original: Data?, adding: [CaptureImage]) throws -> CaptureRequest.Payload {
        if pages.isEmpty, let original, adding.isEmpty, PDFPageRendering.pageCount(original) > 0 {
            return .pdf(original)
        }
        let kept = (pages.isEmpty ? [original].compactMap { $0 } : pages)
            .compactMap { ImageScaling.decoded($0, maxLongEdge: nil) }
            .map { CaptureImage(image: $0) }
        guard !kept.isEmpty else { throw Failure.nothingToRead }
        return .images(kept + adding)
    }

    /// The kind a document of this type is read as, when capture has one for it.
    static func kind(for values: FieldValues) -> CaptureDocumentKind? {
        guard let type = typeKey(values) else { return nil }
        return CaptureDocumentKind.allCases.first { $0.profile.documentType == type }
    }

    /// What was read, without changing the type the person keeps: a reading may say what
    /// a document is only when it has no type yet, or is "Alt document".
    static func keepingType(of form: FieldValues, in read: FieldValues) -> FieldValues {
        guard let type = typeKey(form), type != DocumentType.other else { return read }
        var read = read
        // A variant read for another type isn't this one's.
        if typeKey(read) != type { read[DocumentType.variantFieldKey] = nil }
        read[DocumentType.typeFieldKey] = nil
        return read
    }

    /// The values reading changed, in the template's order.
    static func changes(from before: FieldValues, to after: FieldValues, definition: TemplateDefinition) -> [Change] {
        definition.allFields.compactMap { field in
            guard let value = after[field.key], before[field.key] != value else { return nil }
            return Change(key: field.key, label: field.label, before: before[field.key], after: value)
        }
    }

    private static func typeKey(_ values: FieldValues) -> String? {
        values[DocumentType.typeFieldKey]?.textValue.flatMap { DocumentType.options.option(for: $0)?.key }
    }
}
