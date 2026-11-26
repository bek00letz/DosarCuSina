import Foundation
import SwiftData
import Testing
@testable import DosarCuSina

/// A moment a case writes, read as the app reads one.
private func readingMoment(_ text: String) -> Date {
    guard let date = MachineText.moment(text) else {
        Issue.record("Not a moment: \(text)")
        return .distantPast
    }
    return date
}

/// A UTC moment on `day`, at ten by default (noon in Bucharest in winter).
private func utc(_ day: String, _ time: String = "10:00:00") -> String { "\(day)T\(time)Z" }

/// The readings and counters engine (`ReadingSeries`, `ReadingDrop`, `LowerReadingAnswer.offered`,
/// `MeasurementKind`, and the one way to record, ask about and take away a reading:
/// `HouseholdMutations.recordReading`, `askAboutReading`, `deleteReading`, in
/// ios/DosarCuSina/Services/History/Readings.swift, and the counter repair's rule,
/// `CounterOutliersStep.verdicts`), run over cases chosen to bite and written to
/// `shared/test-vectors/readings/`, one file per rule: each input with the answer this app gives. The
/// Android app's tests read the same files and must give the same answers (docs/ANDROID_PLAN.md, "How
/// parity is kept"): its engine (android/core, `core.readings`) and its store's actions
/// (android/store, `store.readings`). A sibling of `ValueVectorsTests`, with a folder of its own.
///
/// Moments are written as UTC moments (`2026-01-10T10:00:00Z`) and an answer names a reading by its
/// moment as the case wrote it, so neither side writes a date. Placeholder data only.
@MainActor
@Suite("Reading vectors")
struct ReadingVectorsTests {
    static var folder: URL {
        URL(filePath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appending(path: "shared/test-vectors/readings")
    }

    /// How to bring the files up to date, said when one isn't.
    static let regenerate = """
    is out of date with the reading rules. Bring shared/test-vectors/readings up to date: \
    TEST_RUNNER_READING_VECTORS_WRITE=1 ./tests/run_tests.sh (or run ReadingVectorsTests in Xcode with \
    READING_VECTORS_WRITE=1 in the scheme's environment), review the diff and commit it, then run the \
    Android tests (./gradlew :core:test :store:test in android/), which read the same files.
    """

    typealias Vectors = ValueVectorsTests.Vectors

    @Test("shared/test-vectors/readings is up to date with the reading rules")
    func vectorsAreUpToDate() throws {
        let files = try Self.all()
        let writes = ProcessInfo.processInfo.environment["READING_VECTORS_WRITE"] == "1"
        let manager = FileManager.default
        if writes { try manager.createDirectory(at: Self.folder, withIntermediateDirectories: true) }
        for file in files {
            let url = Self.folder.appending(path: "\(file.name).json")
            let fresh = try ValueVectorsTests.render(file)
                .replacingOccurrences(of: "ios/DosarCuSinaTests/ValueVectorsTests.swift", with: "ios/DosarCuSinaTests/ReadingVectorsTests.swift")
            if writes {
                try fresh.write(to: url, atomically: true, encoding: .utf8)
                continue
            }
            let committed = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
            #expect(committed == fresh, Comment(rawValue: "\(file.name).json " + Self.regenerate))
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
        try [measurementKinds(), series(), distances(), drops(), outliers(), recording(), deleting()]
    }

    // MARK: Helpers

    /// A reading of a series, written in a case: its moment as written, its value, and its flags.
    struct Point {
        let at: String
        let metric: Double
        var starts = false
        var estimate = false

        var reading: ReadingSeries.Reading { .init(date: readingMoment(at), metric: metric, startsCounter: starts, isEstimate: estimate) }

        var json: JSONValue {
            .object(["at": .string(at), "metric": .number(metric), "startsCounter": .bool(starts), "isEstimate": .bool(estimate)])
        }
    }

    /// Writes `readings` naming each by the moment its case wrote.
    static func written(_ readings: [ReadingSeries.Reading], names: [Date: String]) -> JSONValue {
        .array(readings.map { reading in
            .object([
                "at": .string(names[reading.date] ?? "?"),
                "metric": .number(reading.metric),
                "startsCounter": .bool(reading.startsCounter),
                "isEstimate": .bool(reading.isEstimate),
            ])
        })
    }

    static func moments(_ points: [Point]) -> [Date: String] {
        Dictionary(points.map { (readingMoment($0.at), $0.at) }, uniquingKeysWith: { first, _ in first })
    }

    // MARK: Kinds

    static func measurementKinds() -> Vectors {
        var cases: [JSONValue] = MeasurementKind.allCases.map { kind in
            .object([
                "raw": .string(kind.rawValue),
                "defaultUnit": kind.defaultUnit.map { .string($0.key) } ?? .null,
                "isCumulative": .bool(kind.isCumulative),
                "mayBeEstimated": .bool(kind.mayBeEstimated),
                "offered": .array(LowerReadingAnswer.offered(for: kind, likelyNewCounter: false).map { .string("\($0)") }),
                "offeredLikelyNewCounter": .array(LowerReadingAnswer.offered(for: kind, likelyNewCounter: true).map { .string("\($0)") }),
            ])
        }
        // A kind a newer build wrote reads as custom.
        cases.append(.object(["stored": "thermometer", "kind": .string(MeasurementKind(rawValue: "thermometer").map(\.rawValue) ?? MeasurementKind.custom.rawValue)]))
        for unit in ["km", "kg", "h", "kwh", "m3", "gcal", "shots", "ore motor"] {
            cases.append(.object(["forUnit": .string(unit), "kind": .string(MeasurementKind.forUnit(MeasurementUnit(unit)).rawValue)]))
        }
        cases.append(.object(["forUnit": .null, "kind": .string(MeasurementKind.forUnit(nil).rawValue)]))
        cases.append(.object(["allAnswers": .array(LowerReadingAnswer.allCases.map { .string("\($0)") })]))
        return Vectors(
            name: "measurement-kind",
            rule: "MeasurementKind (defaultUnit, isCumulative, mayBeEstimated, forUnit), LowerReadingAnswer.allCases and offered(for:likelyNewCounter:)",
            source: "ios/DosarCuSina/Models/Schema/RecordModels.swift, ios/DosarCuSina/Services/History/Readings.swift",
            shape: "raw: a kind with its default unit's key, whether it only goes up, whether its readings may be estimated, and the answers a lower reading offers (offered) and offers when it looks like a new counter (offeredLikelyNewCounter). stored: a raw a newer build wrote, and the kind it reads as. forUnit: a unit's key (null for none) and the kind a field in it records. allAnswers: every answer, in order.",
            cases: cases
        )
    }

    // MARK: The series

    /// The series' cases: each a name and its readings, oldest or not, as a section keeps them.
    static let seriesInputs: [(String, [Point], Bool)] = {
        let d = { (day: String) in utc(day) }
        return [
            ("a typo is set aside", [Point(at: d("2026-01-01"), metric: 40_000), Point(at: d("2026-01-31"), metric: 45_724), Point(at: d("2026-03-02"), metric: 457)], true),
            ("a first reading too high", [Point(at: d("2026-01-01"), metric: 450_000), Point(at: d("2026-01-31"), metric: 46_000), Point(at: d("2026-03-02"), metric: 47_000)], true),
            ("on a tie the earlier wins", [Point(at: d("2026-01-01"), metric: 10_000), Point(at: d("2026-01-31"), metric: 9_000)], true),
            ("a weight is the newest", [Point(at: d("2026-01-01"), metric: 80), Point(at: d("2026-01-31"), metric: 75)], false),
            ("a weight out of order", [Point(at: d("2026-03-01"), metric: 81.5), Point(at: d("2026-01-31"), metric: 75), Point(at: d("2026-02-15"), metric: 78.2)], false),
            ("a replaced dashboard", [
                Point(at: d("2026-01-01"), metric: 100_000), Point(at: d("2026-04-01"), metric: 103_000),
                Point(at: d("2026-05-01"), metric: 500, starts: true), Point(at: d("2026-06-01"), metric: 1_500),
            ], true),
            ("a counter that went round", [
                Point(at: d("2025-01-01"), metric: 99_000), Point(at: d("2025-12-01"), metric: 99_990),
                Point(at: d("2026-01-15"), metric: 12, starts: true), Point(at: d("2026-03-15"), metric: 410),
            ], true),
            ("three counters", [
                Point(at: d("2025-01-01"), metric: 10_000), Point(at: d("2025-03-01"), metric: 11_000),
                Point(at: d("2025-04-01"), metric: 100, starts: true), Point(at: d("2025-06-01"), metric: 900),
                Point(at: d("2025-07-01"), metric: 5, starts: true), Point(at: d("2025-09-01"), metric: 505),
            ], true),
            ("an estimate counts until a lower reading", [
                Point(at: d("2026-06-05"), metric: 10_000), Point(at: d("2026-07-05"), metric: 10_100, estimate: true),
                Point(at: d("2026-08-05"), metric: 10_200, estimate: true),
            ], true),
            ("a regularisation corrects the estimates", [
                Point(at: d("2026-06-05"), metric: 10_000), Point(at: d("2026-07-05"), metric: 10_100, estimate: true),
                Point(at: d("2026-08-05"), metric: 10_200, estimate: true), Point(at: d("2026-09-05"), metric: 10_300, estimate: true),
                Point(at: d("2026-10-05"), metric: 10_150),
            ], true),
            ("a new meter corrects nothing", [
                Point(at: d("2026-06-05"), metric: 10_000), Point(at: d("2026-07-05"), metric: 10_100, estimate: true),
                Point(at: d("2026-08-05"), metric: 10_200, estimate: true), Point(at: d("2026-09-05"), metric: 5, starts: true),
            ], true),
            ("an estimate lowered by a later estimate", [
                Point(at: d("2026-01-05"), metric: 100), Point(at: d("2026-02-05"), metric: 190, estimate: true),
                Point(at: d("2026-03-05"), metric: 160, estimate: true), Point(at: d("2026-04-05"), metric: 175),
            ], true),
            ("readings at the same moment", [
                Point(at: d("2026-03-01"), metric: 10_050), Point(at: d("2026-03-01"), metric: 10_000),
                Point(at: d("2026-03-02"), metric: 10_100),
            ], true),
            ("a new counter at the same moment as the old one's last", [
                Point(at: d("2026-03-01"), metric: 99_999), Point(at: d("2026-03-01"), metric: 3, starts: true),
                Point(at: d("2026-04-01"), metric: 300),
            ], true),
            ("across the clock change", [
                Point(at: utc("2026-03-01"), metric: 1_000), Point(at: utc("2026-04-01", "09:00:00"), metric: 1_930),
                Point(at: utc("2026-10-26", "10:30:00"), metric: 8_200),
            ], true),
            ("engine hours with a decimal", [
                Point(at: d("2026-01-01"), metric: 312.5), Point(at: d("2026-03-01"), metric: 340.25), Point(at: d("2026-04-01"), metric: 340.1),
            ], true),
            ("one reading", [Point(at: d("2026-01-01"), metric: 45_724)], true),
            ("no readings", [], true),
        ]
    }()

    static func progress(_ series: ReadingSeries) -> JSONValue {
        guard let progress = series.progress() else { return .null }
        return .object(["distance": .number(progress.distance), "days": .number(progress.days)])
    }

    static func series() -> Vectors {
        let cases: [JSONValue] = seriesInputs.map { name, points, cumulative in
            let names = moments(points)
            let series = ReadingSeries(points.map(\.reading), cumulative: cumulative)
            return .object([
                "name": .string(name),
                "cumulative": .bool(cumulative),
                "readings": .array(points.map(\.json)),
                "counters": .array(series.counters.map { written($0, names: names) }),
                "counted": written(series.readings, names: names),
                "setAside": written(series.setAside, names: names),
                "corrected": written(series.corrected, names: names),
                "counterStarts": .array(series.counterStarts.map { .string(names[$0] ?? "?") }),
                "current": series.current.map { .number($0) } ?? .null,
                "progress": progress(series),
                "madeAgain": .bool(ReadingSeries(series.readings, cumulative: cumulative) == series),
            ])
        }
        return Vectors(
            name: "reading-series",
            rule: "ReadingSeries(_:cumulative:): counters, readings, setAside, corrected, counterStarts, current, progress()",
            source: "ios/DosarCuSina/Services/History/Readings.swift",
            shape: "readings: a section's readings as kept (at, metric, startsCounter, isEstimate), cumulative whether they only go up. counters: each counter's readings that count; counted: all of them, the first of each later counter starting it; setAside, corrected: what is left out and the estimates a lower reading corrected; counterStarts: when each later counter starts; current: the value now; progress: distance and days counter by counter (days of 24 hours), or null. madeAgain: a series made again from its counted readings is the same.",
            cases: cases
        )
    }

    static func distances() -> Vectors {
        let d = { (day: String) in utc(day) }
        let inputs: [(String, [Point], [(String, Double, String, Double)])] = [
            ("a replaced dashboard", seriesInputs.first { $0.0 == "a replaced dashboard" }!.1, [
                (d("2026-02-01"), 101_000, d("2026-06-01"), 1_500), (d("2026-05-15"), 900, d("2026-06-01"), 1_500),
                (d("2026-01-01"), 100_000, d("2026-04-01"), 103_000), (d("2026-06-01"), 1_500, d("2026-05-15"), 900),
                (d("2025-12-01"), 99_000, d("2026-06-01"), 1_500),
            ]),
            ("three counters", seriesInputs.first { $0.0 == "three counters" }!.1, [
                (d("2025-02-01"), 10_500, d("2025-08-01"), 300), (d("2025-05-01"), 400, d("2025-09-01"), 505),
                (d("2025-01-01"), 10_000, d("2025-09-01"), 505),
            ]),
            ("one counter", [Point(at: d("2026-01-01"), metric: 1_000), Point(at: d("2026-02-01"), metric: 2_000)], [
                (d("2026-01-01"), 1_000, d("2026-02-01"), 2_000), (d("2026-02-01"), 2_000, d("2026-01-01"), 1_000),
            ]),
        ]
        var cases: [JSONValue] = []
        for (name, points, queries) in inputs {
            let series = ReadingSeries(points.map(\.reading))
            for (startAt, startMetric, endAt, endMetric) in queries {
                cases.append(.object([
                    "name": .string(name),
                    "readings": .array(points.map(\.json)),
                    "from": .object(["at": .string(startAt), "metric": .number(startMetric)]),
                    "to": .object(["at": .string(endAt), "metric": .number(endMetric)]),
                    "distance": .number(series.distance(from: (readingMoment(startAt), startMetric), to: (readingMoment(endAt), endMetric))),
                    "counterAtFrom": .int(series.counter(at: readingMoment(startAt))),
                    "counterAtTo": .int(series.counter(at: readingMoment(endAt))),
                ]))
            }
        }
        return Vectors(
            name: "reading-distance",
            rule: "ReadingSeries.distance(from:to:) and counter(at:)",
            source: "ios/DosarCuSina/Services/History/Readings.swift",
            shape: "readings: a section's readings as kept. from, to: a value at a moment. distance: how far the counter moved between them, counter by counter, never below zero. counterAtFrom, counterAtTo: the counter each moment belongs to.",
            cases: cases
        )
    }

    static func drops() -> Vectors {
        let d = { (day: String) in utc(day) }
        let gas = [Point(at: d("2026-06-05"), metric: 10_000), Point(at: d("2026-09-05"), metric: 10_300)]
        let short = [Point(at: d("2026-06-05"), metric: 10_000), Point(at: d("2026-07-05"), metric: 10_300)]
        let still = [Point(at: d("2026-01-05"), metric: 10_000), Point(at: d("2026-06-05"), metric: 10_000)]
        let inputs: [(Double, Double, [Point])] = [
            (99_999, 0, []), (10_300, 15, gas), (10_300, 103, gas), (10_300, 104, gas), (10_300, 10_150, gas),
            (10_300, 10_050, gas), (10_300, 9_700, gas), (10_300, 8_000, gas), (10_300, 9_103, gas),
            (10_300, 10_200, short), (10_000, 9_990, still), (10_300, 10_200, []),
            (103_000, 102_900, [Point(at: d("2026-01-10"), metric: 100_000), Point(at: d("2026-04-10"), metric: 103_000)]),
            (103_000, 80_000, [Point(at: d("2026-01-10"), metric: 100_000), Point(at: d("2026-04-10"), metric: 103_000)]),
        ]
        let cases: [JSONValue] = inputs.map { highest, value, points in
            .object([
                "highest": .number(highest),
                "value": .number(value),
                "readings": .array(points.map(\.json)),
                "size": .string("\(ReadingDrop(from: highest, to: value, series: ReadingSeries(points.map(\.reading))).size)"),
            ])
        }
        return Vectors(
            name: "reading-drop",
            rule: "ReadingDrop(from:to:series:).size",
            source: "ios/DosarCuSina/Services/History/Readings.swift",
            shape: "highest: the highest reading before, value: the lower one, readings: the counter's readings the drop is measured against. size: small, unsure or large.",
            cases: cases
        )
    }

    static func outliers() -> Vectors {
        let inputs: [[Double]] = [
            [45_724, 457], [45_000, 4_600_000, 47_000], [100, 1_000], [45_724, 4_572.4], [12_345, 123], [12_350, 124],
            [12_450, 125], [12_450, 124], [10, 5], [47_000, 470, 48_000], [1_000, 100_000, 1_200], [1_000, 50, 1_200],
            [0, 0, 0], [500, 50_000_000], [45_724], [],
        ]
        let cases: [JSONValue] = inputs.map { values in
            let verdicts = CounterOutliersStep.verdicts(values).sorted { $0.key < $1.key }.map { index, verdict -> JSONValue in
                switch verdict {
                case .correct(let to): .object(["index": .int(index), "correctTo": .number(to)])
                case .remove: .object(["index": .int(index), "remove": .bool(true)])
                }
            }
            return .object(["values": .array(values.map { .number($0) }), "verdicts": .array(verdicts)])
        }
        return Vectors(
            name: "counter-outliers",
            rule: "CounterOutliersStep.verdicts(_:) and lostDigits(_:of:)",
            source: "ios/DosarCuSina/Services/Repairs/DataRepairSteps.swift",
            shape: "values: one counter's readings, oldest first. verdicts: by place, a value to correct it to (it lost its last digits) or that it goes (ten times off both neighbours).",
            cases: cases
        )
    }

    // MARK: Recording

    /// A reading a section keeps, in a case.
    struct Log {
        let key: Int
        let at: String
        let value: Double
        var unit = "km"
        var kind = "odometer"
        var starts = false
        var basis: String?

        var json: JSONValue {
            .object([
                "key": .int(key), "at": .string(at), "value": .number(value), "unit": .string(unit), "kind": .string(kind),
                "startsCounter": .bool(starts), "basis": basis.map { .string($0) } ?? .null,
            ])
        }
    }

    /// A reading a step plans: its value, or the text it is typed as with the number's kind.
    struct Planned {
        var value: Double?
        var typed: String?
        var numberKind: NumberKind = .kilometres
        let at: String
        var source: ReadingSource = .person
        var unit: String? = "km"
        var kind: String?
        var basis: String?
        var replaces: [Int] = []

        var json: JSONValue {
            .object([
                "value": value.map { .number($0) } ?? .null,
                "typed": typed.map { .string($0) } ?? .null,
                "numberKind": .string("\(numberKind)"),
                "at": .string(at),
                "source": .string("\(source)"),
                "unit": unit.map { .string($0) } ?? .null,
                "kind": kind.map { .string($0) } ?? .null,
                "basis": basis.map { .string($0) } ?? .null,
                "replaces": .array(replaces.map { .int($0) }),
            ])
        }

        var number: Double? {
            if let value { return value }
            guard let typed, let read = RomanianNumber.value(typed, as: numberKind) else { return nil }
            return NSDecimalNumber(decimal: read).doubleValue
        }
    }

    static let recordingInputs: [(String, [Log], Planned)] = {
        let d = { (day: String) in utc(day) }
        let gas = { (key: Int, day: String, value: Double, basis: String?) in
            Log(key: key, at: d(day), value: value, unit: "m3", kind: "gas", basis: basis)
        }
        let summer = [gas(1, "2026-06-05", 10_000, "read"), gas(2, "2026-07-05", 10_100, "estimated"),
                      gas(3, "2026-08-05", 10_200, "estimated"), gas(4, "2026-09-05", 10_300, "estimated")]
        let gasBill = { (day: String, value: Double, basis: String?) in
            Planned(value: value, at: d(day), source: .document, unit: "m3", kind: "gas", basis: basis)
        }
        let golf = [Log(key: 1, at: d("2026-01-10"), value: 45_724, basis: "read")]
        let replaced = [Log(key: 1, at: d("2026-01-10"), value: 145_000, basis: "read"),
                        Log(key: 2, at: d("2026-03-01"), value: 1_200, starts: true, basis: "read"),
                        Log(key: 3, at: d("2026-04-01"), value: 2_500, basis: "read")]
        let tractor = [Log(key: 1, at: d("2026-01-10"), value: 5_000, basis: "read"),
                       Log(key: 2, at: d("2026-02-10"), value: 300, unit: "h", kind: "engineHours", basis: "read")]
        return [
            ("a car's typo", golf, Planned(value: 4_572, at: d("2026-03-01"))),
            ("a car's dashboard replaced", [Log(key: 1, at: d("2026-01-10"), value: 145_000)], Planned(value: 1_200, at: d("2026-03-01"))),
            ("a car's small drop", [Log(key: 1, at: d("2026-01-10"), value: 100_000, basis: "read"), Log(key: 2, at: d("2026-04-10"), value: 103_000, basis: "read")],
             Planned(value: 102_900, at: d("2026-05-10"))),
            ("a car's drop of more than a year", [Log(key: 1, at: d("2026-01-10"), value: 100_000, basis: "read"), Log(key: 2, at: d("2026-04-10"), value: 103_000, basis: "read")],
             Planned(value: 80_000, at: d("2026-05-10"))),
            ("a lower reading on the new counter", replaced, Planned(value: 2_000, at: d("2026-05-01"))),
            ("a higher reading on the new counter", replaced, Planned(value: 2_900, at: d("2026-05-01"))),
            ("an older document never lowers the counter", golf, Planned(value: 40_000, at: d("2025-06-02"), source: .document)),
            ("an older document on the old counter", [Log(key: 1, at: d("2026-01-10"), value: 140_000), Log(key: 2, at: d("2026-03-01"), value: 1_200, starts: true)],
             Planned(value: 142_000, at: d("2026-02-01"), source: .document)),
            ("correcting a typo on the new counter", [Log(key: 1, at: d("2026-01-10"), value: 145_000), Log(key: 2, at: d("2026-03-01"), value: 12_000, starts: true)],
             Planned(value: 1_200, at: d("2026-03-02"))),
            ("filing the new counter's paper again", [Log(key: 1, at: d("2026-01-10"), value: 145_000), Log(key: 2, at: d("2026-03-01"), value: 1_200, starts: true)],
             Planned(value: 1_250, at: d("2026-03-01"), source: .document, replaces: [2])),
            ("a counter that went round", [Log(key: 1, at: d("2025-01-01"), value: 99_990), Log(key: 2, at: d("2025-12-01"), value: 99_999)],
             Planned(value: 5, at: d("2026-01-15"))),
            ("a regularisation below the estimates", summer, gasBill("2026-10-05", 10_150, "read")),
            ("a new gas meter", summer, gasBill("2026-10-05", 15, "read")),
            ("a gas drop of more than a year", [gas(1, "2026-06-05", 10_000, nil), gas(2, "2026-09-05", 10_300, nil)], gasBill("2026-10-05", 8_000, nil)),
            ("below a reading not known as an estimate", [gas(1, "2026-06-05", 10_000, nil), gas(2, "2026-09-05", 10_300, nil)], gasBill("2026-10-05", 10_050, nil)),
            ("an estimate far above the real index", [gas(1, "2026-01-05", 10_000, "read"), gas(2, "2026-07-05", 10_600, "read"), gas(3, "2026-10-05", 13_000, "estimated")],
             gasBill("2026-11-05", 10_700, "read")),
            ("after a regularisation the next bill", summer + [gas(5, "2026-10-05", 10_150, "read")], gasBill("2026-11-05", 10_250, nil)),
            ("below a corrected estimate", summer + [gas(5, "2026-10-05", 10_150, "read")], gasBill("2026-11-05", 10_120, nil)),
            ("engine hours apart from kilometres", tractor, Planned(value: 250, at: d("2026-03-10"), unit: "h", kind: "engineHours")),
            ("engine hours below the kilometres", tractor, Planned(value: 400, at: d("2026-03-10"), unit: "h", kind: "engineHours")),
            ("kilometres below the kilometres beside engine hours", tractor, Planned(value: 4_900, at: d("2026-03-10"))),
            ("the same moment", [Log(key: 1, at: d("2026-03-01"), value: 10_000), Log(key: 2, at: d("2026-03-01"), value: 10_050)], Planned(value: 10_020, at: d("2026-03-01"))),
            ("the same day, earlier", [Log(key: 1, at: d("2026-03-01"), value: 10_000), Log(key: 2, at: d("2026-03-01"), value: 10_050)],
             Planned(value: 10_020, at: utc("2026-03-01", "08:00:00"))),
            ("typed with a thousands dot", golf, Planned(typed: "45.724", at: d("2026-03-01"))),
            ("typed with a thousands comma", golf, Planned(typed: "45,724 km", at: d("2026-03-01"))),
            ("typed a tenth", golf, Planned(typed: "4.572", at: d("2026-03-01"))),
            ("typed an index with decimals", [gas(1, "2026-06-05", 1_300, nil)],
             Planned(typed: "1.234,5", numberKind: .meterIndex, at: d("2026-07-05"), unit: "m3", kind: "gas")),
            ("an estimate is never stored", golf, Planned(value: 46_000, at: d("2026-03-01"), source: .estimate)),
            ("a person's reading is read", golf, Planned(value: 46_000, at: d("2026-03-01"), basis: "estimated")),
            ("a weight only goes where it goes", [Log(key: 1, at: d("2026-01-10"), value: 80, unit: "kg", kind: "bodyWeight")],
             Planned(value: 75, at: d("2026-03-01"), unit: "kg", kind: "bodyWeight")),
            ("a kind from its unit", [Log(key: 1, at: d("2026-01-10"), value: 900, unit: "kwh", kind: "electricity")],
             Planned(value: 850, at: d("2026-03-01"), source: .document, unit: "kwh")),
        ]
    }()

    /// The section a case keeps: one of no category, so the hero value is no part of it.
    static func section(_ logs: [Log], in context: ModelContext) -> (Asset, [Int: MeasurementLog]) {
        let asset = Asset(name: "Secțiune Exemplu", templateKey: "test.readings")
        context.insert(asset)
        var byKey: [Int: MeasurementLog] = [:]
        for log in logs {
            let kept = MeasurementLog(kind: MeasurementKind(rawValue: log.kind) ?? .custom, name: "", value: log.value,
                                      unit: MeasurementUnit(log.unit), recordedAt: readingMoment(log.at))
            kept.startsCounter = log.starts
            kept.basisRaw = log.basis
            context.insert(kept)
            kept.asset = asset
            byKey[log.key] = kept
        }
        return (asset, byKey)
    }

    /// The section's readings after a step, by key ("new" for the one it recorded), each as kept.
    static func after(_ asset: Asset, byKey: [Int: MeasurementLog], new: MeasurementLog?, names: [Date: String]) -> JSONValue {
        let keys = Dictionary(byKey.map { ($0.value.id, $0.key) }, uniquingKeysWith: { first, _ in first })
        let logs = (asset.measurements ?? []).filter { !$0.isDeleted }
        let rows: [(String, MeasurementLog)] = logs.map { log in
            (log.id == new?.id ? "new" : keys[log.id].map(String.init) ?? "?", log)
        }
        return .array(rows.sorted { $0.0.localizedStandardCompare($1.0) == .orderedAscending }.map { key, log in
            .object([
                "key": .string(key), "at": .string(names[log.recordedAt] ?? "?"), "value": .number(log.value),
                "unit": .string(log.unit), "kind": .string(log.kindRaw), "startsCounter": .bool(log.startsCounter),
                "basis": log.basisRaw.map { .string($0) } ?? .null,
            ])
        })
    }

    static func question(_ question: LowerReadingQuestion?, names: [Date: String]) -> JSONValue {
        guard let question else { return .null }
        return .object([
            "previous": .number(question.previous),
            "previousAt": .string(names[question.previousDate] ?? "?"),
            "value": .number(question.value),
            "unit": question.unit.map { .string($0.key) } ?? .null,
            "answers": .array(question.answers.map { .string("\($0)") }),
        ])
    }

    static func recording() throws -> Vectors {
        var cases: [JSONValue] = []
        for (name, logs, planned) in recordingInputs {
            var names = Dictionary(logs.map { (readingMoment($0.at), $0.at) }, uniquingKeysWith: { first, _ in first })
            names[readingMoment(planned.at)] = names[readingMoment(planned.at)] ?? planned.at
            // What the step asks, with no answer.
            let asked: LowerReadingQuestion? = try {
                let context = try makeContext()
                let (asset, byKey) = section(logs, in: context)
                let reading = plan(planned, on: asset, byKey: byKey)
                do {
                    try HouseholdMutations.askAboutReading(reading, answer: nil)
                    return nil
                } catch let question as LowerReadingQuestion {
                    return question
                }
            }()
            // What recording does with each answer the question offers, or with none when it asks nothing.
            let answers: [LowerReadingAnswer?] = asked.map { $0.answers.map { Optional($0) } } ?? [nil]
            var outcomes: [JSONValue] = []
            for answer in answers {
                let context = try makeContext()
                let (asset, byKey) = section(logs, in: context)
                let reading = plan(planned, on: asset, byKey: byKey)
                let new = try reading.map { try HouseholdMutations.recordReading($0, answer: answer, in: context) } ?? nil
                let series = HouseholdMutations.readingSeries(of: asset, unit: reading?.unit)
                outcomes.append(.object([
                    "answer": answer.map { .string("\($0)") } ?? .null,
                    "recorded": .bool(new != nil),
                    "after": after(asset, byKey: byKey, new: new, names: names),
                    "current": series.current.map { .number($0) } ?? .null,
                    "setAside": .array(series.setAside.map { .number($0.metric) }),
                    "counterStart": HouseholdMutations.counterStart(of: asset, unit: reading?.unit).map { .number($0.value) } ?? .null,
                ]))
            }
            let context = try makeContext()
            let (asset, byKey) = section(logs, in: context)
            let reading = plan(planned, on: asset, byKey: byKey)
            cases.append(.object([
                "name": .string(name),
                "readings": .array(logs.map(\.json)),
                "planned": planned.json,
                "plannedAs": reading.map { reading in
                    .object([
                        "value": .number(reading.value), "unit": reading.unit.map { .string($0.key) } ?? .null,
                        "kind": .string(reading.kind.rawValue), "basis": reading.basis.map { .string($0.rawValue) } ?? .null,
                        "isStored": .bool(reading.isStored), "continuesCounter": .bool(reading.continuesCounter),
                    ])
                } ?? .null,
                "question": question(asked, names: names),
                "outcomes": .array(outcomes),
            ]))
        }
        return Vectors(
            name: "recording",
            rule: "PlannedReading, HouseholdMutations.askAboutReading(_:answer:) and recordReading(_:answer:in:), readingSeries(of:unit:), counterStart(of:unit:)",
            source: "ios/DosarCuSina/Services/History/Readings.swift",
            shape: "readings: a section's readings, each by a key (at, value, unit key, kind, startsCounter, basis). planned: the reading a step plans (its value, or typed text read as numberKind; at; source; unit key, kind and basis when given; the keys of readings it replaces). plannedAs: what the plan makes of it, null when typed text isn't a number. question: what recording it asks with no answer (the highest reading before and when, the new value and unit, the answers offered), or null. outcomes: for each answer offered (or none, when it asks nothing), whether a reading was recorded, the section's readings after it by key (\"new\" for the one recorded), the series' value now, what it sets aside, and the value that started the counter in use.",
            cases: cases
        )
    }

    static func plan(_ planned: Planned, on asset: Asset, byKey: [Int: MeasurementLog]) -> PlannedReading? {
        guard let value = planned.number else { return nil }
        let replaced = Set(planned.replaces.compactMap { byKey[$0]?.id })
        return PlannedReading(value, on: asset, at: readingMoment(planned.at), source: planned.source, unit: planned.unit.flatMap(MeasurementUnit.init),
                              kind: planned.kind.flatMap(MeasurementKind.init(rawValue:)), basis: planned.basis.flatMap(ReadingBasis.init(rawValue:)),
                              replacing: { replaced.contains($0.id) })
    }

    // MARK: Taking a reading away

    static func deleting() throws -> Vectors {
        let d = { (day: String) in utc(day) }
        let counter = [Log(key: 1, at: d("2026-01-10"), value: 145_000), Log(key: 2, at: d("2026-03-01"), value: 1_200, starts: true),
                       Log(key: 3, at: d("2026-04-01"), value: 2_500), Log(key: 4, at: d("2026-05-01"), value: 3_100)]
        let inputs: [(String, [Log], Int)] = [
            ("the first of a new counter hands it on", counter, 2),
            ("a reading after the start", counter, 3),
            ("the old counter's reading", counter, 1),
            ("a new counter with one reading", Array(counter.prefix(2)), 2),
            ("a second new counter", counter + [Log(key: 5, at: d("2026-06-01"), value: 10, starts: true), Log(key: 6, at: d("2026-07-01"), value: 700)], 5),
            ("another unit's reading stays", counter + [Log(key: 5, at: d("2026-03-15"), value: 40, unit: "h", kind: "engineHours")], 2),
        ]
        var cases: [JSONValue] = []
        for (name, logs, key) in inputs {
            let context = try makeContext()
            let (asset, byKey) = section(logs, in: context)
            if let log = byKey[key] { HouseholdMutations.deleteReading(log, in: context) }
            let names = Dictionary(logs.map { (readingMoment($0.at), $0.at) }, uniquingKeysWith: { first, _ in first })
            cases.append(.object([
                "name": .string(name),
                "readings": .array(logs.map(\.json)),
                "delete": .int(key),
                "after": after(asset, byKey: byKey, new: nil, names: names),
            ]))
        }
        return Vectors(
            name: "deleting",
            rule: "HouseholdMutations.deleteReading(_:in:)",
            source: "ios/DosarCuSina/Services/History/Readings.swift",
            shape: "readings: a section's readings by key. delete: the key of the one that goes. after: the readings left by key, a counter the deleted one started handed on to the next of its counter.",
            cases: cases
        )
    }
}
