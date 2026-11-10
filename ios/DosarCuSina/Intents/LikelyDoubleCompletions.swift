import Foundation
import SwiftData

/// Deadlines whose last "done" may have come from an old reminder button, before
/// buttons acted only on the cycle they were about: the two latest completions a
/// few days apart, closing consecutive cycles, the second still well ahead. Such
/// a cycle can't be told apart with certainty from one paid early, so `find`
/// changes nothing. The repair list shows each one and runs `undoSecond` only
/// with the person's OK.
enum LikelyDoubleCompletions {
    /// The second completion came this soon after the first.
    static let withinDays = 7
    /// And closed a cycle at least this far ahead of the day it was recorded.
    static let aheadDays = 8

    struct Candidate: Hashable, Sendable {
        var obligationId: UUID
        /// The completion to offer to delete: the latest, so deleting it moves the deadline back.
        var historyEntryId: UUID
        var closedCycle: CalendarDay
    }

    struct Completion: Hashable, Sendable {
        var id: UUID
        var occurredAt: Date
        /// The cycle it closed.
        var cycle: CalendarDay?
        /// The due day it moved the obligation to.
        var next: CalendarDay?
    }

    /// Whether the two latest completions (newest first) look like one real and one stale tap.
    static func isLikely(latest: Completion, previous: Completion, calendar: Calendar = .dosar) -> Bool {
        guard let closed = latest.cycle, previous.next == closed else { return false }
        let latestDay = CalendarDay(latest.occurredAt, calendar: calendar)
        let apart = CalendarDay(previous.occurredAt, calendar: calendar).days(to: latestDay, calendar: calendar)
        return (0...withinDays).contains(apart) && latestDay.days(to: closed, calendar: calendar) >= aheadDays
    }

    /// Every likely case in the household. Reads only.
    @MainActor
    static func find(in context: ModelContext, calendar: Calendar = .dosar) throws -> [Candidate] {
        try context.fetch(FetchDescriptor<Obligation>()).compactMap { candidate(for: $0, calendar: calendar) }
    }

    /// Deletes the second completion of a case the person confirmed, as Istoric would: it is
    /// the latest, so the deadline goes back to the cycle it closed. Safe to run again: it
    /// acts only while that completion is still the latest and still looks like a stale
    /// tap, and returns whether it changed anything.
    @MainActor
    @discardableResult
    static func undoSecond(_ candidate: Candidate, in context: ModelContext, calendar: Calendar = .dosar) throws -> Bool {
        let id = candidate.obligationId
        var descriptor = FetchDescriptor<Obligation>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        guard let obligation = try context.fetch(descriptor).first,
              self.candidate(for: obligation, calendar: calendar) == candidate,
              let entry = obligation.history.first, obligation.latestCompletion?.id == entry.id
        else { return false }
        try HistoryActions(context: context).delete(entry)
        return true
    }

    @MainActor
    private static func candidate(for obligation: Obligation, calendar: Calendar) -> Candidate? {
        let history = obligation.history.prefix(2).map {
            Completion(
                id: $0.id,
                occurredAt: $0.occurredAt,
                cycle: $0.cycleDueDate.map { CalendarDay($0, calendar: calendar) },
                next: $0.nextDueDate.map { CalendarDay($0, calendar: calendar) }
            )
        }
        guard history.count == 2, isLikely(latest: history[0], previous: history[1], calendar: calendar),
              let closed = history[0].cycle else { return nil }
        return Candidate(obligationId: obligation.id, historyEntryId: history[0].id, closedCycle: closed)
    }
}
