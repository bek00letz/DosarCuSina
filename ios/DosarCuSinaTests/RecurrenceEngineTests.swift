import Foundation
import Testing
@testable import DosarCuSina

@Suite("Recurrence engine")
struct RecurrenceEngineTests {
    let calendar = Calendar.bucharest

    @Test func dueDateAnchorKeepsTheCycleEvenWhenPaidLate() {
        let next = RecurrenceEngine.nextDue(
            after: CalendarDay("2026-01-31"), completedOn: CalendarDay("2026-02-10"),
            rule: .interval(.months(1), anchor: .dueDate), calendar: calendar
        )
        #expect(next?.day == CalendarDay("2026-02-28"))
    }

    @Test func completionAnchorCountsFromTheDayItWasDone() {
        let next = RecurrenceEngine.nextDue(
            after: CalendarDay("2026-06-01"), completedOn: CalendarDay("2026-05-20"),
            rule: .interval(.years(2), anchor: .completion), calendar: calendar
        )
        #expect(next?.day == CalendarDay("2028-05-20"))
    }

    @Test func leapDayRollsToTheTwentyEighth() {
        let next = RecurrenceEngine.nextDue(
            after: CalendarDay("2028-02-29"), completedOn: CalendarDay("2028-02-29"),
            rule: .interval(.years(1), anchor: .dueDate), calendar: calendar
        )
        #expect(next?.day == CalendarDay("2029-02-28"))
    }

    @Test func fixedDatesMoveToTheNextInstallment() {
        let rule = RecurrenceRule.fixedDates([MonthDay(month: 3, day: 31), MonthDay(month: 9, day: 30)])
        #expect(RecurrenceEngine.nextDue(after: CalendarDay("2026-03-31"), completedOn: CalendarDay("2026-03-20"), rule: rule, calendar: calendar)?.day == CalendarDay("2026-09-30"))
        #expect(RecurrenceEngine.nextDue(after: CalendarDay("2026-09-30"), completedOn: CalendarDay("2026-09-30"), rule: rule, calendar: calendar)?.day == CalendarDay("2027-03-31"))
        // Paid very late: the next installment is still owed, so it is not skipped.
        #expect(RecurrenceEngine.nextDue(after: CalendarDay("2026-03-31"), completedOn: CalendarDay("2026-11-01"), rule: rule, calendar: calendar)?.day == CalendarDay("2026-09-30"))
    }

    @Test func oneOffObligationsHaveNoNextCycle() {
        #expect(RecurrenceEngine.nextDue(after: CalendarDay("2026-01-01"), completedOn: CalendarDay("2026-01-01"), rule: .none, calendar: calendar) == nil)
    }

    @Test("ITP follows the vehicle's age and use", arguments: [
        (2018.0, "Personală", "2026-05-20", "2028-05-20"),
        (2014.0, "Personală", "2026-05-20", "2028-05-20"),
        (2013.0, "Personală", "2026-05-20", "2027-05-20"),
        (2022.0, "Ridesharing sau taxi", "2026-05-20", "2026-11-20"),
    ])
    func itpInterval(year: Double, usage: String, done: String, expected: String) {
        var values = FieldValues()
        values["vehicle.year"] = .number(year)
        values["vehicle.usage"] = .text(usage)
        let next = RecurrenceEngine.nextDue(
            after: CalendarDay(done), completedOn: CalendarDay(done), rule: .legal(.vehicleITP),
            context: RecurrenceContext(assetValues: values), calendar: calendar
        )
        #expect(next?.day == CalendarDay(expected))
    }

    @Test func itpWithUnknownAgeUsesTheShorterInterval() {
        let next = RecurrenceEngine.nextDue(after: CalendarDay("2026-05-20"), completedOn: CalendarDay("2026-05-20"), rule: .legal(.vehicleITP), calendar: calendar)
        #expect(next?.day == CalendarDay("2027-05-20"))
    }

    @Test func metricRuleUsesTheProjectionOrTheFallbackWhicheverIsFirst() {
        // 50 km a day: 15 000 km takes 300 days, the one-year fallback is later.
        let start = noon("2026-01-01")
        let readings = [
            CadenceCalculator.TelemetryReading(date: start, metric: 100_000),
            CadenceCalculator.TelemetryReading(date: calendar.date(byAdding: .day, value: 40, to: start)!, metric: 102_000),
        ]
        let fast = RecurrenceEngine.nextDue(
            after: CalendarDay("2026-02-10"), completedOn: CalendarDay("2026-02-10"),
            rule: .metric(every: 15_000, unit: "km", fallback: .years(1)),
            context: RecurrenceContext(readings: readings, currentMetric: 102_000), calendar: calendar
        )
        #expect(fast?.metric == 117_000)
        #expect(fast.map { CalendarDay("2026-02-10").days(to: $0.day, calendar: calendar) } == 300)

        // Barely driven: the calendar fallback wins.
        let slow = RecurrenceEngine.nextDue(
            after: CalendarDay("2026-02-10"), completedOn: CalendarDay("2026-02-10"),
            rule: .metric(every: 15_000, unit: "km", fallback: .years(1)),
            context: RecurrenceContext(readings: [
                CadenceCalculator.TelemetryReading(date: start, metric: 100_000),
                CadenceCalculator.TelemetryReading(date: calendar.date(byAdding: .day, value: 40, to: start)!, metric: 100_100),
            ], currentMetric: 100_100),
            calendar: calendar
        )
        #expect(slow?.day == CalendarDay("2027-02-10"))
    }

    @Test func metricRuleWithoutReadingsFallsBack() {
        let next = RecurrenceEngine.nextDue(after: CalendarDay("2026-02-10"), completedOn: CalendarDay("2026-02-10"),
                                            rule: .metric(every: 150, unit: "km", fallback: .months(1)), calendar: calendar)
        #expect(next?.day == CalendarDay("2026-03-10"))
        #expect(next?.metric == nil)
    }

    @Test func firstDueComesFromFieldsIntervalsOrFixedDates() {
        var values = FieldValues()
        values["document.expiry"] = .date(CalendarDay("2027-06-01"))
        let today = CalendarDay("2026-11-02")
        let renew = ObligationBlueprint(key: "r", title: "R", kind: .renewal, recurrence: .none, firstDue: .field(key: "document.expiry", offsetDays: -30))
        #expect(RecurrenceEngine.firstDue(for: renew, values: values, today: today, calendar: calendar) == CalendarDay("2027-05-02"))
        #expect(RecurrenceEngine.firstDue(for: renew, values: FieldValues(), today: today, calendar: calendar) == nil)

        let tax = ObligationBlueprint(key: "t", title: "T", kind: .tax, recurrence: .fixedDates([MonthDay(month: 3, day: 31), MonthDay(month: 9, day: 30)]), firstDue: .nextFixedDate)
        #expect(RecurrenceEngine.firstDue(for: tax, values: values, today: today, calendar: calendar) == CalendarDay("2027-03-31"))

        let ask = ObligationBlueprint(key: "a", title: "A", kind: .legal, recurrence: .legal(.vehicleITP), firstDue: .ask)
        #expect(RecurrenceEngine.firstDue(for: ask, values: values, today: today, calendar: calendar) == nil)
    }

    @Test func rulesRoundTripThroughTheArchiveEncoding() throws {
        let rules: [RecurrenceRule] = [
            .none,
            .interval(.years(2), anchor: .completion),
            .fixedDates([MonthDay(month: 9, day: 30), MonthDay(month: 3, day: 31)]),
            .metric(every: 15_000, unit: "km", fallback: .years(1)),
            .legal(.vehicleITP),
        ]
        for rule in rules {
            let decoded = try JSONDecoder().decode(RecurrenceRule.self, from: JSONEncoder().encode(rule))
            if case .fixedDates(let dates) = rule {
                #expect(decoded == .fixedDates(dates.sorted()))
            } else {
                #expect(decoded == rule)
            }
        }
    }

    @Test func everyBuiltInBlueprintIsUsable() {
        for template in BuiltInTemplates.all {
            let keys = Set(template.allFields.map(\.key))
            #expect(keys.count == template.allFields.count, "Duplicate field keys in \(template.key)")
            for blueprint in template.blueprints {
                if case .field(let key, _) = blueprint.firstDue {
                    #expect(keys.contains(key), "\(blueprint.key) reads missing field \(key)")
                }
                if case .nextFixedDate = blueprint.firstDue, case .fixedDates = blueprint.recurrence {} else if case .nextFixedDate = blueprint.firstDue {
                    Issue.record("\(blueprint.key) asks for a fixed date without fixed dates")
                }
            }
        }
    }
}
