import Foundation
import SwiftData
import Testing
@testable import DosarCuSina

@MainActor
@Suite("A series keeps its day of the month")
struct RecurrenceSeriesTests {
    let calendar = Calendar.bucharest

    private func lastDay(year: Int, month: Int) -> Int {
        let start = CalendarDay(year: year, month: month, day: 1).noonDate(in: calendar)
        return calendar.range(of: .day, in: .month, for: start)?.count ?? 0
    }

    @Test func monthlyOnThe31stNeverDrifts() throws {
        let context = try makeContext()
        let actions = ObligationActions(context: context, calendar: calendar, now: { noon("2027-01-01") })
        let rent = try actions.create(title: "Chirie", kind: .payment, dueDay: CalendarDay("2027-01-31"), for: nil,
                                      recurrence: .interval(.months(1), anchor: .dueDate))
        for step in 1...24 {
            try actions.complete(rent)
            let month = (step % 12) + 1
            let year = 2027 + step / 12
            #expect(rent.dueDay == CalendarDay(year: year, month: month, day: min(31, lastDay(year: year, month: month))))
        }
    }

    @Test func the29thOfFebruaryComesBackInLeapYears() throws {
        let context = try makeContext()
        let actions = ObligationActions(context: context, calendar: calendar, now: { noon("2028-01-01") })
        let tax = try actions.create(title: "Taxă", kind: .tax, dueDay: CalendarDay("2028-02-29"), for: nil,
                                     recurrence: .interval(.years(1), anchor: .dueDate))
        let expected = ["2029-02-28", "2030-02-28", "2031-02-28", "2032-02-29", "2033-02-28", "2034-02-28", "2035-02-28", "2036-02-29"]
        for day in expected {
            try actions.complete(tax)
            #expect(tax.dueDay == CalendarDay(day))
        }
    }

    @Test func aDayMovedByHandStartsANewSeries() throws {
        let context = try makeContext()
        let actions = ObligationActions(context: context, calendar: calendar, now: { noon("2027-01-01") })
        let rent = try actions.create(title: "Chirie", kind: .payment, dueDay: CalendarDay("2027-01-31"), for: nil,
                                      recurrence: .interval(.months(1), anchor: .dueDate))
        try actions.complete(rent)
        #expect(rent.dueDay == CalendarDay("2027-02-28"))
        try actions.reschedule(rent, to: CalendarDay("2027-03-15"))
        try actions.complete(rent)
        #expect(rent.dueDay == CalendarDay("2027-04-15"))
    }

    @Test func theSeriesStartIsReadFromItsCompletions() {
        typealias Step = RecurrenceEngine.SeriesStep
        // A series that already drifted (31 January, 28 February, 28 March) still remembers the 31st.
        let steps = [Step(cycle: CalendarDay("2027-02-28"), next: CalendarDay("2027-03-28")),
                     Step(cycle: CalendarDay("2027-01-31"), next: CalendarDay("2027-02-28"))]
        #expect(RecurrenceEngine.seriesStart(current: CalendarDay("2027-03-28"), completions: steps) == CalendarDay("2027-01-31"))
        #expect(RecurrenceEngine.seriesStart(current: CalendarDay("2027-03-15"), completions: steps) == CalendarDay("2027-03-15"),
                "A due day that no completion led to was set by hand")
        let next = RecurrenceEngine.nextDue(after: CalendarDay("2027-03-28"), completedOn: CalendarDay("2027-03-28"),
                                            rule: .interval(.months(1), anchor: .dueDate),
                                            context: RecurrenceContext(seriesDayOfMonth: 31), calendar: calendar)
        #expect(next?.day == CalendarDay("2027-04-30"))
    }
}
