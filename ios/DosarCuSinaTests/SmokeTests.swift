import Testing
@testable import DosarCuSina

@Suite("Test target")
struct SmokeTests {
    @Test("The host app module links into the test bundle")
    func hostAppLinks() {
        #expect(CadenceCalculator.isLeapYear(2028))
    }
}
