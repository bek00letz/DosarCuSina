import Foundation

/// What deleting a record from Istoric does, worked out once: the confirmation says it,
/// and `HistoryActions.delete` does exactly it.
///
/// - Its line items go, and so does the reading it recorded (the kilometres noted at a
///   visit); the value on the section follows the readings left.
/// - The documents filed with it stay in the binder, under the same section.
/// - A completion moves its deadline back to the cycle it closed only when it's the latest
///   one (`Obligation.latestCompletion`): deleting it is as if the deadline wasn't done.
///   An older completion leaves the deadline where it is.
///
/// Taking back the step just taken is different: that's the toast's undo receipt.
public struct HistoryDeletion: Equatable {
    /// The due day the deadline goes back to, when this is its latest completion.
    public var reopensCycle: CalendarDay?
    /// The deadline that stays as it is, when this is an older completion.
    public var keepsDeadline: Bool
    /// The reading that goes with the record.
    public var removedReading: Double?
    /// Documents filed with the record, which stay.
    public var keptDocuments: Int

    public init(of entry: HistoryEntry) {
        let isLatest = entry.isCompletion && entry.obligation?.latestCompletion?.id == entry.id
        reopensCycle = isLatest ? entry.cycleDueDay : nil
        keepsDeadline = entry.isCompletion && entry.obligation != nil && !isLatest
        let recorded = entry.metricReading.flatMap { reading in
            (entry.asset?.measurements ?? []).contains { !$0.isDeleted && $0.recordedAt == entry.occurredAt && $0.value == reading } ? reading : nil
        }
        removedReading = recorded
        keptDocuments = (entry.attachments ?? []).filter { !$0.isDeleted }.count
    }
}

extension DosarSchemaV10.Obligation {
    /// The completion the deadline's current cycle comes from: the one that closed the
    /// latest cycle. Ordered by the cycle closed, which only moves forward, so a completion
    /// dated in the past ("on date" last month) still counts as the latest when it is.
    public var latestCompletion: HistoryEntry? {
        (historyEntries ?? []).filter { $0.isCompletion && !$0.isDeleted }.max {
            ($0.cycleDueDay ?? .earliest, $0.occurredAt) < ($1.cycleDueDay ?? .earliest, $1.occurredAt)
        }
    }
}
