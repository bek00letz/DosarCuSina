import Foundation
import Testing
@testable import DosarCuSina

/// One wording for a paper already in the binder, in the review, the visit form and
/// "Am rezolvat" (`FiledPaperWording`, drawn by `DSFiledPaperNotice`). Placeholder data only.
@Suite("What the app says about a paper already filed")
struct FiledPaperWordingTests {
    private let today = CalendarDay("2026-11-10")

    private func filed(_ match: FiledPaper.Match, in section: String) -> FiledPaper {
        FiledPaper(entryID: UUID(), match: match, sectionID: UUID(), section: section, day: CalendarDay("2026-10-05"))
    }

    @Test func theNoticeAndItsActions() {
        #expect(FiledPaperWording.title == "Factura e deja în dosar")
        #expect(FiledPaperWording.open == "Vezi factura")
        #expect(FiledPaperWording.another == "E altă factură")
    }

    @Test func aBill() {
        let gas = "Gaz – ENGIE Romania S.A."
        #expect(FiledPaperWording.message(filed(.sameDocument, in: gas), paper: .bill, today: today)
            == "E în „\(gas)”, cea din 5 octombrie. Dacă salvezi, o actualizez cu ce am citit acum.")
        #expect(FiledPaperWording.message(filed(.number, in: gas), paper: .bill, today: today)
            == "E în „\(gas)”, cea din 5 octombrie, cu același număr. Dacă salvezi, o actualizez cu ce am citit acum, iar poza asta devine copia ei nouă.")
        #expect(FiledPaperWording.message(filed(.dayAndTotal, in: gas), paper: .bill, today: today)
            == "În „\(gas)” e una cu aceeași dată și același total, cea din 5 octombrie. Dacă e aceeași, o actualizez, iar poza asta devine copia ei nouă.")
    }

    @Test func aVisitsInvoice() {
        let car = "VW Golf 2018"
        #expect(FiledPaperWording.message(filed(.sameDocument, in: car), paper: .invoice, today: today)
            == "E în istoricul „\(car)”, din 5 octombrie. Dacă salvezi, actualizez ce s-a trecut atunci cu ce e aici.")
        #expect(FiledPaperWording.message(filed(.numberOnly, in: car), paper: .invoice, today: today)
            == "În istoricul „\(car)” e una cu același număr, din 5 octombrie. Dacă e aceeași factură, o actualizez, iar poza asta devine copia ei nouă.",
                "The number alone says it may be the same, never that it is")
        #expect(FiledPaperWording.message(filed(.dayAndTotal, in: car), paper: .invoice, today: today)
            == "În istoricul „\(car)” e una cu aceeași dată și același total, din 5 octombrie. Dacă e aceeași factură, o actualizez, iar poza asta devine copia ei nouă.")
    }

    @Test(arguments: [FiledPaper.Match.sameDocument, .number, .numberOnly, .dayAndTotal])
    func everyMatchSaysWhereItIs(match: FiledPaper.Match) {
        for paper in [FiledPaperWording.Paper.bill, .invoice] {
            let message = FiledPaperWording.message(filed(match, in: "VW Golf 2018"), paper: paper, today: today)
            #expect(message.contains("„VW Golf 2018”") && message.contains("5 octombrie"), "\(match), \(paper)")
        }
    }
}
