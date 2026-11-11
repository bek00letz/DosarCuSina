import Foundation
import SwiftData

/// "Editează" on a personal document's page: the values the person corrected, and what
/// reading the document again brought (the back of a card, the text read off it), kept
/// as one step that "Anulează" takes back whole.
extension AssetActions {
    /// What the document page's edit keeps.
    public struct DocumentEdit {
        public var name: String
        public var values: FieldValues
        public var notes: String?
        /// The back being added, as capture prepared it.
        public var addedPages: AddedPages?
        /// The text read off the document again ("Citește din nou", or with its back).
        public var readText: String?
        /// What the form started from; only what changed from it is written (`update`). Nil:
        /// the document as stored now.
        public var start: SectionEditStart?

        public init(name: String, values: FieldValues, notes: String?, addedPages: AddedPages? = nil, readText: String? = nil,
                    startedFrom start: SectionEditStart? = nil) {
            self.name = name
            self.values = values
            self.notes = notes
            self.addedPages = addedPages
            self.readText = readText
            self.start = start
        }
    }

    /// Saves a personal document's edit in one undoable step: the pages added to its
    /// picture (`AttachmentActions.addPages`), the text read again, and the values through
    /// `update` (sealing, deadlines, reminders), all or nothing. A name that is still the
    /// type's own follows a corrected type (`DocumentNaming.retyped`); a name the person
    /// changed in the same edit is theirs.
    @discardableResult
    public func editDocument(_ document: Asset, _ edit: DocumentEdit, picture: Attachment?) throws -> Undoable<EditOutcome> {
        // A photo of the person's own (the back) never lands in an example without asking.
        if edit.addedPages != nil {
            // The type the edit leaves must keep a back too (a document turned into a bank card
            // in the same edit takes none).
            guard DocumentType.keepsBackSide(edit.values[DocumentType.typeFieldKey]?.textValue) else {
                throw AddedPages.Refusal.noBackSide
            }
            _ = try ExampleOwnership.requireReal(document)
        }
        return try UnitOfWork.performUndoable(in: context, now: now()) { () throws -> EditOutcome in
            if let picture {
                let attachments = AttachmentActions(context: context)
                if let pages = edit.addedPages { try attachments.addPages(pages, to: picture) }
                if let text = edit.readText { try attachments.setReadText(text, of: picture) }
            }
            let start = edit.start ?? SectionEditStart(document)
            var name = edit.name
            if name == start.name, let oldName = Self.documentName(start.values),
               let newName = Self.documentName(edit.values),
               let retyped = DocumentNaming.retyped(start.name, from: oldName, to: newName) {
                name = retyped
            }
            return try update(document, name: name, values: edit.values, notes: edit.notes, startedFrom: start)
        }
    }

    /// What a personal document is called by its type and variant ("Carte de identitate",
    /// "Cazier judiciar"), when it has a type.
    static func documentName(_ values: FieldValues) -> String? {
        guard let stored = values[DocumentType.typeFieldKey]?.textValue,
              let type = DocumentType.options.option(for: stored)?.key else { return nil }
        let variant = values[DocumentType.variantFieldKey]?.textValue.flatMap { DocumentType.variantOptions.option(for: $0)?.key }
        return DocumentType.documentName(type: type, variant: variant)
    }
}
