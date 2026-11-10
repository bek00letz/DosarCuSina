import Foundation
import Testing
@testable import DosarCuSina

/// The one rule that makes a paper the same paper, whichever photo of it is filed (a bill in
/// its subscription, a visit's invoice on its section): its number when both have one, certain
/// only from the same issuer, else its day and total together, and its firm when both name
/// one. Placeholder numbers only.
@Suite("What makes a paper the same paper")
struct PaperIdentityTests {
    private let day = CalendarDay("2026-10-05")

    @Test func theSameNumberIsTheSameBillHoweverItIsWritten() {
        let bill = PaperIdentity.bill(number: "EXM 0000001", day: day, total: Money(245))
        #expect(bill.match(.bill(number: "exm-0000001", day: CalendarDay("2026-10-06"), total: Money(254))) == .number,
                "A number read another way, a day and a total read wrong: still the same bill, its subscription is one provider's")
    }

    @Test func anotherNumberIsAnotherPaperEvenOnTheSameDayForTheSameAmount() {
        let bill = PaperIdentity.bill(number: "EXM 0000001", day: day, total: Money(245))
        #expect(bill.match(.bill(number: "EXM 0000002", day: day, total: Money(245))) == nil)
        let invoice = PaperIdentity(number: "SRV 0000001", day: day, total: Money(480), issuer: "Service Exemplu SRL")
        #expect(invoice.match(PaperIdentity(number: "SRV 0000002", day: day, total: Money(480), issuer: "Service Exemplu SRL")) == nil)
    }

    @Test func withoutANumberOnBothTheDayAndTotalDecide() {
        let bill = PaperIdentity.bill(number: "EXM 0000001", day: day, total: Money(245))
        #expect(bill.match(.bill(number: nil, day: day, total: Money(Decimal(string: "245.00")!))) == .dayAndTotal)
        #expect(bill.match(.bill(number: "  ", day: day, total: Money(245))) == .dayAndTotal, "A blank number is no number")
        #expect(bill.match(.bill(number: nil, day: CalendarDay("2026-10-06"), total: Money(245))) == nil, "Another day")
        #expect(bill.match(.bill(number: nil, day: day, total: Money(246))) == nil, "Another amount")
        #expect(bill.match(.bill(number: nil, day: day, total: Money(245, currency: "EUR"))) == nil, "Another currency")
    }

    @Test func aPaperWithNeitherANumberNorATotalIsNeverTakenForAnother() {
        let bare = PaperIdentity(number: nil, day: day, total: nil)
        #expect(bare.match(PaperIdentity(number: nil, day: day, total: nil)) == nil)
        #expect(bare.match(PaperIdentity(number: nil, day: day, total: Money(245))) == nil)
    }

    @Test func theMostCertainMatchWinsAmongSeveral() {
        let invoices = [
            PaperIdentity(number: nil, day: day, total: Money(245), issuer: "Service Exemplu SRL"),
            PaperIdentity(number: "SRV 0000001", day: CalendarDay("2026-09-05"), total: Money(199)),
            PaperIdentity(number: "SRV 0000001", day: day, total: Money(199), issuer: "Service Exemplu SRL"),
        ]
        let found = PaperIdentity(number: "SRV 0000001", day: day, total: Money(245), issuer: "Service Exemplu SRL").filed(among: invoices) { $0 }
        #expect(found?.match == .number)
        #expect(found?.paper == invoices[2], "The same number from the same firm on the same day, before the number alone")
        let alone = PaperIdentity(number: "SRV 0000001", day: day, total: Money(245)).filed(among: Array(invoices.prefix(2))) { $0 }
        #expect(alone?.match == .numberOnly, "The number alone, before the day and total")
        #expect(alone?.paper == invoices[1])
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
    }

    // MARK: Firms number their own invoices

    @Test func theSameNumberFromAnotherFirmIsAnotherInvoice() {
        let invoice = PaperIdentity(number: "EXM 0000001", day: day, total: Money(480), issuer: "Service Exemplu SRL")
        #expect(invoice.match(PaperIdentity(number: "EXM-0000001", day: day, total: Money(480), issuer: "Altă firmă SRL")) == nil,
                "Each firm numbers its own invoices: never the same paper across two firms")
    }

    @Test func theSameNumberFromTheSameFirmOnTheSameDayIsCertain() {
        let invoice = PaperIdentity(number: "SRV 0000001", day: day, total: Money(480), issuer: "Service Exemplu SRL")
        #expect(invoice.match(PaperIdentity(number: "srv-0000001", day: day, total: Money(520), issuer: "SERVICE EXEMPLU S.R.L.")) == .number,
                "A total read wrong on one photo: still the same invoice")
    }

    @Test func theSameNumberFromTheSameFirmAYearLaterMayBeAnother() {
        let invoice = PaperIdentity(number: "SRV 0000001", day: day, total: Money(480), issuer: "Service Exemplu SRL")
        #expect(invoice.match(PaperIdentity(number: "SRV 0000001", day: CalendarDay("2027-10-04"), total: Money(310), issuer: "Service Exemplu SRL")) == .numberOnly,
                "Numbering that starts again each year, or a day read wrong: the person says which")
    }

    @Test func theSameNumberWithAFirmOnOneOfThemOnlyMayBeAnother() {
        let invoice = PaperIdentity(number: "SRV 0000001", day: day, total: Money(480), issuer: "Service Exemplu SRL")
        #expect(invoice.match(PaperIdentity(number: "SRV 0000001", day: day, total: Money(480))) == .numberOnly)
        #expect(PaperIdentity(number: "SRV 0000001", day: day, total: Money(480)).match(PaperIdentity(number: "SRV 0000001", day: day, total: Money(480))) == .numberOnly,
                "No firm on either: the number alone")
    }

    @Test func onlyACertainMatchOffersNoChoice() {
        let section = UUID()
        func filed(_ match: FiledPaper.Match) -> FiledPaper {
            FiledPaper(entryID: UUID(), match: match, sectionID: section, section: "VW Golf 2018", day: day)
        }
        #expect(!filed(.sameDocument).mayBeAnother)
        #expect(!filed(.number).mayBeAnother)
        #expect(filed(.numberOnly).mayBeAnother, "„E altă factură”")
        #expect(filed(.dayAndTotal).mayBeAnother, "„E altă factură”")
    }
}
