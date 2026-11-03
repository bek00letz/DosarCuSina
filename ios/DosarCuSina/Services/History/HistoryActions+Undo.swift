import Foundation
import SwiftData

extension HistoryActions {
    /// Takes back a visit recorded a moment ago with `recordVisit`, in one save:
    /// the entry and its line items, the documents filed with it, and the counter
    /// reading it logged. The hero value follows the readings left.
    /// A document that was already in the binder and moved to the visit (`moved`) goes
    /// back where it was instead: only what the visit made is deleted.
    /// For the "Anulează" right after saving; older entries are deleted with `delete(_:)`.
    public func undoVisit(_ entry: HistoryEntry, restoring moved: RefileReceipt? = nil) throws {
        for attachment in entry.attachments ?? [] where attachment.id != moved?.attachmentID {
            context.delete(attachment)
        }
        if let moved { AttachmentActions(context: context).restore(moved) }
        HouseholdMutations.removeReading(recordedBy: entry, in: context)
        context.delete(entry)
        try UnitOfWork.save(context)
    }
}
