import Foundation
import Testing
@testable import DosarCuSina

/// Text written for machines (ISO days, digests) comes from one helper, the same on every
/// phone whatever its region or digits.
@Suite("Machine text")
struct MachineTextTests {
    @Test func daysAreZeroPaddedISO() {
        #expect(MachineText.isoDay(year: 2031, month: 3, day: 2) == "2031-03-02")
        #expect(MachineText.isoDay(year: 987, month: 12, day: 31) == "0987-12-31")
        #expect(MachineText.isoMonthDay(month: 4, day: 15) == "04-15")
        #expect(MachineText.padded(12_345, to: 4) == "12345", "A longer number is kept whole")
    }

    @Test("Every day type writes its ISO text the same way")
    func dayTypesAgree() {
        #expect(CalendarDay(year: 2031, month: 3, day: 2).isoString == "2031-03-02")
        #expect(MonthDay(month: 11, day: 1).isoString == "11-01")
        #expect(CaptureDay(year: 2031, month: 3, day: 2)?.description == "2031-03-02")
    }

    @Test("Digests are lowercase hex, two digits a byte")
    func hexDigest() {
        #expect(MachineText.hex([0x00, 0x0F, 0xA0, 0xFF]) == "000fa0ff")
        #expect(MachineText.hex([UInt8]()) == "")
        #expect(Hashing.sha256(Data("abc".utf8)) == "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
    }
}
