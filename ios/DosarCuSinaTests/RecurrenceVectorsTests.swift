import Foundation
import Testing
@testable import DosarCuSina

/// How a deadline repeats (`RecurrenceEngine`: the next cycle of every rule, a series' start, a
/// cycle's start, a first due day, the one calendar step), run over cases chosen to bite (month ends,
/// the 31st kept by a series, 29 February, a deadline done late by several cycles, money still owed,
/// fixed dates, a counter's projection and its fallback, the ITP by a car's age and use, values held
/// to their bounds) and written to `shared/test-vectors/recurrence/`, one file per rule: each input
/// with the answer this app gives. The Android app's tests read the same files and must give the same
/// answers (docs/ANDROID_PLAN.md, "How parity is kept"): its engine (android/catalog,
/// `RecurrenceEngine`). A sibling of `ValueVectorsTests`, with a folder of its own.
///
/// Every case names the time zone it counts in (only a counter's projection reads it), so no answer
/// depends on the machine. Rules, values and blueprints are written in the archive's form; moments as
/// UTC moments. Placeholder data only.
@Suite("Recurrence vectors")
struct RecurrenceVectorsTests {
    static var folder: URL {
        URL(filePath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appending(path: "shared/test-vectors/recurrence")
    }

    /// How to bring the files up to date, said when one isn't.
    static let regenerate = """
    is out of date with the recurrence rules. Bring shared/test-vectors/recurrence up to date: \
    TEST_RUNNER_RECURRENCE_VECTORS_WRITE=1 ./tests/run_tests.sh (or run RecurrenceVectorsTests in Xcode with \
    RECURRENCE_VECTORS_WRITE=1 in the scheme's environment), review the diff and commit it, then run the \
    Android tests (./gradlew :catalog:test in android/), which read the same files.
    """

    typealias Vectors = ValueVectorsTests.Vectors

    @Test("shared/test-vectors/recurrence is up to date with the recurrence rules")
    func vectorsAreUpToDate() throws {
        let files = try Self.all()
        let writes = ProcessInfo.processInfo.environment["RECURRENCE_VECTORS_WRITE"] == "1"
        let manager = FileManager.default
        if writes { try manager.createDirectory(at: Self.folder, withIntermediateDirectories: true) }
        for file in files {
            let url = Self.folder.appending(path: "\(file.name).json")
            let fresh = try ValueVectorsTests.render(file)
                .replacingOccurrences(of: "ios/DosarCuSinaTests/ValueVectorsTests.swift", with: "ios/DosarCuSinaTests/RecurrenceVectorsTests.swift")
            if writes {
                try fresh.write(to: url, atomically: true, encoding: .utf8)
                continue
            }
            let committed = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
            #expect(committed == fresh, Comment(rawValue: "\(file.name).json " + Self.regenerate))
            // The file as it should be, kept in the run's result bundle, so a run on GitHub hands it over too.
            if committed != fresh { Testing.Attachment.record(Data(fresh.utf8), named: "recurrence-\(file.name).json") }
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

    static func all() throws -> [Vectors] {
        try [nextDue(), seriesStart(), cycleStart(), firstDue(), adding()]
    }

    // MARK: Helpers

    static func day(_ text: String) -> CalendarDay { ValueVectorsTests.day(text) }
    static func iso(_ day: CalendarDay?) -> JSONValue { ValueVectorsTests.iso(day) }

    /// `value` as this app writes it, read back as JSON.
    static func encoded<Value: Encodable>(_ value: Value) throws -> JSONValue {
        try ValueVectorsTests.json(ValueVectorsTests.compact(value))
    }

    /// What `json` is, read as this app reads `type` from an archive.
    static func decoded<Value: Decodable>(_ type: Value.Type, _ json: JSONValue) throws -> Value {
        try MachineText.jsonDecoder().decode(type, from: MachineText.jsonEncoder(.compact).encode(json))
    }

    static func moment(_ text: String) -> Date {
        guard let date = MachineText.moment(text) else {
            Issue.record("Not a moment: \(text)")
            return .distantPast
        }
        return date
    }

    static func number(_ value: Double?) -> JSONValue { value.map(JSONValue.number) ?? .null }

    /// A section's values in the archive's form, from text, numbers and days.
    static func values(_ pairs: [(String, FieldValue)]) -> FieldValues {
        var values = FieldValues()
        for (key, value) in pairs { values[key] = value }
        return values
    }

    // MARK: Next cycle

    /// A reading a case's section keeps: its moment as written and its value.
    struct Point {
        let at: String
        let metric: Double
        var starts = false
        var estimate = false

        var reading: CadenceCalculator.TelemetryReading {
            .init(date: RecurrenceVectorsTests.moment(at), metric: metric, startsCounter: starts, isEstimate: estimate)
        }

        var json: JSONValue {
            .object(["at": .string(at), "metric": .number(metric), "startsCounter": .bool(starts), "isEstimate": .bool(estimate)])
        }
    }

    struct NextCase {
        let name: String
        let rule: JSONValue
        let due: String
        let done: String
        var zone = "Europe/Bucharest"
        var values: [(String, FieldValue)] = []
        var readings: [Point] = []
        var current: Double?
        var seriesDay: Int?
        var owed = false
    }

    static func interval(_ every: Int, _ unit: String, _ anchor: String? = "dueDate") -> JSONValue {
        var rule: [String: JSONValue] = ["type": "interval", "every": .int(every), "unit": .string(unit)]
        if let anchor { rule["anchor"] = .string(anchor) }
        return .object(rule)
    }

    static func fixed(_ dates: [String]) -> JSONValue { .object(["type": "fixedDates", "dates": .array(dates.map(JSONValue.string))]) }

    static func metric(_ every: Double, _ unit: String = "km", fallback: (Int, String)? = nil) -> JSONValue {
        var rule: [String: JSONValue] = ["type": "metric", "every": .number(every), "unit": .string(unit)]
        if let fallback {
            rule["fallbackEvery"] = .int(fallback.0)
            rule["fallbackUnit"] = .string(fallback.1)
        }
        return .object(rule)
    }

    static let itp: JSONValue = .object(["type": "legal", "rule": "vehicleITP"])

    static func car(year: Double?, usage: String?) -> [(String, FieldValue)] {
        var pairs: [(String, FieldValue)] = []
        if let year { pairs.append((VehicleFields.year, .number(year))) }
        if let usage { pairs.append(("vehicle.usage", .text(usage))) }
        return pairs
    }

    static let nextCases: [NextCase] = {
        let fast = [Point(at: "2026-01-01T10:00:00Z", metric: 100_000), Point(at: "2026-02-10T10:00:00Z", metric: 102_000)]
        let slow = [Point(at: "2026-01-01T10:00:00Z", metric: 100_000), Point(at: "2026-02-10T10:00:00Z", metric: 100_100)]
        return [
            NextCase(name: "a month from the 31st, done on time", rule: interval(1, "month"), due: "2026-01-31", done: "2026-01-25"),
            NextCase(name: "a series keeps the 31st after February", rule: interval(1, "month"), due: "2026-02-28", done: "2026-02-28", seriesDay: 31),
            NextCase(name: "a month from the 31st, done ten days late", rule: interval(1, "month"), due: "2026-01-31", done: "2026-02-10"),
            NextCase(name: "a month done three months late moves past the day it was done", rule: interval(1, "month"), due: "2026-01-15", done: "2026-04-20"),
            NextCase(name: "rent done three months late closes one month", rule: interval(1, "month"), due: "2026-01-15", done: "2026-04-20", owed: true),
            NextCase(name: "a month done on the next cycle's own day", rule: interval(1, "month"), due: "2026-01-15", done: "2026-02-15"),
            NextCase(name: "29 February a year on", rule: interval(1, "year"), due: "2028-02-29", done: "2028-02-29"),
            NextCase(name: "a year on from 28 February kept as the 29th", rule: interval(1, "year"), due: "2027-02-28", done: "2027-02-20", seriesDay: 29),
            NextCase(name: "a week done eighteen days late", rule: interval(1, "week"), due: "2026-03-02", done: "2026-03-20"),
            NextCase(name: "every three days done nine days late", rule: interval(3, "day"), due: "2026-03-01", done: "2026-03-10"),
            NextCase(name: "every two years by the due day, done early", rule: interval(2, "year"), due: "2026-06-30", done: "2026-06-01"),
            NextCase(name: "every two years from the day it was done", rule: interval(2, "year", "completion"), due: "2026-06-01", done: "2026-05-20"),
            NextCase(name: "a month from the day it was done, on the 31st", rule: interval(1, "month", "completion"), due: "2026-02-10", done: "2026-01-31"),
            NextCase(name: "every 0 months is every month", rule: interval(0, "month"), due: "2026-03-31", done: "2026-03-31"),
            NextCase(name: "every 200 years is a hundred", rule: interval(200, "year"), due: "2026-03-31", done: "2026-03-31"),
            NextCase(name: "an interval without its anchor counts from the due day", rule: interval(1, "month", nil), due: "2026-01-31", done: "2026-03-05"),
            NextCase(name: "fixed dates, done early", rule: fixed(["03-31", "09-30"]), due: "2026-03-31", done: "2026-03-20"),
            NextCase(name: "fixed dates, done on the day", rule: fixed(["03-31", "09-30"]), due: "2026-09-30", done: "2026-09-30"),
            NextCase(name: "a tax installment paid very late is still owed", rule: fixed(["03-31", "09-30"]), due: "2026-03-31", done: "2026-11-01", owed: true),
            NextCase(name: "fixed dates done very late move past the day", rule: fixed(["03-31", "09-30"]), due: "2026-03-31", done: "2026-11-01"),
            NextCase(name: "fixed dates done on the next date's own day", rule: fixed(["03-31", "09-30"]), due: "2026-03-31", done: "2026-09-30"),
            NextCase(name: "a fixed 29 February in a common year", rule: fixed(["02-29"]), due: "2028-02-29", done: "2028-02-29"),
            NextCase(name: "no fixed dates", rule: fixed([]), due: "2026-03-31", done: "2026-03-31"),
            NextCase(name: "one-off", rule: .object(["type": "none"]), due: "2026-01-01", done: "2026-01-01"),
            NextCase(name: "a rule a newer build wrote", rule: .object(["type": "weekly", "on": "monday"]), due: "2026-01-01", done: "2026-01-01"),
            NextCase(name: "a legal rule a newer build wrote", rule: .object(["type": "legal", "rule": "vehicleRCA"]), due: "2026-01-01", done: "2026-01-01"),
            NextCase(name: "an anchor a newer build wrote", rule: interval(1, "month", "firstMonday"), due: "2026-01-01", done: "2026-01-01"),
            NextCase(name: "ITP of a car eight years old", rule: itp, due: "2026-05-20", done: "2026-05-20", values: car(year: 2018, usage: "vehicleUse.personal")),
            NextCase(name: "ITP of a car twelve years old", rule: itp, due: "2026-05-20", done: "2026-05-20", values: car(year: 2014, usage: nil)),
            NextCase(name: "ITP of a car thirteen years old", rule: itp, due: "2026-05-20", done: "2026-05-20", values: car(year: 2013, usage: "Personală")),
            NextCase(name: "ITP of a taxi", rule: itp, due: "2026-05-20", done: "2026-05-20", values: car(year: 2022, usage: "vehicleUse.commercial")),
            NextCase(name: "ITP of a ridesharing car named by its label", rule: itp, due: "2026-05-20", done: "2026-05-20", values: car(year: 2022, usage: "Ridesharing sau taxi")),
            NextCase(name: "ITP of a car named by an alias", rule: itp, due: "2026-08-31", done: "2026-08-31", values: car(year: 2022, usage: "uber")),
            NextCase(name: "ITP of a car of unknown age", rule: itp, due: "2026-05-20", done: "2026-05-20"),
            NextCase(name: "ITP of a car whose year no whole number holds", rule: itp, due: "2026-05-20", done: "2026-05-20", values: car(year: 1e19, usage: nil)),
            NextCase(name: "ITP of a car made next year", rule: itp, due: "2026-05-20", done: "2026-05-20", values: car(year: 2030, usage: nil)),
            NextCase(name: "ITP of a car whose year is a fraction", rule: itp, due: "2026-05-20", done: "2026-05-20", values: car(year: 2013.5, usage: nil)),
            NextCase(name: "a service at 50 km a day comes before its year", rule: metric(15_000, fallback: (1, "year")), due: "2026-02-10", done: "2026-02-10",
                     readings: fast, current: 102_000),
            NextCase(name: "a service barely driven comes at its year", rule: metric(15_000, fallback: (1, "year")), due: "2026-02-10", done: "2026-02-10",
                     readings: slow, current: 100_100),
            NextCase(name: "a service with no readings comes at its fallback", rule: metric(150, fallback: (1, "month")), due: "2026-02-10", done: "2026-02-10"),
            NextCase(name: "a service with no fallback comes in six months", rule: metric(150), due: "2026-02-10", done: "2026-02-10"),
            NextCase(name: "the counter now is the last reading", rule: metric(15_000, fallback: (1, "year")), due: "2026-02-10", done: "2026-02-10", readings: fast),
            NextCase(name: "a counter step of 0 is due the next day", rule: metric(0, fallback: (1, "year")), due: "2026-02-10", done: "2026-02-10",
                     readings: fast, current: 102_000),
            NextCase(name: "a new counter counts on its own", rule: metric(5_000, fallback: (1, "year")), due: "2026-03-01", done: "2026-03-01",
                     readings: [Point(at: "2026-01-01T10:00:00Z", metric: 145_000), Point(at: "2026-01-21T10:00:00Z", metric: 146_000),
                                Point(at: "2026-02-01T10:00:00Z", metric: 1_000, starts: true), Point(at: "2026-03-01T10:00:00Z", metric: 2_400)],
                     current: 2_400),
            NextCase(name: "readings hours apart on one day", rule: metric(1_000, fallback: (1, "year")), due: "2026-03-01", done: "2026-03-01",
                     readings: [Point(at: "2026-03-01T06:00:00Z", metric: 10_000), Point(at: "2026-03-01T18:00:00Z", metric: 10_100)],
                     current: 10_100),
            NextCase(name: "readings across the clocks going forward", rule: metric(3_000, fallback: (1, "year")), due: "2026-04-01", done: "2026-04-01",
                     readings: [Point(at: "2026-03-28T22:30:00Z", metric: 20_000), Point(at: "2026-03-31T21:30:00Z", metric: 20_300)],
                     current: 20_300),
            NextCase(name: "readings near midnight far east", rule: metric(3_000, fallback: (1, "year")), due: "2026-04-01", done: "2026-04-01",
                     zone: "Pacific/Auckland",
                     readings: [Point(at: "2026-03-28T10:30:00Z", metric: 20_000), Point(at: "2026-03-31T11:30:00Z", metric: 20_300)],
                     current: 20_300),
            NextCase(name: "readings set aside count for nothing", rule: metric(10_000, fallback: (1, "year")), due: "2026-03-01", done: "2026-03-01",
                     readings: [Point(at: "2026-01-01T10:00:00Z", metric: 100_000), Point(at: "2026-01-11T10:00:00Z", metric: 10_050),
                                Point(at: "2026-01-21T10:00:00Z", metric: 101_000)],
                     current: 101_000),
            NextCase(name: "a counter that barely moves is due in a hundred years at most", rule: metric(10_000_000, fallback: (100, "year")),
                     due: "2026-03-01", done: "2026-03-01",
                     readings: [Point(at: "2026-01-01T10:00:00Z", metric: 100_000), Point(at: "2026-03-01T10:00:00Z", metric: 100_001)],
                     current: 100_001),
        ]
    }()

    static func nextDue() throws -> Vectors {
        var cases: [JSONValue] = []
        for item in nextCases {
            let calendar = Calendar.dosar(in: ValueVectorsTests.zone(item.zone))
            let rule = try decoded(RecurrenceRule.self, item.rule)
            let context = RecurrenceContext(assetValues: values(item.values), readings: item.readings.map(\.reading),
                                            currentMetric: item.current, seriesDayOfMonth: item.seriesDay, missedCyclesStayOwed: item.owed)
            let next = RecurrenceEngine.nextDue(after: day(item.due), completedOn: day(item.done), rule: rule, context: context, calendar: calendar)
            cases.append(.object([
                "name": .string(item.name),
                "zone": .string(item.zone),
                "rule": item.rule,
                "due": .string(item.due),
                "completedOn": .string(item.done),
                "values": try encoded(values(item.values)),
                "readings": .array(item.readings.map(\.json)),
                "currentMetric": number(item.current),
                "seriesDayOfMonth": item.seriesDay.map(JSONValue.int) ?? .null,
                "missedCyclesStayOwed": .bool(item.owed),
                "next": next.map { .object(["day": .string($0.day.isoString), "metric": number($0.metric)]) } ?? .null,
            ]))
        }
        return Vectors(
            name: "next-due",
            rule: "RecurrenceEngine.nextDue(after:completedOn:rule:context:calendar:), with itpInterval and the counter's projection (CadenceCalculator.projectTelemetryDueDate)",
            source: "ios/DosarCuSina/Services/Obligations/RecurrenceEngine.swift, ios/DosarCuSina/Services/Cadence/CadenceCalculator.swift",
            shape: "rule: how it repeats, as the archive writes it (a rule a newer build wrote is kept and repeats as one-off). due: the cycle closed. completedOn: the day it was done. values: the section's values in the archive's form. readings: the section's counter readings, oldest first (at, metric, startsCounter, isEstimate). currentMetric: the counter now, when known. seriesDayOfMonth: the day of the month the series keeps. missedCyclesStayOwed: each cycle is money still owed. zone: the time zone days are counted in. next: the next cycle's day and the counter it is due at, or null for none.",
            cases: cases
        )
    }

    // MARK: A series and a cycle

    static func seriesStart() throws -> Vectors {
        typealias Step = RecurrenceEngine.SeriesStep
        let inputs: [(String, String, (Int, String), [(String?, String?)])] = [
            ("an unbroken month from the 31st", "2026-04-30", (1, "month"), [("2026-03-31", "2026-04-30"), ("2026-02-28", "2026-03-31"), ("2026-01-31", "2026-02-28")]),
            ("a day set by hand starts a new series", "2026-05-15", (1, "month"), [("2026-03-31", "2026-04-30"), ("2026-02-28", "2026-03-31")]),
            ("a step another rule took starts a new series", "2026-05-31", (1, "month"), [("2026-04-30", "2026-05-31"), ("2026-04-23", "2026-04-30")]),
            ("a completion done late by two cycles", "2026-04-30", (1, "month"), [("2026-01-31", "2026-04-30"), ("2025-12-31", "2026-01-31")]),
            ("a completion with no next day ends the walk", "2026-03-31", (1, "month"), [(nil, "2026-03-31"), ("2026-01-31", nil)]),
            ("no completions", "2026-03-31", (1, "month"), []),
            ("weeks", "2026-03-23", (1, "week"), [("2026-03-16", "2026-03-23"), ("2026-03-02", "2026-03-16")]),
            ("every three days, one off", "2026-03-11", (3, "day"), [("2026-03-07", "2026-03-11")]),
            ("years from 29 February", "2029-02-28", (1, "year"), [("2028-02-29", "2029-02-28")]),
            ("every two years, a year apart", "2028-06-30", (2, "year"), [("2027-06-30", "2028-06-30")]),
            ("a day earlier than the step", "2026-03-01", (1, "month"), [("2026-03-05", "2026-03-01")]),
        ]
        var cases: [JSONValue] = []
        for (name, current, interval, steps) in inputs {
            let rule = RecurrenceInterval(every: interval.0, unit: RecurrenceInterval.Unit(rawValue: interval.1) ?? .day)
            let completions = steps.map { Step(cycle: $0.0.map(day), next: $0.1.map(day)) }
            let start = RecurrenceEngine.seriesStart(current: day(current), completions: completions, interval: rule, calendar: .bucharest)
            cases.append(.object([
                "name": .string(name),
                "current": .string(current),
                "interval": .object(["every": .int(interval.0), "unit": .string(interval.1)]),
                "completions": .array(completions.map { .object(["cycle": iso($0.cycle), "next": iso($0.next)]) }),
                "start": .string(start.isoString),
                "seriesDayOfMonth": .int(start.day),
            ]))
        }
        return Vectors(
            name: "series-start",
            rule: "RecurrenceEngine.seriesStart(current:completions:interval:calendar:) and isStep(of:from:to:)",
            source: "ios/DosarCuSina/Services/Obligations/RecurrenceEngine.swift",
            shape: "current: the due day now. interval: the rule's step. completions: newest first, each the cycle it closed and the day it moved to (null when none). start: the first due day of the unbroken series, and its day of the month, the one the series keeps.",
            cases: cases
        )
    }

    static func cycleStart() throws -> Vectors {
        let inputs: [(String, String, JSONValue)] = [
            ("a month before the 31st", "2026-03-31", interval(1, "month")),
            ("a month before 31 May", "2026-05-31", interval(1, "month", "completion")),
            ("a year before 29 February", "2028-02-29", interval(1, "year")),
            ("two weeks", "2026-03-15", interval(2, "week")),
            ("three days", "2026-03-02", interval(3, "day")),
            ("every 0 days is every day", "2026-03-02", interval(0, "day")),
            ("the fixed date before, in the same year", "2026-09-30", fixed(["03-31", "09-30"])),
            ("the fixed date before, last year", "2026-03-31", fixed(["03-31", "09-30"])),
            ("a due day between the fixed dates", "2026-06-15", fixed(["03-31", "09-30"])),
            ("no fixed dates", "2026-06-15", fixed([])),
            ("one-off", "2026-06-15", .object(["type": "none"])),
            ("a counter", "2026-06-15", metric(15_000, fallback: (1, "year"))),
            ("the ITP", "2026-06-15", itp),
            ("a rule a newer build wrote", "2026-06-15", .object(["type": "weekly"])),
        ]
        var cases: [JSONValue] = []
        for (name, due, json) in inputs {
            let rule = try decoded(RecurrenceRule.self, json)
            cases.append(.object([
                "name": .string(name), "due": .string(due), "rule": json,
                "start": iso(RecurrenceEngine.cycleStart(endingOn: day(due), rule: rule, calendar: .bucharest)),
            ]))
        }
        return Vectors(
            name: "cycle-start",
            rule: "RecurrenceEngine.cycleStart(endingOn:rule:calendar:)",
            source: "ios/DosarCuSina/Services/Obligations/RecurrenceEngine.swift",
            shape: "due: the cycle's due day. rule: how it repeats, as the archive writes it. start: the day the cycle began, or null for a rule whose cycle has no set length.",
            cases: cases
        )
    }

    // MARK: First cycle and the calendar step

    static func firstDue() throws -> Vectors {
        let expiry: [(String, FieldValue)] = [("document.expiry", .date(day("2027-06-01")))]
        let inputs: [(String, JSONValue, JSONValue, [(String, FieldValue)], String)] = [
            ("a field's day, a month before", .object(["type": "field", "field": "document.expiry", "offsetDays": .int(-30)]), .object(["type": "none"]), expiry, "2026-11-02"),
            ("a field's day without an offset", .object(["type": "field", "field": "document.expiry"]), .object(["type": "none"]), expiry, "2026-11-02"),
            ("a field that is empty", .object(["type": "field", "field": "document.expiry", "offsetDays": .int(0)]), .object(["type": "none"]), [], "2026-11-02"),
            ("a field that holds text", .object(["type": "field", "field": "document.expiry", "offsetDays": .int(0)]), .object(["type": "none"]),
             [("document.expiry", .text("2027-06-01"))], "2026-11-02"),
            ("a year after 29 February", .object(["type": "afterInterval", "every": .int(1), "unit": "year"]), .object(["type": "none"]), [], "2028-02-29"),
            ("a month after the 31st", .object(["type": "afterInterval", "every": .int(1), "unit": "month"]), .object(["type": "none"]), [], "2026-01-31"),
            ("every 0 weeks after today is one", .object(["type": "afterInterval", "every": .int(0), "unit": "week"]), .object(["type": "none"]), [], "2026-11-02"),
            ("a unit a newer build wrote asks", .object(["type": "afterInterval", "every": .int(1), "unit": "fortnight"]), .object(["type": "none"]), [], "2026-11-02"),
            ("the next fixed date", .object(["type": "nextFixedDate"]), fixed(["03-31", "09-30"]), [], "2026-11-02"),
            ("the next fixed date is today", .object(["type": "nextFixedDate"]), fixed(["03-31", "09-30"]), [], "2026-09-30"),
            ("the next fixed date without fixed dates", .object(["type": "nextFixedDate"]), interval(1, "year"), [], "2026-11-02"),
            ("asked", .object(["type": "ask"]), itp, [], "2026-11-02"),
            ("a rule a newer build wrote asks", .object(["type": "fromSeason"]), .object(["type": "none"]), [], "2026-11-02"),
        ]
        var cases: [JSONValue] = []
        for (name, first, recurrence, pairs, today) in inputs {
            let blueprintJSON: JSONValue = .object([
                "key": "test.deadline", "title": "Termen", "kind": "renewal", "completion": "newDocument",
                "recurrence": recurrence, "firstDue": first,
            ])
            let blueprint = try decoded(ObligationBlueprint.self, blueprintJSON)
            let found = RecurrenceEngine.firstDue(for: blueprint, values: values(pairs), today: day(today), calendar: .bucharest)
            cases.append(.object([
                "name": .string(name), "blueprint": blueprintJSON, "values": try encoded(values(pairs)),
                "today": .string(today), "day": iso(found),
            ]))
        }
        return Vectors(
            name: "first-due",
            rule: "RecurrenceEngine.firstDue(for:values:today:calendar:)",
            source: "ios/DosarCuSina/Services/Obligations/RecurrenceEngine.swift, ios/DosarCuSina/Models/Obligations/ObligationTypes.swift (FirstDueRule)",
            shape: "blueprint: a category's usual deadline as the archive writes it (its firstDue and recurrence are what count). values: the section's values in the archive's form. today: the day it is made. day: its first due day, or null when the person is asked.",
            cases: cases
        )
    }

    static func adding() throws -> Vectors {
        let inputs: [(Int, String, String, Int?)] = [
            (1, "month", "2026-01-31", nil), (1, "month", "2026-01-31", 31), (1, "month", "2026-02-28", 31), (1, "month", "2026-02-28", 30),
            (1, "year", "2028-02-29", nil), (1, "year", "2027-02-28", 29), (4, "year", "2028-02-29", nil), (13, "month", "2026-01-31", nil),
            (2, "week", "2026-12-25", nil), (10, "day", "2026-12-25", nil), (0, "day", "2026-12-25", nil), (-3, "month", "2026-12-25", nil),
            (200, "year", "2026-12-25", nil), (40_000, "day", "2026-12-25", nil), (1, "month", "2026-03-15", 31),
        ]
        var cases: [JSONValue] = []
        for (every, unit, from, dayOfMonth) in inputs {
            let interval = RecurrenceInterval(every: every, unit: RecurrenceInterval.Unit(rawValue: unit) ?? .day)
            let result = RecurrenceEngine.add(interval, to: day(from), dayOfMonth: dayOfMonth, calendar: .bucharest)
            cases.append(.object([
                "every": .int(every), "unit": .string(unit), "day": .string(from),
                "dayOfMonth": dayOfMonth.map(JSONValue.int) ?? .null,
                "heldTo": .int(interval.every), "result": .string(result.isoString),
            ]))
        }
        return Vectors(
            name: "add",
            rule: "RecurrenceInterval(every:unit:) held to its bounds and RecurrenceEngine.add(_:to:dayOfMonth:calendar:), the one calendar step",
            source: "ios/DosarCuSina/Models/Obligations/ObligationTypes.swift, ios/DosarCuSina/Services/Obligations/RecurrenceEngine.swift",
            shape: "every and unit: an interval as written, from outside. heldTo: its every once made (at least one, a hundred years at most). day: the day moved. dayOfMonth: the day a series keeps, or null. result: the day it lands on.",
            cases: cases
        )
    }
}
