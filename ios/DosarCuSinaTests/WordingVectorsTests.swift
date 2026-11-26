import Foundation
import Testing
@testable import DosarCuSina

/// The app's words for durations, money, units and dates, run over cases chosen to bite and
/// written to `shared/test-vectors/wording/`, one file per rule: each input with the finished
/// Romanian this app writes. The rules are `DayCount`, `CalendarCount`, `DurationWording`
/// (`distance`, `lead`, `inside`) and `WhenWording` (ios/Shared/DurationWording.swift),
/// `Money`'s `formatted`, `formattedCompact` and `currencyName`, `MeasurementUnit.written`,
/// `DosarFormat` (ios/Shared/DosarFormat.swift) and `DueWording`'s words. The Android app's
/// `core.wording` writes the same words from the same String Catalogs (scripts/android-words.py)
/// and its tests compare them word for word (docs/ANDROID_PLAN.md, "How parity is kept"). A
/// sibling of `AttentionVectorsTests`, with a folder of its own.
///
/// No answer depends on the machine: days are counted in Bucharest's calendar whatever the
/// simulator's zone (`Calendar.bucharest`), every "today" is a case's own, moments are fixed
/// seconds written in the time zones the cases name, and the words are the app's locale's.
/// Placeholder data only.
@Suite("Wording vectors")
struct WordingVectorsTests {
    static var folder: URL {
        URL(filePath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appending(path: "shared/test-vectors/wording")
    }

    /// How to bring the files up to date, said when one isn't.
    static let regenerate = """
    is out of date with the wording rules. Bring shared/test-vectors/wording up to date: \
    TEST_RUNNER_WORDING_VECTORS_WRITE=1 ./tests/run_tests.sh (or run WordingVectorsTests in Xcode with \
    WORDING_VECTORS_WRITE=1 in the scheme's environment), review the diff and commit it, then run the \
    Android tests (./gradlew :core:test in android/), which read the same files.
    """

    typealias Vectors = ValueVectorsTests.Vectors

    /// The one calendar every case counts days in.
    static let calendar = Calendar.bucharest

    @MainActor
    @Test("shared/test-vectors/wording is up to date with the wording rules")
    func vectorsAreUpToDate() throws {
        let files = Self.all()
        let environment = ProcessInfo.processInfo.environment
        let writes = environment["WORDING_VECTORS_WRITE"] == "1"
        // A run that keeps its results (GitHub's, through tests/run_tests.sh) leaves a file that
        // is out of date made afresh there, so the run's test-results holds what to commit.
        let out = environment["VECTORS_OUT"].map { URL(filePath: $0).appending(path: "wording") }
        let manager = FileManager.default
        if writes { try manager.createDirectory(at: Self.folder, withIntermediateDirectories: true) }
        for file in files {
            let url = Self.folder.appending(path: "\(file.name).json")
            let fresh = try ValueVectorsTests.render(file)
                .replacingOccurrences(of: "ios/DosarCuSinaTests/ValueVectorsTests.swift", with: "ios/DosarCuSinaTests/WordingVectorsTests.swift")
            if writes {
                try fresh.write(to: url, atomically: true, encoding: .utf8)
                continue
            }
            let committed = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
            #expect(committed == fresh, Comment(rawValue: "\(file.name).json " + Self.regenerate))
            if committed != fresh, let out {
                try manager.createDirectory(at: out, withIntermediateDirectories: true)
                try fresh.write(to: out.appending(path: "\(file.name).json"), atomically: true, encoding: .utf8)
            }
        }
        // A file no rule writes any more goes, so Android never tests against an old answer.
        let names = Set(files.map { "\($0.name).json" })
        let present = (try? manager.contentsOfDirectory(atPath: Self.folder.path(percentEncoded: false))) ?? []
        for stale in present where stale.hasSuffix(".json") && !names.contains(stale) {
            if writes {
                try manager.removeItem(at: Self.folder.appending(path: stale))
            } else {
                Issue.record(Comment(rawValue: "\(stale) is written by no rule any more " + Self.regenerate))
            }
        }
    }

    static func all() -> [Vectors] {
        [counts(), distances(), leads(), whens(), money(), currencyNames(), units(), days(), moments(), times(), dueLines()]
    }

    // MARK: Helpers

    static func day(_ iso: String) -> CalendarDay { CalendarDay(iso) }
    static func noonOf(_ iso: String) -> Date { day(iso).noonDate(in: calendar) }

    // MARK: Counts

    /// Every count Romanian says apart: one, few (0, 2 to 19, and 101 to 119 and on), other (20
    /// and on, with „de”), and the large ones written with the app's grouping.
    static let countsToSay = [0, 1, 2, 3, 19, 20, 21, 99, 100, 101, 102, 110, 119, 120, 121, 1000, 1001, 1250, 1_000_000, -1, -20]

    static func counts() -> Vectors {
        let units: [(String, (Int) -> String)] = [
            ("days", DayCount.phrase), ("weeks", CalendarCount.weeks), ("months", CalendarCount.months), ("years", CalendarCount.years),
        ]
        var cases: [JSONValue] = []
        for (unit, say) in units {
            for count in countsToSay {
                cases.append(.object(["unit": .string(unit), "count": .int(count), "text": .string(say(count))]))
            }
        }
        return Vectors(
            name: "counts",
            rule: "DayCount.phrase and CalendarCount.weeks, months and years",
            source: "ios/Shared/DurationWording.swift",
            shape: "unit: days, weeks, months or years; count: the number (its sign ignored); text: the words.",
            cases: cases
        )
    }

    // MARK: Durations

    static func distances() -> Vectors {
        let todays = ["2026-11-26", "2026-01-31", "2025-01-31", "2024-02-29", "2026-12-31", "2026-03-29"]
        let spans = [
            0, 1, 2, 7, 20, 21, 22, 27, 28, 29, 30, 31, 35, 41, 42, 59, 60, 61, 62, 89, 90, 91, 120, 180, 334,
            364, 365, 366, 371, 400, 500, 729, 730, 731, 760, 1000, 1094, 1095, 1096, 1460, 3650, -1, -21, -45, -400,
        ]
        var cases: [JSONValue] = []
        for today in todays {
            for days in spans {
                let distance = DurationWording.distance(days: days, from: noonOf(today), calendar: calendar)
                cases.append(.object([
                    "today": .string(today), "days": .int(days), "distance": .string(distance),
                    "inside": .string(DurationWording.inside(distance)),
                    "insideStartingSentence": .string(DurationWording.inside(distance, startsSentence: true)),
                ]))
            }
        }
        return Vectors(
            name: "distance",
            rule: "DurationWording.distance(days:from:calendar:) and inside(_:startsSentence:)",
            source: "ios/Shared/DurationWording.swift",
            shape: "today: the day counted from; days: how far (its sign ignored); distance: the words; inside: after „în” („într-o lună”); insideStartingSentence: the same starting a sentence.",
            cases: cases
        )
    }

    static func leads() -> Vectors {
        let leads = [0, 1, 7, 14, 29, 30, 31, 60, 90, 180, 365, 366, 395, 730, 1095, 36_500, 40_000, -30]
        return Vectors(
            name: "lead",
            rule: "DurationWording.lead(days:)",
            source: "ios/Shared/DurationWording.swift",
            shape: "days: a reminder's lead; text: the words (whole months and years as calendar months).",
            cases: leads.map { .object(["days": .int($0), "text": .string(DurationWording.lead(days: $0))]) }
        )
    }

    static func whens() -> Vectors {
        let today = "2026-11-26"
        let pairs: [(AttentionUrgency, [Int])] = [
            (.overdue, [-1, -2, -21, -30, -400]), (.withinGrace, [-1, -3]), (.today, [0]), (.soon, [1, 2, 7]),
            (.upcoming, [1, 14, 25]), (.later, [1, 31, 60, 400]),
        ]
        var cases: [JSONValue] = []
        for (urgency, days) in pairs {
            for remaining in days {
                cases.append(.object([
                    "urgency": .string(urgency.rawValue), "today": .string(today), "daysRemaining": .int(remaining),
                    "phrase": .string(WhenWording.phrase(urgency, daysRemaining: remaining, from: noonOf(today), calendar: calendar)),
                    "standalone": .string(WhenWording.standalone(urgency, daysRemaining: remaining, from: noonOf(today), calendar: calendar)),
                ]))
            }
        }
        return Vectors(
            name: "when",
            rule: "WhenWording.phrase and standalone",
            source: "ios/Shared/DurationWording.swift",
            shape: "urgency: as stored; today; daysRemaining; phrase: the words in a sentence; standalone: starting a line.",
            cases: cases
        )
    }

    // MARK: Money and units

    static func money() -> Vectors {
        let amounts = [
            "0", "1", "2", "19", "20", "21", "100", "101", "102", "119", "120", "1250", "1000000", "1.5", "1250.5",
            "1250.55", "0.125", "0.135", "2.675", "-1", "-12.5", "-20", "0.001", "-0.001",
        ]
        var cases: [JSONValue] = []
        for currency in ["RON", "EUR", "USD", "GBP", "CHF", "MDL", "JPY"] {
            for amount in amounts {
                guard let money = Money(amountString: amount, currency: currency) else {
                    Issue.record("Not an amount: \(amount)")
                    continue
                }
                cases.append(.object([
                    "amount": .string(amount), "currency": .string(currency),
                    "formatted": .string(money.formatted()), "formattedCompact": .string(money.formattedCompact()),
                ]))
            }
        }
        return Vectors(
            name: "money",
            rule: "Money.formatted() and formattedCompact()",
            source: "ios/DosarCuSina/Models/Values/Money.swift",
            shape: "amount: in machine form; currency: its code; formatted: with two decimals; formattedCompact: without them when the amount is whole.",
            cases: cases
        )
    }

    static func currencyNames() -> Vectors {
        Vectors(
            name: "currency-name",
            rule: "Money.currencyName(_:)",
            source: "ios/DosarCuSina/Models/Values/Money.swift",
            shape: "code: as given; name: what a currency menu shows.",
            cases: ["RON", "ron", "EUR", "usd", "XYZ"].map { .object(["code": .string($0), "name": .string(Money.currencyName($0))]) }
        )
    }

    static func units() -> Vectors {
        let values = ["0", "1", "2", "19", "20", "21", "101", "119", "120", "1250", "45724", "12.5", "1.5", "0.35", "0.45", "2.25", "1.05", "-3", "-20"]
        let units: [String?] = ["km", "kwh", "m3", "gcal", "mgdl", "months", "shots", "ore motor", nil]
        let ranges: [ClosedRange<Int>] = [0...1, 0...2, 2...2]
        var cases: [JSONValue] = []
        for unitText in units {
            let unit = unitText.flatMap { MeasurementUnit($0) }
            for text in values {
                guard let value = Double(text) else { continue }
                for range in ranges {
                    cases.append(.object([
                        "value": .string(text), "unit": unitText.map(JSONValue.string) ?? .null,
                        "fractionDigits": .array([.int(range.lowerBound), .int(range.upperBound)]),
                        "text": .string(MeasurementUnit.written(value, in: unit, fractionDigits: range)),
                    ]))
                }
            }
        }
        return Vectors(
            name: "units",
            rule: "MeasurementUnit.written(_:in:fractionDigits:)",
            source: "ios/DosarCuSina/Models/Values/MeasurementUnit.swift",
            shape: "value: the number in machine form, read as a Double; unit: as stored or typed, null for none; fractionDigits: [least, most]; text: the number with its unit.",
            cases: cases
        )
    }

    // MARK: Dates

    static func days() -> Vectors {
        let months = ["2025-01-14", "2025-02-14", "2025-03-14", "2025-04-14", "2025-05-14", "2025-06-14", "2025-07-14", "2025-08-14", "2025-09-14", "2025-10-14", "2025-11-14", "2025-12-14"]
        let others = ["2026-01-05", "2024-02-29", "2026-02-30", "1999-12-31", "2100-07-01", "2026-11-01"]
        let cases: [JSONValue] = (months + others).map { iso in
            let written = Self.day(iso)
            return .object([
                "day": .string(iso), "isOnCalendar": .bool(written.isOnCalendar),
                "dayText": .string(DosarFormat.day(written)), "longDay": .string(DosarFormat.longDay(written)),
                "dayMonth": .string(DosarFormat.dayMonth(written)), "monthYear": .string(DosarFormat.monthYear(written)),
                "cardExpiry": .string(DosarFormat.cardExpiry(written)),
            ])
        }
        return Vectors(
            name: "days",
            rule: "DosarFormat.day, longDay, dayMonth, monthYear and cardExpiry, for a CalendarDay",
            source: "ios/Shared/DosarFormat.swift",
            shape: "day: as stored (one the calendar doesn't have is written with its own numbers); dayText, longDay, dayMonth, monthYear, cardExpiry: the words.",
            cases: cases
        )
    }

    static func moments() -> Vectors {
        let seconds = [1_741_953_900, 1_798_756_200, 1_774_744_200, 1_792_888_200, 1_767_596_400, 1_783_209_599]
        let zones = ["Europe/Bucharest", "America/New_York", "Asia/Tokyo", "UTC", "Pacific/Kiritimati", "America/Los_Angeles"]
        var cases: [JSONValue] = []
        for second in seconds {
            let moment = Date(timeIntervalSince1970: TimeInterval(second))
            for zone in zones {
                let calendar = Calendar.dosar(in: TimeZone(identifier: zone) ?? .gmt)
                cases.append(.object([
                    "seconds": .int(second), "zone": .string(zone),
                    "dayText": .string(DosarFormat.day(moment, calendar: calendar)),
                    "longDay": .string(DosarFormat.longDay(moment, calendar: calendar)),
                    "dayMonth": .string(DosarFormat.dayMonth(moment, calendar: calendar)),
                    "monthYear": .string(DosarFormat.monthYear(moment, calendar: calendar)),
                    "numericDay": .string(DosarFormat.numericDay(moment, calendar: calendar)),
                    "time": .string(DosarFormat.time(moment, calendar: calendar)),
                ]))
            }
        }
        return Vectors(
            name: "moments",
            rule: "DosarFormat.day, longDay, dayMonth, monthYear, numericDay and time, for a moment",
            source: "ios/Shared/DosarFormat.swift",
            shape: "seconds: the moment, after 1970 in UTC; zone: the time zone it is written in; the rest: the words.",
            cases: cases
        )
    }

    static func times() -> Vectors {
        let minutes = [0, 5, 59, 60, 540, 750, 1439, 1440, -1, 2000]
        return Vectors(
            name: "times",
            rule: "DosarFormat.time(minuteOfDay:calendar:)",
            source: "ios/Shared/DosarFormat.swift",
            shape: "minuteOfDay: minutes after midnight (held to the day); text: the time.",
            cases: minutes.map { .object(["minuteOfDay": .int($0), "text": .string(DosarFormat.time(minuteOfDay: $0, calendar: calendar))]) }
        )
    }

    // MARK: Due lines

    static func dueLines() -> Vectors {
        let today = "2026-11-26"
        let dues = ["2026-12-17", "2027-01-26", "2027-02-14", "2028-03-01", "2026-10-26", "2026-09-01", "2025-11-26"]
        var cases: [JSONValue] = []
        for kind in ObligationKind.allCases {
            for due in dues {
                cases.append(.object([
                    "kind": .string(kind.rawValue), "today": .string(today), "due": .string(due),
                    "text": .string(DueWording.line(kind: kind, due: day(due), today: day(today), calendar: calendar)),
                ]))
            }
        }
        for consequence in Consequence.allCases {
            cases.append(.object(["consequence": .string(consequence.rawValue), "text": .string(DueWording.consequence(consequence))]))
        }
        return Vectors(
            name: "due-lines",
            rule: "DueWording.line(kind:due:today:calendar:) for distances of weeks, months and years, and DueWording.consequence",
            source: "ios/DosarCuSina/Services/Attention/DueWording.swift",
            shape: "kind, today and due: text is the due line; or consequence: text is why it matters. The shorter lines and a passport's are in shared/test-vectors/attention/due-line.json.",
            cases: cases
        )
    }
}
