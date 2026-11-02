import Foundation
import Testing
@testable import DosarCuSina

/// Typed numbers: what a field shows reads back as the same number, in every locale.
@Suite("Number input")
struct NumberInputTests {

    @Test("A shown number reads back unchanged", arguments: ["ro_RO", "ro", "en_RO", "en_US", "ro_US", "de_DE", "fr_FR"])
    func shownNumbersReadBackUnchanged(localeID: String) {
        let locale = Locale(identifier: localeID)
        for value: Decimal in [45724, 142_500, 7, 1250.5, 0.5] {
            let shown = DSNumberInput.display(value, locale: locale, fractionDigits: 0...1)
            #expect(DSNumberInput.decimal(from: shown, locale: locale) == value, "\(localeID): \(shown)")
        }
    }

    @Test func romanianTypingReadsAsExpected() {
        let ro = Locale(identifier: "ro_RO")
        #expect(DSNumberInput.decimal(from: "45.724", locale: ro) == 45724)
        #expect(DSNumberInput.decimal(from: "45724", locale: ro) == 45724)
        #expect(DSNumberInput.decimal(from: "1.250,50", locale: ro) == Decimal(string: "1250.50"))
        #expect(DSNumberInput.decimal(from: "12 km", locale: ro) == nil)
    }
}
