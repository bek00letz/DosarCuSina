import Foundation
import Testing
@testable import DosarCuSina

/// The one rule that makes a bill the same bill, whichever photo of it is filed: its number
/// when both have one, else its day and total together. Placeholder numbers only.
@Suite("What makes a bill the same bill")
struct BillIdentityTests {
    private let day = CalendarDay("2026-10-05")

    @Test func theSameNumberIsTheSameBillHoweverItIsWritten() {
        let bill = BillIdentity(number: "EXM 0000001", day: day, total: Money(245))
        #expect(bill.match(BillIdentity(number: "exm-0000001", day: CalendarDay("2026-10-06"), total: Money(254))) == .number,
                "A number read another way, a day and a total read wrong: still the same bill")
    }

    @Test func anotherNumberIsAnotherBillEvenOnTheSameDayForTheSameAmount() {
        let bill = BillIdentity(number: "EXM 0000001", day: day, total: Money(245))
        #expect(bill.match(BillIdentity(number: "EXM 0000002", day: day, total: Money(245))) == nil)
    }

    @Test func withoutANumberOnBothTheDayAndTotalDecide() {
        let bill = BillIdentity(number: "EXM 0000001", day: day, total: Money(245))
        #expect(bill.match(BillIdentity(number: nil, day: day, total: Money(Decimal(string: "245.00")!))) == .dayAndTotal)
        #expect(bill.match(BillIdentity(number: "  ", day: day, total: Money(245))) == .dayAndTotal, "A blank number is no number")
        #expect(bill.match(BillIdentity(number: nil, day: CalendarDay("2026-10-06"), total: Money(245))) == nil, "Another day")
        #expect(bill.match(BillIdentity(number: nil, day: day, total: Money(246))) == nil, "Another amount")
        #expect(bill.match(BillIdentity(number: nil, day: day, total: Money(245, currency: "EUR"))) == nil, "Another currency")
    }

    @Test func aBillWithNeitherANumberNorATotalIsNeverTakenForAnother() {
        let bare = BillIdentity(number: nil, day: day, total: nil)
        #expect(bare.match(BillIdentity(number: nil, day: day, total: nil)) == nil)
        #expect(bare.match(BillIdentity(number: nil, day: day, total: Money(245))) == nil)
    }

    @Test func theNumberWinsOverTheDayAndTotalAmongSeveral() {
        let bills = [
            BillIdentity(number: nil, day: day, total: Money(245)),
            BillIdentity(number: "EXM 0000001", day: CalendarDay("2026-09-05"), total: Money(199)),
        ]
        let found = BillIdentity(number: "EXM 0000001", day: day, total: Money(245)).filed(among: bills) { $0 }
        #expect(found?.match == .number)
        #expect(found?.bill == bills[1])
    }
}
