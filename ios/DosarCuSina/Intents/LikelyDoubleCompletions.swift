import Foundation
import SwiftData

/// Deadlines whose last "done" may have come from an old reminder button, before
/// buttons acted only on the cycle they were about: two completions a few days
/// apart, the second closing a cycle that was still well ahead. Such a cycle can't
/// be told apart from one paid early, so nothing is changed here. The repair list
/// shows each one and offers to undo the second completion, only with the person's OK.
enum LikelyDoubleCompletions {
    /// The second completion came this soon after the first.
    static let withinDays = 7
    /// And closed a cycle at least this far ahead of the day it was recorded.
    static let aheadDays = 8

    struct Candidate: Hashable, Sendable {
        var obligationId: UUID
        /// The completion to offer to undo: the latest, so `ObligationActions.undo` accepts it.
        var historyEntryId: UUID
        var closedCycle: CalendarDay
    }

    struct Completion: Hashable, Sendable {
        var id: UUID
        var occurredAt: Date
        var cycle: CalendarDay?
    }

    /// Whether the two latest completions (newest first) look like one real and one stale tap.
    static func isLikely(latest: Completion, previous: Completion, calendar: Calendar = .current) -> Bool {
        guard let closed = latest.cycle, let earlier = previous.cycle, closed > earlier else { return false }
        let latestDay = CalendarDay(latest.occurredAt, calendar: calendar)
        let apart = CalendarDay(previous.occurredAt, calendar: calendar).days(to: latestDay, calendar: calendar)
        return (0...withinDays).contains(apart) && latestDay.days(to: closed, calendar: calendar) >= aheadDays
    }

    @MainActor
    static func find(in context: ModelContext, calendar: Calendar = .current) throws -> [Candidate] {
        try context.fetch(FetchDescriptor<Obligation>()).compactMap { obligation in
            let history = obligation.history.prefix(2).map {
                Completion(id: $0.id, occurredAt: $0.occurredAt, cycle: $0.cycleDueDate.map { CalendarDay($0, calendar: calendar) })
            }
            guard history.count == 2, isLikely(latest: history[0], previous: history[1], calendar: calendar),
                  let closed = history[0].cycle else { return nil }
            return Candidate(obligationId: obligation.id, historyEntryId: history[0].id, closedCycle: closed)
        }
    }
}
