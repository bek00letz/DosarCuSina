import Foundation
import Testing
@testable import DosarCuSina

@Suite("Box status line")
struct BoxStatusTests {
    let calendar = Calendar.bucharest
    let today = noon("2026-11-02")

    @Test func allGoodWhenNothingIsInItsWindow() {
        let status = BoxStatus.make([snapshot("ITP", kind: .legal, due: "2027-05-01", offsets: [30, 7], consequence: .legal)], now: today, calendar: calendar)
        #expect(status.state == .allGood)
        #expect(status.line(isSensitive: false) == "Totul e în regulă")
    }

    @Test func showsTheSingleMostPressingItemLikeUrmeaza() {
        let car = UUID()
        let obligations = [
            snapshot("Revizie", kind: .maintenance, due: "2026-11-05", asset: (car, "VW Golf"), offsets: [14], consequence: .comfort),
            snapshot("ITP", kind: .legal, due: "2026-11-11", asset: (car, "VW Golf"), offsets: [30, 7], consequence: .legal),
            snapshot("RCA", kind: .insurance, due: "2026-12-30", asset: (car, "VW Golf"), offsets: [30, 7], consequence: .legal),
        ]
        let status = BoxStatus.make(forAsset: car, in: obligations, now: today, calendar: calendar)
        #expect(status.entry?.obligation.title == AttentionModel.digest(obligations, now: today, calendar: calendar).now.first?.obligation.title)
        #expect(status.line(isSensitive: false) == "ITP · în 9 zile")
    }

    @Test("Romanian day counts", arguments: [
        (1, "1 zi"), (2, "2 zile"), (19, "19 zile"), (20, "20 de zile"), (21, "21 de zile"),
        (101, "101 zile"), (119, "119 zile"), (120, "120 de zile"), (0, "0 zile"),
    ])
    func dayCounts(count: Int, text: String) {
        #expect(DayCount.phrase(count) == text)
    }

    @Test("Distances step up from days to weeks, months and years, never rounding up", arguments: [
        (5, "5 zile"), (20, "20 de zile"), (21, "3 săptămâni"), (27, "3 săptămâni"),
        (87, "2 luni și 3 săptămâni"), (92, "3 luni"), (400, "1 an și 1 lună"),
        (3_077, "8 ani"), (14_000, "38 de ani"), (-14_000, "38 de ani"),
    ])
    func durations(days: Int, text: String) {
        #expect(DurationWording.phrase(days: days, from: today, calendar: calendar) == text)
    }

    @Test func overdueTodayTomorrowAndGraceReadDifferently() {
        func line(_ due: String, consequence: Consequence = .legal, grace: Int = 0) -> String {
            BoxStatus.make([snapshot("RCA", kind: .insurance, due: due, offsets: [7, 0], consequence: consequence, grace: grace)], now: today, calendar: calendar)
                .line(isSensitive: false)
        }
        #expect(line("2026-10-31") == "RCA · depășit de 2 zile")
        #expect(line("2026-11-02") == "RCA · azi")
        #expect(line("2026-11-03") == "RCA · mâine")
        #expect(line("2026-10-31", consequence: .health, grace: 7) == "RCA · întârziat 2 zile")
        let late = BoxStatus.make([snapshot("RCA", kind: .insurance, due: "2026-10-31", offsets: [7], consequence: .legal)], now: today, calendar: calendar)
        #expect(late.isAlarming)
    }

    @Test func lockedSectionsNeverShowWhatIsInside() {
        let status = BoxStatus.make([snapshot("Colonoscopie", kind: .health, due: "2026-11-05", offsets: [7], consequence: .health)], now: today, calendar: calendar)
        let line = status.line(isSensitive: true)
        #expect(!line.contains("Colonoscopie"))
        #expect(line == "O scadență · în 3 zile")
    }

    @Test func childrenCountTowardsTheParentBox() {
        let home = UUID(), tenancy = UUID()
        let obligations = [snapshot("Se termină contractul", kind: .renewal, due: "2026-11-20", asset: (tenancy, "Chiriaș"), offsets: [60], consequence: .financial)]
        #expect(BoxStatus.make(forAsset: home, in: obligations, now: today, calendar: calendar).state == .allGood)
        #expect(BoxStatus.make(forAsset: home, descendants: [tenancy], in: obligations, now: today, calendar: calendar).entry != nil)
    }
}
