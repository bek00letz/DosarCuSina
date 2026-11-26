import Foundation
import Testing
@testable import DosarCuSina

/// The value rules every `.dosar` record depends on (days, moments, machine JSON, Romanian
/// numbers, money's stored form, units, and values a newer version wrote kept raw), run over a
/// wide set of inputs and written to `shared/test-vectors/values/`, one file per rule: each
/// input with the answer this app gives, refusals included. The Android app's tests read the
/// same files and must give the same answers (docs/ANDROID_PLAN.md, "How parity is kept"), so
/// iOS stays the source of truth. The files are committed; this test fails when one is out of
/// date, as `CopyMatrixTests` does for docs/COPY_MATRIX.md. Placeholder data only.
@Suite("Value vectors")
struct ValueVectorsTests {
    /// The committed vectors.
    static var folder: URL {
        URL(filePath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appending(path: "shared/test-vectors/values")
    }

    /// How to bring the files up to date, said when one isn't.
    static let regenerate = """
    is out of date with the value rules. Bring shared/test-vectors/values up to date: \
    TEST_RUNNER_VALUE_VECTORS_WRITE=1 ./tests/run_tests.sh (or run ValueVectorsTests in Xcode with \
    VALUE_VECTORS_WRITE=1 in the scheme's environment), review the diff and commit it, then run \
    the Android tests (./gradlew :core:test in android/), which read the same files.
    """

    /// One file: the rule it pins, where the rule lives, what a case holds, and the cases.
    struct Vectors {
        let name: String
        let rule: String
        let source: String
        let shape: String
        let cases: [JSONValue]
    }

    @Test("shared/test-vectors/values is up to date with the value rules")
    func vectorsAreUpToDate() throws {
        let files = try Self.all()
        let writes = ProcessInfo.processInfo.environment["VALUE_VECTORS_WRITE"] == "1"
        let manager = FileManager.default
        if writes { try manager.createDirectory(at: Self.folder, withIntermediateDirectories: true) }
        for file in files {
            let url = Self.folder.appending(path: "\(file.name).json")
            let fresh = try Self.render(file)
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
        try [
            calendarDayParsing(), calendarDayValidity(), calendarDayMonths(), calendarDayDays(),
            calendarDayOrder(), monthDays(), appCalendar(), machineText(), machineMoments(),
            machineMomentWriting(), machineJSON(), jsonNumbers(), jsonDoubles(), jsonLaying(),
            jsonMappingKept(), threeWay(), keptLists(), keptObjects(),
            romanianNumberReading(), romanianNumberCanonical(), romanianNumberFormat(),
            money(), measurementUnits(), romanianTextFold(),
        ]
    }

    static func render(_ file: Vectors) throws -> String {
        let document: JSONValue = .object([
            "rule": .string(file.rule),
            "source": .string(file.source),
            "shape": .string(file.shape),
            "writtenBy": "ios/DosarCuSinaTests/ValueVectorsTests.swift",
            "cases": .array(file.cases),
        ])
        return String(decoding: try MachineText.jsonEncoder(.readable).encode(document), as: UTF8.self) + "\n"
    }

    // MARK: Helpers

    struct NotJSON: Error { let text: String }

    /// JSON text as this app reads it into a `JSONValue`.
    static func json(_ text: String) throws -> JSONValue {
        guard let value = try? JSONDecoder().decode(JSONValue.self, from: Data(text.utf8)) else { throw NotJSON(text: text) }
        return value
    }

    /// A value written as compact machine JSON.
    static func compact<Value: Encodable>(_ value: Value) throws -> String {
        String(decoding: try MachineText.jsonEncoder(.compact).encode(value), as: UTF8.self)
    }

    static func iso(_ day: CalendarDay?) -> JSONValue { day.map { JSONValue.string($0.isoString) } ?? .null }

    static func day(_ text: String) -> CalendarDay {
        guard let day = CalendarDay(isoString: text) else {
            Issue.record("Not a day: \(text)")
            return .earliest
        }
        return day
    }

    static func zone(_ identifier: String) -> TimeZone {
        guard let zone = TimeZone(identifier: identifier) else {
            Issue.record("No time zone \(identifier)")
            return .gmt
        }
        return zone
    }

    /// The time zones a day's arithmetic must not depend on: where the phone is never changes
    /// which day a day plus a month is. Among them, zones whose clocks skip midnight
    /// (São Paulo in 2018) or a whole day (Apia in 2011).
    static let zones = ["UTC", "Europe/Bucharest", "America/Sao_Paulo", "Pacific/Apia", "Asia/Kolkata", "America/St_Johns"].map(ValueVectorsTests.zone)

    /// The one answer `work` gives in every zone, recorded as an issue when two disagree.
    static func sameEverywhere(_ what: String, _ work: (Calendar) -> String) -> String {
        let answers = zones.map { work(.dosar(in: $0)) }
        #expect(Set(answers).count == 1, "\(what) depends on the time zone: \(answers)")
        return answers[0]
    }

    // MARK: Days

    static func calendarDayParsing() -> Vectors {
        let inputs = [
            "2026-11-25", "2026-02-28", "2026-02-29", "2024-02-29", "1999-02-29", "2026-02-30", "2026-02-31",
            "2026-04-31", "2026-06-31", "2567-02-29", "2026-1-5", "2026-01-5", "0001-01-01", "0000-01-01",
            "9999-12-31", "999999-1-1", "+2026-01-01", "2026-+1-+1", "-2026-01-01", "-202-01-01", "2026--11-25",
            "2026-11-25T08:00:00Z", "2026-11-25T08:00:00+02:00", "2026-11-25 and more", "2026-12-31x",
            "2026-11-2", "2026/11/25", "20261125", "2026-13-01", "2026-00-10", "2026-12-00", "2026-12-32",
            " 2026-11-25", "2026-11-25 ", "", "2026", "2026-11", "2026-11-25-01",
            "\u{0662}\u{0660}\u{0662}\u{0666}-\u{0661}\u{0661}-\u{0662}\u{0665}", "\u{FF12}\u{FF10}\u{FF12}\u{FF16}-11-25",
            "2026-11-2\u{0301}5", "2026-11-\u{0301}25", "2026-07-04\n",
        ]
        let cases: [JSONValue] = inputs.map { raw in
            let day = CalendarDay(isoString: raw)
            return .object([
                "input": .string(raw),
                "day": day.map { JSONValue.array([.int($0.year), .int($0.month), .int($0.day)]) } ?? .null,
                "written": iso(day),
                "isOnCalendar": day.map { JSONValue.bool($0.isOnCalendar) } ?? .null,
                "onCalendar": iso(day?.onCalendar),
                "storedDay": iso(StoredDay.day(raw)),
            ])
        }
        return Vectors(
            name: "calendar-day-parse",
            rule: "CalendarDay(isoString:), isoString, isOnCalendar, onCalendar; StoredDay.day(_:)",
            source: "ios/Shared/CalendarDay.swift, ios/DosarCuSina/Models/Values/StoredDay.swift",
            shape: "input: text. day: [year, month, day] as read (numbers kept as written), or null when refused. written: its ISO text. isOnCalendar, onCalendar: whether the calendar has it, and the day it has (its month's last day for one past it). storedDay: what the database reads from the same text (ten characters only).",
            cases: cases
        )
    }

    static func calendarDayValidity() -> Vectors {
        let inputs: [(Int, Int, Int)] = [
            (2026, 2, 28), (2026, 2, 29), (2024, 2, 29), (1900, 2, 29), (2000, 2, 29), (2100, 2, 29), (1600, 2, 29),
            (1700, 2, 29), (2026, 4, 30), (2026, 4, 31), (2026, 6, 31), (2026, 12, 31), (2026, 1, 31), (2026, 13, 1),
            (2026, 0, 1), (2026, 1, 0), (2026, 1, -1), (2026, 1, 32), (2026, -1, 10), (9999, 12, 31), (10000, 2, 29),
            (2028, 2, 29), (2027, 2, 29),
        ]
        let cases: [JSONValue] = inputs.map { year, month, day in
            .object([
                "input": .array([.int(year), .int(month), .int(day)]),
                "day": iso(CalendarDay(validYear: year, month: month, day: day)),
            ])
        }
        return Vectors(
            name: "calendar-day-valid",
            rule: "CalendarDay(validYear:month:day:)",
            source: "ios/Shared/CalendarDay.swift",
            shape: "input: [year, month, day]. day: the day's ISO text, or null when the Gregorian calendar has no such day.",
            cases: cases
        )
    }

    static func calendarDayMonths() -> Vectors {
        var cases: [JSONValue] = []
        let moves: [(String, Int, Int?)] = [
            ("2026-01-31", 1, nil), ("2024-01-31", 1, nil), ("2024-02-29", 12, nil), ("2024-02-29", 48, nil),
            ("2026-03-31", -1, nil), ("2024-03-31", -1, nil), ("2026-02-28", 1, 31), ("2026-02-28", 2, 31),
            ("2026-12-31", 1, nil), ("2026-01-15", -13, nil), ("2026-05-31", 0, nil), ("2026-05-10", 0, 31),
            ("2026-02-10", 0, 31), ("2026-02-10", 0, 29), ("2024-02-10", 0, 30), ("2026-02-10", 0, 0),
            ("2026-02-10", 0, -5), ("2026-01-31", 1200, nil), ("2026-02-30", 1, nil), ("2026-02-31", 0, nil),
            ("2026-04-31", 0, nil), ("1900-01-31", 1, nil), ("2000-01-31", 1, nil), ("2026-08-31", 6, nil),
            ("2026-10-31", 1, nil), ("2026-01-31", -4000, nil), ("2026-11-25", 1, 40), ("2026-11-25", -11, nil),
            ("2026-11-25", 12, nil), ("2026-11-25", -12, nil), ("2026-11-25", 24, 31), ("2027-02-28", 12, 29),
        ]
        for (start, months, dayOfMonth) in moves {
            let from = day(start)
            let moved = sameEverywhere("\(start) + \(months) months") { from.adding(months: months, dayOfMonth: dayOfMonth, calendar: $0).isoString }
            cases.append(.object([
                "start": .string(start), "months": .int(months), "dayOfMonth": dayOfMonth.map(JSONValue.int) ?? .null,
                "day": .string(moved),
            ]))
        }
        // A monthly series on the 31st, each month from its first day: the series keeps its day.
        var series = day("2026-01-31")
        for _ in 1...14 {
            let next = series.adding(months: 1, dayOfMonth: 31, calendar: .dosar(in: zone("UTC")))
            cases.append(.object([
                "start": .string(series.isoString), "months": .int(1), "dayOfMonth": .int(31), "day": .string(next.isoString),
            ]))
            series = next
        }
        // How long each month is.
        var lengths: [JSONValue] = []
        var measured: [(Int, Int)] = (1...12).map { (2026, $0) }
        measured += (1...12).map { (2024, $0) }
        measured += [(1600, 2), (1700, 2), (1900, 2), (2000, 2), (2100, 2), (2400, 2), (2026, 13), (2026, 0)]
        for (year, month) in measured {
            let length = sameEverywhere("days in \(year)-\(month)") { "\(CalendarDay(year: year, month: month, day: 1).daysInMonth(calendar: $0))" }
            lengths.append(.object(["year": .int(year), "month": .int(month), "daysInMonth": .int(Int(length) ?? 0)]))
        }
        cases.append(.object(["daysInMonth": .array(lengths)]))
        return Vectors(
            name: "calendar-day-months",
            rule: "CalendarDay.adding(months:dayOfMonth:), daysInMonth",
            source: "ios/Shared/CalendarDay.swift",
            shape: "start + months (dayOfMonth: the day a series keeps, or null for the start's own) = day, clamped to the month's last day. The last case lists daysInMonth for [year, month] (month 13 and 0 are the next and previous year's).",
            cases: cases
        )
    }

    static func calendarDayDays() -> Vectors {
        var cases: [JSONValue] = []
        let moves: [(String, Int)] = [
            ("2026-12-31", 1), ("2026-02-28", 1), ("2024-02-28", 1), ("2024-02-28", 2), ("2026-03-01", -1),
            ("2024-03-01", -1), ("2026-02-30", 0), ("2026-02-30", 1), ("2026-04-31", 0), ("2026-03-29", 1),
            ("2026-10-25", 1), ("2026-01-01", 365), ("2024-01-01", 366), ("2026-01-01", -36500),
            ("2026-11-25", 100_000), ("2026-11-25", -7), ("2026-06-31", 1),
        ]
        for (start, days) in moves {
            let from = day(start)
            let moved = sameEverywhere("\(start) + \(days) days") { from.adding(days: days, calendar: $0).isoString }
            cases.append(.object(["start": .string(start), "addDays": .int(days), "day": .string(moved)]))
        }
        let spans: [(String, String)] = [
            ("2026-01-01", "2026-12-31"), ("2026-12-31", "2026-01-01"), ("2024-02-28", "2024-03-01"),
            ("2026-03-28", "2026-03-30"), ("2026-10-24", "2026-10-26"), ("2026-02-30", "2026-03-01"),
            ("2026-11-25", "2026-11-25"), ("1900-01-01", "2100-01-01"), ("2026-02-31", "2026-02-28"),
        ]
        for (from, to) in spans {
            let start = day(from), end = day(to)
            let count = sameEverywhere("\(from) to \(to)") { "\(start.days(to: end, calendar: $0))" }
            cases.append(.object(["start": .string(from), "end": .string(to), "days": .int(Int(count) ?? 0)]))
        }
        return Vectors(
            name: "calendar-day-days",
            rule: "CalendarDay.adding(days:), days(to:)",
            source: "ios/Shared/CalendarDay.swift",
            shape: "start + addDays = day; or start, end: days from one to the other (negative when end is earlier). A day the calendar doesn't have counts as its month's last day.",
            cases: cases
        )
    }

    static func calendarDayOrder() -> Vectors {
        let days = ["2026-11-25", "2026-02-30", "2026-03-01", "2026-02-28", "0000-01-01", "2025-12-31", "2026-11-24", "2026-11-25", "9999-12-31", "2026-12-01"]
        let sorted = days.map(day).sorted()
        let pairs: [(String, String)] = [("2026-02-30", "2026-03-01"), ("2026-02-30", "2026-02-28"), ("2026-11-25", "2026-11-25"), ("2025-12-31", "2026-01-01")]
        var cases: [JSONValue] = [.object(["days": .array(days.map(JSONValue.string)), "sorted": .array(sorted.map { JSONValue.string($0.isoString) })])]
        for (left, right) in pairs {
            cases.append(.object([
                "left": .string(left), "right": .string(right),
                "isBefore": .bool(day(left) < day(right)), "isEqual": .bool(day(left) == day(right)),
            ]))
        }
        cases.append(.object(["earliest": .string(CalendarDay.earliest.isoString)]))
        return Vectors(
            name: "calendar-day-order",
            rule: "CalendarDay's order (Comparable), equality and earliest",
            source: "ios/Shared/CalendarDay.swift",
            shape: "days: sorted; or left, right: isBefore and isEqual (by year, then month, then day, as written); or earliest: what a missing day sorts as.",
            cases: cases
        )
    }

    static func monthDays() -> Vectors {
        var cases: [JSONValue] = []
        for raw in ["03-31", "3-1", "12-31", "13-01", "02-30", "02-29", "00-10", "01-00", "01-32", "-03-31", "03-31-", "0331", "03-31-2026", "", "+3-+1", " 03-31", "03--31"] {
            let read = MonthDay(isoString: raw)
            cases.append(.object(["input": .string(raw), "monthDay": read.map { JSONValue.string($0.isoString) } ?? .null]))
        }
        let years: [(String, Int)] = [("02-29", 2027), ("02-29", 2028), ("02-29", 1900), ("12-31", 2026), ("04-31", 2026), ("02-30", 2024), ("01-01", 2026)]
        for (raw, year) in years {
            guard let read = MonthDay(isoString: raw) else { continue }
            let found = sameEverywhere("\(raw) in \(year)") { read.day(inYear: year, calendar: $0).isoString }
            cases.append(.object(["monthDay": .string(raw), "year": .int(year), "day": .string(found)]))
        }
        return Vectors(
            name: "month-day",
            rule: "MonthDay(isoString:), isoString, day(inYear:)",
            source: "ios/Shared/CalendarDay.swift",
            shape: "input: text, monthDay: its MM-dd text or null when refused; or monthDay, year: the day it is that year (clamped to the month's last day).",
            cases: cases
        )
    }

    /// The app's calendar: Gregorian, Romanian, weeks from Monday, in a time zone.
    static func appCalendar() -> Vectors {
        let calendar = Calendar.dosar(in: zone("UTC"))
        var cases: [JSONValue] = [.object([
            "identifier": .string(calendar.identifier == .gregorian ? "gregorian" : "\(calendar.identifier)"),
            "locale": .string(calendar.locale?.identifier ?? ""),
            "firstWeekday": .int(calendar.firstWeekday),
            "minimumDaysInFirstWeek": .int(calendar.minimumDaysInFirstWeek),
            "followsThePhonesTimeZone": .bool(Calendar.dosar.timeZone == TimeZone.current),
        ])]
        // Weeks: weekday (1 is Sunday, 2 Monday… as Foundation counts), week of the year.
        for raw in ["2026-01-01", "2026-01-04", "2026-01-05", "2026-11-25", "2026-12-31", "2027-01-01", "2027-01-03", "2027-01-04", "2024-12-30", "2021-01-03"] {
            let date = day(raw).startDate(in: calendar)
            cases.append(.object([
                "week": .string(raw),
                "weekday": .int(calendar.component(.weekday, from: date)),
                "weekOfYear": .int(calendar.component(.weekOfYear, from: date)),
                "yearForWeekOfYear": .int(calendar.component(.yearForWeekOfYear, from: date)),
            ]))
        }
        // The day a moment falls on, where the phone is.
        let moments: [(Int, String)] = [
            (1_793_606_400, "UTC"), (1_793_606_400, "Pacific/Kiritimati"), (1_793_606_400, "Pacific/Pago_Pago"),
            (1_795_651_199, "Europe/Bucharest"), (1_795_644_000, "Europe/Bucharest"), (1_795_643_999, "Europe/Bucharest"),
            (1_325_239_200, "Pacific/Apia"), (1_541_300_400, "America/Sao_Paulo"), (0, "America/New_York"),
            (-1, "UTC"), (1_774_746_000, "Europe/Bucharest"), (1_793_606_400, "Australia/Lord_Howe"),
        ]
        for (seconds, zoneName) in moments {
            let found = CalendarDay(Date(timeIntervalSince1970: TimeInterval(seconds)), calendar: .dosar(in: zone(zoneName)))
            cases.append(.object(["moment": .int(seconds), "zone": .string(zoneName), "day": .string(found.isoString)]))
        }
        // When a day starts, and a time of day on it, by the clock on the wall.
        let starts: [(String, Int, String)] = [
            ("2026-11-25", 0, "Europe/Bucharest"), ("2026-11-25", 540, "Europe/Bucharest"), ("2026-03-29", 210, "Europe/Bucharest"),
            ("2026-03-29", 180, "Europe/Bucharest"), ("2026-03-29", 240, "Europe/Bucharest"), ("2026-10-25", 210, "Europe/Bucharest"),
            ("2026-10-25", 0, "Europe/Bucharest"), ("2018-11-04", 0, "America/Sao_Paulo"), ("2018-11-04", 30, "America/Sao_Paulo"),
            ("2018-11-04", 60, "America/Sao_Paulo"), ("2011-12-30", 0, "Pacific/Apia"), ("2011-12-31", 0, "Pacific/Apia"),
            ("2026-02-30", 600, "UTC"), ("2026-04-31", 0, "Asia/Kolkata"), ("2026-10-04", 120, "Australia/Lord_Howe"),
            ("2026-11-25", 1439, "Pacific/Kiritimati"), ("2026-03-08", 150, "America/New_York"), ("2026-11-01", 90, "America/New_York"),
        ]
        for (raw, minute, zoneName) in starts {
            let moment = day(raw).moment(atMinute: minute, in: .dosar(in: zone(zoneName)))
            cases.append(.object([
                "start": .string(raw), "minute": .int(minute), "zone": .string(zoneName),
                "moment": .int(Int(moment.timeIntervalSince1970.rounded())),
            ]))
        }
        return Vectors(
            name: "app-calendar",
            rule: "Calendar.dosar and Calendar.dosar(in:); CalendarDay(_:calendar:), moment(atMinute:in:) and startDate(in:)",
            source: "ios/Shared/DosarCalendar.swift, ios/Shared/CalendarDay.swift",
            shape: "The first case says what the calendar is. week: weekday (Foundation's, 1 is Sunday), weekOfYear and yearForWeekOfYear. moment (seconds since 1970) in zone: the day it falls on. start, minute (after midnight), zone: the moment (seconds since 1970) the wall clock shows that time; a time the clocks skip is the first minute after the gap, a time shown twice the first of the two; minute 0 is the start of the day.",
            cases: cases
        )
    }

    // MARK: Machine text

    static func machineText() -> Vectors {
        var cases: [JSONValue] = []
        for (number, width) in [(7, 2), (12_345, 4), (0, 4), (-5, 4), (2026, 4), (5, 0), (42, 6)] {
            cases.append(.object(["padded": .array([.int(number), .int(width)]), "text": .string(MachineText.padded(number, to: width))]))
        }
        for (year, month, day) in [(2031, 3, 2), (987, 12, 31), (1, 1, 1), (12_345, 6, 7), (-1, 1, 1), (2026, 13, 40)] {
            cases.append(.object(["isoDay": .array([.int(year), .int(month), .int(day)]), "text": .string(MachineText.isoDay(year: year, month: month, day: day))]))
        }
        for (month, day) in [(4, 15), (12, 1), (1, 31)] {
            cases.append(.object(["isoMonthDay": .array([.int(month), .int(day)]), "text": .string(MachineText.isoMonthDay(month: month, day: day))]))
        }
        let byteSets: [[UInt8]] = [[], [0], [255], [0x00, 0x0F, 0xA0, 0xFF], Array(0...255)]
        for bytes in byteSets {
            cases.append(.object(["hex": .array(bytes.map { JSONValue.int(Int($0)) }), "text": .string(MachineText.hex(bytes))]))
        }
        return Vectors(
            name: "machine-text",
            rule: "MachineText.padded, isoDay, isoMonthDay, hex",
            source: "ios/Shared/MachineText.swift",
            shape: "padded: [number, width]; isoDay: [year, month, day]; isoMonthDay: [month, day]; hex: bytes. text: what MachineText writes.",
            cases: cases
        )
    }

    private struct Stamp: Codable { let at: Date }

    /// The moment as Android compares it: whole seconds since 1970 (rounded down) and the
    /// microseconds after them.
    static func moment(_ date: Date) -> JSONValue {
        let interval = date.timeIntervalSince1970
        var seconds = interval.rounded(.down)
        var micros = ((interval - seconds) * 1_000_000).rounded()
        if micros >= 1_000_000 { seconds += 1; micros -= 1_000_000 }
        return .object(["seconds": .int(Int(seconds)), "micros": .int(Int(micros))])
    }

    /// How a moment is written in machine JSON.
    static func written(_ date: Date) throws -> JSONValue {
        try json(compact(Stamp(at: date)))["at"] ?? .null
    }

    static func machineMoments() throws -> Vectors {
        let inputs = [
            "2026-11-02T08:00:00Z", "2026-11-02T10:00:00+02:00", "2026-11-02T10:00:00+0200", "2026-11-02T10:00:00+02",
            "2026-11-02T03:00:00-05:00", "2026-11-02T13:30:00+05:30", "2026-11-02T08:00:00+00:00", "2026-11-02T08:00:00-00:00",
            "2026-11-02T22:00:00+14:00", "2026-11-01T20:00:00-12:00", "2026-11-02T08:00:00+15:00", "2026-11-02T08:00:00+02:00:30",
            "2026-11-02T08:00:00.000Z", "2026-11-02T08:00:00.5Z", "2026-11-02T08:00:00.75Z", "2026-11-02T08:00:00.123456Z",
            "2026-11-02T08:00:00.123456789Z", "2026-11-02T08:00:00.999999999Z", "2026-11-02T08:00:00,5Z", "2026-11-02T08:00:00.Z",
            "2026-11-02T10:00:00.5+02:00", "2026-11-02T08:00:00z", "2026-11-02t08:00:00Z", "2026-11-02 08:00:00Z",
            "2026-11-02T08:00Z", "2026-11-02T08:00", "2026-11-02T08:00:00", "2026-11-02T080000Z", "20261102T080000Z",
            "2026-11-02T08:00:00GMT", "2026-11-02T08:00:00UTC", "2026-11-02T08:00:00 Z",
            "2026-11-02", "2026-02-30", "2026-02-29", "2024-02-29", "2026-13-01", "2026-1-2", "2026-11-2",
            "2026-11-02T24:00:00Z", "2026-11-02T23:59:60Z", "2026-11-02T25:00:00Z", "2026-11-02T08:60:00Z",
            "2026-02-30T08:00:00Z", "2026-02-29T08:00:00Z", "2024-02-29T08:00:00Z", "2026-1-2T08:00:00Z",
            " 2026-11-02T08:00:00Z", "2026-11-02T08:00:00Z ", "1970-01-01T00:00:00Z", "1600-03-01T00:00:00Z",
            "9999-12-31T23:59:59Z", "10000-01-01T00:00:00Z", "2 noiembrie 2026", "", "2026-W45-1", "2026-306",
            "2026-11-02T08:00:00Zjunk", "2026-11-02T08:00:00ZZ", "2026-11-02T10:00:00+02:00 more", "2026-11-02T10:00:00GMT+02:00",
            "2026-11-02T10:00:00UTC+0200", "2026-11-02T10:00:00GMT+2", "2026-11-02T8:00:00Z", "2026-11-02T08:0:0Z",
            "2026-11-02T10:00:00+2", "2026-11-02T10:00:00+2:00", "2026-11-02T10:00:00+02:0", "2026-11-02T10:00:00+020",
            "2026-11-02T08:00:00.5", "2026-00-10T08:00:00Z", "2026-11-00T08:00:00Z", "2026-13-02T08:00:00Z",
            "+2026-11-02T08:00:00Z", "-2026-11-02T08:00:00Z", "2026-11-02T10:00:00.123+02:00junk", "02026-11-02T08:00:00Z",
            "2026-11-02T08:00:00.5Zjunk", "2026-11-02T08:00:00-0530", "2026-11-02T08:00:00+05:30:15:00",
        ]
        let cases: [JSONValue] = try inputs.map { raw in
            guard let date = MachineText.moment(raw) else { return .object(["input": .string(raw), "moment": .null, "written": .null]) }
            return .object(["input": .string(raw), "moment": moment(date), "written": try written(date)])
        }
        return Vectors(
            name: "machine-moment-read",
            rule: "MachineText.moment(_:), what MachineText.jsonDecoder() reads a moment with",
            source: "ios/Shared/MachineText.swift",
            shape: "input: text. moment: seconds since 1970 (rounded down) and the microseconds after them, or null when it isn't a moment. written: the same moment as machine JSON writes it.",
            cases: cases
        )
    }

    static func machineMomentWriting() throws -> Vectors {
        let intervals: [Double] = [
            1_793_606_400, 1_793_606_400.75, 1_793_606_400.999, 1_793_606_399.999_999, 0, -0.5, -1, -0.000_001,
            9_999_999_999, -9_999_999_999, 253_402_300_799, 253_402_300_799.5, -11_644_473_600, 1_774_746_000,
        ]
        let cases: [JSONValue] = try intervals.map { interval in
            let date = Date(timeIntervalSince1970: interval)
            return .object(["moment": moment(date), "written": try written(date)])
        }
        return Vectors(
            name: "machine-moment-write",
            rule: "How MachineText.jsonEncoder() writes a moment: ISO 8601 in UTC, to the second",
            source: "ios/Shared/MachineText.swift",
            shape: "moment: seconds since 1970 (rounded down) and the microseconds after them. written: the text machine JSON writes for it.",
            cases: cases
        )
    }

    static func machineJSON() throws -> Vectors {
        let inputs = [
            #"{"b":1,"a":"x","B":true,"A":null,"a10":[],"a2":{},"_":-3,"é":0.5,"e":"/","aa":1,"Z":2,"z":3,"10":1,"9":2,"ș":1,"t":1,"😀":1,"�":1,"a b":1,"a-b":1}"#,
            #"["a/b","quote\"","back\\slash","tab\t","nl\n","cr\r","bs\b","ff\f","\u0000","\u001f","\u007f","é","ș"," "," ","😀","<>&'","dosarcusina://obligation/1"]"#,
            #"{"a":{"b":{"c":[1,[2,[3,{}]],{"d":[]}]}}}"#,
            #"[]"#, #"{}"#, #""x""#, #"1"#, #"true"#, #"false"#, #"null"#, #"[[]]"#, #"[{}]"#, #"{"a":[]}"#, #"{"a":{}}"#,
            #"[0,1,-1,42,9223372036854775807,-9223372036854775808,0.5,-0.25,1.5,123.456]"#,
            #"{"amount":"175.50","currency":"RON","note":"Placă „Exemplu”","plate":"B-123-ABC"}"#,
        ]
        let cases: [JSONValue] = try inputs.map { text in
            let value = try json(text)
            return .object([
                "input": .string(text),
                "compact": .string(try compact(value)),
                "readable": .string(String(decoding: try MachineText.jsonEncoder(.readable).encode(value), as: UTF8.self)),
            ])
        }
        return Vectors(
            name: "machine-json-write",
            rule: "MachineText.jsonEncoder(.compact) and (.readable): keys sorted, the readable form indented with slashes as they are",
            source: "ios/Shared/MachineText.swift",
            shape: "input: JSON text. compact, readable: the exact text each layout writes for it.",
            cases: cases
        )
    }

    static func kind(_ value: JSONValue) -> String {
        switch value {
        case .string: "string"
        case .int: "int"
        case .number: "number"
        case .bool: "bool"
        case .null: "null"
        case .array: "array"
        case .object: "object"
        }
    }

    static func jsonNumbers() throws -> Vectors {
        let inputs = [
            "0", "-0", "1", "1.0", "-1.0", "2.0", "1.5", "1e2", "1E2", "1e+2", "1.25e+2", "1e-2", "100", "0.1",
            "0.30000000000000004", "3.14159", "123456.789", "1e-07", "1e+16", "1e+15", "1e21", "1.5e+300",
            "12345678901234567890", "9223372036854775807", "9223372036854775808", "-9223372036854775808",
            "-9223372036854775810", "123456789012345678901234567890", "1.7976931348623157e308", "5e-324",
            "1e400", "1e-400", "0.000001", "0.0000001", "1234567890123456.5", "true", "false", "null", #""1""#,
        ]
        let cases: [JSONValue] = inputs.map { text in
            guard let value = try? json(text) else { return .object(["input": .string(text), "kind": .null, "written": .null]) }
            return .object(["input": .string(text), "kind": .string(kind(value)), "written": (try? compact(value)).map(JSONValue.string) ?? .null])
        }
        return Vectors(
            name: "json-numbers",
            rule: "How a JSON number is read into JSONValue (a whole number, else a Double) and written again",
            source: "ios/DosarCuSina/Services/AI/AIProviderAdapters.swift (JSONValue), ios/Shared/MachineText.swift",
            shape: "input: JSON text. kind: what JSONValue reads it as (int, number, bool, null, string), or null when it can't. written: what machine JSON writes for it then. Two numbers are the same value when they read as the same kind and value.",
            cases: cases
        )
    }

    /// How a Double the app keeps (a reading, a page's corner) is written in machine JSON.
    static func jsonDoubles() throws -> Vectors {
        let values: [Double] = [
            0, -0.0, 1, -1, 12, 100, 45_724, 0.5, -2.5, 0.1, 0.2, 1.0 / 3, 2.0 / 3, 4.35, 0.300_000_000_000_000_04,
            0.0001, 0.000_12, 0.000_09, 0.000_01, 1e-7, 123_456.789, 1_234_567_890_123_456.5, 9_007_199_254_740_992,
            9_007_199_254_740_994, 18_014_398_509_481_984, 1e16, 1.5e16, 1e21, 1e22, 1.797_693_134_862_315_7e308,
            5e-324, 2.225_073_858_507_201_4e-308, 1e300, 299_792_458, 6.022_140_76e23, 9.999_999_999_999_999e-5,
            0.25, 0.123_456_789_012_345_67, 1e-300, 8.5e-5,
        ]
        let cases: [JSONValue] = try values.map { value in
            let written = try compact([value])
            return .object([
                "value": .string(value.description),
                "written": .string(String(written.dropFirst().dropLast())),
            ])
        }
        return Vectors(
            name: "json-doubles",
            rule: "How MachineText.jsonEncoder() writes a Double",
            source: "ios/Shared/MachineText.swift",
            shape: "value: how Swift describes the Double, the shortest text that reads back as it exactly. written: the text machine JSON writes for it.",
            cases: cases
        )
    }

    // MARK: Values from a newer version

    /// Cases for `JSONValue.laying`: the stored JSON, what this build read of it, the edit.
    static let layings: [(String, String, String, String)] = [
        ("Left as read: what was stored stays, unknown keys included",
         #"{"type":"interval","every":2,"unit":"year","future":{"x":1}}"#, #"{"type":"interval","every":2,"unit":"year"}"#, #"{"type":"interval","every":2,"unit":"year"}"#),
        ("A known value changed: the edit wins, an unknown key stays",
         #"{"type":"interval","every":2,"unit":"year","future":true}"#, #"{"type":"interval","every":2,"unit":"year"}"#, #"{"type":"interval","every":3,"unit":"year"}"#),
        ("Unknown keys two levels deep stay",
         #"{"type":"interval","every":2,"extra":{"x":1,"y":[1,2]},"anchor":{"kind":"completion","future":{"deep":true}}}"#,
         #"{"type":"interval","every":2,"anchor":{"kind":"completion"}}"#, #"{"type":"interval","every":5,"anchor":{"kind":"completion"}}"#),
        ("A deeper value changed beside an unknown key at the same depth",
         #"{"type":"interval","anchor":{"kind":"completion","future":{"deep":true}}}"#, #"{"type":"interval","anchor":{"kind":"completion"}}"#,
         #"{"type":"interval","anchor":{"kind":"dueDate"}}"#),
        ("A value read as something else, left as read, stays as stored",
         #"{"leadDays":[30,7,0],"consequence":"catastrophic","graceDays":0}"#, #"{"leadDays":[30,7,0],"consequence":"legal","graceDays":0}"#,
         #"{"leadDays":[14,0],"consequence":"legal","graceDays":0}"#),
        ("A value read as something else, changed: the edit wins",
         #"{"leadDays":[30,7,0],"consequence":"catastrophic"}"#, #"{"leadDays":[30,7,0],"consequence":"legal"}"#, #"{"leadDays":[30,7,0],"consequence":"health"}"#),
        ("A type that changed keeps nothing of the old one",
         #"{"type":"metric","every":15000,"unit":"km","future":1}"#, #"{"type":"metric","every":15000,"unit":"km"}"#, #"{"type":"interval","every":1,"unit":"year"}"#),
        ("A type this build doesn't know, read as a fallback and left: stored stays",
         #"{"type":"lunar","phase":"full"}"#, #"{"type":"none"}"#, #"{"type":"none"}"#),
        ("A type this build doesn't know, read as a fallback, then a known one chosen",
         #"{"type":"lunar","phase":"full"}"#, #"{"type":"none"}"#, #"{"type":"interval","every":1,"unit":"month"}"#),
        ("An object without a type and one with: another value",
         #"{"every":1}"#, #"{"every":1}"#, #"{"type":"none","every":2}"#),
        ("A key the edit took out goes",
         #"{"a":1,"b":2,"future":3}"#, #"{"a":1,"b":2}"#, #"{"a":1}"#),
        ("A key left as read that is no longer stored stays out",
         #"{"a":1,"future":3}"#, #"{"a":1,"b":2}"#, #"{"a":5,"b":2}"#),
        ("A key the edit changed that is no longer stored comes back",
         #"{"a":1,"future":3}"#, #"{"a":1,"b":2}"#, #"{"a":1,"b":9}"#),
        ("A key the edit adds",
         #"{"a":1,"future":3}"#, #"{"a":1}"#, #"{"a":1,"c":4}"#),
        ("A key stored but not read, which the edit sets: the edit wins",
         #"{"a":1,"future":3}"#, #"{"a":1}"#, #"{"a":1,"future":4}"#),
        ("A stored null this build doesn't read stays",
         #"{"a":null,"b":1}"#, #"{"b":1}"#, #"{"b":2}"#),
        ("Entries known by id: one edited keeps what it kept",
         #"[{"id":"r1","label":"Loc","future":1},{"id":"r2","label":"Cod","future":2}]"#,
         #"[{"id":"r1","label":"Loc"},{"id":"r2","label":"Cod"}]"#, #"[{"id":"r1","label":"Loc în port"},{"id":"r2","label":"Cod"}]"#),
        ("A list entry taken out goes, with what it kept",
         #"[{"id":"r1","label":"Loc","future":1},{"id":"r2","label":"Cod","future":2}]"#,
         #"[{"id":"r1","label":"Loc"},{"id":"r2","label":"Cod"}]"#, #"[{"id":"r2","label":"Cod nou"}]"#),
        ("An entry the edit adds",
         #"[{"id":"r1","label":"Loc","future":1}]"#, #"[{"id":"r1","label":"Loc"}]"#, #"[{"id":"r1","label":"Loc"},{"id":"r3","label":"Nou"}]"#),
        ("An entry stored with an id never read stays, at the end",
         #"[{"id":"r1","label":"Loc"},{"id":"r9","label":"Alt telefon"}]"#, #"[{"id":"r1","label":"Loc"}]"#, #"[{"id":"r1","label":"Loc schimbat"}]"#),
        ("An entry left as read that is no longer stored stays out",
         #"[{"id":"r2","label":"Cod"}]"#, #"[{"id":"r1","label":"Loc"},{"id":"r2","label":"Cod"}]"#, #"[{"id":"r1","label":"Loc"},{"id":"r2","label":"Cod nou"}]"#),
        ("An entry changed that is no longer stored stays, as edited",
         #"[{"id":"r2","label":"Cod"}]"#, #"[{"id":"r1","label":"Loc"},{"id":"r2","label":"Cod"}]"#, #"[{"id":"r1","label":"Loc nou"},{"id":"r2","label":"Cod"}]"#),
        ("Entries reordered by id keep what they kept",
         #"[{"id":"a","v":1,"x":"A"},{"id":"b","v":2,"x":"B"}]"#, #"[{"id":"a","v":1},{"id":"b","v":2}]"#, #"[{"id":"b","v":2},{"id":"a","v":3}]"#),
        ("Ids compared without case",
         #"[{"id":"ABC","v":1,"x":true}]"#, #"[{"id":"abc","v":1}]"#, #"[{"id":"Abc","v":2}]"#),
        ("An entry known by its key before its id",
         #"[{"key":"k1","id":"zzz","v":1,"x":1}]"#, #"[{"key":"k1","id":"other","v":1}]"#, #"[{"key":"k1","id":"other","v":2}]"#),
        ("A key that isn't text: known by its id instead",
         #"[{"key":5,"id":"i1","v":1,"x":1}]"#, #"[{"key":5,"id":"i1","v":1}]"#, #"[{"key":5,"id":"i1","v":2}]"#),
        ("Entries without key or id, the list's length kept: paired by place",
         #"[{"v":1,"x":"a"},{"v":2,"x":"b"}]"#, #"[{"v":1},{"v":2}]"#, #"[{"v":1},{"v":5}]"#),
        ("Entries without key or id, the length changed: an unchanged one pairs, a changed one is new",
         #"[{"v":1,"x":"a"},{"v":2,"x":"b"}]"#, #"[{"v":1},{"v":2}]"#, #"[{"v":2},{"v":7},{"v":8}]"#),
        ("Entries without key or id, stored longer than read: nothing paired by place",
         #"[{"v":1,"x":"a"},{"v":2,"x":"b"},{"weird":true}]"#, #"[{"v":1},{"v":2}]"#, #"[{"v":1},{"v":9}]"#),
        ("Entries an older build couldn't read, without an id, aren't added back by this rule",
         #"[{"id":"a"},{"id":"b","x":1},{"weird":true}]"#, #"[{"id":"a"},{"id":"b"}]"#, #"[{"id":"a"},{"id":"b","y":2}]"#),
        ("Two stored entries with one id: the first is laid over",
         #"[{"id":"d","v":1,"x":"first"},{"id":"d","v":1,"x":"second"}]"#, #"[{"id":"d","v":1}]"#, #"[{"id":"d","v":2}]"#),
        ("Plain values: the edit wins",
         #""stored""#, #""read""#, #""edited""#),
        ("Plain values left as read: stored stays",
         #""stored""#, #""read""#, #""read""#),
        ("A list read as an object: the edit as it is",
         #"[1,2]"#, #"{"a":1}"#, #"{"a":2}"#),
        ("Lists of numbers",
         #"[30,7,0]"#, #"[30,7,0]"#, #"[30,7,1]"#),
        ("Deep: an object in a list in an object in a list",
         #"{"sections":[{"key":"s1","fields":[{"key":"f1","type":"text","future":{"a":[{"id":"x","b":1}]}},{"key":"f2","type":"number"}]}]}"#,
         #"{"sections":[{"key":"s1","fields":[{"key":"f1","type":"text"},{"key":"f2","type":"number"}]}]}"#,
         #"{"sections":[{"key":"s1","fields":[{"key":"f1","type":"text","label":"Nou"},{"key":"f2","type":"number"}]}]}"#),
        ("A field whose type changed inside a list keeps nothing of the old one",
         #"{"fields":[{"key":"f1","type":"lunar","future":1}]}"#, #"{"fields":[{"key":"f1","type":"text"}]}"#, #"{"fields":[{"key":"f1","type":"date"}]}"#),
    ]

    static func jsonLaying() throws -> Vectors {
        let cases: [JSONValue] = try layings.map { name, stored, read, edited in
            let result = JSONValue.laying(try json(edited), over: try json(stored), readAs: try json(read))
            return .object(["name": .string(name), "stored": try json(stored), "read": try json(read), "edited": try json(edited), "written": result])
        }
        return Vectors(
            name: "json-laying",
            rule: "JSONValue.laying(_:over:readAs:), the one rule a stored JSON value is written again by",
            source: "ios/DosarCuSina/Models/Values/KeptJSON.swift",
            shape: "stored: as kept; read: what this build made of it; edited: the edit. written: what goes back. Objects compare without their keys' order.",
            cases: cases
        )
    }

    static func transform(_ name: String) -> (JSONValue) -> JSONValue? {
        switch name {
        case "upper": { $0.mappingStrings { $0.uppercased() } }
        case "dropSealed": { $0.containsString { $0.hasPrefix("sealed:v1:") } ? nil : $0 }
        default: { $0 }
        }
    }

    static let keptMappings: [(String, String, String, String)] = [
        ("Only the parts this build doesn't read change",
         #"{"type":"interval","every":2,"note":"citit","future":{"a":"nou"}}"#, #"{"type":"interval","every":2,"note":"citit"}"#, "upper"),
        ("A part read as something else changes as kept",
         #"{"consequence":"catastrophic","label":"citit"}"#, #"{"consequence":"legal","label":"citit"}"#, "upper"),
        ("A part dropped by the transform is left out",
         #"{"code":"sealed:v1:abc","label":"Cod","future":"sealed:v1:def"}"#, #"{"label":"Cod"}"#, "dropSealed"),
        ("A part this build reads, dropped by the transform, is kept as read",
         #"{"label":"sealed:v1:abc"}"#, #"{"label":"Cod"}"#, "dropSealed"),
        ("Entries of a list, by id",
         #"[{"id":"r1","label":"a","future":"x"},{"id":"r2","label":"b"},{"id":"r3","secret":"sealed:v1:z"}]"#,
         #"[{"id":"r1","label":"a"},{"id":"r2","label":"b"}]"#, "dropSealed"),
        ("Entries of a list, by id, upper",
         #"[{"id":"r1","label":"a","future":"x"},{"id":"r2","label":"b"},{"id":"r3","more":"y"}]"#,
         #"[{"id":"r1","label":"a"},{"id":"r2","label":"b"}]"#, "upper"),
        ("A type that changed: the whole as the transform gives it",
         #"{"type":"lunar","phase":"plină"}"#, #"{"type":"none"}"#, "upper"),
        ("A type that changed, dropped: as read",
         #"{"type":"lunar","phase":"sealed:v1:q"}"#, #"{"type":"none"}"#, "dropSealed"),
        ("The same as read: nothing changes",
         #"{"a":"x"}"#, #"{"a":"x"}"#, "upper"),
    ]

    static func jsonMappingKept() throws -> Vectors {
        let cases: [JSONValue] = try keptMappings.map { name, stored, read, transformName in
            let result = try json(stored).mappingKept(readAs: try json(read), transform(transformName))
            return .object(["name": .string(name), "stored": try json(stored), "read": try json(read), "transform": .string(transformName), "written": result])
        }
        return Vectors(
            name: "json-mapping-kept",
            rule: "JSONValue.mappingKept(readAs:_:): an exit's rule reaching the parts this build doesn't read",
            source: "ios/DosarCuSina/Models/Values/KeptJSON.swift",
            shape: "stored, read as in json-laying; transform: upper (every text inside in capitals) or dropSealed (left out when any text inside starts with sealed:v1:). written: the result.",
            cases: cases
        )
    }

    static let threeWays: [(String, String, String, String)] = [
        ("Nothing changed in the form: what is stored now", #"{"a":1}"#, #"{"a":2,"b":3}"#, #"{"a":1}"#),
        ("Nothing changed since the form opened: the edit", #"{"a":5}"#, #"{"a":1}"#, #"{"a":1}"#),
        ("Different parts changed: both", #"{"a":5,"b":1}"#, #"{"a":1,"b":7}"#, #"{"a":1,"b":1}"#),
        ("The same part changed on both: the person's", #"{"a":5}"#, #"{"a":7}"#, #"{"a":1}"#),
        ("A row another device added stays", #"[{"id":"r1","v":2}]"#, #"[{"id":"r1","v":1},{"id":"r2","v":1}]"#, #"[{"id":"r1","v":1}]"#),
        ("A row another device removed stays gone", #"[{"id":"r1","v":2},{"id":"r2","v":1}]"#, #"[{"id":"r1","v":1}]"#, #"[{"id":"r1","v":1},{"id":"r2","v":1}]"#),
        ("A row the person removed goes", #"[{"id":"r2","v":1}]"#, #"[{"id":"r1","v":1},{"id":"r2","v":3}]"#, #"[{"id":"r1","v":1},{"id":"r2","v":1}]"#),
        ("A key another device removed stays gone", #"{"a":5,"b":1}"#, #"{"a":1}"#, #"{"a":1,"b":1}"#),
        ("Plain text", #""person""#, #""device""#, #""start""#),
    ]

    static func threeWay() throws -> Vectors {
        var cases: [JSONValue] = try threeWays.map { name, edited, stored, base in
            let result = ThreeWay.laying(try json(edited), over: try json(stored), startedFrom: try json(base))
            return .object(["name": .string(name), "edited": try json(edited), "stored": try json(stored), "base": try json(base), "written": result])
        }
        for (edited, stored, base) in [("b", "c", "a"), ("a", "c", "a"), ("a", "a", "a"), ("b", "a", "a")] {
            cases.append(.object([
                "value": .array([.string(edited), .string(stored), .string(base)]),
                "written": .string(ThreeWay.value(edited, over: stored, startedFrom: base)),
            ]))
        }
        return Vectors(
            name: "three-way",
            rule: "ThreeWay.laying(_:over:startedFrom:) and ThreeWay.value: a form saves only what was changed in it",
            source: "ios/DosarCuSina/Models/Values/ThreeWay.swift",
            shape: "edited: as the person left it; stored: as stored now; base: as the form opened. written: what the save writes. value: [edited, stored, base] for one whole value.",
            cases: cases
        )
    }

    /// A row as a list keeps it: read only when its id and label are text.
    struct Row: Codable, Hashable, Sendable, Identifiable {
        var id: String
        var label: String
        var isSensitive: Bool?
    }

    static let keptListCases: [(String, String, String, String)] = [
        ("Read and written again unchanged", #"[{"id":"r1","label":"Loc","future":1},{"id":"r2","label":"Cod"}]"#, "none", ""),
        ("An entry this build can't read stays in its place", #"[{"id":"r1","label":"Loc"},{"id":5,"label":"Număr"},{"id":"r3","label":"Cod"}]"#, "none", ""),
        ("Editing the readable ones keeps the others in place",
         #"[{"id":"r1","label":"Loc","future":1},{"id":5,"label":"Număr"},{"id":"r3","label":"Cod"}]"#, "replaceItems",
         #"[{"id":"r1","label":"Loc nou"},{"id":"r3","label":"Cod"}]"#),
        ("A readable entry with an unreadable one's id takes its place",
         #"[{"id":"r1","label":"Loc"},{"id":"R2","label":7}]"#, "replaceItems", #"[{"id":"r1","label":"Loc"},{"id":"r2","label":"Șapte"}]"#),
        ("An entry taken out goes, what it kept with it",
         #"[{"id":"r1","label":"Loc","future":1},{"id":"r2","label":"Cod","future":2},{"label":"Fără id"}]"#, "replaceItems", #"[{"id":"r2","label":"Cod"}]"#),
        ("An entry added, and the order changed",
         #"[{"id":"r1","label":"Loc","future":1},{"id":"r2","label":"Cod"},{"id":null,"label":"x"}]"#, "replaceItems",
         #"[{"id":"r2","label":"Cod"},{"id":"r4","label":"Nou","isSensitive":true},{"id":"r1","label":"Loc"}]"#),
        ("All entries taken out: the unreadable ones stay",
         #"[{"id":"r1","label":"Loc"},"text",{"id":"r2","label":"Cod"},42]"#, "replaceItems", #"[]"#),
        ("Two entries with one id: the first one's JSON",
         #"[{"id":"d","label":"A","future":"first"},{"id":"D","label":"A","future":"second"}]"#, "none", ""),
        ("A sensitive flag that isn't a yes or no: unreadable", #"[{"id":"r1","label":"Loc","isSensitive":"da"},{"id":"r2","label":"Cod","isSensitive":null}]"#, "none", ""),
        ("Kept parts changed on the way out",
         #"[{"id":"r1","label":"Loc","future":"x"},{"id":9,"label":"y"},{"id":"r2","label":"Cod"}]"#, "mappingKept", "upper"),
        ("Kept parts left out on the way out",
         #"[{"id":"r1","label":"Loc","future":"sealed:v1:a"},{"id":"r9","secret":"sealed:v1:b"},{"id":"r2","label":"Cod"}]"#, "mappingKept", "dropSealed"),
        ("Another list's entries replace the ones they name, the rest stay",
         #"[{"id":"r1","label":"Loc","future":1},{"id":7,"label":"x"},{"id":"r2","label":"Cod"}]"#, "replaceEntries",
         #"[{"id":"r2","label":"Cod din copie","more":true},{"id":"r5","bad":1},{"id":"r6","label":"Nou"}]"#),
        ("Only the entries kept by a rule: the readable ones without r2, the unreadable ones without an id",
         #"[{"id":"r1","label":"Loc","future":1},{"id":"r2","label":"Cod"},{"id":"r9","bad":1},{"bad":2}]"#, "filtered", "r2"),
    ]

    static func rows(_ list: KeptList<Row>) throws -> JSONValue {
        .array(try list.items.map { row in
            guard let value = JSONValue(encoding: row) else { throw NotJSON(text: "\(row)") }
            return value
        })
    }

    static func encoded(_ list: KeptList<Row>) throws -> JSONValue {
        try json(String(decoding: try JSONEncoder().encode(list), as: UTF8.self))
    }

    static func keptLists() throws -> Vectors {
        var cases: [JSONValue] = []
        for (name, stored, operation, argument) in keptListCases {
            let read = KeptList<Row>.stored(in: Data(stored.utf8))
            let result: KeptList<Row>
            switch operation {
            case "replaceItems": result = read.replacingItems(try JSONDecoder().decode([Row].self, from: Data(argument.utf8)))
            case "mappingKept": result = read.mappingKept(transform(argument))
            case "replaceEntries": result = read.replacingEntries(with: KeptList<Row>.stored(in: Data(argument.utf8)))
            case "filtered": result = read.filtered({ $0.id != argument }, unreadable: { $0.keptIdentity != nil })
            default: result = read
            }
            let argumentValue: JSONValue
            if operation == "replaceItems" || operation == "replaceEntries" {
                argumentValue = try json(argument)
            } else {
                argumentValue = .string(argument)
            }
            cases.append(.object([
                "name": .string(name),
                "stored": try json(stored),
                "operation": .string(operation),
                "argument": argumentValue,
                "items": try rows(read),
                "unreadablePositions": .array(read.unreadable.map { JSONValue.int($0.position) }),
                "isFullyRead": .bool(read.isFullyRead),
                "identities": .array(read.identities.sorted().map(JSONValue.string)),
                "written": try encoded(result),
            ]))
        }
        return Vectors(
            name: "kept-list",
            rule: "KeptList: a stored list's readable entries and the ones kept raw, written back by JSONValue.laying",
            source: "ios/DosarCuSina/Models/Values/KeptList.swift",
            shape: "Entries are rows {id, label, isSensitive?}: readable only when id and label are text and isSensitive, if there, is a yes or no (null counts as missing). stored: the list as kept. items, unreadablePositions, isFullyRead, identities (sorted): how it reads. operation: none (written again as read), replaceItems (argument: the new readable entries), mappingKept (argument: upper or dropSealed, as in json-mapping-kept), replaceEntries (argument: another stored list), filtered (readable entries whose id isn't the argument, unreadable ones with a key or id). written: the list then written.",
            cases: cases
        )
    }

    /// A rule as an object keeps it: read only when its type is text.
    struct Rule: Codable, Hashable, Sendable {
        var type: String
        var every: Int?
        var unit: String?
    }

    static let keptObjectCases: [(String, String?, String?, String?)] = [
        ("Read and written again unchanged", #"{"type":"interval","every":2,"unit":"year","future":{"a":1}}"#, nil, nil),
        ("Edited: what it kept stays", #"{"type":"interval","every":2,"unit":"year","future":{"a":1}}"#, #"{"type":"interval","every":3,"unit":"year"}"#, nil),
        ("A known part taken out by the edit goes", #"{"type":"interval","every":2,"unit":"year","future":1}"#, #"{"type":"interval","every":2}"#, nil),
        ("Another type keeps nothing", #"{"type":"interval","every":2,"unit":"year","future":1}"#, #"{"type":"none"}"#, nil),
        ("Unreadable: read as the fallback, written back as stored", #"{"type":7,"every":2}"#, nil, nil),
        ("Unreadable, then edited: the edit", #"{"type":7,"every":2}"#, #"{"type":"interval","every":1,"unit":"month"}"#, nil),
        ("A value of a type this build doesn't know", #"{"type":"lunar","every":1,"phase":"full"}"#, nil, nil),
        ("Made here: nothing kept", nil, #"{"type":"interval","every":6,"unit":"month"}"#, nil),
        ("Kept parts changed on the way out", #"{"type":"interval","every":2,"note":"text","future":"nou"}"#, nil, "upper"),
        ("Kept parts left out on the way out", #"{"type":"interval","every":2,"future":"sealed:v1:abc"}"#, nil, "dropSealed"),
    ]

    static func keptObjects() throws -> Vectors {
        let fallback = Rule(type: "none")
        var cases: [JSONValue] = []
        for (name, stored, edited, transformName) in keptObjectCases {
            var kept: KeptObject<Rule>
            if let stored {
                guard let read = KeptObject<Rule>.stored(in: Data(stored.utf8), fallback: fallback) else { throw NotJSON(text: stored) }
                kept = read
            } else {
                kept = KeptObject(fallback)
            }
            let readValue = JSONValue(encoding: kept.value) ?? .null
            let keptMoreAsRead = kept.keepsMore
            if let edited {
                let rule = try JSONDecoder().decode(Rule.self, from: Data(edited.utf8))
                kept = stored == nil ? KeptObject(rule) : kept.replacingValue(rule)
            }
            if let transformName { kept = kept.mappingKept(transform(transformName)) }
            cases.append(.object([
                "name": .string(name),
                "stored": try stored.map(json) ?? .null,
                "value": readValue,
                "keepsMore": .bool(keptMoreAsRead),
                "edited": try edited.map(json) ?? .null,
                "transform": transformName.map(JSONValue.string) ?? .null,
                "written": kept.json ?? .null,
                "keepsMoreWritten": .bool(kept.keepsMore),
            ]))
        }
        return Vectors(
            name: "kept-object",
            rule: "KeptObject: one stored object, the value this build reads and the JSON it was read from",
            source: "ios/DosarCuSina/Models/Values/KeptObject.swift",
            shape: "The value is a rule {type, every?, unit?}: readable only when type is text and every, if there, a whole number; else read as the fallback {\"type\":\"none\"}. stored: as kept (null: a value made here, from edited). value, keepsMore: how it reads. edited: the new value, if any; transform: applied on the way out (as in json-mapping-kept), if any. written, keepsMoreWritten: what it writes then.",
            cases: cases
        )
    }

    // MARK: Romanian numbers

    static let numberInputs = [
        "1.250,50", "1,250.50", "45,724", "45.724", "3,750", "0,725", "1 250 000", "1 250,50", "1.250.500", "1,250,500",
        "1.250", "1,25", "1.25", "1.2345", "12.345,678", "1.250,50,5", "1,2.3", "1 250.500,5", "0,5", ",5", "5,", ".", ",",
        "-", "-12", "\u{2212}12", "- 12", "-0", "-0,00", "+5", "12-5", "12-05", "5\u{00B2}", "12 km", "12km", "86.420 km",
        "86,420 km", "84200KM", "350 lei", "350 LEI", "350lei", "350 Lei", "1 leu", "350 RON", "350 ron", "350 EUR", "350 euro",
        "350€", "350 €", "€350", "$350", "350 $", "350 usd", "12,5 m\u{00B3}", "12,5 mc", "12,5 m3", "12,5 MC", "4 kWh", "4kwh",
        "7 Gcal", "4,5 kg", "Index nou: 12.345", "Total: 1.250,50 lei", "12:30", "Km bord: 86420", "a: 12", "Index 2: 12",
        "Index: ", " 12 ", "\u{00A0}12\u{00A0}", "12\t", "\t12", "1\u{202F}250", "1\u{2009}250", "1\u{00A0}450,50 lei",
        "0012", "012.345", "0.345", "00,5", "0", "000", "12", "1234,567", "123456789012345678901234567890",
        "1.234.567.890.123.456.789.012.345.678.901", "12345678901234567890123456789012345678901234567890",
        "0,1234567890123456789", "\u{0661}\u{0662}\u{0663}", "\u{FF11}\u{FF12}", "\u{0661}.\u{0662}\u{0663}\u{0664}", "kkm",
        "12 kkm", "km", "lei", "", "   ", "abc", "1e3", "1_000", "12 345 678", "12  345", "1 23", "1 2345", "12\n", "\n12",
        "12 h", "12 ore motor", "12 cafele", "24 luni", "1.250 cafele",
    ]

    static func reading(_ result: Result<RomanianNumber.Reading, RomanianNumber.Problem>) -> JSONValue {
        switch result {
        case .success(let reading):
            .object(["value": .string("\(reading.value)"), "ambiguous": .bool(reading.isAmbiguous), "needsCheck": .bool(reading.needsCheck)])
        case .failure(let problem):
            .object(["problem": .string("\(problem)")])
        }
    }

    static func romanianNumberReading() -> Vectors {
        var cases: [JSONValue] = []
        for input in numberInputs {
            var answers: [String: JSONValue] = ["input": .string(input), "origin": "document", "unit": .null]
            for kind in NumberKind.allCases {
                answers["\(kind)"] = reading(RomanianNumber.read(input, as: kind, from: .document))
            }
            cases.append(.object(answers))
        }
        // Typed numbers are never marked for a check.
        for input in ["3,750", "45.724", "1.250,50"] {
            var answers: [String: JSONValue] = ["input": .string(input), "origin": "typed", "unit": .null]
            for kind in NumberKind.allCases { answers["\(kind)"] = reading(RomanianNumber.read(input, as: kind, from: .typed)) }
            cases.append(.object(answers))
        }
        // A field's own unit after its number.
        let withUnits: [(String, String)] = [
            ("12 h", "h"), ("12h", "h"), ("12 ore motor", "ore motor"), ("12 ORE MOTOR", "ore motor"), ("1.250 cafele", "cafele"),
            ("24 luni", "luni"), ("24 luni", "months"), ("90 kg", "kg"), ("12,5 m\u{00B2}", "m2"), ("12,5 mp", "m2"), ("120 CP", "hp"),
            ("4,5 dpt", "dpt"), ("120 mmHg", "mmHg"), ("95 mg/dL", "mgdl"), ("1.600 cm\u{00B3}", "cm3"), ("12 h", "km"),
        ]
        for (input, unitText) in withUnits {
            var answers: [String: JSONValue] = ["input": .string(input), "origin": "document", "unit": .string(unitText)]
            for kind in NumberKind.allCases {
                answers["\(kind)"] = reading(RomanianNumber.read(input, as: kind, from: .document, unit: MeasurementUnit(unitText)))
            }
            cases.append(.object(answers))
        }
        return Vectors(
            name: "romanian-number-read",
            rule: "RomanianNumber.read(_:as:from:unit:)",
            source: "ios/DosarCuSina/Models/Values/RomanianNumber.swift",
            shape: "input: text; origin: document or typed; unit: a field's unit as written (read with MeasurementUnit), or null. For each kind (money, count, meterIndex, kilometres): value (the number, as Foundation's Decimal writes it), ambiguous and needsCheck, or problem (empty, unreadable, negative, notWhole, tooManyDigits).",
            cases: cases
        )
    }

    static func romanianNumberCanonical() -> Vectors {
        let inputs = [
            "1250.5", "-3", "45724", "0", "-0", "-0.0", "0.00", "175.50", "1.250,5", "45,724", "1e3", "+5", " 12 ", "12\n",
            "\t12", ".5", "5.", "1.2.3", "--1", "00012.3400", "123456789012345678901234567890.123456789",
            "12345678901234567890123456789012345678901234567890", "0.0000000000000000000000000000000000000001",
            "\u{0661}\u{0662}", "\u{FF11}\u{FF12}", "", "abc", "12a", "1 000",
        ]
        let cases: [JSONValue] = inputs.map { input in
            .object(["input": .string(input), "value": RomanianNumber.canonical(input).map { JSONValue.string("\($0)") } ?? .null])
        }
        return Vectors(
            name: "romanian-number-canonical",
            rule: "RomanianNumber.canonical(_:), the machine form archives and stored JSON use",
            source: "ios/DosarCuSina/Models/Values/RomanianNumber.swift",
            shape: "input: text. value: the number as Foundation's Decimal writes it, or null when refused.",
            cases: cases
        )
    }

    static func romanianNumberFormat() -> Vectors {
        let inputs: [(String, Int, Int, Bool)] = [
            ("45724", 0, 2, true), ("1250.5", 0, 2, true), ("1250.5", 2, 2, true), ("1234", 0, 2, true), ("123", 0, 2, true),
            ("12345", 0, 2, true), ("1234567.891", 0, 2, true), ("1234567.891", 0, 2, false), ("0", 0, 2, true), ("0", 2, 2, true),
            ("2.345", 0, 2, true), ("2.355", 0, 2, true), ("2.5", 0, 0, true), ("3.5", 0, 0, true), ("-2.5", 0, 0, true),
            ("0.005", 0, 2, true), ("0.015", 0, 2, true), ("-0.004", 0, 2, true), ("-1250.5", 0, 2, true), ("12.3456", 0, 1, true),
            ("12.3456", 1, 3, true), ("1000000", 0, 2, true), ("123456789012345678901234567890", 0, 2, true),
            ("0.125", 0, 2, true), ("12.5", 0, 1, true), ("45724", 0, 1, false),
        ]
        let cases: [JSONValue] = inputs.map { value, least, most, groups in
            let number = RomanianNumber.canonical(value) ?? 0
            return .object([
                "value": .string(value), "fractionDigits": .array([.int(least), .int(most)]), "groupsDigits": .bool(groups),
                "text": .string(RomanianNumber.format(number, fractionDigits: least...most, groupsDigits: groups)),
                "readsBack": RomanianNumber.value(RomanianNumber.format(number, fractionDigits: least...most, groupsDigits: groups), as: .meterIndex).map { JSONValue.string("\($0)") } ?? .null,
            ])
        }
        return Vectors(
            name: "romanian-number-format",
            rule: "RomanianNumber.format(_:fractionDigits:groupsDigits:)",
            source: "ios/DosarCuSina/Models/Values/RomanianNumber.swift",
            shape: "value: the number in machine form; fractionDigits: [least, most]; groupsDigits. text: how the app writes it. readsBack: the text read again as a meter index (null when it can't be).",
            cases: cases
        )
    }

    // MARK: Money, units, folding

    static func money() throws -> Vectors {
        var cases: [JSONValue] = []
        let amounts: [(String, String)] = [
            ("175.50", "RON"), ("175.5", "ron"), ("0", "EUR"), ("12", "usd"), ("0.125", "RON"), ("0.135", "RON"), ("0.005", "RON"),
            ("-0.005", "RON"), ("-12.345", "RON"), ("-12.355", "RON"), ("2.675", "RON"), ("1250.999", "RON"), ("-0", "RON"),
            ("12345678901234567890123.456", "RON"), ("1.250,50", "RON"), ("1e3", "RON"), ("", "RON"), (" 12.50 ", "RON"),
            ("12.50", "Ron"), ("12.50", ""), ("00012.3", "RON"),
        ]
        for (amount, currency) in amounts {
            guard let value = Money(amountString: amount, currency: currency) else {
                cases.append(.object(["amountString": .string(amount), "currency": .string(currency), "money": .null]))
                continue
            }
            cases.append(.object([
                "amountString": .string(amount), "currency": .string(currency),
                "money": .object(["amount": .string("\(value.amount)"), "currency": .string(value.currency), "written": .string(value.amountString)]),
            ]))
        }
        let stored = [
            #"{"amount":"175.50","currency":"RON"}"#, #"{"amount":"12","currency":"eur"}"#, #"{"amount":12.5,"currency":"RON"}"#,
            #"{"amount":"1.250,50","currency":"RON"}"#, #"{"currency":"RON"}"#, #"{"amount":"12"}"#, #"{"amount":"0.125","currency":"RON","future":1}"#,
            #"{"amount":"-3","currency":"RON"}"#,
        ]
        for text in stored {
            let read = try? JSONDecoder().decode(Money.self, from: Data(text.utf8))
            cases.append(.object(["json": .string(text), "written": try read.map { JSONValue.string(try compact($0)) } ?? .null]))
        }
        return Vectors(
            name: "money",
            rule: "Money's stored value: Money(amountString:currency:), amountString, and its JSON",
            source: "ios/DosarCuSina/Models/Values/Money.swift",
            shape: "amountString, currency: as stored. money: the amount (as Foundation's Decimal writes it), the currency (in capitals) and the amount written again (rounded to two decimals, half to even); null when refused. Or json: a stored money object, written: as machine JSON writes it again, or null when it can't be read.",
            cases: cases
        )
    }

    static func measurementUnits() -> Vectors {
        let inputs = [
            "km", "KM", "Km ", " km", "m\u{00B3}", "M\u{00B3}", "mc", "MC", "m3", "kWh", "KWH", "kwh", "Gcal", "GCAL", "kg",
            "mg/dL", "mgdl", "MG/DL", "mmHg", "mmhg", "dpt", "cm\u{00B3}", "cm3", "CP", "cp", "hp", "m\u{00B2}", "m2", "mp", "months",
            "luni", "Luni", "LUNI", "shots", "cafele", "Cafele", "h", "H", "ore motor", "  ore motor  ", "Ore Motor", "", "   ",
            "\n", "kWh\n", "lună", "km/h", "\u{FF4B}\u{FF4D}",
        ]
        let cases: [JSONValue] = inputs.map { text in
            guard let unit = MeasurementUnit(text) else {
                return .object(["input": .string(text), "unit": .null, "storedKey": .string(MeasurementUnit.storedKey(for: text))])
            }
            return .object([
                "input": .string(text),
                "unit": .object(["key": .string(unit.key), "label": .string(unit.label), "isCatalog": .bool(unit.isCatalog)]),
                "storedKey": .string(MeasurementUnit.storedKey(for: text)),
            ])
        }
        return Vectors(
            name: "measurement-unit",
            rule: "MeasurementUnit(_:), key, label, isCatalog, storedKey(for:)",
            source: "ios/DosarCuSina/Models/Values/MeasurementUnit.swift",
            shape: "input: a unit as stored or typed. unit: its key, the label a person sees, and whether it is the catalog's; null for no unit. storedKey: what is stored for it (\"\" for none).",
            cases: cases
        )
    }

    static func romanianTextFold() -> Vectors {
        let inputs = [
            "ȘȚĂÎÂ șțăîâ", "ŞŢ şţ", "\u{FF2B}\u{FF2D}", "\u{2212}12", "1\u{00A0}250", "1\u{202F}250", "1\u{2009}250", "Café", "e\u{0301}",
            "m\u{00B3}", "LEI", "€ $", "Index nou: 12.345", "Œ æ ø đ ł", "\u{00C5}ngstr\u{00F6}m", "ÇÑ", "B-123-ABC",
        ]
        let cases: [JSONValue] = inputs.map { .object(["input": .string($0), "folded": .string(RomanianText.fold($0))]) }
        return Vectors(
            name: "romanian-text-fold",
            rule: "RomanianText.fold(_:), as the number reader and the unit catalog read units",
            source: "ios/Shared/RomanianText.swift",
            shape: "input: text. folded: without case, diacritics or wide forms, no-break spaces as spaces, a typographic minus as -.",
            cases: cases
        )
    }
}
