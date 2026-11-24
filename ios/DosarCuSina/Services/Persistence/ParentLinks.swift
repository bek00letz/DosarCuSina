import Foundation
import SwiftData

/// Each record a section, a record of history or a document holds keeps the id of the one that
/// holds it beside its link (`Obligation.assetID`, `Attachment.assetID`, `HistoryEntry.assetID`,
/// `MeasurementLog.assetID`, `ServiceItem.entryID`, `AttachmentPage.attachmentID`), so what
/// this device added to a record never goes when another device's deletion of it arrives.
///
/// iCloud brings another device's deletions in as they are, outside the app's steps, and the
/// database only lets go of the links (version 18; `RecordContents` deletes what a record holds
/// when the app deletes it). A record left without what held it, while its id still names it:
/// - goes back to it by that id when a copy with the id is here: two copies of one section
///   were joined on another device and the one this device added to went (`rehome`), the same
///   on every device;
/// - else, once the binder has all arrived (`CloudArrival`), waits in the repair list, to be
///   kept in a section of its own or left as it is (`LostRecordsStep`).
///
/// The ids follow the links in one place, `stamp`, which every save of the app's runs before
/// change times and undo read the step, so an id is never a change of its own: it is never part
/// of a record's own state (`ChangeTimes.isOwnState`).
enum ParentLinks {
    /// The names of the ids, in every model that has one.
    static let idNames: Set<String> = ["assetID", "entryID", "attachmentID"]

    /// Writes the id of what holds each record the context inserted or changed, from its link.
    nonisolated static func stamp(_ context: ModelContext) {
        context.processPendingChanges()
        for model in context.insertedModelsArray + context.changedModelsArray where !model.isDeleted {
            switch model {
            case let record as Obligation: follow(&record.assetID, record.asset?.id)
            case let record as Attachment: follow(&record.assetID, record.asset?.id)
            case let record as HistoryEntry: follow(&record.assetID, record.asset?.id)
            case let record as MeasurementLog: follow(&record.assetID, record.asset?.id)
            case let record as ServiceItem: follow(&record.entryID, record.entry?.id)
            case let record as AttachmentPage: follow(&record.attachmentID, record.attachment?.id)
            default: break
            }
        }
    }

    nonisolated private static func follow(_ id: inout UUID?, _ link: UUID?) {
        if id != link { id = link }
    }

    // MARK: Left without what held them

    /// Every record whose link let go while its id still names what held it.
    struct Loose {
        var obligations: [Obligation] = []
        var attachments: [Attachment] = []
        var history: [HistoryEntry] = []
        var readings: [MeasurementLog] = []
        var items: [ServiceItem] = []
        var pages: [AttachmentPage] = []

        var isEmpty: Bool {
            obligations.isEmpty && attachments.isEmpty && history.isEmpty && readings.isEmpty && items.isEmpty && pages.isEmpty
        }
    }

    @MainActor
    static func loose(in context: ModelContext) throws -> Loose {
        Loose(
            obligations: try context.fetch(FetchDescriptor<Obligation>(predicate: #Predicate { $0.asset == nil && $0.assetID != nil })).filter { !$0.isDeleted },
            attachments: try context.fetch(FetchDescriptor<Attachment>(predicate: #Predicate { $0.asset == nil && $0.assetID != nil })).filter { !$0.isDeleted },
            history: try context.fetch(FetchDescriptor<HistoryEntry>(predicate: #Predicate { $0.asset == nil && $0.assetID != nil })).filter { !$0.isDeleted },
            readings: try context.fetch(FetchDescriptor<MeasurementLog>(predicate: #Predicate { $0.asset == nil && $0.assetID != nil })).filter { !$0.isDeleted },
            items: try context.fetch(FetchDescriptor<ServiceItem>(predicate: #Predicate { $0.entry == nil && $0.entryID != nil })).filter { !$0.isDeleted },
            pages: try context.fetch(FetchDescriptor<AttachmentPage>(predicate: #Predicate { $0.attachment == nil && $0.attachmentID != nil })).filter { !$0.isDeleted }
        )
    }

    /// Puts back every record left without what held it whose holder is here by its id, as the
    /// app's own step (it gives no change time: the link is what the person last saw). Returns
    /// whether anything changed. Run at launch and after every synced change, before copies
    /// meet (`RecordsMeet`), so a record is back with its section before anything reads it.
    @MainActor @discardableResult
    static func rehome(in context: ModelContext) throws -> Bool {
        let loose = try loose(in: context)
        guard !loose.isEmpty else { return false }
        return try UnitOfWork.perform(in: context, origin: .app) {
            var changed = false
            func holder<M: UndoableRecord>(_ type: M.Type, _ id: UUID?) -> M? {
                id.flatMap { M.find($0.uuidString, in: context) }.flatMap { $0.isDeleted ? nil : $0 }
            }
            for record in loose.obligations { if let asset = holder(Asset.self, record.assetID) { record.asset = asset; changed = true } }
            for record in loose.attachments { if let asset = holder(Asset.self, record.assetID) { record.asset = asset; changed = true } }
            for record in loose.history { if let asset = holder(Asset.self, record.assetID) { record.asset = asset; changed = true } }
            for record in loose.readings { if let asset = holder(Asset.self, record.assetID) { record.asset = asset; changed = true } }
            for record in loose.items { if let entry = holder(HistoryEntry.self, record.entryID) { record.entry = entry; changed = true } }
            for record in loose.pages { if let attachment = holder(Attachment.self, record.attachmentID) { record.attachment = attachment; changed = true } }
            if changed { try UnitOfWork.save(context) }
            return changed
        }
    }
}
