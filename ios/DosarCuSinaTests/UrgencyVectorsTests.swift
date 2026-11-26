import Foundation
import SwiftData
import Testing
@testable import DosarCuSina

/// How urgent a deadline is and when it reminds (`UrgencyRule`, `ReminderLead`, `ReminderProfile`
/// and its cycle's leads, `DateUrgency`, `ReminderPlanner`, `BadgePlanner`, `ReminderTrigger`'s
/// date parts, `ReminderClock` and which shown reminders are outdated), run over cases chosen to
/// bite (month ends and leap days, a lead longer than the repeat, a snooze on a lead's day, a time
/// the clocks skip, Lord Howe Island's half-hour gap, a passport's travel margin, the badge across
/// days, time zones far east and west) and written to `shared/test-vectors/urgency/`, one file per
/// rule: each input with the answer this app gives. The Android app's tests read the same files and
/// must give the same answers (docs/ANDROID_PLAN.md, "How parity is kept"). A sibling of
/// `ValueVectorsTests`, with a folder of its own.
///
/// No words: what a reminder says comes from the strings, so a planned reminder is written with
/// everything it carries but its title and body. Placeholder data only.
@Suite("Urgency vectors")
struct UrgencyVectorsTests {
    static var folder: URL {
        URL(filePath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appending(path: "shared/test-vectors/urgency")
    }

    /// How to bring the files up to date, said when one isn't.
    static let regenerate = """
    is out of date with the urgency and reminder rules. Bring shared/test-vectors/urgency up to date: \
    TEST_RUNNER_URGENCY_VECTORS_WRITE=1 ./tests/run_tests.sh (or run UrgencyVectorsTests in Xcode with \
    URGENCY_VECTORS_WRITE=1 in the scheme's environment), review the diff and commit it, then run the \
    Android tests (./gradlew :core:test in android/), which read the same files.
    """

    typealias Vectors = ValueVectorsTests.Vectors

    @Test("shared/test-vectors/urgency is up to date with the urgency and reminder rules")
    @MainActor
    func vectorsAreUpToDate() throws {
        let files = try Self.all()
        let writes = ProcessInfo.processInfo.environment["URGENCY_VECTORS_WRITE"] == "1"
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

    @MainActor
    static func all() throws -> [Vectors] {
        try [
            reminderLeads(), storedKinds(), reminderProfiles(), urgencyRules(), dateUrgency(),
            reminderClock(), reminderPlans(), badgePlans(), reminderIdentifiers(), shownReminders(),
        ]
    }

    static func render(_ file: Vectors) throws -> String {
        let document: JSONValue = .object([
            "rule": .string(file.rule),
            "source": .string(file.source),
            "shape": .string(file.shape),
            "writtenBy": "ios/DosarCuSinaTests/UrgencyVectorsTests.swift",
            "cases": .array(file.cases),
        ])
        return String(decoding: try MachineText.jsonEncoder(.readable).encode(document), as: UTF8.self) + "\n"
    }

    // MARK: Helpers

    static func day(_ text: String) -> CalendarDay { ValueVectorsTests.day(text) }
    static func iso(_ day: CalendarDay?) -> JSONValue { ValueVectorsTests.iso(day) }
    static func inZone(_ zone: String) -> Calendar { .dosar(in: ValueVectorsTests.zone(zone)) }
    static func seconds(_ date: Date) -> JSONValue { .int(Int(date.timeIntervalSince1970.rounded())) }
    static func date(_ seconds: Int) -> Date { Date(timeIntervalSince1970: TimeInterval(seconds)) }
    static func optional(_ value: Int?) -> JSONValue { value.map(JSONValue.int) ?? .null }

    /// The placeholder id of deadline `n`: `aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaa00nn`, letters in every
    /// group, so no run of its digits reads as a card number to the privacy check.
    static func id(_ n: Int) -> UUID {
        let digits = String(n)
        let text = "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaa" + String(repeating: "0", count: max(0, 4 - digits.count)) + digits
        return UUID(uuidString: text) ?? UUID()
    }

    static func uuid(_ id: UUID?) -> JSONValue { id.map { .string($0.uuidString.lowercased()) } ?? .null }

    /// A moment's date parts as the system gets them, written `yyyy-MM-ddTHH:mm`.
    static func trigger(_ fire: Date, _ calendar: Calendar) -> JSONValue {
        let parts = ReminderTrigger.components(firingAt: fire, calendar: calendar)
        #expect(parts.calendar?.identifier == .gregorian)
        func two(_ n: Int?) -> String { let t = String(n ?? 0); return t.count < 2 ? "0" + t : t }
        let year = String(parts.year ?? 0)
        let paddedYear = String(repeating: "0", count: max(0, 4 - year.count)) + year
        return .string("\(paddedYear)-\(two(parts.month))-\(two(parts.day))T\(two(parts.hour)):\(two(parts.minute))")
    }

    /// A profile as a case gives it: its consequence's stored text, a follow-up only when it says.
    struct Profile {
        var leadDays: [Int]
        var consequence: String = "legal"
        var graceDays: Int = 0
        var followUp: Bool?
        var travelMargin: Int = 0

        var made: ReminderProfile {
            ReminderProfile(leadDays: leadDays, consequence: Consequence(stored: consequence), graceDays: graceDays,
                            followUpAfterLapse: followUp, travelMarginDays: travelMargin)
        }

        var json: JSONValue {
            .object([
                "leadDays": .array(leadDays.map(JSONValue.int)), "consequence": .string(consequence),
                "graceDays": .int(graceDays), "followUpAfterLapse": followUp.map(JSONValue.bool) ?? .null,
                "travelMarginDays": .int(travelMargin),
            ])
        }
    }

    static func written(_ profile: ReminderProfile) -> JSONValue {
        .object([
            "leadDays": .array(profile.leadDays.map(JSONValue.int)), "consequence": .string(profile.consequence.rawValue),
            "graceDays": .int(profile.graceDays), "followUpAfterLapse": .bool(profile.followUpAfterLapse),
            "travelMarginDays": .int(profile.travelMarginDays),
        ])
    }

    static func written(_ rule: UrgencyRule) -> JSONValue {
        .object([
            "graceDays": .int(rule.graceDays), "firstLeadDays": .int(rule.firstLeadDays),
            "maxWindowDays": .int(rule.maxWindowDays), "travelMarginDays": .int(rule.travelMarginDays),
        ])
    }

    /// A deadline as a case gives it. Its snapshot's reminders are its stored profile as the cycle
    /// that began on `cycleStart` uses them (`ReminderProfile.forCycle`), as the app fills one.
    struct Deadline {
        var n: Int
        var status = "active"
        var due: String
        var snoozed: String?
        var profile: Profile
        var cycleStart: String?
        var minute: Int?
        var sensitive = false
        var example = false
        var knownSince: Int?
        var inApp = false

        var snapshot: ObligationSnapshot {
            let dueDay = UrgencyVectorsTests.day(due)
            let start = cycleStart.map(UrgencyVectorsTests.day)
            let made = ObligationSnapshot(
                id: UrgencyVectorsTests.id(n), title: "Termen \(n)", kind: .legal,
                status: ObligationStatus(stored: status), dueDay: dueDay,
                snoozedUntil: snoozed.map(UrgencyVectorsTests.day),
                reminders: profile.made.forCycle(startingOn: start, due: dueDay),
                reminderMinuteOfDay: minute, isSensitive: sensitive, isExample: example,
                cycleKnownSince: knownSince.map(UrgencyVectorsTests.date),
                completion: inApp ? .newDocument : .chore
            )
            #expect(made.closesInTheApp == inApp, "Deadline \(n): its completion closes \(inApp ? "in" : "outside") the app")
            return made
        }

        var json: JSONValue {
            .object([
                "id": UrgencyVectorsTests.uuid(UrgencyVectorsTests.id(n)), "status": .string(status), "dueDay": .string(due),
                "snoozedUntil": snoozed.map(JSONValue.string) ?? .null, "reminders": profile.json,
                "cycleStart": cycleStart.map(JSONValue.string) ?? .null,
                "reminderMinuteOfDay": UrgencyVectorsTests.optional(minute), "isSensitive": .bool(sensitive),
                "isExample": .bool(example), "cycleKnownSince": UrgencyVectorsTests.optional(knownSince),
                "closesInTheApp": .bool(inApp),
            ])
        }
    }

    static func written(_ reminder: PlannedReminder, _ calendar: Calendar) -> JSONValue {
        .object([
            "identifier": .string(reminder.identifier), "obligationId": uuid(reminder.obligationId),
            "cycle": iso(reminder.cycle), "fireAt": seconds(reminder.fireDate), "trigger": trigger(reminder.fireDate, calendar),
            "isTimeSensitive": .bool(reminder.isTimeSensitive), "isProtected": .bool(reminder.isProtected),
            "closesInTheApp": .bool(reminder.closesInTheApp), "badge": optional(reminder.badge),
            "showsAlert": .bool(reminder.showsAlert),
        ])
    }

    /// The moment `minute` after midnight on `text` in `zone`, as seconds since 1970.
    static func at(_ text: String, _ minute: Int, _ zone: String) -> Int {
        Int(day(text).moment(atMinute: minute, in: inZone(zone)).timeIntervalSince1970.rounded())
    }

    // MARK: Leads

    static func reminderLeads() -> Vectors {
        let dues = ["2026-03-31", "2028-02-29", "2026-12-31", "2027-03-01", "2026-05-31", "2026-11-26"]
        let sizes = [0, 1, 7, 29, 30, 31, 45, 59, 60, 90, 180, 183, 364, 365, 366, 390, 730, 1095, -7, -30, 36_500, 40_000, Int(Int32.min)]
        var cases: [JSONValue] = sizes.map { size -> JSONValue in
            let lead = ReminderLead(days: size)
            let kind: JSONValue
            switch lead {
            case .days(let n): kind = .object(["days": .int(n)])
            case .months(let n): kind = .object(["months": .int(n)])
            }
            return .object([
                "days": .int(size), "lead": kind,
                "before": .array(dues.map { due -> JSONValue in
                    .object(["due": .string(due), "day": iso(lead.day(before: day(due), calendar: .dosar(in: .gmt)))])
                }),
            ])
        }
        for raw in [-5, 0, 7, 36_500, 36_501, Int(Int32.max)] {
            cases.append(.object(["bounded": .int(raw), "is": .int(ReminderLead.bounded(raw))]))
        }
        return Vectors(
            name: "reminder-lead",
            rule: "ReminderLead(days:), day(before:calendar:) and bounded(_:)",
            source: "ios/Shared/Urgency.swift",
            shape: "days: a lead as stored; lead: what it is ({days: n} or {months: n}, whole months being 30 days and whole years 365, by its size, held to a hundred years); before: the day it falls on before each due day (whole months as calendar months, the month's last day when it is shorter). bounded: a length held to 0…36500, is: what it becomes.",
            cases: cases
        )
    }

    // MARK: Stored kinds

    static func storedKinds() -> Vectors {
        var cases: [JSONValue] = Consequence.allCases.map { consequence -> JSONValue in
            .object([
                "consequence": .string(consequence.rawValue), "weight": .int(consequence.weight),
                "maxAttentionWindowDays": .int(consequence.maxAttentionWindowDays),
                "allowsTimeSensitiveReminders": .bool(consequence.allowsTimeSensitiveReminders),
                "followsUpByDefault": .bool(ReminderProfile.defaultFollowUp(for: consequence)),
            ])
        }
        let raws: [String?] = ["legal", "financial", "health", "comfort", "Legal", "newer", "", nil]
        for raw in raws {
            cases.append(.object(["storedConsequence": raw.map(JSONValue.string) ?? .null, "reads": .string(Consequence(stored: raw).rawValue)]))
        }
        let statuses: [String?] = ["active", "paused", "done", "archived", "snoozed", "", nil]
        for raw in statuses {
            cases.append(.object(["storedStatus": raw.map(JSONValue.string) ?? .null, "reads": .string(ObligationStatus(stored: raw).rawValue)]))
        }
        let ordered = AttentionUrgency.allCases.sorted()
        for urgency in AttentionUrgency.allCases {
            cases.append(.object([
                "urgency": .string(urgency.rawValue), "order": .int(ordered.firstIndex(of: urgency) ?? -1),
                "tone": .string(urgency.tone.rawValue), "isAlarming": .bool(urgency.isAlarming),
                "needsAttentionNow": .bool(urgency.needsAttentionNow),
            ]))
        }
        return Vectors(
            name: "stored-kinds",
            rule: "Consequence (its weight, window, time-sensitive reminders, default follow-up) and Consequence(stored:); ObligationStatus(stored:); AttentionUrgency's order, tone, isAlarming and needsAttentionNow",
            source: "ios/DosarCuSina/Models/Obligations/ObligationTypes.swift, ios/Shared/Urgency.swift",
            shape: "consequence: what it says of itself. storedConsequence / storedStatus: a stored text (null when missing), reads: what this build reads it as (unknown is the loudest). urgency: its place from the most urgent (order 0), its tone, whether the badge counts it and whether it needs the person now.",
            cases: cases
        )
    }

    // MARK: Profiles and their cycle

    static func reminderProfiles() -> Vectors {
        let made: [Profile] = [
            Profile(leadDays: [30, 7, 0]),
            Profile(leadDays: [0, 7, 30, 7, -7], consequence: "financial"),
            Profile(leadDays: [], consequence: "comfort", graceDays: 3),
            Profile(leadDays: [90, 0], travelMargin: 180),
            Profile(leadDays: [40_000, -40_000], consequence: "health", graceDays: -5, followUp: true, travelMargin: 99_999),
            Profile(leadDays: [14, 1], consequence: "newer", followUp: false),
            Profile(leadDays: [7, 1], consequence: "health", graceDays: 7),
        ]
        var cases: [JSONValue] = made.map { input -> JSONValue in
            let profile = input.made
            return .object([
                "input": input.json, "profile": written(profile), "urgencyRule": written(profile.urgencyRule),
                "hasTravelCutoff": .bool(profile.hasTravelCutoff),
            ])
        }
        // Each lead is kept for the cycle when it falls after the day the cycle began.
        let cycles: [(Profile, String, RecurrenceRule, String)] = [
            (Profile(leadDays: [7, 1, 0]), "2026-11-26", .interval(RecurrenceInterval(every: 3, unit: .day), anchor: .dueDate), "every 3 days"),
            (Profile(leadDays: [7, 3]), "2026-11-26", .interval(RecurrenceInterval(every: 3, unit: .day), anchor: .dueDate), "every 3 days, no lead fits"),
            (Profile(leadDays: [30, 7, 0]), "2026-03-31", .interval(RecurrenceInterval(every: 1, unit: .month), anchor: .dueDate), "every month from a month's end"),
            (Profile(leadDays: [30, 7, 0]), "2026-03-30", .interval(RecurrenceInterval(every: 1, unit: .month), anchor: .dueDate), "every month"),
            (Profile(leadDays: [60, 30, 7]), "2026-03-01", .interval(RecurrenceInterval(every: 1, unit: .month), anchor: .dueDate), "every month, after February"),
            (Profile(leadDays: [365, 30]), "2028-02-29", .interval(RecurrenceInterval(every: 1, unit: .year), anchor: .dueDate), "every year from a leap day"),
            (Profile(leadDays: [14, 7, 0]), "2026-12-14", .interval(RecurrenceInterval(every: 2, unit: .week), anchor: .completion), "every two weeks"),
            (Profile(leadDays: [90, 0], travelMargin: 180), "2027-08-31", .interval(RecurrenceInterval(every: 10, unit: .year), anchor: .dueDate), "a passport every ten years"),
            (Profile(leadDays: [90, 0], travelMargin: 180), "2027-08-31", .interval(RecurrenceInterval(every: 7, unit: .month), anchor: .dueDate), "a travel margin longer than the lead's room"),
            (Profile(leadDays: [30, 7]), "2026-11-26", .none, "doesn't repeat"),
            (Profile(leadDays: [30, 7]), "2026-11-26", .fixedDates([MonthDay(month: 3, day: 31), MonthDay(month: 9, day: 30)]), "fixed dates"),
        ]
        for (input, due, rule, what) in cycles {
            let dueDay = day(due)
            let start = RecurrenceEngine.cycleStart(endingOn: dueDay, rule: rule, calendar: .dosar(in: .gmt))
            let profile = input.made.forCycle(startingOn: start, due: dueDay, calendar: .dosar(in: .gmt))
            cases.append(.object([
                "cycle": .string(what), "stored": input.json, "due": .string(due), "cycleStart": iso(start),
                "leadDays": .array(profile.leadDays.map(JSONValue.int)),
            ]))
        }
        return Vectors(
            name: "reminder-profile",
            rule: "ReminderProfile(leadDays:consequence:graceDays:followUpAfterLapse:travelMarginDays:), its urgencyRule and hasTravelCutoff; forCycle(startingOn:due:)",
            source: "ios/DosarCuSina/Models/Obligations/ObligationTypes.swift, ios/DosarCuSina/Services/Obligations/CycleReminders.swift",
            shape: "input: a profile as given (the consequence's stored text; followUpAfterLapse null when it doesn't say); profile: what it is (leads by their size, each once, largest first, every length held to 0…36500, the follow-up by its consequence when it doesn't say); urgencyRule: its rule. cycle: a stored profile of a deadline due on due whose cycle began on cycleStart (RecurrenceEngine's, null when the rule has no set length), leadDays: the leads that cycle reminds with.",
            cases: cases
        )
    }

    // MARK: The urgency rule

    static func urgencyRules() -> Vectors {
        // grace, first lead, window, travel margin; then the due days.
        let rules: [(String, UrgencyRule)] = [
            ("nothing reminds", .noReminders),
            ("a legal deadline, a month ahead", UrgencyRule(graceDays: 0, firstLeadDays: 30, maxWindowDays: 30)),
            ("an identity card, three months ahead, a month's window", UrgencyRule(graceDays: 0, firstLeadDays: 90, maxWindowDays: 30)),
            ("a week's lead in a month's window", UrgencyRule(graceDays: 0, firstLeadDays: 7, maxWindowDays: 30)),
            ("a payment two days ahead", UrgencyRule(graceDays: 0, firstLeadDays: 2, maxWindowDays: 21)),
            ("on the day only, a financial window", UrgencyRule(graceDays: 0, firstLeadDays: 0, maxWindowDays: 21)),
            ("a vaccine with a week's grace", UrgencyRule(graceDays: 7, firstLeadDays: 7, maxWindowDays: 7)),
            ("a chore on the day with three days' grace", UrgencyRule(graceDays: 3, firstLeadDays: 0, maxWindowDays: 3)),
            ("a passport", UrgencyRule(graceDays: 0, firstLeadDays: 90, maxWindowDays: 30, travelMarginDays: 180)),
            ("a travel margin and no window", UrgencyRule(graceDays: 0, firstLeadDays: 0, maxWindowDays: 0, travelMarginDays: 30)),
            ("a travel margin of 45 days", UrgencyRule(graceDays: 2, firstLeadDays: 14, maxWindowDays: 21, travelMarginDays: 45)),
            ("a year's lead", UrgencyRule(graceDays: 0, firstLeadDays: 365, maxWindowDays: 30)),
            ("lengths out of bounds", UrgencyRule(graceDays: -5, firstLeadDays: 99_999, maxWindowDays: -1, travelMarginDays: -30)),
        ]
        let dues = ["2026-03-31", "2028-02-29", "2027-08-31", "2026-12-25"]
        var cases: [JSONValue] = []
        let calendar = Calendar.dosar(in: .gmt)
        for (what, rule) in rules {
            for raw in dues {
                let due = day(raw)
                let anchor = rule.reminderAnchor(for: due, calendar: calendar)
                let start = rule.attentionStart(before: due, calendar: calendar)
                // Every day from before anything changes to past the grace: only where it changes.
                let from = min(start, anchor.adding(days: -UrgencyRule.upcomingWindowDays - 1, calendar: calendar)).adding(days: -3, calendar: calendar)
                let to = due.adding(days: rule.graceDays + 3, calendar: calendar)
                var changes: [JSONValue] = []
                var previous: AttentionUrgency?
                var today = from
                while today <= to {
                    let urgency = rule.urgency(of: due, today: today, calendar: calendar)
                    if urgency != previous { changes.append(.object(["from": iso(today), "urgency": .string(urgency.rawValue)])) }
                    previous = urgency
                    today = today.adding(days: 1, calendar: calendar)
                }
                cases.append(.object([
                    "name": .string(what), "rule": written(rule), "due": .string(raw),
                    "travelCutoff": iso(rule.travelCutoff(before: due, calendar: calendar)), "reminderAnchor": iso(anchor),
                    "attentionStart": iso(start), "windowDays": .int(rule.windowDays(before: due, calendar: calendar)),
                    "sweep": .object(["from": iso(from), "to": iso(to), "changes": .array(changes)]),
                ]))
            }
        }
        return Vectors(
            name: "urgency-rule",
            rule: "UrgencyRule(graceDays:firstLeadDays:maxWindowDays:travelMarginDays:): travelCutoff(before:), reminderAnchor(for:), attentionStart(before:), windowDays(before:) and urgency(of:today:)",
            source: "ios/Shared/Urgency.swift",
            shape: "rule: the rule as made (every length held to 0…36500); due: its due day; then its travel cut-off (null without a margin), the day its reminders count from, the first day it needs the person and how many days ahead that is. sweep: its urgency on every day from from to to, written only where it changes: each change's first day and the urgency from then on.",
            cases: cases
        )
    }

    // MARK: A date on a page

    @MainActor
    static func dateUrgency() throws -> Vectors {
        let scenarios: [(String, [Deadline], [String])] = [
            ("an expiry and its deadline", [
                Deadline(n: 1, due: "2027-03-31", profile: Profile(leadDays: [90, 30, 7])),
                Deadline(n: 2, due: "2026-12-15", profile: Profile(leadDays: [30, 7, 0])),
            ], ["2027-03-31", "2026-12-15", "2027-04-01", "2026-12-14"]),
            ("a paused deadline doesn't drive its date", [
                Deadline(n: 3, status: "paused", due: "2027-01-10", profile: Profile(leadDays: [30], consequence: "financial")),
                Deadline(n: 4, status: "done", due: "2027-02-10", profile: Profile(leadDays: [7], consequence: "health", graceDays: 7)),
                Deadline(n: 5, due: "2027-02-10", profile: Profile(leadDays: [0], consequence: "comfort", graceDays: 3)),
            ], ["2027-01-10", "2027-02-10"]),
            ("a passport's expiry", [
                Deadline(n: 6, due: "2027-08-31", profile: Profile(leadDays: [90, 0], travelMargin: 180)),
            ], ["2027-08-31", "2027-02-28"]),
            ("a section with no deadline", [], ["2026-11-26"]),
        ]
        var cases: [JSONValue] = []
        for (what, deadlines, days) in scenarios {
            let context = try makeContext()
            let asset = Asset(name: "VW Golf 2018", templateKey: "vehicle", values: FieldValues())
            context.insert(asset)
            for deadline in deadlines {
                let made = Obligation(id: id(deadline.n), title: "Termen", kind: .legal, dueDay: day(deadline.due), reminders: deadline.profile.made)
                made.status = ObligationStatus(stored: deadline.status)
                context.insert(made)
                made.asset = asset
            }
            for raw in days {
                let rule = DateUrgency.rule(for: day(raw), on: asset, calendar: .dosar(in: .gmt))
                cases.append(.object([
                    "name": .string(what), "deadlines": .array(deadlines.map(\.json)), "day": .string(raw), "rule": written(rule),
                ]))
            }
        }
        return Vectors(
            name: "date-urgency",
            rule: "DateUrgency.rule(for:on:)",
            source: "ios/DosarCuSina/Services/Attention/DateUrgency.swift",
            shape: "deadlines: a section's deadlines (as in reminder-plan); day: a date its page shows; rule: the urgency rule that date is drawn with (the open deadline due that day's, else nothing reminds).",
            cases: cases
        )
    }

    // MARK: The reminder time

    static func reminderClock() -> Vectors {
        var cases: [JSONValue] = [-100, -1, 0, 540, 1439, 1440, 5000].map { minute -> JSONValue in .object(["clamped": .int(minute), "is": .int(ReminderClock.clamped(minute))]) }
        let moments: [(String, Int, String)] = [
            ("2026-11-26", 540, "Europe/Bucharest"), ("2026-03-29", 210, "Europe/Bucharest"), ("2026-03-29", 180, "Europe/Bucharest"),
            ("2026-03-29", 240, "Europe/Bucharest"), ("2026-10-25", 210, "Europe/Bucharest"), ("2026-03-08", 150, "America/New_York"),
            ("2026-10-04", 120, "Australia/Lord_Howe"), ("2026-10-04", 135, "Australia/Lord_Howe"), ("2026-10-04", 150, "Australia/Lord_Howe"),
            ("2027-04-04", 105, "Australia/Lord_Howe"), ("2026-11-25", 1439, "Pacific/Kiritimati"), ("2026-11-25", 0, "Pacific/Pago_Pago"),
            ("2026-11-26", 2000, "Europe/Bucharest"), ("2026-11-26", -5, "Europe/Bucharest"), ("2026-02-30", 540, "Asia/Kolkata"),
        ]
        for (raw, minute, zone) in moments {
            let calendar = inZone(zone)
            let fire = ReminderPlanner.fireDate(day: day(raw), minuteOfDay: minute, calendar: calendar)
            cases.append(.object([
                "day": .string(raw), "minute": .int(minute), "zone": .string(zone), "fireAt": seconds(fire),
                "trigger": trigger(fire, calendar), "minuteOfDay": .int(ReminderClock.minuteOfDay(of: fire, calendar: calendar)),
            ]))
        }
        let skips: [(Int, Int, String)] = [
            (210, at("2026-11-26", 540, "Europe/Bucharest"), "Europe/Bucharest"), (180, at("2026-11-26", 540, "Europe/Bucharest"), "Europe/Bucharest"),
            (240, at("2026-11-26", 540, "Europe/Bucharest"), "Europe/Bucharest"), (540, at("2026-11-26", 540, "Europe/Bucharest"), "Europe/Bucharest"),
            (210, at("2027-03-28", 600, "Europe/Bucharest"), "Europe/Bucharest"), (135, at("2026-11-26", 540, "Australia/Lord_Howe"), "Australia/Lord_Howe"),
            (120, at("2026-11-26", 540, "Australia/Lord_Howe"), "Australia/Lord_Howe"), (150, at("2026-11-26", 540, "America/New_York"), "America/New_York"),
            (150, at("2026-11-26", 540, "Asia/Kolkata"), "Asia/Kolkata"), (30, at("2026-11-26", 540, "Pacific/Kiritimati"), "Pacific/Kiritimati"),
        ]
        for (minute, now, zone) in skips {
            let found = ReminderClock.springForward(minuteOfDay: minute, after: date(now), calendar: inZone(zone))
            cases.append(.object([
                "springForward": .int(minute), "now": .int(now), "zone": .string(zone),
                "skipped": found.map { .object(["day": iso($0.day), "remindsAt": .int($0.remindsAt)]) } ?? .null,
            ]))
        }
        return Vectors(
            name: "reminder-clock",
            rule: "ReminderClock.clamped, ReminderPlanner.fireDate(day:minuteOfDay:calendar:), ReminderTrigger.components(firingAt:calendar:), ReminderClock.minuteOfDay(of:) and springForward(minuteOfDay:after:)",
            source: "ios/Shared/ReminderClock.swift, ios/DosarCuSina/Services/Reminders/ReminderPlanner.swift, ios/DosarCuSina/Services/Reminders/ReminderTrigger.swift",
            shape: "clamped: a minute of the day, is: held to 0…1439. day, minute, zone: the moment a reminder set for that time fires (seconds since 1970; a time the clocks skip is the first minute after the gap, a time shown twice the first of the two), its date parts as the system gets them (yyyy-MM-ddTHH:mm, Gregorian, in that zone) and the minute the wall clock shows then. springForward: a reminder time, now (seconds since 1970) and zone: the next day within a year the clocks skip it and the time it comes at then, or null.",
            cases: cases
        )
    }

    // MARK: The reminder plan

    struct Plan {
        var name: String
        var now: Int
        var zone: String
        var defaultMinute = 540
        var limit = ReminderPlanner.defaultLimit
        var deadlines: [Deadline]
    }

    static func planCase(_ plan: Plan, badges: Bool) -> JSONValue {
        let calendar = inZone(plan.zone)
        let snapshots = plan.deadlines.map(\.snapshot)
        let now = date(plan.now)
        var made = ReminderPlanner.plan(snapshots, now: now, calendar: calendar, defaultMinuteOfDay: plan.defaultMinute, limit: plan.limit)
        var fields: [String: JSONValue] = [
            "name": .string(plan.name), "now": .int(plan.now), "zone": .string(plan.zone),
            "defaultMinuteOfDay": .int(plan.defaultMinute), "limit": .int(plan.limit),
            "deadlines": .array(plan.deadlines.map(\.json)),
        ]
        if badges {
            made = BadgePlanner.plan(made, obligations: snapshots, now: now, calendar: calendar, limit: plan.limit)
            let today = CalendarDay(now, calendar: calendar)
            fields["counts"] = .array((0...BadgePlanner.horizonDays + 1).map { offset -> JSONValue in
                let day = today.adding(days: offset, calendar: calendar)
                return .object(["day": iso(day), "count": .int(BadgePlanner.count(snapshots, on: day, calendar: calendar))])
            })
        }
        fields["plan"] = .array(made.map { written($0, calendar) })
        return .object(fields)
    }

    static func reminderPlans() -> Vectors {
        let legal = Profile(leadDays: [30, 7, 0])
        let passport = Profile(leadDays: [90, 0], travelMargin: 180)
        let bucharest = "Europe/Bucharest"
        var plans: [Plan] = [
            Plan(name: "an ITP's leads and its follow-up", now: at("2026-11-01", 570, bucharest), zone: bucharest, deadlines: [
                Deadline(n: 1, due: "2026-12-15", profile: legal),
            ]),
            Plan(name: "a lead whose time today has passed", now: at("2026-11-15", 600, bucharest), zone: bucharest, deadlines: [
                Deadline(n: 1, due: "2026-12-15", profile: legal),
            ]),
            Plan(name: "leads in months from a month's end", now: at("2025-01-01", 0, bucharest), zone: bucharest, deadlines: [
                Deadline(n: 2, due: "2026-03-31", profile: Profile(leadDays: [365, 60, 30, 0], consequence: "financial")),
            ]),
            Plan(name: "leads from a leap day", now: at("2026-12-01", 0, bucharest), zone: bucharest, deadlines: [
                Deadline(n: 3, due: "2028-02-29", profile: Profile(leadDays: [730, 365, 30, 1], consequence: "health", graceDays: 7)),
            ]),
            Plan(name: "two leads on one day", now: at("2026-01-01", 0, bucharest), zone: bucharest, deadlines: [
                Deadline(n: 4, due: "2026-03-31", profile: Profile(leadDays: [31, 30, 0])),
            ]),
            Plan(name: "a lead longer than the repeat", now: at("2026-11-20", 0, bucharest), zone: bucharest, deadlines: [
                Deadline(n: 5, due: "2026-11-26", profile: Profile(leadDays: [7, 1, 0], consequence: "comfort", graceDays: 1), cycleStart: "2026-11-23"),
                Deadline(n: 6, due: "2026-11-27", profile: Profile(leadDays: [7, 5], consequence: "comfort"), cycleStart: "2026-11-24"),
            ]),
            Plan(name: "a snooze that ends on a lead's day", now: at("2026-11-20", 600, bucharest), zone: bucharest, deadlines: [
                Deadline(n: 7, due: "2026-12-15", snoozed: "2026-12-08", profile: legal),
            ]),
            Plan(name: "a snooze between leads", now: at("2026-11-20", 600, bucharest), zone: bucharest, deadlines: [
                Deadline(n: 8, due: "2026-12-15", snoozed: "2026-12-10", profile: legal),
            ]),
            Plan(name: "a snooze that ends on the follow-up's day", now: at("2026-12-14", 600, bucharest), zone: bucharest, deadlines: [
                Deadline(n: 9, due: "2026-12-15", snoozed: "2026-12-16", profile: legal),
            ]),
            Plan(name: "a snooze already over", now: at("2026-12-09", 600, bucharest), zone: bucharest, deadlines: [
                Deadline(n: 10, due: "2026-12-15", snoozed: "2026-12-08", profile: legal),
            ]),
            Plan(name: "a reminder time the clocks skip", now: at("2026-03-01", 0, bucharest), zone: bucharest, deadlines: [
                Deadline(n: 11, due: "2026-04-29", profile: Profile(leadDays: [30, 7]), minute: 210),
                Deadline(n: 12, due: "2026-03-29", profile: Profile(leadDays: [0], consequence: "comfort"), minute: 180),
            ]),
            Plan(name: "a reminder time in New York's skipped hour", now: at("2026-03-01", 0, "America/New_York"), zone: "America/New_York", deadlines: [
                Deadline(n: 13, due: "2026-03-09", profile: Profile(leadDays: [1, 0], consequence: "financial"), minute: 150),
            ]),
            Plan(name: "a reminder time in Lord Howe Island's half-hour gap", now: at("2026-09-20", 0, "Australia/Lord_Howe"), zone: "Australia/Lord_Howe", deadlines: [
                Deadline(n: 14, due: "2026-10-05", profile: Profile(leadDays: [1, 0], consequence: "health"), minute: 135),
                Deadline(n: 15, due: "2026-10-04", profile: Profile(leadDays: [0], consequence: "comfort"), minute: 120),
            ]),
            Plan(name: "a reminder time held to the day", now: at("2026-11-01", 0, bucharest), zone: bucharest, deadlines: [
                Deadline(n: 16, due: "2026-11-10", profile: Profile(leadDays: [1], consequence: "financial"), minute: 2000),
                Deadline(n: 17, due: "2026-11-11", profile: Profile(leadDays: [1], consequence: "financial"), minute: -5),
            ]),
            Plan(name: "a deadline already passed", now: at("2026-11-01", 480, bucharest), zone: bucharest, deadlines: [
                Deadline(n: 18, due: "2026-10-31", profile: legal),
                Deadline(n: 19, due: "2026-10-01", profile: legal),
                Deadline(n: 20, due: "2026-10-31", profile: Profile(leadDays: [7, 1], consequence: "health", graceDays: 7)),
                Deadline(n: 21, due: "2026-10-20", snoozed: "2026-11-05", profile: legal),
            ]),
            Plan(name: "a passport counts from its travel cut-off", now: at("2026-06-01", 0, bucharest), zone: bucharest, deadlines: [
                Deadline(n: 22, due: "2027-08-31", profile: passport, inApp: true),
            ]),
            Plan(name: "a passport past its cut-off", now: at("2027-03-15", 600, bucharest), zone: bucharest, deadlines: [
                Deadline(n: 23, due: "2027-08-31", profile: passport, inApp: true),
            ]),
            Plan(name: "a card known after its warnings passed", now: at("2026-11-02", 720, bucharest), zone: bucharest, deadlines: [
                Deadline(n: 24, due: "2026-11-22", profile: Profile(leadDays: [90, 30, 7]), knownSince: at("2026-11-02", 720, bucharest)),
                Deadline(n: 25, due: "2026-11-22", profile: Profile(leadDays: [90, 30]), knownSince: at("2026-11-02", 480, bucharest)),
                Deadline(n: 26, due: "2026-11-22", profile: Profile(leadDays: [30, 7]), knownSince: at("2026-10-01", 480, bucharest)),
                Deadline(n: 27, due: "2026-11-03", profile: Profile(leadDays: [30, 0]), knownSince: at("2026-11-02", 720, bucharest)),
                Deadline(n: 28, due: "2026-11-03", profile: Profile(leadDays: [30]), knownSince: at("2026-11-02", 720, bucharest)),
            ]),
            Plan(name: "a catch-up held back by a snooze", now: at("2026-11-02", 720, bucharest), zone: bucharest, deadlines: [
                Deadline(n: 29, due: "2026-11-22", snoozed: "2026-11-05", profile: Profile(leadDays: [90, 30]), knownSince: at("2026-11-02", 600, bucharest)),
            ]),
            Plan(name: "a passport known after its cut-off", now: at("2027-04-01", 600, bucharest), zone: bucharest, deadlines: [
                Deadline(n: 30, due: "2027-08-31", profile: passport, knownSince: at("2027-04-01", 600, bucharest), inApp: true),
            ]),
            Plan(name: "what reminds and what doesn't", now: at("2026-11-01", 0, bucharest), zone: bucharest, deadlines: [
                Deadline(n: 31, status: "paused", due: "2026-11-20", profile: legal),
                Deadline(n: 32, status: "done", due: "2026-11-20", profile: legal),
                Deadline(n: 33, status: "archived", due: "2026-11-20", profile: legal),
                Deadline(n: 34, due: "2026-11-20", profile: legal, example: true),
                Deadline(n: 35, status: "newer", due: "2026-11-21", profile: Profile(leadDays: [1, 0], consequence: "newer")),
                Deadline(n: 36, due: "2026-11-22", profile: Profile(leadDays: [1, 0], consequence: "comfort"), sensitive: true),
                Deadline(n: 37, due: "2026-11-23", profile: Profile(leadDays: [2, 1, 0], consequence: "financial", followUp: false), inApp: true),
            ]),
        ]
        // The same deadlines, as far east and as far west as clocks go.
        for zone in ["Pacific/Kiritimati", "Pacific/Pago_Pago", "UTC"] {
            plans.append(Plan(name: "far from Bucharest: \(zone)", now: 1_795_737_600, zone: zone, defaultMinute: 1200, deadlines: [
                Deadline(n: 38, due: "2026-12-01", profile: Profile(leadDays: [7, 1, 0])),
                Deadline(n: 39, due: "2026-11-28", profile: Profile(leadDays: [1, 0], consequence: "health"), minute: 30),
            ]))
        }
        // More than the phone keeps: every deadline's next reminder first, the most consequential first.
        let consequences = ["comfort", "legal", "health", "financial"]
        plans.append(Plan(name: "more than the phone keeps", now: at("2026-11-01", 0, bucharest), zone: bucharest, limit: 8, deadlines: (0..<10).map { i in
            Deadline(n: 40 + i, due: day("2026-12-01").adding(days: i * 3, calendar: .dosar(in: .gmt)).isoString,
                     profile: Profile(leadDays: [21, 14, 7, 0], consequence: consequences[i % 4]))
        }))
        plans.append(Plan(name: "more than the phone keeps, running out tomorrow", now: at("2026-11-01", 600, bucharest), zone: bucharest, limit: 3, deadlines: [
            Deadline(n: 50, due: "2026-11-02", profile: Profile(leadDays: [0], consequence: "comfort")),
            Deadline(n: 51, due: "2026-11-02", profile: Profile(leadDays: [0], consequence: "comfort"), minute: 600),
            Deadline(n: 52, due: "2026-11-02", profile: Profile(leadDays: [0], consequence: "comfort"), minute: 660),
            Deadline(n: 53, due: "2026-11-02", profile: Profile(leadDays: [0], consequence: "comfort"), minute: 720),
        ]))
        plans.append(Plan(name: "more than the phone keeps, nothing kept", now: at("2026-11-01", 0, bucharest), zone: bucharest, limit: 0, deadlines: [
            Deadline(n: 54, due: "2026-11-10", profile: legal),
        ]))
        return Vectors(
            name: "reminder-plan",
            rule: "ReminderPlanner.plan(_:now:calendar:defaultMinuteOfDay:limit:)",
            source: "ios/DosarCuSina/Services/Reminders/ReminderPlanner.swift",
            shape: "now (seconds since 1970), zone, defaultMinuteOfDay (the general reminder time), limit (how many the phone keeps); deadlines: each one's id, stored status, due day, snoozedUntil, stored reminders (as in reminder-profile), cycleStart (its reminders are those of the cycle that began then, null keeps every lead), reminderMinuteOfDay (null for the general time), isSensitive, isExample, cycleKnownSince (seconds since 1970, or null) and closesInTheApp. plan: every reminder in order, each with its identifier, the deadline and cycle it is about, when it fires (seconds since 1970) and its date parts as the system gets them, whether it is time-sensitive, protected or closes in the app, its badge (null: none) and whether it shows. No words.",
            cases: plans.map { planCase($0, badges: false) }
        )
    }

    // MARK: The badge

    static func badgePlans() -> Vectors {
        let bucharest = "Europe/Bucharest"
        var plans: [Plan] = [
            Plan(name: "the badge across a week", now: at("2026-11-26", 600, bucharest), zone: bucharest, deadlines: [
                Deadline(n: 1, due: "2026-11-28", profile: Profile(leadDays: [7, 0])),
                Deadline(n: 2, due: "2026-11-27", profile: Profile(leadDays: [1], consequence: "health", graceDays: 2)),
                Deadline(n: 3, due: "2026-11-26", profile: Profile(leadDays: [0], consequence: "comfort", graceDays: 3)),
                Deadline(n: 4, due: "2026-11-30", snoozed: "2026-12-02", profile: Profile(leadDays: [0], consequence: "financial")),
                Deadline(n: 5, status: "paused", due: "2026-11-27", profile: Profile(leadDays: [0])),
                Deadline(n: 6, due: "2026-11-29", profile: Profile(leadDays: [0], consequence: "financial"), example: true),
            ]),
            Plan(name: "nothing changes", now: at("2026-11-26", 600, bucharest), zone: bucharest, deadlines: [
                Deadline(n: 7, due: "2026-10-01", profile: Profile(leadDays: [0])),
                Deadline(n: 8, due: "2027-05-01", profile: Profile(leadDays: [30])),
            ]),
            Plan(name: "a badge with little room", now: at("2026-11-26", 600, bucharest), zone: bucharest, limit: 3, deadlines: [
                Deadline(n: 9, due: "2026-11-27", profile: Profile(leadDays: [0], consequence: "comfort")),
                Deadline(n: 10, due: "2026-11-28", profile: Profile(leadDays: [0], consequence: "comfort", graceDays: 1)),
                Deadline(n: 11, due: "2026-11-30", profile: Profile(leadDays: [0], consequence: "comfort", graceDays: 1)),
                Deadline(n: 12, due: "2026-12-02", profile: Profile(leadDays: [0], consequence: "comfort", graceDays: 1)),
            ]),
            Plan(name: "a badge across the change of clocks", now: at("2026-10-23", 600, bucharest), zone: bucharest, deadlines: [
                Deadline(n: 13, due: "2026-10-25", profile: Profile(leadDays: [1, 0], consequence: "health", graceDays: 1), minute: 210),
            ]),
        ]
        for zone in ["Pacific/Kiritimati", "Pacific/Pago_Pago"] {
            plans.append(Plan(name: "the badge far from Bucharest: \(zone)", now: 1_795_737_600, zone: zone, deadlines: [
                Deadline(n: 14, due: "2026-11-27", profile: Profile(leadDays: [1, 0], consequence: "health", graceDays: 2)),
                Deadline(n: 15, due: "2026-11-29", profile: Profile(leadDays: [0], consequence: "financial")),
            ]))
        }
        return Vectors(
            name: "badge-plan",
            rule: "BadgePlanner.plan(_:obligations:now:calendar:limit:) over ReminderPlanner.plan, and BadgePlanner.count(_:on:calendar:)",
            source: "ios/DosarCuSina/Services/Reminders/BadgePlanner.swift",
            shape: "As reminder-plan; counts: the badge on each day from today (where the phone is) through the day after the horizon (active, not snoozed, overdue past its grace or due today); plan: the reminders, each with the badge of the day it fires, then a badge-only reminder (obligation.badge.<day>, at the day's start, showing nothing) on each of the next seven days whose count changes, while there is room under the limit.",
            cases: plans.map { planCase($0, badges: true) }
        )
    }

    // MARK: Identifiers

    static func reminderIdentifiers() -> Vectors {
        let one = id(1).uuidString.lowercased()
        let identifiers = [
            "obligation.\(one).d7", "obligation.\(one).d0", "obligation.\(one).d-3", "obligation.\(one).d", "obligation.\(one).dx",
            "obligation.\(one).lapse", "obligation.\(one).snooze", "obligation.\(one).catchup", "obligation.\(one).t30",
            "obligation.\(id(1).uuidString).d30", "obligation..\(one).d7", "obligation.\(one)..d7", "obligation.\(one).d7.",
            "obligation.\(one)", "obligation.badge.2026-11-27", "obligation.continue", "reminder.\(one).d7",
            "obligation.1-1-1-1-1.d7", "obligation.\(one).d36500", "obligation.\(one).d+2",
        ]
        let delivered = ["2026-11-26", "2026-03-01"]
        var cases: [JSONValue] = []
        for identifier in identifiers {
            cases.append(.object([
                "identifier": .string(identifier), "obligationId": uuid(ReminderPlanner.obligationId(fromIdentifier: identifier)),
                "cycles": .array(delivered.map { raw -> JSONValue in
                    .object(["deliveredOn": .string(raw), "cycle": iso(ReminderPlanner.cycle(fromIdentifier: identifier, deliveredOn: day(raw), calendar: .dosar(in: .gmt)))])
                }),
            ]))
        }
        cases.append(.object(["made": .string(ReminderPlanner.identifier(obligationId: id(1), suffix: "d7")), "suffix": "d7", "id": uuid(id(1))]))
        return Vectors(
            name: "reminder-identifiers",
            rule: "ReminderPlanner.identifier(obligationId:suffix:), obligationId(fromIdentifier:) and cycle(fromIdentifier:deliveredOn:)",
            source: "ios/DosarCuSina/Services/Reminders/ReminderPlanner.swift",
            shape: "identifier: a reminder's identifier; obligationId: the deadline it names (null for none); cycles: for a day it was delivered on, the cycle it was about when it carries none (a lead d<n> is n days later, the follow-up the day before; null when it can't be told). made: the identifier made for id and suffix.",
            cases: cases
        )
    }

    // MARK: Shown reminders

    static func shownReminders() -> Vectors {
        let open: [UUID: CalendarDay] = [id(1): day("2026-11-30"), id(2): day("2026-12-05")]
        let locked: Set<UUID> = [id(2)]
        let shown: [DeliveredReminder] = [
            DeliveredReminder(identifier: "obligation.badge.2026-11-27", obligationId: nil, cycle: nil),
            DeliveredReminder(identifier: "obligation.continue", obligationId: nil, cycle: nil),
            DeliveredReminder(identifier: "a", obligationId: id(1), cycle: day("2026-11-30")),
            DeliveredReminder(identifier: "b", obligationId: id(1), cycle: day("2026-10-30")),
            DeliveredReminder(identifier: "c", obligationId: id(1), cycle: nil),
            DeliveredReminder(identifier: "d", obligationId: id(3), cycle: day("2026-11-30")),
            DeliveredReminder(identifier: "e", obligationId: id(2), cycle: day("2026-12-05")),
            DeliveredReminder(identifier: "f", obligationId: id(2), cycle: day("2026-12-05"), isProtected: true),
            DeliveredReminder(identifier: "g", obligationId: id(1), cycle: day("2026-11-30"), isProtected: true),
            DeliveredReminder(identifier: "h", obligationId: id(2), cycle: day("2026-11-05"), isProtected: true),
        ]
        let cases: [JSONValue] = shown.map { reminder -> JSONValue in
            .object([
                "openCycles": .object(Dictionary(open.map { ($0.key.uuidString.lowercased(), iso($0.value)) }, uniquingKeysWith: { first, _ in first })),
                "locked": .array(locked.map { uuid($0) }),
                "identifier": .string(reminder.identifier), "obligationId": uuid(reminder.obligationId), "cycle": iso(reminder.cycle),
                "isProtected": .bool(reminder.isProtected),
                "isOutdated": .bool(NotificationReconciler.isOutdated(reminder, openCycles: open, locked: locked)),
            ])
        }
        return Vectors(
            name: "shown-reminders",
            rule: "NotificationReconciler.isOutdated(_:openCycles:locked:)",
            source: "ios/DosarCuSina/Services/Reminders/NotificationReconciler.swift",
            shape: "openCycles: the due day of each deadline that still reminds; locked: the deadlines whose category is locked now; a reminder shown in Notification Center (its identifier, deadline, cycle and whether it was written with a locked category's words); isOutdated: whether a pass clears it (its cycle closed or gone, or it names a deadline locked since).",
            cases: cases
        )
    }
}
