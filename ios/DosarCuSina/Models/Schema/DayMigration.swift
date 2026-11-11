import Foundation
import SwiftData

/// The move from version 8, which kept days as moments, to version 9, which keeps them as days
/// (`StoredDay`). One stage of `DosarMigrationPlan`, carried by `MigrationCarry`:
///
/// 1. Before the store changes shape (`willMigrate`, version 8's models), every stored moment
///    is read as the day it meant (`StoredDay.day(of:storedAs:calendar:)`), by record, and kept in
///    a file beside the store. If it can't be kept, the stage throws and the store stays at 8.
/// 2. The store changes shape: the moments go, the day texts come, empty.
/// 3. Once the store opens, at whatever version is current then, each record gets its days back
///    as text (`StoredDay.text`), the store is saved once (`UnitOfWork.performPrivate`) and the
///    file goes (`finish`). An upgrade stopped after step 2 finishes at the next launch the same
///    way. Change times stay as they were: the days mean what they meant.
///
/// The time zone a moment was written in wasn't kept, so the moments are read in the phone's
/// time zone at the upgrade (`Calendar.dosar`): the one it was written in for nearly everyone,
/// and noon keeps the day for any time zone up to eleven hours away.
enum DayMigration: MigrationCarrying {
    /// The calendar the moments are read in; nil is the app's (`Calendar.dosar`). Tests upgrade
    /// a store as if the phone were in another time zone with `$calendar.withValue`.
    @TaskLocal static var calendar: Calendar?

    typealias Carried = [String: Days]

    static var carryName: String { "days-v9" }

    static var stage: MigrationStage {
        .custom(
            fromVersion: DosarSchemaV8.self,
            toVersion: DosarSchemaV9.self,
            willMigrate: { context in
                let days = try read(context, calendar: calendar ?? .dosar)
                guard !days.isEmpty else { return }
                try MigrationCarry.keep(days, for: DayMigration.self, from: context)
            },
            didMigrate: nil
        )
    }

    /// The days of one record, in the order its type keeps them, as their stored text.
    struct Days: Codable, Sendable, Equatable {
        var first: String?
        var second: String?

        init(first: CalendarDay?, second: CalendarDay?) {
            self.first = first.map(StoredDay.text)
            self.second = second.map(StoredDay.text)
        }
    }

    /// A record's place in the carried days: its id and a moment it keeps, so two records that
    /// share an id (a backup brought in twice by an old build) keep their own.
    static func key(_ type: String, _ id: UUID, _ moment: Date) -> String {
        "\(type)|\(id.uuidString)|\(moment.timeIntervalSinceReferenceDate)"
    }

    /// Every day a version 8 store keeps, by record, read before it changes shape.
    static func read(_ context: ModelContext, calendar: Calendar) throws -> [String: Days] {
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
        return found
    }

    /// Writes the carried days into the store as the current version keeps them, saved once.
    /// Written again, they are the same text.
    static func finish(_ carried: [String: Days], in container: ModelContainer) throws {
        let context = PersistenceController.context(in: container)
        try UnitOfWork.performPrivate(in: context) {
            for deadline in try context.fetch(FetchDescriptor<Obligation>()) {
                guard let days = carried[key("Obligation", deadline.id, deadline.createdAt)] else { continue }
                if let due = days.first { deadline.dueDayISO = due }
                deadline.snoozedUntilISO = days.second
            }
            for entry in try context.fetch(FetchDescriptor<HistoryEntry>()) {
                guard let days = carried[key("HistoryEntry", entry.id, entry.occurredAt)] else { continue }
                entry.cycleDueDayISO = days.first
                entry.nextDueDayISO = days.second
            }
            for document in try context.fetch(FetchDescriptor<Attachment>()) {
                guard let days = carried[key("Attachment", document.id, document.createdAt)] else { continue }
                document.documentDayISO = days.first
                document.validUntilISO = days.second
            }
        }
    }
}
