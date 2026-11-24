import Foundation
import SwiftData

/// What a record holds and goes with it when the app deletes it: a section's deadlines,
/// documents (with their pages), records of history (with their parts) and readings; a record
/// of history's parts; a document's pages.
///
/// The database never deletes these by itself (since version 18 its links only let go): iCloud
/// brings another device's deletions in as they are, and one that took what a record holds
/// with it would take what this device added to it meanwhile, offline or on a copy of it that
/// was joined into another (`ParentLinks`). So every deletion the app makes of a record that
/// holds others goes through here, once, and takes them as the database used to.
enum RecordContents {
    /// What each kind of record holds, by the name of the relationship: what `delete` takes
    /// with it, and what an undo receipt brings back with it (`UndoableRecords.ownedRelationships`).
    /// `ParentLinksTests` checks `delete` against it.
    static let owned: [String: Set<String>] = [
        "Asset": ["obligations", "attachments", "history", "measurements"],
        "HistoryEntry": ["items"],
        "Attachment": ["pages"],
    ]

    /// Deletes `record` and everything it holds (`owned`), the parts first.
    static func delete(_ record: any PersistentModel, in context: ModelContext) {
        switch record {
        case let asset as Asset:
            for obligation in asset.obligations ?? [] { context.delete(obligation) }
            for attachment in asset.attachments ?? [] { delete(attachment, in: context) }
            for entry in asset.history ?? [] { delete(entry, in: context) }
            for reading in asset.measurements ?? [] { context.delete(reading) }
        case let entry as HistoryEntry:
            for item in entry.items ?? [] { context.delete(item) }
        case let attachment as Attachment:
            for page in attachment.pages ?? [] { context.delete(page) }
        default:
            break
        }
        context.delete(record)
    }
}
