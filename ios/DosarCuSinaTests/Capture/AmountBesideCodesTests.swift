import Foundation
import Testing
@testable import DosarCuSina

/// The one amount rule: a digit glued to letters (a bonus-malus class, an instalment, a
/// product code) is never an amount, and a label's amount is the one it states. Every
/// value is a placeholder.
@Suite("Amounts beside codes")
struct AmountBesideCodesTests {

    @Test("Digits glued to letters are never amounts", arguments: ["clasa bonus-malus: b6", "valoare rate r1:", "ulei 5w30", "categoria m2"])
    func gluedDigits(line: String) {
        #expect(RomanianFieldExtractor.amounts(inLine: line).isEmpty, "\(line)")
    }

    @Test("A currency may touch an amount")
    func currencyTouches() {
        #expect(RomanianFieldExtractor.amounts(inLine: "total 350lei").map(\.amount) == [350])
        #expect(RomanianFieldExtractor.amounts(inLine: "prima de asigurare 1234.56 lei, clasa bonus-malus: b6").map(\.amount) == [Decimal(string: "1234.56")!])
    }

    @Test("A label's amount is the one before its currency; another label's on the next line never is")
    func statedAmount() {
        let premium = RomanianFieldExtractor.total(in: CaptureText("Prima de asigurare 1234.56 LEI, Clasă Bonus-Malus: B6"))
        #expect(premium?.money.amount == Decimal(string: "1234.56"))
        let stated = RomanianFieldExtractor.total(in: CaptureText("Total de plată: 1.190,00 lei (din care TVA 190,00 lei)"))
        #expect(stated?.money.amount == 1190)
        let underneath = RomanianFieldExtractor.total(in: CaptureText("Total de plată\n348,50 lei"))
        #expect(underneath?.money.amount == Decimal(string: "348.5"))
        let elsewhere = RomanianFieldExtractor.total(in: CaptureText("""
        Prima de asigurare
        Nr. rate 1 Valoare rate R1: 1234.56 Lei
        Limita de despăgubire: 6.070.000 Lei
        """))
        #expect(elsewhere?.money == nil)
    }

    @Test("The owner's policy: the premium, never the bonus-malus class, an instalment or a limit")
    func ownersPremium() {
        let analysis = CaptureAnalyzer().analyze(text: RCAPages.contract, referenceDate: Date(timeIntervalSince1970: 1_793_577_600), as: .rcaPolicy)
        #expect(analysis.fields.first { $0.key == .total }?.value.money == Money(Decimal(string: "1234.56")!, currency: "RON"))
        #expect(analysis.fields.first { $0.key == .bonusMalusClass }?.value.text == "B6")
    }
}
