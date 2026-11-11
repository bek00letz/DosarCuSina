import Foundation
import SwiftData
import Testing
@testable import DosarCuSina

/// Every day the database keeps (a due day, a snooze's end, the cycles a completion closed and
/// opened, a document's date and its last valid day) is kept as a day: the same day on a phone
/// in any time zone, sorted as the days are.
@MainActor
@Suite("Days stored as days")
struct DaysStoredAsDaysTests {
    /// Every whole-hour time zone a phone can be set to, twelve hours behind to fourteen ahead.
    nonisolated static let zones: [TimeZone] = (-12...14).compactMap { TimeZone(secondsFromGMT: $0 * 3600) }

    /// The only moments the database keeps: when something happened, was made, last changed or
    /// was made smaller, and since when a deadline's cycle is known. A new property that means a
    /// day is a `StoredDay` text, never a `Date`.
    @Test func everyStoredMomentIsAMoment() {
        let moments: Set<String> = [
            "CategoryTemplate.createdAt", "CategoryTemplate.updatedAt", "Asset.createdAt", "Asset.updatedAt",
            "Obligation.createdAt", "Obligation.updatedAt", "Obligation.cycleKnownAt", "HistoryEntry.occurredAt", "HistoryEntry.updatedAt",
            "ServiceItem.updatedAt", "MeasurementLog.recordedAt", "MeasurementLog.updatedAt",
            "Attachment.compactedAt", "Attachment.createdAt", "Attachment.updatedAt",
            "Provider.createdAt", "Provider.updatedAt",
        ]
        let stored = Set(Schema(versionedSchema: DosarSchemaV13.self).entities.flatMap { entity in
            entity.attributes.filter { $0.valueType == Date.self || $0.valueType == Date?.self }.map { "\(entity.name).\($0.name)" }
        })
        #expect(stored == moments)
    }

    @Test func aDayIsKeptAsItsISOText() {
        let rca = Obligation(title: "RCA", kind: .insurance, dueDay: CalendarDay("2026-11-15"))
        #expect(rca.dueDayISO == "2026-11-15")
        rca.snoozedUntil = CalendarDay("2026-11-05")
        #expect(rca.snoozedUntilISO == "2026-11-05")
        rca.snoozedUntil = nil
        #expect(rca.snoozedUntilISO == nil)

        let paid = HistoryEntry(kind: .payment, title: "RCA", occurredAt: noon("2026-11-10"))
        #expect(!paid.isCompletion)
        paid.cycleDueDay = CalendarDay("2026-11-15")
        paid.nextDueDay = CalendarDay("2027-11-15")
        #expect(paid.cycleDueDayISO == "2026-11-15" && paid.nextDueDayISO == "2027-11-15")
        #expect(paid.isCompletion)

        let policy = DosarCuSina.Attachment(fileName: "polita.pdf", contentType: "com.adobe.pdf", data: nil, kind: .policy)
        policy.documentDay = CalendarDay("2026-11-14")
        policy.validUntil = CalendarDay("2027-11-14")
        #expect(policy.documentDayISO == "2026-11-14" && policy.validUntilISO == "2027-11-14")
    }

    @Test func aStoredTextThatIsNoDayReadsAsNone() {
        #expect(StoredDay.day(nil) == nil)
        #expect(StoredDay.day("") == nil)
        #expect(StoredDay.day("2026-13-01") == nil)
        #expect(StoredDay.day("2026-11-15T12:00:00Z") == nil, "Only a day, never a moment")
        #expect(StoredDay.day("0031-03-12") == CalendarDay(year: 31, month: 3, day: 12), "Read as stored: the repair list finds a year that can't be")
        let made = noon("2026-11-02")
        let broken = Obligation(title: "ITP", kind: .legal, dueDay: CalendarDay("2026-11-15"))
        broken.createdAt = made
        broken.dueDayISO = ""
        #expect(broken.dueDay == CalendarDay(made), "A deadline with no day is due on the day it was made")
    }

    @Test(arguments: zones)
    func aDayReadsTheSameInEveryTimeZone(zone: TimeZone) throws {
        let calendar = Calendar.dosar(in: zone)
        let context = try makeContext()
        let rca = Obligation(title: "RCA", kind: .insurance, dueDay: CalendarDay("2026-11-15"))
        context.insert(rca)
        try UnitOfWork.save(context)
        #expect(rca.dueDay == CalendarDay("2026-11-15"))
        #expect(rca.daysRemaining(from: CalendarDay("2026-11-05").noonDate(in: calendar), calendar: calendar) == 10, "\(zone.identifier)")
        rca.snoozedUntil = CalendarDay("2026-11-08")
        #expect(rca.isSnoozed(at: CalendarDay("2026-11-07").noonDate(in: calendar).addingTimeInterval(11 * 3600), calendar: calendar))
        #expect(!rca.isSnoozed(at: CalendarDay("2026-11-08").startDate(in: calendar), calendar: calendar), "Back as its day starts there")
        #expect(rca.snoozeEnds(in: calendar) == CalendarDay("2026-11-08").startDate(in: calendar))
    }

    /// Version 8's moments, read back as the day they meant: noon keeps the day up to eleven
    /// hours away, and so does the start of a day.
    @Test(arguments: zones)
    func aMomentVersionEightWroteReadsAsItsDay(zone: TimeZone) {
        let written = Calendar.dosar(in: zone)
        let day = CalendarDay("2026-03-29") // Summer time starts in Romania that night.
        #expect(StoredDay.day(of: day.noonDate(in: written), storedAs: .noon, calendar: written) == day)
        #expect(StoredDay.day(of: day.startDate(in: written), storedAs: .startOfDay, calendar: written) == day)
        for hours in -11...11 {
            guard let near = TimeZone(secondsFromGMT: zone.secondsFromGMT() + hours * 3600) else { continue }
            let there = Calendar.dosar(in: near)
            #expect(StoredDay.day(of: day.noonDate(in: written), storedAs: .noon, calendar: there) == day, "\(zone.identifier) read \(hours) h away")
            #expect(StoredDay.day(of: day.startDate(in: written), storedAs: .startOfDay, calendar: there) == day, "\(zone.identifier) read \(hours) h away")
        }
    }

    /// Fetches sort by the stored day and find what is due by it, across months and years.
    @Test func fetchesSortAndFindByTheDay() throws {
        let context = try makeContext()
        for (title, day) in [("C", "2027-01-05"), ("A", "2026-09-30"), ("B", "2026-10-01"), ("D", "2030-02-28")] {
            context.insert(Obligation(title: title, kind: .routine, dueDay: CalendarDay(day)))
        }
        try UnitOfWork.save(context)
        let sorted = try context.fetch(FetchDescriptor<Obligation>(sortBy: [Obligation.byDueDay]))
        #expect(sorted.map(\.title) == ["A", "B", "C", "D"])
        let cutoff = StoredDay.text(CalendarDay("2026-12-31"))
        let dueThisYear = try context.fetch(FetchDescriptor<Obligation>(predicate: #Predicate { $0.dueDayISO <= cutoff }, sortBy: [Obligation.byDueDay]))
        #expect(dueThisYear.map(\.title) == ["A", "B"])
        #expect(try ObligationSnapshot.fetchAll(in: context).map(\.title) == ["A", "B", "C", "D"], "What reminders, widgets and Spotlight read, soonest first")
    }

    /// A backup carries a snooze as the moment it ends; read back on a phone up to eleven hours
    /// away, it ends on the same day.
    @Test func aSnoozeInABackupEndsOnItsDayWhereItIsRead() {
        let bucharest = Calendar.dosar(in: TimeZone(identifier: "Europe/Bucharest")!)
        let newYork = Calendar.dosar(in: TimeZone(identifier: "America/New_York")!)
        let written = CalendarDay("2026-11-08").startDate(in: bucharest)
        #expect(StoredDay.day(of: written, storedAs: .startOfDay, calendar: newYork) == CalendarDay("2026-11-08"))
    }
}
