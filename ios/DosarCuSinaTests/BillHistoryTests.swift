import Foundation
import Testing
@testable import DosarCuSina

/// A subscription's bills: the trend in plain words, per currency, and the calm note
/// when one hasn't come. Every date is relative to the day the test runs.
@Suite("Bill history")
struct BillHistoryTests {

    private let calendar = Calendar.bucharest
    private var today: CalendarDay { CalendarDay(Date(), calendar: calendar) }

    private func monthsAgo(_ months: Int, plusDays days: Int = 0) -> CalendarDay {
        let day = calendar.date(byAdding: .month, value: -months, to: today.noonDate(in: calendar)) ?? Date()
        return CalendarDay(day, calendar: calendar).adding(days: days, calendar: calendar)
    }

    private func bill(_ day: CalendarDay, _ amount: Decimal? = 100, currency: String = "RON") -> BillRecord {
        BillRecord(day: day, amount: amount.map { Money($0, currency: currency) })
    }

    // MARK: Trend

    @Test func theTrendComparesWithTheBillBeforeInTheSameCurrency() throws {
        let bills = [bill(monthsAgo(2), Decimal(string: "213.20")!), bill(monthsAgo(1), Decimal(string: "245.30")!)]
        let trend = try #require(BillHistory.trend(bills, today: today, calendar: calendar))
        #expect(trend.last.amount == Money(Decimal(string: "245.30")!))
        #expect(trend.direction == .up)
        #expect(BillHistory.changeSentence(trend) == "Cu \(Money(Decimal(string: "32.10")!).formattedCompact()) mai mult decât cea dinainte.")
        #expect(trend.averageLastYear == [Money(Decimal(string: "229.25")!)])

        let lower = try #require(BillHistory.trend(bills.reversed().map { $0 } + [bill(today, 200)], today: today, calendar: calendar))
        #expect(lower.direction == .down)
        #expect(BillHistory.changeSentence(lower)?.contains("mai puțin") == true)
    }

    @Test func leiAndEuroAreNeverAddedOrCompared() throws {
        let bills = [bill(monthsAgo(2), 100), bill(monthsAgo(1), 10, currency: "EUR")]
        let trend = try #require(BillHistory.trend(bills, today: today, calendar: calendar))
        #expect(trend.change == nil, "Nothing in euro to compare with")
        #expect(BillHistory.changeSentence(trend) == nil)
        #expect(Set(trend.averageLastYear) == [Money(100), Money(10, currency: "EUR")], "One average per currency")
        #expect(BillHistory.trend([bill(today, nil)], today: today, calendar: calendar) == nil)
    }

    // MARK: The missing bill

    @Test func aMonthlyBillWellPastItsUsualDayIsMissing() throws {
        // The last bill came a month and three weeks ago: this month's is well past due.
        let late = [bill(monthsAgo(3, plusDays: -21)), bill(monthsAgo(2, plusDays: -21)), bill(monthsAgo(1, plusDays: -21))]
        let missing = try #require(BillHistory.missing(late, cycleMonths: 1, today: today, calendar: calendar))
        #expect(missing.lastDay == monthsAgo(1, plusDays: -21))

        // It came five days ago: nothing to say yet.
        #expect(BillHistory.missing([bill(today.adding(days: -5, calendar: calendar))], cycleMonths: 1, today: today, calendar: calendar) == nil)
        // A few days past a month is within the grace.
        #expect(BillHistory.missing([bill(monthsAgo(1, plusDays: -5))], cycleMonths: 1, today: today, calendar: calendar) == nil)
        // No bill yet: the binder doesn't know when one comes.
        #expect(BillHistory.missing([], cycleMonths: 1, today: today, calendar: calendar) == nil)
    }

    @Test func aProviderThatAlwaysBillsLateIsGivenItsUsualDelay() {
        // Its bills came twelve days past the month before: that is this provider's habit.
        let usual = [bill(monthsAgo(3, plusDays: -12 * 2)), bill(monthsAgo(2, plusDays: -12)), bill(monthsAgo(1, plusDays: -12))]
        let lateButUsual = BillHistory.missing(usual, cycleMonths: 1, today: today, calendar: calendar)
        #expect(lateButUsual == nil, "Twelve days late is this provider's habit")
    }

    @Test func afterTwoMissedCyclesItStopsSayingSo() {
        #expect(BillHistory.missing([bill(monthsAgo(2, plusDays: -15))], cycleMonths: 1, today: today, calendar: calendar) != nil)
        #expect(BillHistory.missing([bill(monthsAgo(3, plusDays: -1))], cycleMonths: 1, today: today, calendar: calendar) == nil,
                "Likely ended or moved to email")
        #expect(BillHistory.missing([bill(monthsAgo(3, plusDays: -20))], cycleMonths: 3, today: today, calendar: calendar) == nil, "A quarterly bill twenty days late is within its grace")
        #expect(BillHistory.missing([bill(monthsAgo(4, plusDays: -5))], cycleMonths: 3, today: today, calendar: calendar) != nil)
    }

    @Test func theNoteIsCalmAndOnlyForBilledServices() throws {
        let missingDays = [bill(monthsAgo(1, plusDays: -21))]
        let gas = BillWatchSnapshot(name: "Gaz – ENGIE Romania S.A.", provider: "ENGIE Romania S.A.", placeName: "Casa Pipera",
                                    service: ServiceKind.gas, bills: missingDays)
        let streaming = BillWatchSnapshot(name: "Netflix", provider: "Netflix", service: ServiceKind.other, bills: missingDays)
        let example = BillWatchSnapshot(name: "Gaz", provider: "ENGIE Romania S.A.", service: ServiceKind.gas, bills: missingDays, isExample: true)
        let locked = BillWatchSnapshot(name: "Telefon", provider: "Orange Romania S.A.", service: ServiceKind.mobile, bills: missingDays, isSensitive: true)
        let notes = AttentionModel.missingBills([gas, streaming, example, locked], now: today.noonDate(in: calendar), calendar: calendar)
        #expect(notes.count == 2)
        let note = try #require(notes.first { $0.assetId == gas.id })
        #expect(note.title == "Factura de la ENGIE n-a venit luna asta")
        #expect(note.detail.hasPrefix("Gaz – ENGIE Romania S.A. · Casa Pipera. Ultima a venit pe "))
        #expect(notes.first { $0.assetId == locked.id }?.title == "O factură n-a venit încă", "A locked section names nothing")

        var quarterly = gas
        quarterly.cycleMonths = 3
        quarterly.bills = [bill(monthsAgo(4, plusDays: -5))]
        #expect(AttentionModel.missingBills([quarterly], now: today.noonDate(in: calendar), calendar: calendar).first?.title
                == "Factura de la ENGIE n-a venit încă")
    }

    @Test func aMissingBillNeverNotifiesOrCountsOnTheBadge() {
        // Notes live apart from obligations: the planner and the digest never see them.
        let digest = AttentionModel.digest([], now: today.noonDate(in: calendar), calendar: calendar)
        #expect(digest.needsActionCount == 0)
        #expect(ReminderPlanner.plan([], now: today.noonDate(in: calendar), calendar: calendar).isEmpty)
    }

    @Test func providersAreNamedAsPeopleSayThem() {
        #expect(SubscriptionMatcher.shortProviderName("ENGIE Romania S.A.") == "ENGIE")
        #expect(SubscriptionMatcher.shortProviderName("E.ON Energie Romania") == "E.ON")
        #expect(SubscriptionMatcher.shortProviderName("Apa Nova București S.A.") == "Apa Nova București")
    }
}
