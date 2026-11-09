import Foundation

/// What a document's page shows, decided once: which picture is the document's own,
/// which values are listed and which of them "Copiază" offers, how a copy is kept, and
/// whether the back can be added. The page draws these; it never works them out.
@MainActor
enum DocumentPageFacts {

    // MARK: The picture

    /// A personal document's own picture: its newest document that is still current (not
    /// archived) and has something to show. An older picture (last year's card, kept when
    /// it was renewed) is listed under it, never shown as the document.
    static func currentPicture(of document: Asset) -> Attachment? {
        pictures(of: document).first { !$0.isArchived }
    }

    /// The document's other pictures, newest first: archived ones and any older one.
    static func olderPictures(of document: Asset) -> [Attachment] {
        let current = currentPicture(of: document)?.id
        return pictures(of: document).filter { $0.id != current }
    }

    /// Whether a filed paper is the picture of its personal document, so opening it opens
    /// the document's page. A paper of another section, or an older picture, has a page of its own.
    static func isCurrentPicture(_ attachment: Attachment, ofPersonalDocument document: Asset) -> Bool {
        currentPicture(of: document)?.id == attachment.id
    }

    /// Every picture filed on the document, newest first, that has a page to show.
    private static func pictures(of document: Asset) -> [Attachment] {
        (document.attachments ?? [])
            .filter { !DocumentPages.sources(of: $0).isEmpty }
            .sorted { $0.createdAt > $1.createdAt }
    }

    /// Whether a list may show the document's picture beside its name: never a bank
    /// card's, whose picture shows its whole number (`DocumentType.sharedWithCare`).
    static func showsPicture(in values: FieldValues) -> Bool {
        !DocumentType.isSharedWithCare(values[DocumentType.typeFieldKey]?.textValue)
    }

    /// What each page is called under the picture: "Fața" and "Spatele" for a card's two
    /// sides, else nothing (a passport's or a PDF's pages are counted, not named).
    static func pageNames(count: Int) -> [String]? {
        guard count == 2 else { return nil }
        return [String(localized: "Fața", comment: "The front of a two-sided document."),
                String(localized: "Spatele", comment: "The back of a two-sided document.")]
    }

    /// Whether "Adaugă spatele" is offered: a document of a type printed on both sides
    /// (`DocumentType.keepsBackSide`, never a bank card), whose picture is one photo.
    /// A PDF keeps its own pages.
    static func canAddBack(_ values: FieldValues, picture: Attachment?) -> Bool {
        guard let picture, picture.takesMorePages, picture.orderedPages.count == 1 else { return false }
        return DocumentType.keepsBackSide(values[DocumentType.typeFieldKey]?.textValue)
    }

    // MARK: The values

    /// One value under the picture, as read off the document or typed in.
    struct ValueRow: Identifiable, Equatable {
        let key: String
        let label: String
        let text: String
        /// "Copiază" is offered: something a form asks to be typed (a number, a series, a
        /// date, a CNP), not a choice the person picked from a list.
        let copies: Bool
        /// The date the document stops being valid: it shows how urgent that is.
        let isExpiry: Bool
        var id: String { key }
    }

    /// Every filled value that applies, in the template's order, except secrets (they have
    /// their own rows, behind a fresh Face ID).
    static func rows(_ values: FieldValues, definition: TemplateDefinition, locale: Locale = .dosarDefault) -> [ValueRow] {
        definition.allFields.compactMap { field in
            guard !field.isSecret, field.applies(to: values), let value = values[field.key] else { return nil }
            let text = FieldFormatter.display(value, field: field, locale: locale)
            guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
            return ValueRow(key: field.key, label: field.label, text: text,
                            copies: copiesValue(of: field.type), isExpiry: field.role == .expiryDate)
        }
    }

    /// The field types whose value is worth copying into a form.
    static func copiesValue(of type: FieldType) -> Bool {
        switch type {
        case .choice, .multiChoice, .toggle, .secret: false
        default: true
        }
    }

    /// How a copy from a document's page is kept: anything read off a personal document,
    /// or kept in a locked category, stays on this phone and is gone after a minute.
    static func copyKind(isPersonalDocument: Bool, isLockedCategory: Bool) -> Clipboard.Kind {
        isPersonalDocument || isLockedCategory ? .personal : .ordinary
    }
}

extension Attachment {
    /// Whether pages can be added after its own: it is kept as pictures, not as one PDF.
    var takesMorePages: Bool {
        !orderedPages.isEmpty
    }
}
