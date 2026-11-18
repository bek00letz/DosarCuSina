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

    /// The fields whose values a section's page shows above its pockets: on a document's page,
    /// every one of its category's (`rows` under „Date de pe act”, the secrets in their own card;
    /// a value that doesn't apply to its type shows nowhere), none on any other page. Its Date
    /// importante leaves them out (`keyFactRows`), so a passport's „Serie și număr” shows once.
    static func listedAbove(definition: TemplateDefinition) -> Set<String> {
        guard DocumentPageLayout.opensAsDocumentPage(role: definition.behavior.role) else { return [] }
        return Set(definition.allFields.map(\.key))
    }

    /// What a section's Date importante holds, on whichever page it shows: the template's key
    /// facts the page doesn't list already, then the person's own rows. The pocket and whether
    /// it shows at all read this one answer.
    static func keyFactRows(of asset: Asset, definition: TemplateDefinition) -> [FactRow] {
        AssetFacts.factRows(asset.values, customFacts: asset.customFacts, template: definition,
                            leavingOut: listedAbove(definition: definition))
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

    // MARK: Replaced by a new one

    /// What a section replaced by a new one says (`CompletionShape.Replacement`): one of its
    /// deadlines whose closing replaces it ("Am rezolvat" on a personal document's renewal,
    /// declared by its completion kind) was closed, and that deadline isn't open again (an
    /// expiry typed in later makes a new one). Nil for any other section. Its page shows it
    /// expired and offers the new one and deleting it; a person's next document to expire
    /// leaves it out.
    /// A deadline that renews one of the holder's own documents (the European health card on a
    /// health file, `Replacement.Replaces.holdersDocument`) never makes its section replaced.
    static func replacement(of section: Asset) -> CompletionShape.Replacement? {
        let deadlines = section.obligations ?? []
        let closed = deadlines.filter { $0.status == .done }
        guard !closed.isEmpty, let context = section.modelContext else { return nil }
        for deadline in closed {
            guard let replacement = deadline.completion(in: context).replacement, replacement.replacesItsSection else { continue }
            let openAgain = deadlines.contains { $0.blueprintKey == deadline.blueprintKey && ($0.status == .active || $0.status == .paused) }
            if !openAgain { return replacement }
        }
        return nil
    }

    /// Whether the new one is already in the binder: another section of the same category and
    /// type under the same holder, made after this one and not replaced itself. "Adaugă actul
    /// nou" is offered only until then.
    static func hasSuccessor(_ section: Asset) -> Bool {
        guard let holder = section.parent else { return false }
        let type = section.values[DocumentType.typeFieldKey]?.textValue
        return (holder.children ?? []).contains { other in
            other.id != section.id && other.templateKey == section.templateKey && other.createdAt > section.createdAt
                && other.values[DocumentType.typeFieldKey]?.textValue == type && !other.wasReplaced
        }
    }

    /// Whether the new one is already in the binder, for the deadline `closed` whose closing
    /// replaced `replacement`: for the section itself, `hasSuccessor(_:)`; for one of the holder's
    /// own documents (the health card on a health file), a document of that type among the holder's,
    /// made after the deadline was closed and not replaced itself.
    @MainActor
    static func hasSuccessor(of replacement: CompletionShape.Replacement, closing closed: Obligation) -> Bool {
        guard let section = closed.asset else { return false }
        guard let type = replacement.holdersDocumentType else { return hasSuccessor(section) }
        guard let holder = section.parent, let context = section.modelContext,
              let templates = try? TemplateStore(context: context).templatesByKey() else { return false }
        let closedAt = closed.history.first?.occurredAt ?? section.createdAt
        return (holder.children ?? []).contains { other in
            templates.plays(.personalDocument, other.templateKey) && other.createdAt > closedAt
                && other.values[DocumentType.typeFieldKey]?.textValue == type && !other.wasReplaced
        }
    }

    /// A holder's documents in the order every list of them shows: the ones still current
    /// first, by `order`; those replaced by a new one after them, by the same order, as
    /// history. Never sorted among the current ones by a date that no longer counts.
    static func currentFirst(_ documents: [Asset], by order: (Asset, Asset) -> Bool) -> [Asset] {
        let sorted = documents.sorted(by: order)
        return sorted.filter { !$0.wasReplaced } + sorted.filter(\.wasReplaced)
    }

    /// The next of `documents` to expire, by `expiry`: never one replaced by a new one, which
    /// is expired already whatever its date says.
    static func nextToExpire(_ documents: [Asset], expiry: (Asset) -> CalendarDay?) -> (document: Asset, day: CalendarDay)? {
        documents.filter { !$0.wasReplaced }
            .compactMap { document in expiry(document).map { (document: document, day: $0) } }
            .min { $0.day < $1.day }
    }
}

extension Asset {
    /// Whether it was replaced by a new one (`DocumentPageFacts.replacement(of:)`): expired,
    /// whatever its date says, and no longer its holder's current document. The one answer
    /// every reader that picks, counts or orders documents reads: the readiness checks through
    /// `ReadinessAsset.wasReplaced`, the person's hero through `DocumentPageFacts.nextToExpire`,
    /// every list of documents through `DocumentPageFacts.currentFirst`.
    @MainActor var wasReplaced: Bool {
        DocumentPageFacts.replacement(of: self) != nil
    }
}

extension Attachment {
    /// Whether pages can be added after its own: it is kept as pictures, not as one PDF.
    var takesMorePages: Bool {
        !orderedPages.isEmpty
    }
}
