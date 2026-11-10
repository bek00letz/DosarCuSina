import Foundation
import Testing
@testable import DosarCuSina

/// The one rule that makes a paper the same paper, whichever photo of it is filed (a bill in
/// its subscription, a visit's invoice on its section): its number when both have one, else
/// its day and total together, and its firm when both name one. Placeholder numbers only.
@Suite("What makes a paper the same paper")
struct PaperIdentityTests {
    private let day = CalendarDay("2026-10-05")

    @Test func theSameNumberIsTheSamePaperHoweverItIsWritten() {
        let bill = PaperIdentity(number: "EXM 0000001", day: day, total: Money(245))
        #expect(bill.match(PaperIdentity(number: "exm-0000001", day: CalendarDay("2026-10-06"), total: Money(254))) == .number,
                "A number read another way, a day and a total read wrong: still the same bill")
    }

    @Test func anotherNumberIsAnotherPaperEvenOnTheSameDayForTheSameAmount() {
        let bill = PaperIdentity(number: "EXM 0000001", day: day, total: Money(245))
        #expect(bill.match(PaperIdentity(number: "EXM 0000002", day: day, total: Money(245))) == nil)
    }

    @Test func withoutANumberOnBothTheDayAndTotalDecide() {
        let bill = PaperIdentity(number: "EXM 0000001", day: day, total: Money(245))
        #expect(bill.match(PaperIdentity(number: nil, day: day, total: Money(Decimal(string: "245.00")!))) == .dayAndTotal)
        #expect(bill.match(PaperIdentity(number: "  ", day: day, total: Money(245))) == .dayAndTotal, "A blank number is no number")
        #expect(bill.match(PaperIdentity(number: nil, day: CalendarDay("2026-10-06"), total: Money(245))) == nil, "Another day")
        #expect(bill.match(PaperIdentity(number: nil, day: day, total: Money(246))) == nil, "Another amount")
        #expect(bill.match(PaperIdentity(number: nil, day: day, total: Money(245, currency: "EUR"))) == nil, "Another currency")
    }

    @Test func aPaperWithNeitherANumberNorATotalIsNeverTakenForAnother() {
        let bare = PaperIdentity(number: nil, day: day, total: nil)
        #expect(bare.match(PaperIdentity(number: nil, day: day, total: nil)) == nil)
        #expect(bare.match(PaperIdentity(number: nil, day: day, total: Money(245))) == nil)
    }

    @Test func theNumberWinsOverTheDayAndTotalAmongSeveral() {
        let bills = [
            PaperIdentity(number: nil, day: day, total: Money(245)),
            PaperIdentity(number: "EXM 0000001", day: CalendarDay("2026-09-05"), total: Money(199)),
        ]
        let found = PaperIdentity(number: "EXM 0000001", day: day, total: Money(245)).filed(among: bills) { $0 }
        #expect(found?.match == .number)
        #expect(found?.paper == bills[1])
    }

    @Test func byDayAndTotalTheFirmMustAgreeWhenBothNameOne() {
        let invoice = PaperIdentity(number: nil, day: day, total: Money(480), issuer: "Service Exemplu SRL")
        #expect(invoice.match(PaperIdentity(number: nil, day: day, total: Money(480), issuer: "SERVICE EXEMPLU S.R.L.")) == .dayAndTotal,
                "The same firm, written another way")
        #expect(invoice.match(PaperIdentity(number: nil, day: day, total: Money(480), issuer: "Vulcanizare Exemplu SRL")) == nil,
                "Another firm on the same day for the same amount is another invoice")
        #expect(invoice.match(PaperIdentity(number: nil, day: day, total: Money(480))) == .dayAndTotal, "A firm on one of them only")
        #expect(invoice.match(PaperIdentity(number: "EXM 0000001", day: day, total: Money(480), issuer: "Service Exemplu SRL")) == .dayAndTotal,
                "A number on one of them only: the day, the total and the firm decide")
        #expect(PaperIdentity(number: "EXM 0000001", day: day, total: Money(480), issuer: "Service Exemplu SRL")
            .match(PaperIdentity(number: "EXM-0000001", day: day, total: Money(480), issuer: "Altă firmă SRL")) == .number,
                "Two numbers decide on their own")
    }
}
