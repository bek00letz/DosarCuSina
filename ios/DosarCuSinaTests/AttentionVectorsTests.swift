import Foundation
import SwiftData
import Testing
@testable import DosarCuSina

/// What the app puts in front of the person, run over cases chosen to bite and written to
/// `shared/test-vectors/attention/`, one file per rule: each input with the answer this app gives.
/// The rules are `AttentionModel` (one deadline's entry, Urmează's digest, the calm notes of „Din
/// timp”), `BoxStatus` (a box's line and a hero's, a grouped box's count, a locked section's line),
/// `DueWording`'s data (which verb, how far, which day, a passport's two lines) and the binder
/// grid's data (`SectionOffers`, `BinderLayout.holds`, `defaultOrder`, `addBoxNames`). The Android
/// app's tests read the same files and must give the same answers (docs/ANDROID_PLAN.md, "How
/// parity is kept"): `core.attention` in android/core, and the catalog's `BinderLayout` and
/// `SectionOffers`. A sibling of `ValueVectorsTests`, with a folder of its own.
///
/// No answer depends on the machine: days are counted in Bucharest's calendar whatever the
/// simulator's zone (`Calendar.bucharest`), every "now" is a case's own noon, and ids and moments
/// are fixed. The app's words are written beside the data (`text`, `title`, `detail`) only for the
/// Android app's strings to come; its tests read the data. Placeholder data only.
@Suite("Attention vectors")
struct AttentionVectorsTests {
    static var folder: URL {
        URL(filePath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appending(path: "shared/test-vectors/attention")
    }

    /// How to bring the files up to date, said when one isn't.
    static let regenerate = """
    is out of date with the attention rules. Bring shared/test-vectors/attention up to date: \
    TEST_RUNNER_ATTENTION_VECTORS_WRITE=1 ./tests/run_tests.sh (or run AttentionVectorsTests in Xcode with \
    ATTENTION_VECTORS_WRITE=1 in the scheme's environment), review the diff and commit it, then run the \
    Android tests (./gradlew :core:test :catalog:test in android/), which read the same files.
    """

    typealias Vectors = ValueVectorsTests.Vectors
    typealias Profile = UrgencyVectorsTests.Profile

    /// The one calendar every case counts days in.
    static let calendar = Calendar.bucharest

    @MainActor
    @Test("shared/test-vectors/attention is up to date with the attention rules")
    func vectorsAreUpToDate() throws {
        let files = try Self.all()
        let environment = ProcessInfo.processInfo.environment
        let writes = environment["ATTENTION_VECTORS_WRITE"] == "1"
        // A run that keeps its results (GitHub's, through tests/run_tests.sh) leaves a file that
        // is out of date made afresh there, so the run's test-results holds what to commit.
        let out = environment["VECTORS_OUT"].map { URL(filePath: $0).appending(path: "attention") }
        let manager = FileManager.default
        if writes { try manager.createDirectory(at: Self.folder, withIntermediateDirectories: true) }
        for file in files {
            let url = Self.folder.appending(path: "\(file.name).json")
            let fresh = try ValueVectorsTests.render(file)
                .replacingOccurrences(of: "ios/DosarCuSinaTests/ValueVectorsTests.swift", with: "ios/DosarCuSinaTests/AttentionVectorsTests.swift")
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

    @MainActor
    static func all() throws -> [Vectors] {
        try [entries(), digests(), boxStatus(), dueLines(), calmNotes(), sectionOffers(), binderGrid()]
    }

    // MARK: Helpers

    static func day(_ iso: String) -> CalendarDay { CalendarDay(iso) }
    static func noonOf(_ iso: String) -> Date { day(iso).noonDate(in: calendar) }

    /// The placeholder id of deadline `n`: letters in every group, so no run of its digits reads
    /// as a card number to the privacy check.
    static func id(_ n: Int) -> UUID { UrgencyVectorsTests.id(n) }

    /// The placeholder id of section `n`, apart from the deadlines' ids.
    static func section(_ n: Int) -> UUID {
        let digits = String(n)
        let text = "bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbb" + String(repeating: "0", count: max(0, 4 - digits.count)) + digits
        return UUID(uuidString: text) ?? UUID()
    }

    static func uuid(_ id: UUID?) -> JSONValue { id.map { .string($0.uuidString.lowercased()) } ?? .null }
    static func iso(_ day: CalendarDay?) -> JSONValue { day.map { .string($0.isoString) } ?? .null }
    static func text(_ value: String?) -> JSONValue { value.map(JSONValue.string) ?? .null }
    static func optional(_ value: Int?) -> JSONValue { value.map(JSONValue.int) ?? .null }

    static func money(_ value: Money?) -> JSONValue { SubscriptionVectorsTests.money(value) }

    /// A fixed moment: seconds after a placeholder start.
    static func moment(_ seconds: Int) -> Date { Date(timeIntervalSince1970: TimeInterval(1_790_000_000 + seconds)) }
    static func seconds(_ date: Date) -> JSONValue { .int(Int(date.timeIntervalSince1970.rounded())) }

    /// A deadline as a case gives it, with what the attention list reads: its title, its cost and
    /// the section it belongs to.
    struct Deadline {
        var n: Int
        var title: String
        var kind: ObligationKind = .legal
        var status = "active"
        var due: String
        var snoozed: String?
        var profile: Profile
        var cost: String?
        var currency = "RON"
        var section: Int?
        var sectionName: String?
        var sensitive = false

        var snapshot: ObligationSnapshot {
            ObligationSnapshot(
                id: AttentionVectorsTests.id(n), title: title, kind: kind, status: ObligationStatus(stored: status),
                dueDay: AttentionVectorsTests.day(due), snoozedUntil: snoozed.map(AttentionVectorsTests.day),
                reminders: profile.made, estimatedCost: cost.map { SubscriptionVectorsTests.money($0, currency) },
                assetId: section.map(AttentionVectorsTests.section), assetName: sectionName, isSensitive: sensitive
            )
        }

        var json: JSONValue {
            .object([
                "id": AttentionVectorsTests.uuid(AttentionVectorsTests.id(n)), "title": .string(title), "kind": .string(kind.rawValue),
                "status": .string(status), "dueDay": .string(due), "snoozedUntil": AttentionVectorsTests.text(snoozed),
                "reminders": profile.json, "estimatedCost": AttentionVectorsTests.money(snapshot.estimatedCost),
                "sectionId": AttentionVectorsTests.uuid(section.map(AttentionVectorsTests.section)),
                "sectionName": AttentionVectorsTests.text(sectionName), "isSensitive": .bool(sensitive),
            ])
        }
    }

    static func written(_ entry: AttentionEntry) -> JSONValue {
        .object([
            "id": uuid(entry.obligation.id), "daysRemaining": .int(entry.daysRemaining),
            "urgency": .string(entry.urgency.rawValue), "score": .int(entry.score),
        ])
    }

    // The profiles the cases use, as the catalog declares them for their kinds.
    static let legal = Profile(leadDays: [30, 7, 0])
    static let insurance = Profile(leadDays: [30, 7, 1])
    static let tax = Profile(leadDays: [14, 1], consequence: "financial")
    static let health = Profile(leadDays: [7, 0], consequence: "health", graceDays: 7)
    static let upkeep = Profile(leadDays: [14], consequence: "comfort")
    static let chore = Profile(leadDays: [0], consequence: "comfort", graceDays: 2)
    static let passport = Profile(leadDays: [30, 7], travelMargin: 180)

    /// A binder on 26 November 2026: something of every urgency, a snoozed, a paused, a done and an
    /// archived deadline, a passport past its travel cut-off and the household's own deadline.
    static let binder: [Deadline] = [
        Deadline(n: 1, title: "RCA", kind: .insurance, due: "2026-11-20", profile: insurance, cost: "1250", section: 1, sectionName: "VW Golf 2018"),
        Deadline(n: 2, title: "Vaccin antirabic", kind: .health, due: "2026-11-23", profile: health, section: 2, sectionName: "PawPaw"),
        Deadline(n: 3, title: "Impozit pe clădiri", kind: .tax, due: "2026-11-26", profile: tax, cost: "450", section: 3, sectionName: "Apartament Exemplu"),
        Deadline(n: 4, title: "ITP", due: "2026-12-03", profile: legal, section: 1, sectionName: "VW Golf 2018"),
        Deadline(n: 5, title: "Revizie", kind: .maintenance, due: "2026-12-15", profile: upkeep, cost: "900", section: 1, sectionName: "VW Golf 2018"),
        Deadline(n: 6, title: "Rovinietă", due: "2027-03-01", profile: legal, cost: "28", currency: "EUR", section: 1, sectionName: "VW Golf 2018"),
        Deadline(n: 7, title: "Pașaport", kind: .renewal, due: "2027-04-10", profile: passport, section: 4, sectionName: "Persoană Exemplu"),
        Deadline(n: 8, title: "Udat", kind: .routine, due: "2026-11-27", profile: chore, section: 5, sectionName: "Monstera"),
        Deadline(n: 9, title: "Abonament sală", kind: .payment, due: "2026-11-25", snoozed: "2026-11-28", profile: tax, section: 6, sectionName: "Sală Exemplu"),
        Deadline(n: 10, title: "Filtru", kind: .maintenance, status: "paused", due: "2026-11-24", profile: upkeep, section: 3, sectionName: "Apartament Exemplu"),
        Deadline(n: 11, title: "Taxă veche", kind: .tax, status: "done", due: "2026-11-01", profile: tax, section: 3, sectionName: "Apartament Exemplu"),
        Deadline(n: 12, title: "Asigurare veche", kind: .insurance, status: "archived", due: "2026-11-02", profile: insurance, section: 3, sectionName: "Apartament Exemplu"),
        Deadline(n: 13, title: "Asigurare locuință", kind: .insurance, due: "2027-01-05", profile: insurance, cost: "1200", section: 3, sectionName: "Apartament Exemplu"),
        Deadline(n: 14, title: "Declarația unică", kind: .tax, due: "2026-12-20", profile: tax),
        Deadline(n: 15, title: "Deparazitare", kind: .health, due: "2026-12-15", profile: Profile(leadDays: [7], consequence: "health"), section: 2, sectionName: "PawPaw"),
        Deadline(n: 16, title: "Taxă locală", kind: .tax, due: "2026-12-10", profile: tax, section: 3, sectionName: "Apartament Exemplu"),
        Deadline(n: 17, title: "Schimb ulei", kind: .maintenance, due: "2026-12-10", profile: upkeep, section: 3, sectionName: "Apartament Exemplu"),
    ]

    // MARK: One deadline

    static func entries() -> Vectors {
        var cases: [(today: String, deadline: Deadline)] = binder.map { ("2026-11-26", $0) }
        // How the score moves as the day comes, and a cost's nudge at its limits.
        for today in ["2026-10-20", "2026-11-03", "2026-11-26", "2026-11-28", "2026-12-04", "2027-01-15"] {
            cases.append((today, Deadline(n: 20, title: "ITP", due: "2026-12-03", profile: legal, cost: "0.4")))
        }
        for (index, cost) in ["0", "1", "9", "99", "999", "1000000", "12.75"].enumerated() {
            cases.append(("2026-11-26", Deadline(n: 21 + index, title: "Factură", kind: .payment, due: "2026-11-30", profile: tax, cost: cost)))
        }
        // Late for a long time: lateness stops counting after a month.
        cases.append(("2026-11-26", Deadline(n: 30, title: "RCA", kind: .insurance, due: "2026-08-01", profile: insurance)))
        cases.append(("2026-11-26", Deadline(n: 31, title: "Udat", kind: .routine, due: "2026-11-25", profile: chore)))
        return Vectors(
            name: "attention-entry",
            rule: "AttentionModel.entry(for:today:calendar:) and its score",
            source: "ios/DosarCuSina/Services/Attention/AttentionModel.swift",
            shape: "today and one deadline (its id, title, kind, stored status, due day, snoozedUntil, its reminders as in the urgency vectors' reminder-profile, estimatedCost {amount, currency} or null, sectionId and sectionName or null, isSensitive); entry: its daysRemaining, its urgency by the one rule (stored text) and its score.",
            cases: cases.map { today, deadline in
                .object([
                    "today": .string(today), "deadline": deadline.json,
                    "entry": written(AttentionModel.entry(for: deadline.snapshot, today: day(today), calendar: calendar)),
                ])
            }
        )
    }

    // MARK: Urmează

    static func digests() -> Vectors {
        let plants = (0..<8).map { i in
            Deadline(n: 40 + i, title: "Udat \(i + 1)", kind: .routine, due: "2026-11-27", profile: chore, section: 10 + i, sectionName: "Plantă \(i + 1)")
        }
        let lists: [(name: String, today: String, maxNow: Int, deadlines: [Deadline])] = [
            ("a binder of every urgency", "2026-11-26", 5, binder),
            ("only the most pressing, as a box asks", "2026-11-26", 1, binder),
            ("nothing", "2026-11-26", 5, []),
            ("nothing needs the person yet", "2026-10-01", 5, binder),
            ("more than Acum holds", "2026-11-26", 5, plants),
            ("a month on", "2026-12-26", 5, binder),
        ]
        let cases: [JSONValue] = lists.map { list in
            let digest = AttentionModel.digest(list.deadlines.map(\.snapshot), now: noonOf(list.today), calendar: calendar, limits: .init(maxNow: list.maxNow))
            return .object([
                "name": .string(list.name), "today": .string(list.today), "maxNow": .int(list.maxNow),
                "deadlines": .array(list.deadlines.map(\.json)),
                "now": .array(digest.now.map(written)),
                "soon": .array(digest.soon.map { group in
                    .object([
                        "sectionId": uuid(group.assetId), "sectionName": .string(group.assetName),
                        "entries": .array(group.entries.map(written)),
                    ])
                }),
                "later": .object([
                    "count": .int(digest.later.count), "nextDay": iso(digest.later.nextDay),
                    "estimatedCost": .array(digest.later.estimatedCost.amounts.map { money($0) }),
                ]),
                "overflowCount": .int(digest.overflowCount), "hiddenCount": .int(digest.hiddenCount),
                "needsActionCount": .int(digest.needsActionCount), "isAllClear": .bool(digest.isAllClear),
            ])
        }
        return Vectors(
            name: "attention-digest",
            rule: "AttentionModel.digest(_:now:calendar:limits:)",
            source: "ios/DosarCuSina/Services/Attention/AttentionModel.swift",
            shape: "today, maxNow (the most Acum lists) and the deadlines, each as in attention-entry; now: Acum's entries in order; soon: Curând's groups in order, each its sectionId (null for the household's own deadlines), the name it is ordered by (the household's own group: „Fără secțiune”, the screen's words) and its entries in order; later: how many, the first day and what they cost by currency (default first); overflowCount, hiddenCount (snoozed and paused), needsActionCount (the badge's count) and isAllClear.",
            cases: cases
        )
    }

    // MARK: Boxes

    static func boxStatus() -> Vectors {
        struct Box {
            var name: String
            var today: String
            var sections: [Int]
            var deadlines: [Deadline]
            /// How many of the category's sections a grouped box holds, and its noun.
            var counting: (count: Int, noun: SectionNoun?)?
        }
        let car = [binder[0], binder[3], binder[4], binder[5]]
        let card = Deadline(n: 60, title: "Carte de identitate", kind: .renewal, due: "2026-12-01", profile: legal, section: 21, sectionName: "Carte de identitate", sensitive: true)
        let person = Deadline(n: 61, title: "Analize", kind: .health, due: "2026-12-20", profile: Profile(leadDays: [7], consequence: "health"), section: 20, sectionName: "Persoană Exemplu")
        let boxes: [Box] = [
            Box(name: "a car's box, the most pressing of its deadlines", today: "2026-11-26", sections: [1], deadlines: car + [binder[1]]),
            Box(name: "all good: nothing in its window", today: "2026-11-26", sections: [1], deadlines: [binder[5]]),
            Box(name: "empty", today: "2026-11-26", sections: [1], deadlines: []),
            Box(name: "due today counts on the badge", today: "2026-12-03", sections: [1], deadlines: car),
            Box(name: "late within its grace", today: "2026-11-26", sections: [2], deadlines: [binder[1]]),
            Box(name: "a person's box with a locked identity card filed under it", today: "2026-11-26", sections: [20, 21], deadlines: [card, person]),
            Box(name: "three plants grouped into one box", today: "2026-11-26", sections: [5, 30, 31], deadlines: [binder[7], Deadline(n: 62, title: "Fertilizat", kind: .routine, due: "2026-12-20", profile: chore, section: 30, sectionName: "Ficus")],
                counting: (3, SectionNoun.plant)),
            Box(name: "a grouped box of a category of one's own, all good", today: "2026-11-26", sections: [40, 41], deadlines: [], counting: (2, nil)),
            Box(name: "two cars grouped, one late", today: "2026-11-26", sections: [1, 50], deadlines: car + [Deadline(n: 63, title: "RCA", kind: .insurance, due: "2026-11-01", profile: insurance, section: 50, sectionName: "Dacia Logan 2020")],
                counting: (2, SectionNoun.car)),
        ]
        let cases: [JSONValue] = boxes.map { box in
            let now = noonOf(box.today)
            let status = BoxStatus.make(forAssets: Set(box.sections.map(section)), in: box.deadlines.map(\.snapshot), now: now, calendar: calendar)
            var lines: [JSONValue] = []
            for isSensitive in [false, true] {
                for sectionsClosed in [true, false] {
                    let locked: (Bool) -> Bool = { sectionIsSensitive in sectionsClosed && sectionIsSensitive }
                    lines.append(.object([
                        "isSensitive": .bool(isSensitive), "lockedSectionsClosed": .bool(sectionsClosed),
                        "showsTitle": .bool(status.showsTitle(isSensitive: isSensitive, isLocked: locked)),
                        "text": .string(status.line(isSensitive: isSensitive, isLocked: locked, now: now, calendar: calendar)),
                    ]))
                }
            }
            var object: [String: JSONValue] = [
                "name": .string(box.name), "today": .string(box.today),
                "sections": .array(box.sections.map { uuid(section($0)) }),
                "deadlines": .array(box.deadlines.map(\.json)),
                "entry": status.entry.map(written) ?? .null,
                "isAlarming": .bool(status.isAlarming), "urgencyTone": .string(status.urgencyTone.rawValue),
                "lines": .array(lines),
            ]
            if let counting = box.counting {
                object["counting"] = .object([
                    "count": .int(counting.count), "noun": text(counting.noun?.rawValue),
                    "text": .string(status.line(counting: counting.count, of: counting.noun, isSensitive: false, now: now, calendar: calendar)),
                ])
            }
            return .object(object)
        }
        return Vectors(
            name: "box-status",
            rule: "BoxStatus.make(forAssets:in:now:calendar:), showsTitle(isSensitive:isLocked:), line(isSensitive:isLocked:) and line(counting:of:isSensitive:isLocked:)",
            source: "ios/DosarCuSina/Services/Attention/BoxStatus.swift",
            shape: "today, the box's sections (its own and what is filed under it) and the deadlines, each as in attention-entry; entry: the deadline its line shows (as in attention-entry) or null when all is good; isAlarming and urgencyTone; lines: for the box locked or not (isSensitive; false is also a section's hero) and the locked sections filed in it closed or open right now, whether the line names its deadline (showsTitle) and its words (text); counting, for a box holding a category's sections grouped into one: how many, the category's noun (null: sections) and the words.",
            cases: cases
        )
    }

    // MARK: Due lines

    static func dueLines() -> Vectors {
        var cases: [JSONValue] = []
        let kinds = ObligationKind.allCases
        let days: [(today: String, due: String)] = [
            ("2026-11-26", "2026-11-26"), ("2026-11-26", "2026-11-27"), ("2026-11-26", "2026-11-25"),
            ("2026-11-26", "2026-12-01"), ("2026-11-26", "2026-11-20"), ("2026-11-26", "2027-02-14"),
            ("2026-11-26", "2025-12-31"), ("2026-12-31", "2027-01-01"), ("2027-01-01", "2026-12-31"),
        ]
        for kind in kinds {
            for pair in days {
                let today = day(pair.today)
                let due = day(pair.due)
                let remaining = today.days(to: due, calendar: calendar)
                cases.append(.object([
                    "kind": .string(kind.rawValue), "today": .string(pair.today), "due": .string(pair.due),
                    "line": .object([
                        "verb": .string(DueWording.verbKind(for: kind).rawValue), "isLate": .bool(remaining < 0),
                        "when": .string(DueWording.when(daysRemaining: remaining).rawValue), "daysRemaining": .int(remaining),
                        "showsYear": .bool(DueWording.showsYear(due, today: today)),
                    ]),
                    "text": .string(DueWording.line(kind: kind, due: due, today: today, calendar: calendar)),
                ]))
            }
        }
        // A passport's two lines, before and past its travel cut-off and once it has expired; a
        // document without a cut-off keeps its due line.
        let travel: [(today: String, due: String, profile: Profile)] = [
            ("2026-11-26", "2027-08-12", passport), ("2027-02-12", "2027-08-12", passport), ("2027-02-13", "2027-08-12", passport),
            ("2027-08-12", "2027-08-12", passport), ("2027-08-13", "2027-08-12", passport), ("2026-11-26", "2028-03-01", passport),
            ("2026-11-26", "2027-08-12", legal),
        ]
        for pair in travel {
            let today = day(pair.today)
            let due = day(pair.due)
            let rule = pair.profile.made.urgencyRule
            let lines: JSONValue
            switch DueWording.travel(due: due, rule: rule, today: today, calendar: calendar) {
            case nil:
                lines = .null
            case .expired(let expiry):
                lines = .object(["expired": .object(["day": iso(expiry), "showsYear": .bool(DueWording.showsYear(expiry, today: today))])])
            case .valid(let expiry, let cutoff, let stillGood):
                lines = .object(["valid": .object([
                    "expiry": .object(["day": iso(expiry), "showsYear": .bool(DueWording.showsYear(expiry, today: today))]),
                    "goodForTravelUntil": .object(["day": iso(cutoff), "showsYear": .bool(DueWording.showsYear(cutoff, today: today))]),
                    "stillGoodForTravel": .bool(stillGood),
                ])])
            }
            cases.append(.object([
                "today": .string(pair.today), "due": .string(pair.due), "reminders": pair.profile.json,
                "travel": lines,
                "texts": DueWording.travelLines(due: due, rule: rule, today: today, calendar: calendar).map { JSONValue.array($0.map(JSONValue.string)) } ?? .null,
            ]))
        }
        return Vectors(
            name: "due-line",
            rule: "DueWording.verbKind(for:), when(daysRemaining:), showsYear(_:today:), line(kind:due:today:calendar:), travel(due:rule:today:calendar:) and travelLines",
            source: "ios/DosarCuSina/Services/Attention/DueWording.swift",
            shape: "A due line: kind, today and due; line: the verb (expires, pay, do), whether it is late, how far it is said (yesterday, ago, today, tomorrow, inside), daysRemaining and whether its date shows the year; text: its words. A passport's lines: today, due and its reminders (as in the urgency vectors' reminder-profile, a travel margin in days); travel: null without a cut-off, else expired with its day, or valid with its expiry, its last day good for travel (each a day and whether it shows the year) and whether it still is; texts: their words, or null.",
            cases: cases
        )
    }

    // MARK: Din timp

    static func calmNotes() -> Vectors {
        struct Watch {
            var number: Int
            var service: String?
            var cycle: RecurrenceInterval = .months(1)
            var days: [String]
            var isSensitive = false
        }
        let lists: [(name: String, today: String, watches: [Watch], suggestions: (count: Int, topics: [String]))] = [
            ("bills that haven't come, then one suggestion", "2026-11-10", [
                Watch(number: 1, service: ServiceKind.gas, days: ["2026-09-20"]),
                Watch(number: 2, service: ServiceKind.mobile, days: ["2026-09-10"], isSensitive: true),
                Watch(number: 3, service: ServiceKind.water, cycle: .months(3), days: ["2026-07-05"]),
                Watch(number: 4, service: ServiceKind.electricity, days: ["2026-11-01"]),
            ], (1, ["Ce ține de altă secțiune"])),
            ("a weekly bill and several suggestions", "2026-11-10", [
                Watch(number: 5, service: ServiceKind.gas, cycle: .weeks(1), days: ["2026-10-27"]),
            ], (3, ["Ce ține de altă secțiune", "Plante fără locuință"])),
            ("only suggestions", "2026-11-10", [], (2, [])),
            ("nothing", "2026-11-10", [Watch(number: 6, service: ServiceKind.streaming, days: ["2026-09-20"])], (0, ["Ce ține de altă secțiune"])),
        ]
        let cases: [JSONValue] = lists.map { list in
            let snapshots = list.watches.map { watch in
                BillWatchSnapshot(id: section(watch.number), name: "Abonament", provider: "ENGIE Romania S.A.", placeName: "Apartament Exemplu",
                                  service: watch.service, cycle: watch.cycle, bills: watch.days.map { BillRecord(day: day($0), amount: nil) },
                                  isSensitive: watch.isSensitive)
            }
            let missing = AttentionModel.missingBills(snapshots, now: noonOf(list.today), calendar: calendar)
            let suggestion = AttentionModel.suggestionNote(count: list.suggestions.count, topics: list.suggestions.topics)
            let cycles = Dictionary(list.watches.map { (section($0.number), $0.cycle) }, uniquingKeysWith: { first, _ in first })
            let notes = AttentionModel.calmNotes(missingBills: missing, suggestions: suggestion)
            return .object([
                "name": .string(list.name), "today": .string(list.today),
                "subscriptions": .array(list.watches.map { watch in
                    .object([
                        "id": uuid(section(watch.number)), "service": text(watch.service), "cycle": SubscriptionVectorsTests.interval(watch.cycle),
                        "days": .array(watch.days.map(JSONValue.string)), "isSensitive": .bool(watch.isSensitive), "isExample": .bool(false),
                    ])
                }),
                "suggestions": .object(["count": .int(list.suggestions.count), "topics": .array(list.suggestions.topics.map(JSONValue.string))]),
                "notes": .array(notes.map { note in
                    var object: [String: JSONValue] = [
                        "expectedDay": iso(note.expectedDay), "title": .string(note.title), "detail": .string(note.detail),
                    ]
                    switch note.opens {
                    case .section(let id):
                        let cycle = cycles[id] ?? .months(1)
                        object["opens"] = .object(["section": uuid(id)])
                        object["isWeekly"] = .bool(cycle.unit == .week && cycle.every == 1)
                        object["monthsApart"] = .int(AttentionModel.monthsApart(cycle))
                    case .suggestions:
                        object["opens"] = "suggestions"
                    }
                    return .object(object)
                }),
            ])
        }
        return Vectors(
            name: "calm-notes",
            rule: "AttentionModel.calmNotes(missingBills:suggestions:) over missingBills(_:now:calendar:locale:) and suggestionNote(count:topics:)",
            source: "ios/DosarCuSina/Services/Attention/MissingBills.swift",
            shape: "today, the binder's subscriptions (as in the subscription vectors' missing-bills) and the suggestions waiting (how many, and the steps' topics); notes: Din timp's notes in order, each what it opens ({section: id}, or \"suggestions\") and the day its bill was expected (null for the suggestions); a bill's whether it comes weekly and how many months its bills come apart (which pick its title's words). title and detail are the words.",
            cases: cases
        )
    }

    // MARK: The binder's grid

    /// The built-in catalog's categories as installed, in their home order, each made at a fixed
    /// moment so nothing depends on when the test ran; and a second copy of the cars' category,
    /// made later, as a backup or another phone may bring before copies are joined.
    @MainActor
    static func builtIns() throws -> [CategoryTemplate] {
        let context = try makeContext()
        let installed = try TemplateStore(context: context).all().sorted { ($0.homeOrder, $0.key) < ($1.homeOrder, $1.key) }
        for (index, template) in installed.enumerated() { template.createdAt = moment(index) }
        return installed
    }

    @MainActor
    static func category(_ template: CategoryTemplate) -> JSONValue {
        let behavior = template.behavior
        return .object([
            "key": .string(template.key), "name": .string(template.name), "homeOrder": .int(template.homeOrder),
            "isOnHome": .bool(template.isOnHome), "createdAt": seconds(template.createdAt),
            "box": .string(behavior.box.rawValue), "role": text(behavior.role?.rawValue),
            "addedOnlyUnderParent": .bool(behavior.addedOnlyUnderParent), "shortlistOrder": optional(behavior.shortlistOrder),
            "groupsSections": .bool(template.groupsSections),
        ])
    }

    static func category(_ info: BinderLayout.TemplateInfo) -> JSONValue {
        .object([
            "key": .string(info.key), "name": .string(info.name), "homeOrder": .int(info.homeOrder),
            "isOnHome": .bool(info.isOnHome), "createdAt": seconds(moment(0)),
            "box": .string(info.box.rawValue), "role": text(info.role?.rawValue),
            "addedOnlyUnderParent": .bool(false), "shortlistOrder": .null, "groupsSections": .bool(info.groupsSections),
        ])
    }

    @MainActor
    static func sectionOffers() throws -> Vectors {
        let installed = try builtIns()
        let cars = try #require(installed.first { $0.key == BuiltInTemplates.Key.vehicle })
        let copy = CategoryTemplate(definition: cars.definition, isBuiltIn: true, homeOrder: cars.homeOrder)
        copy.createdAt = moment(1_000)
        let lists: [(name: String, templates: [CategoryTemplate])] = [
            ("the built-in catalog", installed),
            ("the built-in catalog with a second copy of a category", installed + [copy]),
        ]
        let cases: [JSONValue] = lists.map { list in
            let offers = SectionOffers(list.templates)
            return .object([
                "name": .string(list.name), "categories": .array(list.templates.map { category($0) }),
                "shortlist": .array(offers.shortlist.map { JSONValue.string($0.key) }),
                "others": .array(offers.others.map { JSONValue.string($0.key) }),
                "inOrder": .array(offers.inOrder.map { JSONValue.string($0.key) }),
                "groups": .object(Dictionary(list.templates.map { template in
                    (template.key, SectionOffers.group(of: template.behavior).map { JSONValue.string($0 == .shortlist ? "shortlist" : "others") } ?? .null)
                }, uniquingKeysWith: { first, _ in first })),
            ])
        }
        return Vectors(
            name: "section-offers",
            rule: "SectionOffers(_:) and SectionOffers.group(of:)",
            source: "ios/DosarCuSina/Services/Templates/SectionOffers.swift",
            shape: "categories: each its key, name, homeOrder, isOnHome, createdAt (seconds since 1970), its box and role (stored text, role null for none), addedOnlyUnderParent, shortlistOrder (null for none) and groupsSections; shortlist, others and inOrder: the keys „Adaugă o secțiune” offers, in order, one of each key; groups: where each key is offered (shortlist, others, or null: only under another section).",
            cases: cases
        )
    }

    @MainActor
    static func binderGrid() throws -> Vectors {
        struct Section {
            var n: Int
            var key: String
            var isTopLevel = true
            var made: Int

            var info: BinderLayout.AssetInfo {
                BinderLayout.AssetInfo(id: AttentionVectorsTests.section(n), templateKey: key, isTopLevel: isTopLevel, createdAt: AttentionVectorsTests.moment(made))
            }

            var json: JSONValue {
                .object([
                    "id": AttentionVectorsTests.uuid(AttentionVectorsTests.section(n)), "templateKey": .string(key),
                    "isTopLevel": .bool(isTopLevel), "createdAt": AttentionVectorsTests.seconds(AttentionVectorsTests.moment(made)),
                ])
            }
        }
        typealias Key = BuiltInTemplates.Key
        let installed = try builtIns()
        let catalog = installed.map { BinderLayout.TemplateInfo($0) }
        let offered = SectionOffers(installed).inOrder.map { BinderLayout.TemplateInfo($0) }
        let made: [BinderLayout.TemplateInfo] = [
            .init(key: "a", homeOrder: 0, isOnHome: true, name: "Mașini"),
            .init(key: "b", homeOrder: 1, isOnHome: true, box: .wholeCategory, name: "Garanții"),
            .init(key: "c", homeOrder: 2, isOnHome: true, box: .insideOther, name: "Chiriași"),
            .init(key: "d", homeOrder: 3, isOnHome: false, name: "Biciclete"),
            .init(key: "e", homeOrder: 4, isOnHome: true, name: "Animale"),
            .init(key: "f", homeOrder: 5, isOnHome: true, groupsSections: true, name: "Plante"),
            .init(key: "g", homeOrder: 6, isOnHome: true, name: "Espressoare"),
            .init(key: "h", homeOrder: 7, isOnHome: true, name: "Altele"),
            .init(key: "i", homeOrder: 8, isOnHome: true, box: .wholeCategory, role: .personalDocument, name: "Acte"),
            .init(key: "j", homeOrder: 9, isOnHome: true, box: .insideOther, role: .holder, name: "Persoane"),
        ]
        let catalogJSON = installed.map { category($0) }
        let madeJSON = made.map { category($0) }
        let lists: [(name: String, catalog: [BinderLayout.TemplateInfo], json: [JSONValue], offered: [BinderLayout.TemplateInfo], sections: [Section], contacts: Bool)] = [
            ("an empty binder", catalog, catalogJSON, offered, [], false),
            ("one car", catalog, catalogJSON, offered, [Section(n: 1, key: Key.vehicle, made: 1)], false),
            ("a household", catalog, catalogJSON, offered, [
                Section(n: 1, key: Key.vehicle, made: 1), Section(n: 2, key: Key.home, made: 2), Section(n: 3, key: Key.tenancy, isTopLevel: false, made: 3),
                Section(n: 4, key: Key.purchase, made: 4), Section(n: 5, key: Key.member, made: 5), Section(n: 6, key: Key.plants, made: 6),
                Section(n: 7, key: Key.plants, isTopLevel: false, made: 7), Section(n: 8, key: Key.plants, made: 8), Section(n: 9, key: Key.vehicle, made: 0),
            ], true),
            ("categories of one's own, nothing in them", made, madeJSON, made, [], false),
            ("categories of one's own, some filled", made, madeJSON, made, [
                Section(n: 1, key: "a", made: 2), Section(n: 2, key: "a", made: 1), Section(n: 3, key: "f", isTopLevel: false, made: 3),
                Section(n: 4, key: "j", made: 4), Section(n: 5, key: "zz", made: 5), Section(n: 6, key: "c", isTopLevel: false, made: 6),
                Section(n: 7, key: "d", made: 7),
            ], true),
        ]
        let cases: [JSONValue] = lists.map { list in
            let sections = list.sections.map(\.info)
            let byKey = Dictionary(list.catalog.map { ($0.key, $0) }, uniquingKeysWith: { first, _ in first })
            let names = BinderLayout.addBoxNames(offered: list.offered, templates: list.catalog, assets: sections)
            return .object([
                "name": .string(list.name), "categories": .array(list.json),
                "sections": .array(list.sections.map(\.json)), "hasContacts": .bool(list.contacts),
                "offered": .array(list.offered.map { JSONValue.string($0.key) }),
                "holdsAnything": .array(list.catalog.filter { BinderLayout.holdsAnything($0, templates: byKey, assets: sections) }.map { JSONValue.string($0.key) }),
                "defaultOrder": .array(BinderLayout.defaultOrder(templates: list.catalog, assets: sections, hasContacts: list.contacts).map { JSONValue.string($0.storageKey) }),
                "addBoxNames": .object(["names": .array(names.names.map(JSONValue.string)), "more": .bool(names.more)]),
                "addBoxLine": text(BinderLayout.addBoxLine(names)),
            ])
        }
        return Vectors(
            name: "binder-grid",
            rule: "BinderLayout.holdsAnything(_:templates:assets:) over holds, defaultOrder(templates:assets:hasContacts:) and addBoxNames(offered:templates:assets:)",
            source: "ios/DosarCuSina/Views/Dosar/BinderLayout.swift",
            shape: "categories (as in section-offers), the binder's sections (each its id, its category's key, whether it is top-level and createdAt, seconds since 1970), hasContacts and offered (the keys „Adaugă o secțiune” offers, in order: section-offers' inOrder for the built-in catalog); holdsAnything: the keys of the categories that hold something; defaultOrder: the boxes before the person rearranges them, as their saved order writes them; addBoxNames: what the add box names, at most four, and whether there are more; addBoxLine: its words.",
            cases: cases
        )
    }
}
