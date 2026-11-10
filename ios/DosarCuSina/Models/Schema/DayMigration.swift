import Foundation
import SwiftData
import Synchronization

/// The move from version 8, which kept days as moments, to version 9, which keeps them as days
/// (`StoredDay`). One stage of `DosarMigrationPlan`:
///
/// 1. Before the store changes shape (`willMigrate`, version 8's models), every stored moment
///    is read as the day it meant (`StoredDay.day(of:storedAs:calendar:)`) and kept in memory,
///    by record.
/// 2. The store changes shape: the moments go, the day texts come, empty.
/// 3. After (`didMigrate`, version 9's models), each record gets its days back as text, and the
///    store is saved once (`UnitOfWork.performPrivate`). Change times stay as they were: the
///    days mean what they meant.
///
/// The time zone a moment was written in wasn't kept, so the moments are read in the phone's
/// time zone at the upgrade (`Calendar.dosar`): the one it was written in for nearly everyone,
/// and noon keeps the day for any time zone up to eleven hours away.
enum DayMigration {
    /// The calendar the moments are read in; nil is the app's (`Calendar.dosar`). Tests upgrade
    /// a store as if the phone were in another time zone with `$calendar.withValue`.
    @TaskLocal static var calendar: Calendar?

    static var stage: MigrationStage {
        let carried = Carried()
        return .custom(
            fromVersion: DosarSchemaV8.self,
            toVersion: DosarSchemaV9.self,
            willMigrate: { context in try carried.read(context, calendar: calendar ?? .dosar) },
            didMigrate: { context in try carried.write(context) }
        )
    }

    /// The days of one record, in the order its type keeps them.
    struct Days: Sendable, Equatable {
        var first: CalendarDay?
        var second: CalendarDay?
    }

    /// A record's place in the carried days: its id and a moment it keeps, so two records that
    /// share an id (a backup brought in twice by an old build) keep their own.
    static func key(_ type: String, _ id: UUID, _ moment: Date) -> String {
        "\(type)|\(id.uuidString)|\(moment.timeIntervalSinceReferenceDate)"
    }

    /// The days read before the store changes shape, until they are written after.
    final class Carried: Sendable {
        private let days = Mutex<[String: Days]>([:])

        func read(_ context: ModelContext, calendar: Calendar) throws {
            var found: [String: Days] = [:]
            var deadlines = FetchDescriptor<DosarSchemaV8.Obligation>()
            deadlines.propertiesToFetch = [\.id, \.createdAt, \.dueDate, \.snoozedUntil]
            for deadline in try context.fetch(deadlines) {
                found[key("Obligation", deadline.id, deadline.createdAt)] = Days(
                    first: StoredDay.day(of: deadline.dueDate, storedAs: .noon, calendar: calendar),
                    second: deadline.snoozedUntil.map { StoredDay.day(of: $0, storedAs: .startOfDay, calendar: calendar) }
                )
            }
            var completions = FetchDescriptor<DosarSchemaV8.HistoryEntry>(predicate: #Predicate { $0.cycleDueDate != nil || $0.nextDueDate != nil })
            completions.propertiesToFetch = [\.id, \.occurredAt, \.cycleDueDate, \.nextDueDate]
            for entry in try context.fetch(completions) {
                found[key("HistoryEntry", entry.id, entry.occurredAt)] = Days(
                    first: entry.cycleDueDate.map { StoredDay.day(of: $0, storedAs: .noon, calendar: calendar) },
                    second: entry.nextDueDate.map { StoredDay.day(of: $0, storedAs: .noon, calendar: calendar) }
                )
            }
            var documents = FetchDescriptor<DosarSchemaV8.Attachment>(predicate: #Predicate { $0.documentDate != nil || $0.validUntil != nil })
            documents.propertiesToFetch = [\.id, \.createdAt, \.documentDate, \.validUntil]
            for document in try context.fetch(documents) {
                found[key("Attachment", document.id, document.createdAt)] = Days(
                    first: document.documentDate.map { StoredDay.day(of: $0, storedAs: .noon, calendar: calendar) },
                    second: document.validUntil.map { StoredDay.day(of: $0, storedAs: .noon, calendar: calendar) }
                )
            }
            days.withLock { $0 = found }
        }

        func write(_ context: ModelContext) throws {
            let carried = days.withLock { kept in
                defer { kept = [:] }
                return kept
            }
            guard !carried.isEmpty else { return }
            try UnitOfWork.performPrivate(in: context) {
                for deadline in try context.fetch(FetchDescriptor<DosarSchemaV9.Obligation>()) {
                    guard let days = carried[key("Obligation", deadline.id, deadline.createdAt)] else { continue }
                    if let due = days.first { deadline.dueDay = due }
                    deadline.snoozedUntil = days.second
                }
                for entry in try context.fetch(FetchDescriptor<DosarSchemaV9.HistoryEntry>()) {
                    guard let days = carried[key("HistoryEntry", entry.id, entry.occurredAt)] else { continue }
                    entry.cycleDueDay = days.first
                    entry.nextDueDay = days.second
                }
                for document in try context.fetch(FetchDescriptor<DosarSchemaV9.Attachment>()) {
                    guard let days = carried[key("Attachment", document.id, document.createdAt)] else { continue }
                    document.documentDay = days.first
                    document.validUntil = days.second
                }
            }
        }
    }
}
