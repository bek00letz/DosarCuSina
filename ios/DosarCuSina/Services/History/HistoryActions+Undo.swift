import Foundation
import SwiftData

extension HistoryActions {
    /// Takes back a visit recorded a moment ago with `recordVisit`, in one save:
    /// the entry and its line items, the documents filed with it, and the counter
    /// reading it logged. The asset's counter goes back to the highest reading left.
    /// A document that was already in the binder and moved to the visit (`moved`) goes
    /// back where it was instead: only what the visit made is deleted.
    /// For the "Anulează" right after saving; older entries are deleted with `delete(_:)`.
    public func undoVisit(_ entry: HistoryEntry, restoring moved: RefileReceipt? = nil) throws {
        let asset = entry.asset
        for attachment in entry.attachments ?? [] where attachment.id != moved?.attachmentID {
            context.delete(attachment)
        }
        if let moved { AttachmentActions(context: context).restore(moved) }
        if let asset, let reading = entry.metricReading {
            let logged = (asset.measurements ?? []).filter { $0.recordedAt == entry.occurredAt && $0.value == reading }
            for log in logged { context.delete(log) }
            HouseholdMutations.restoreHeroMetric(of: asset, excluding: Set(logged.map(\.id)), in: context)
        }
        context.delete(entry)
        try UnitOfWork.save(context)
    }
}

extension HouseholdMutations {
    /// Sets a counter hero field (odometer) to the highest cumulative reading
    /// left, after readings were taken back. Leaves it alone when none are left.
    static func restoreHeroMetric(of asset: Asset, excluding removed: Set<UUID>, in context: ModelContext) {
        guard let template = try? TemplateStore(context: context).template(forKey: asset.templateKey),
              let field = heroMetricField(of: template.definition) else { return }
        let remaining = (asset.measurements ?? []).filter { !removed.contains($0.id) && $0.unit == field.unit && $0.kind.isCumulative }
        guard let highest = remaining.map(\.value).max() else { return }
        var values = asset.values
        values[field.key] = .number(highest)
        asset.values = values
    }
}
