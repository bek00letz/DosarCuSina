import Foundation
import SwiftData
import Testing
@testable import DosarCuSina

/// A day kept with another calendar's year (a phone set to the Buddhist calendar before the
/// app counted in one Gregorian calendar) is offered back in its Gregorian year, asking first;
/// a year that can't be and can't be worked back safely is only listed, with what to check.
/// Every value is a placeholder.
@MainActor
@Suite("Repair: days with another calendar's year")
struct DayYearsRepairTests {
    private func repairs(_ context: ModelContext) -> DataRepairs {
        DataRepairs(context: context, calendar: .bucharest,
                    ledger: DataRepairLedger(defaults: UserDefaults(suiteName: "day-years-\(UUID().uuidString)")!))
    }

    private func passport(_ context: ModelContext, _ values: [String: FieldValue]) throws -> Asset {
        let passport = Asset(name: "Pașaport", templateKey: BuiltInTemplates.Key.documents, values: FieldValues(values))
        context.insert(passport)
        try UnitOfWork.save(context)
        return passport
    }

    @Test("Which years can't be, and what they mean", arguments: [
        ("2026-03-31", DayYearsStep.Verdict.possible),
        ("2226-03-31", .possible),
        ("1890-06-01", .possible),
        ("2569-03-31", .means(CalendarDay("2026-03-31"))),
        ("2483-05-01", .means(CalendarDay("1940-05-01"))),
        ("2567-02-29", .means(CalendarDay("2024-02-29"))),
        ("2227-01-01", .unknown),
        ("1484-03-31", .unknown),
        ("0008-03-31", .unknown),
        ("5787-01-01", .unknown),
    ])
    func verdict(day: String, expected: DayYearsStep.Verdict) {
        #expect(DayYearsStep.verdict(CalendarDay(day), thisYear: 2026) == expected, "\(day)")
    }

    @Test("A Buddhist year is offered back, asking first, and idempotent")
    func aBuddhistYearIsOfferedBack() throws {
        let context = try makeContext()
        let document = try passport(context, [
            DocumentFields.expiry: .date(CalendarDay("2574-03-31")),
            DocumentFields.issueDate: .date(CalendarDay("2021-04-01")),
        ])
        let renewal = Obligation(title: "Reînnoire", kind: .renewal, dueDay: CalendarDay("2574-03-31"))
        context.insert(renewal)
        renewal.asset = document
        try UnitOfWork.save(context)

        let list = repairs(context)
        let found = try list.detect().filter { $0.step == .dayYears }
        try #require(found.count == 2)
        #expect(found.allSatisfy { $0.isFixable })
        #expect(found.allSatisfy { $0.message.contains("31 martie 2574") && $0.message.contains("31 martie 2031") })
        #expect(document.value(DocumentFields.expiry) == .date(CalendarDay("2574-03-31")), "Nothing changes before the owner says so")

        try list.apply(found)
        #expect(document.value(DocumentFields.expiry) == .date(CalendarDay("2031-03-31")))
        #expect(document.value(DocumentFields.issueDate) == .date(CalendarDay("2021-04-01")), "A day that can be stays")
        #expect(renewal.dueDay == CalendarDay("2031-03-31"))
        #expect(try list.detect().filter { $0.step == .dayYears }.isEmpty, "Found nothing once applied")
        try list.apply(found)
        #expect(renewal.dueDay == CalendarDay("2031-03-31"))
        #expect(!context.hasChanges)
    }

    @Test("A year that can't be worked back only says what to check")
    func anotherCalendarsYearIsOnlyListed() throws {
        let context = try makeContext()
        let document = try passport(context, [DocumentFields.expiry: .date(CalendarDay("0008-03-31"))])
        let policy = DosarCuSina.Attachment(fileName: "polita.pdf", contentType: "com.adobe.pdf", data: nil, kind: .policy)
        policy.title = "Poliță"
        policy.validUntil = CalendarDay("1484-03-31")
        context.insert(policy)
        policy.asset = document
        try UnitOfWork.save(context)

        let list = repairs(context)
        let found = try list.detect().filter { $0.step == .dayYears }
        try #require(found.count == 2)
        #expect(found.allSatisfy { !$0.isFixable })
        #expect(found.allSatisfy { $0.message.contains("Verifică data") })
        try list.apply(found)
        #expect(document.value(DocumentFields.expiry) == .date(CalendarDay("0008-03-31")), "Nothing it can't decide changes")
        #expect(policy.validUntil == CalendarDay("1484-03-31"))
    }

    @Test("A day changed since it was found stays as it is now")
    func aDayChangedSinceStays() throws {
        let context = try makeContext()
        let document = try passport(context, [DocumentFields.expiry: .date(CalendarDay("2574-03-31"))])
        let list = repairs(context)
        let found = try list.detect().filter { $0.step == .dayYears }
        try #require(found.count == 1)
        var values = document.values
        values[DocumentFields.expiry] = .date(CalendarDay("2032-01-15"))
        document.values = values
        try UnitOfWork.save(context)
        try list.apply(found)
        #expect(document.value(DocumentFields.expiry) == .date(CalendarDay("2032-01-15")))
    }

    @Test func theStepComesAfterTheOnesBeforeItWithItsOwnStoredID() throws {
        let ids = DataRepairs.steps.map { type(of: $0).id }
        let visits = try #require(ids.firstIndex(of: .sameVisitTwice))
        let days = try #require(ids.firstIndex(of: .dayYears))
        #expect(visits < days, "A new repair is a new step at the end")
        #expect(DataRepairStepID.dayYears.rawValue == "day-years")
    }
}
