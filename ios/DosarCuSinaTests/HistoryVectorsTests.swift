import Foundation
import SwiftData
import Testing
@testable import DosarCuSina

/// A section's history: what a visit's form asks by its kind (`VisitKind`, `VisitShape`, `VisitForm`), the
/// titles a record is written with, what a line of work is that is never a part (`LabourLine`), when a
/// paper is one already filed (`PaperIdentity`), what a record's page in Istoric shows
/// (`HistoryEntryShape`), the maintenance log (`MaintenanceLog`), and what every `HistoryActions` action
/// leaves in the binder (a visit of each kind with its parts and jobs, filed from its form, a repair, a
/// purchase, a note, a rating, a completion's parts, a deletion that moves a deadline back), run over cases
/// chosen to bite and written to `shared/test-vectors/history/`, one file per rule. The Android app's tests
/// read the same files and must give the same answers (docs/ANDROID_PLAN.md, "How parity is kept"):
/// `core.history`, `core.capture` and `store.history`, the actions run through the real Room store. A
/// sibling of `SectionVectorsTests`.
///
/// Words are data here only where the store writes them (a record's title) or a page is worded by kinds
/// Android words in Phase 4: each file that needs them carries the iOS words it compares with.
///
/// Nothing depends on the machine: the calendar is the app's in Bucharest (`Calendar.dosar(in:)`) and now
/// is fixed. Placeholder data only.
@MainActor
@Suite("History vectors")
struct HistoryVectorsTests {
    static var folder: URL {
        URL(filePath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appending(path: "shared/test-vectors/history")
    }

    /// How to bring the files up to date, said when one isn't.
    static let regenerate = """
    is out of date with the history rules. Bring shared/test-vectors/history up to date: a failed run on \
    GitHub keeps them made afresh in its test-results artifact, test-vectors/history/ (copy them over), or \
    TEST_RUNNER_HISTORY_VECTORS_WRITE=1 ./tests/run_tests.sh (or run HistoryVectorsTests in Xcode with \
    HISTORY_VECTORS_WRITE=1 in the scheme's environment); review the diff and commit it, then run the \
    Android tests (./gradlew :core:test :store:test in android/), which read the same files.
    """

    typealias Vectors = ValueVectorsTests.Vectors

    /// The app's calendar in Bucharest, whatever the machine's time zone.
    static var calendar: Calendar { Calendar.dosar(in: TimeZone(identifier: "Europe/Bucharest") ?? .gmt) }

    /// Every action's clock.
    static let now = CalendarDay("2026-11-26").noonDate(in: Calendar.dosar(in: TimeZone(identifier: "Europe/Bucharest") ?? .gmt))

    @Test("shared/test-vectors/history is up to date with the history rules")
    func vectorsAreUpToDate() async throws {
        let files = try await Self.all()
        let environment = ProcessInfo.processInfo.environment
        let writes = environment["HISTORY_VECTORS_WRITE"] == "1"
        let manager = FileManager.default
        if writes { try manager.createDirectory(at: Self.folder, withIntermediateDirectories: true) }
        var fresh: [String: String] = [:]
        var outOfDate: [String] = []
        for file in files {
            let name = "\(file.name).json"
            let text = try ValueVectorsTests.render(file)
                .replacingOccurrences(of: "ios/DosarCuSinaTests/ValueVectorsTests.swift", with: "ios/DosarCuSinaTests/HistoryVectorsTests.swift")
            fresh[name] = text
            let url = Self.folder.appending(path: name)
            if writes {
                try text.write(to: url, atomically: true, encoding: .utf8)
                continue
            }
            let committed = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
            if committed != text { outOfDate.append(name) }
        }
        // A file no rule writes any more goes, so Android never tests against an old answer.
        let present = (try? manager.contentsOfDirectory(atPath: Self.folder.path(percentEncoded: false))) ?? []
        for stale in present where stale.hasSuffix(".json") && fresh[stale] == nil {
            if writes {
                try manager.removeItem(at: Self.folder.appending(path: stale))
            } else {
                Issue.record(Comment(rawValue: "\(stale) is written by no rule any more " + Self.regenerate))
            }
        }
        // A run that finds them out of date leaves them as they should be, for a failed run on GitHub to keep.
        if !outOfDate.isEmpty, let out = environment["VECTORS_OUT"], !out.isEmpty {
            let folder = URL(filePath: out, directoryHint: .isDirectory).appending(path: "history")
            try manager.createDirectory(at: folder, withIntermediateDirectories: true)
            for (name, text) in fresh { try text.write(to: folder.appending(path: name), atomically: true, encoding: .utf8) }
        }
        for name in outOfDate.sorted() {
            Issue.record(Comment(rawValue: "\(name) " + Self.regenerate))
        }
    }

    static func all() async throws -> [Vectors] {
        var files = try [visitKinds(), titles(), labour(), papers(), entryShapes(), maintenanceLog()]
        files.append(try await actions())
        return files
    }

    // MARK: Helpers

    nonisolated static func text(_ value: String?) -> JSONValue { value.map(JSONValue.string) ?? .null }
    nonisolated static func int(_ value: Int?) -> JSONValue { value.map(JSONValue.int) ?? .null }
    nonisolated static func number(_ value: Double?) -> JSONValue { value.map(JSONValue.number) ?? .null }
    nonisolated static func amount(_ value: Decimal?) -> JSONValue { value.map { .string("\($0)") } ?? .null }
    static func seconds(_ date: Date) -> JSONValue { .int(Int(date.timeIntervalSince1970.rounded())) }
    nonisolated static func date(_ seconds: Int) -> Date { Date(timeIntervalSince1970: TimeInterval(seconds)) }
    static func money(_ value: Money?) throws -> JSONValue { try value.map { try RecurrenceVectorsTests.encoded($0) } ?? .null }
    static func noonOf(_ iso: String) -> Date { CalendarDay(iso).noonDate(in: calendar) }

    // MARK: What a visit's form asks

    static func shape(_ shape: VisitShape?) -> JSONValue {
        guard let shape else { return .null }
        return .object([
            "historyKind": .string(shape.historyKind.rawValue), "paper": text(shape.paper?.rawValue),
            "paperIsInvoice": .bool(shape.paper?.isInvoice ?? false), "documentKind": text(shape.paper?.documentKind.rawValue),
            "asksWork": .bool(shape.work != nil), "asksBrand": .bool(shape.asksBrand), "asksNote": .bool(shape.note != nil),
            "asksCounter": .bool(shape.asksCounter), "costIsOptional": .bool(shape.costHint != nil),
            "sum": .string(shape.sum == .parts ? "parts" : "rows"), "checksWarranty": .bool(shape.checksWarranty),
            "providerTrade": text(shape.provider?.trade.rawValue),
            "requirement": shape.requirement.map { .array($0.fields.map(\.rawValue).sorted().map(JSONValue.string)) } ?? .null,
            "fields": .array(shape.fields.map(\.rawValue).sorted().map(JSONValue.string)),
        ])
    }

    static func visitKinds() throws -> Vectors {
        var cases: [JSONValue] = VisitKind.allCases.map { kind in
            .object([
                "visitKind": .string(kind.rawValue), "shape": shape(kind.shape), "offersVisit": .bool(kind.offersVisit),
                "addsNote": .bool(kind.addsNote),
            ])
        }
        for definition in BuiltInTemplates.all {
            let form = VisitForm.make(for: definition)
            cases.append(.object([
                "category": .string(definition.key), "visitKind": .string(definition.behavior.visit.rawValue),
                "form": form.map { form in
                    .object([
                        "fields": .array(form.fields.map(\.rawValue).sorted().map(JSONValue.string)),
                        "hasChecklist": .bool(form.hasChecklist), "hasRows": .bool(form.hasRows),
                        "rowsAreParts": .bool(form.rowsAreParts), "components": .array(form.components.map { .string($0.key) }),
                        "counterField": text(form.counterField?.key), "warrantyField": text(form.warrantyField?.key),
                        "paperFacts": .array(form.paperFacts.map { fact -> JSONValue in
                            switch fact {
                            case .day: "day"
                            case .total: "total"
                            case .issuer: "issuer"
                            }
                        }),
                    ])
                } ?? .null,
                "listsParts": .bool(VisitForm.listsParts(definition)),
            ]))
        }
        return Vectors(
            name: "visit-kinds",
            rule: "VisitKind (shape, offersVisit, addsNote), VisitShape (fields, requirement, paper), VisitForm.make(for:) over every built-in category, VisitForm.listsParts",
            source: "ios/DosarCuSina/Models/Templates/VisitKind.swift, VisitShape.swift, ios/DosarCuSina/Services/History/VisitForm.swift",
            shape: "visitKind with shape: what a kind's visit asks (null for one with no visits): the history kind it writes, its paper (raw, whether an invoice, how it is kept), whether it asks what was done, a part's brand, a note, the counter, whether its cost may be nothing (a hint under it), what its rows add up to (parts or rows), whether it checks the warranty, the trade of a firm it adds, what saving needs (any one of these fields, null: the day alone) and every field it shows. category with form: a built-in's form (null for none): the fields it shows, whether it ticks a checklist and writes rows, whether its rows are parts, the parts it ticks, its counter field and warranty field, what a paper fills in; listsParts: whether a record's page calls its rows parts.",
            cases: cases
        )
    }

    // MARK: A record's title

    static func titles() throws -> Vectors {
        let inputs: [(String, [String])] = [
            ("nothing listed", []), ("one thing", ["Ulei și filtru de ulei"]),
            ("two things", ["Plăcuțe frână față", "Odorizant"]), ("labour is no work it names", ["Plăcuțe frână față", "Manoperă"]),
            ("labour alone keeps its name", ["Manoperă 1,5 ore"]), ("three things are counted", ["Ulei", "Filtru de aer", "Bujii"]),
            ("four things, one labour", ["Ulei", "Filtru de aer", "Bujii", "Manoperă"]), ("five things", ["A", "B", "C", "D", "E"]),
            ("a blank name says nothing", ["", "Ulei"]),
        ]
        var cases: [JSONValue] = inputs.map { name, items in
            .object([
                "name": .string(name), "items": .array(items.map(JSONValue.string)),
                "visitTitle": .string(HistoryActions.visitTitle(for: items.map { LineItemDraft(name: $0) })),
            ])
        }
        for definition in BuiltInTemplates.all {
            guard let form = VisitForm.make(for: definition) else { continue }
            for (name, items) in inputs {
                cases.append(.object([
                    "name": .string("\(definition.key): \(name)"), "category": .string(definition.key),
                    "items": .array(items.map(JSONValue.string)), "entryTitle": .string(form.entryTitle(for: items)),
                ]))
            }
        }
        // The words a record's title is written with when nothing done names it, as the Android test words them.
        var words: [String: JSONValue] = ["visit": .string(HistoryActions.visitTitle(for: []))]
        for kind in VisitKind.allCases { if let shape = kind.shape { words[kind.rawValue] = .string(shape.entryTitle) } }
        var many: [String: JSONValue] = [:]
        for count in 3...6 {
            many[String(count)] = .string(HistoryActions.visitTitle(for: (0..<count).map { LineItemDraft(name: "Lucrare \($0)") }))
        }
        words["manyJobs"] = .object(many)
        cases.append(.object(["name": "the words", "words": .object(words)]))
        return Vectors(
            name: "titles",
            rule: "HistoryActions.visitTitle(for:) and VisitForm.entryTitle(for:), over LabourLine.work",
            source: "ios/DosarCuSina/Services/History/HistoryActions.swift, VisitForm.swift",
            shape: "items: the names of what a visit lists. visitTitle: the record's title when nothing names its kind. category with entryTitle: the title its form gives it. words: the iOS words a title is written with (visit: a visit of no kind; each visit kind's title; manyJobs: a service of so many jobs, by count), which the Android test words its titles with.",
            cases: cases
        )
    }

    // MARK: Labour

    static func labour() throws -> Vectors {
        let lines = [
            "Manoperă 1,5 ore", "Manopera service", "MÂNĂ DE LUCRU", "Mana lucru", "Ore lucrate: 2", "Ore de muncă",
            "Analize de laborator", "Filtru ulei", "Labour", "Laborator", "manoperei aferente", "Plăcuțe frână față",
            "", "Lucru", "Ore",
        ]
        var cases: [JSONValue] = lines.map { .object(["line": .string($0), "matches": .bool(LabourLine.matches($0))]) }
        let lists: [[String]] = [["Plăcuțe frână față", "Manoperă"], ["Manoperă"], ["Manoperă", "Mână de lucru"], [], ["Ulei", "Bujii"]]
        for names in lists {
            cases.append(.object(["names": .array(names.map(JSONValue.string)), "work": .array(LabourLine.work(names).map(JSONValue.string))]))
        }
        for name in ["Plăcuțe frână spate", "placute de frana spate", "Baterie", "Odorizant", "  ", "Schimb ulei motor"] {
            let key = ComponentCatalog.key(for: name, in: BuiltInTemplates.vehicle.components)
            cases.append(.object(["partName": .string(name), "category": .string(BuiltInTemplates.Key.vehicle), "key": .string(key)]))
        }
        return Vectors(
            name: "labour",
            rule: "LabourLine.matches(_:) and work(_:), over CaptureLexicon.labourWords; ComponentCatalog.key(for:in:)",
            source: "ios/DosarCuSina/Services/Capture/CaptureComponentResolver.swift, CaptureLexicon.swift, ios/DosarCuSina/Models/Templates/ComponentCatalog.swift",
            shape: "line with matches: whether a line item's name is labour. names with work: what a visit's title counts of them. partName with category and key: the part a line names in the category's parts, or the key of a part of one's own.",
            cases: cases
        )
    }

    // MARK: The same paper

    struct Paper {
        var number: String?
        var day: String
        var total: Decimal?
        var issuer: String?
        var isBill = false

        var identity: PaperIdentity {
            let money = total.map { Money($0) }
            if isBill { return .bill(number: number, day: CalendarDay(day), total: money) }
            return PaperIdentity(number: number, day: CalendarDay(day), total: money, issuer: issuer)
        }

        var json: JSONValue {
            .object([
                "number": HistoryVectorsTests.text(number), "day": .string(day), "total": HistoryVectorsTests.amount(total),
                "issuer": isBill ? JSONValue.string("section") : HistoryVectorsTests.text(issuer),
            ])
        }
    }

    static func match(_ match: PaperIdentity.Match?) -> JSONValue {
        switch match {
        case .number?: "number"
        case .numberOnly?: "numberOnly"
        case .dayAndTotal?: "dayAndTotal"
        case nil: .null
        }
    }

    static func papers() throws -> Vectors {
        let firm = "Service Exemplu SRL"
        let pairs: [(String, Paper, Paper)] = [
            ("the same number from the same firm on the same day", Paper(number: "SRV 0000001", day: "2026-05-30", total: 480, issuer: firm),
             Paper(number: "srv-0000001", day: "2026-05-30", total: 480, issuer: "SERVICE EXEMPLU S.R.L.")),
            ("the same number from the same firm on another day", Paper(number: "SRV 0000001", day: "2026-05-30", total: 480, issuer: firm),
             Paper(number: "SRV 0000001", day: "2025-05-30", total: 300, issuer: firm)),
            ("the same number from another firm", Paper(number: "0001", day: "2026-05-30", total: 480, issuer: firm),
             Paper(number: "0001", day: "2026-05-30", total: 480, issuer: "Vulcanizare Exemplu SRL")),
            ("the same number, a firm on one only", Paper(number: "0001", day: "2026-05-30", total: 480, issuer: firm),
             Paper(number: "0001", day: "2026-05-30", total: 480, issuer: nil)),
            ("another number on the same day for the same total", Paper(number: "0001", day: "2026-05-30", total: 480, issuer: firm),
             Paper(number: "0002", day: "2026-05-30", total: 480, issuer: firm)),
            ("no number, the same day and total and firm", Paper(number: nil, day: "2026-05-30", total: 480, issuer: firm),
             Paper(number: "0001", day: "2026-05-30", total: 480, issuer: firm)),
            ("no number, the same day and total, another firm", Paper(number: nil, day: "2026-05-30", total: 480, issuer: firm),
             Paper(number: nil, day: "2026-05-30", total: 480, issuer: "Vulcanizare Exemplu SRL")),
            ("no number, the same day and total, a firm on one only", Paper(number: nil, day: "2026-05-30", total: 480, issuer: firm),
             Paper(number: nil, day: "2026-05-30", total: 480, issuer: nil)),
            ("no number, another day", Paper(number: nil, day: "2026-05-30", total: 480, issuer: firm),
             Paper(number: nil, day: "2026-05-31", total: 480, issuer: firm)),
            ("neither a number nor a total", Paper(number: nil, day: "2026-05-30", total: nil, issuer: firm),
             Paper(number: nil, day: "2026-05-30", total: nil, issuer: firm)),
            ("a blank number is no number", Paper(number: " - ", day: "2026-05-30", total: 480, issuer: firm),
             Paper(number: nil, day: "2026-05-30", total: 480, issuer: firm)),
            ("two bills of one subscription with the same number", Paper(number: "EXM 0000001", day: "2026-05-30", total: 120, isBill: true),
             Paper(number: "EXM 0000001", day: "2026-06-30", total: 125, isBill: true)),
            ("a bill and a visit's invoice with the same number", Paper(number: "EXM 0000001", day: "2026-05-30", total: 120, isBill: true),
             Paper(number: "EXM 0000001", day: "2026-05-30", total: 120, issuer: firm)),
        ]
        var cases: [JSONValue] = pairs.map { name, one, other in
            .object(["name": .string(name), "paper": one.json, "other": other.json, "match": match(one.identity.match(other.identity))])
        }
        // The most certain match first, whatever the order they were filed in.
        let paper = Paper(number: "SRV 0000001", day: "2026-05-30", total: 480, issuer: firm)
        let among = [
            Paper(number: nil, day: "2026-05-30", total: 480, issuer: firm),
            Paper(number: "SRV 0000001", day: "2026-04-30", total: 300, issuer: firm),
            Paper(number: "SRV 0000001", day: "2026-05-30", total: 480, issuer: firm),
        ]
        for count in 1...among.count {
            let papers = Array(among.prefix(count))
            let found = paper.identity.filed(among: papers.indices.map { $0 }) { papers[$0].identity }
            cases.append(.object([
                "name": .string("the most certain of \(count)"), "paper": paper.json, "among": .array(papers.map(\.json)),
                "found": int(found?.paper), "foundMatch": match(found?.match),
            ]))
        }
        return Vectors(
            name: "paper-identity",
            rule: "PaperIdentity.match(_:), filed(among:identity:) and comparable(_:)",
            source: "ios/DosarCuSina/Services/History/PaperIdentity.swift",
            shape: "paper and other: two papers, each its number as printed (null: none), its day, its total in lei (null: none) and who issued it (a name, null for nobody named, \"section\" for a bill, whose subscription is its issuer). match: how they are the same paper (number, numberOnly, dayAndTotal), null for another paper. among with found and foundMatch: the paper filed before that this one is, by index, null for none, and how.",
            cases: cases
        )
    }

    // MARK: A record's page

    static func entryShape(_ shape: HistoryEntryShape) -> JSONValue {
        let reference: String = switch shape.reference {
        case .number: "number"
        case .invoice: "invoice"
        case .policy: "policy"
        }
        let rating: String = switch shape.rating {
        case .job: "job"
        case .withSomeone: "withSomeone"
        case .never: "never"
        }
        return .object([
            "items": .string(shape.itemsHeader), "provider": text(shape.providerHeader), "reference": .string(reference),
            "rating": .string(rating), "ratingHeader": .string(shape.ratingHeader), "rowsAreParts": .bool(shape.rowsAreParts),
            "asksRating": .array([
                .bool(shape.asksRating(isCompletion: false, hasSomeone: false)), .bool(shape.asksRating(isCompletion: false, hasSomeone: true)),
                .bool(shape.asksRating(isCompletion: true, hasSomeone: false)), .bool(shape.asksRating(isCompletion: true, hasSomeone: true)),
            ]),
        ])
    }

    static func entryShapes() throws -> Vectors {
        let visits: [VisitKind?] = [nil] + VisitKind.allCases
        var cases: [JSONValue] = []
        for kind in HistoryKind.allCases {
            for visit in visits {
                for listsParts in [false, true] {
                    let shape = HistoryEntryShape.make(kind, visit: visit?.shape, listsParts: listsParts)
                    cases.append(.object([
                        "historyKind": .string(kind.rawValue), "visit": text(visit?.rawValue), "listsParts": .bool(listsParts),
                        "shape": entryShape(shape),
                    ]))
                }
            }
        }
        for completion in CompletionKind.allCases {
            for visit in visits {
                let shape = HistoryEntryShape.make(completing: completion, stored: .note, visit: visit?.shape, listsParts: true)
                cases.append(.object([
                    "completing": .string(completion.rawValue), "visit": text(visit?.rawValue), "listsParts": true,
                    "shape": entryShape(shape),
                ]))
            }
        }
        // The words, as the Android test words its kinds with them.
        var visitWords: [String: JSONValue] = [:]
        for kind in VisitKind.allCases {
            guard let shape = kind.shape else { continue }
            visitWords[kind.rawValue] = .object([
                "work": text(shape.work?.header), "provider": text(shape.provider?.header), "rating": text(shape.provider?.rating),
            ])
        }
        var from: [String: JSONValue] = [:]
        for origin in [CompletionShape.Paper.Origin.issued, .signed] {
            for gender in [CompletionShape.Paper.Gender.masculine, .feminine, .plural] {
                let paper = CompletionShape.Paper(name: "", gender: gender, use: .keep, action: "", example: "", origin: origin)
                from["\(origin.rawValue).\(gender.rawValue)"] = .string(HistoryEntryWording.from(paper))
            }
        }
        from["none"] = .string(HistoryEntryWording.from(nil))
        let words: [String: JSONValue] = [
            "whatWasDone": .string(HistoryEntryWording.whatWasDone), "whatWasRepaired": .string(HistoryEntryWording.whatWasRepaired),
            "whatWasChecked": .string(HistoryEntryWording.whatWasChecked), "whatWasBought": .string(HistoryEntryWording.whatWasBought),
            "whatTheBillHolds": .string(HistoryEntryWording.whatTheBillHolds), "whatWasPaid": .string(HistoryEntryWording.whatWasPaid),
            "whatItCovers": .string(HistoryEntryWording.whatItCovers), "whatWasNoted": .string(HistoryEntryWording.whatWasNoted),
            "whoWorked": .string(HistoryEntryWording.whoWorked), "whoChecked": .string(HistoryEntryWording.whoChecked),
            "whoGaveIt": .string(HistoryEntryWording.whoGaveIt), "boughtFrom": .string(HistoryEntryWording.boughtFrom),
            "paidTo": .string(HistoryEntryWording.paidTo), "insurer": .string(HistoryEntryWording.insurer),
            "howItWent": .string(HistoryEntryWording.howItWent), "visits": .object(visitWords), "from": .object(from),
        ]
        cases.append(.object(["name": "the words", "words": .object(words)]))
        return Vectors(
            name: "entry-shapes",
            rule: "HistoryEntryShape.make(_:visit:listsParts:), make(completing:stored:visit:listsParts:) and asksRating(isCompletion:hasSomeone:)",
            source: "ios/DosarCuSina/Services/History/HistoryEntryShape.swift",
            shape: "historyKind or completing: a record's kind, or the completion it closed, in a category whose visits are visit (null: none) and list parts when listsParts. shape: what its page says above its rows (items), above who did it (provider, null for no one), before its paper's number (reference), when it asks for stars (rating) and above them (ratingHeader), whether its rows are parts, and asksRating for (not a completion, no one), (not a completion, someone), (a completion, no one), (a completion, someone). words: the iOS words of each header kind, each visit kind's own (work, provider, rating) and who a renewed paper comes from by its origin and gender (\"none\": no paper), which the Android test words its shapes with.",
            cases: cases
        )
    }

    // MARK: The maintenance log

    struct LogCase {
        var name: String
        var items: [(String?, String, String, Double?)]
        var readings: [(String, Double, Bool)] = []
        var current: Double?
        var now: String = "2026-01-10"
    }

    static let logCases: [LogCase] = [
        LogCase(name: "one job is not a pattern", items: [("brakes.padsFront", "Plăcuțe", "2023-01-10", 60_000)], current: nil),
        LogCase(name: "by time without a pace", items: [("brakes.padsFront", "Plăcuțe", "2023-01-10", 60_000), ("brakes.padsFront", "Plăcuțe", "2025-01-10", 90_000)],
                current: nil),
        LogCase(name: "by distance and pace", items: [("brakes.padsFront", "Plăcuțe", "2023-01-10", 60_000), ("brakes.padsFront", "Plăcuțe", "2025-01-10", 90_000)],
                readings: [("2025-07-10T10:00:00Z", 100_000, false), ("2026-01-06T10:00:00Z", 106_000, false)], current: 106_000),
        LogCase(name: "a pace too slow to be honest goes by time", items: [("engine.oil", "Ulei", "2024-01-10", 100_000), ("engine.oil", "Ulei", "2025-01-10", 110_000)],
                readings: [("2025-01-10T10:00:00Z", 110_000, false), ("2026-01-06T10:00:00Z", 110_001, false)], current: 110_001),
        LogCase(name: "a new dashboard is never a drop", items: [("engine.oil", "Ulei", "2024-01-10", 180_000), ("engine.oil", "Ulei", "2025-01-10", 195_000)],
                readings: [("2024-01-10T10:00:00Z", 180_000, false), ("2025-01-10T10:00:00Z", 195_000, false), ("2025-03-01T10:00:00Z", 1_000, true),
                           ("2026-01-01T10:00:00Z", 13_000, false)], current: 13_000),
        LogCase(name: "several parts, newest activity first", items: [("engine.oil", "Ulei", "2025-06-01", nil), ("filters.air", "Filtru de aer", "2025-09-01", nil),
                                                                       (nil, "Manoperă", "2025-10-01", nil), ("engine.oil", "Ulei", "2024-06-01", nil),
                                                                       ("custom.odorizant", "Odorizant", "2025-02-01", nil)], current: nil),
        LogCase(name: "three jobs, the median gap", items: [("tyres.winter", "Anvelope", "2022-11-01", 40_000), ("tyres.winter", "Anvelope", "2023-11-05", 52_000),
                                                             ("tyres.winter", "Anvelope", "2025-11-20", 70_000)], current: nil, now: "2026-11-26"),
    ]

    static func maintenanceLog() throws -> Vectors {
        let cases: [JSONValue] = logCases.map { item in
            let now = noonOf(item.now)
            let items = item.items.map { key, name, day, metric in
                HistoryItemSnapshot(componentKey: key, name: name, occurredAt: noonOf(day), metricReading: metric)
            }
            let readings = item.readings.map { at, metric, starts in
                CadenceCalculator.TelemetryReading(date: RecurrenceVectorsTests.moment(at), metric: metric, startsCounter: starts)
            }
            let tracked = MaintenanceLog.trackedComponents(in: items)
            let per: [JSONValue] = Set(tracked).sorted().map { key in
                let last = MaintenanceLog.lastOccurrence(of: key, in: items, currentMetric: item.current, readings: readings, now: now, calendar: calendar)
                let typical = MaintenanceLog.typicalInterval(of: key, in: items, readings: readings, calendar: calendar)
                let next = MaintenanceLog.nextEstimate(of: key, in: items, readings: readings, currentMetric: item.current, now: now, calendar: calendar)
                return .object([
                    "key": .string(key),
                    "occurrences": .int(MaintenanceLog.occurrences(of: key, in: items, now: now, calendar: calendar).count),
                    "last": last.map { last in
                        .object(["name": .string(last.name), "date": seconds(last.date), "metricAtTime": number(last.metricAtTime),
                                 "metricSince": number(last.metricSince), "daysSince": .int(last.daysSince)])
                    } ?? .null,
                    "typical": typical.map { .object(["metric": number($0.metric), "days": int($0.days), "sampleCount": .int($0.sampleCount)]) } ?? .null,
                    "next": next.map { next in
                        .object(["day": .string(next.day.isoString), "metric": number(next.metric),
                                 "basis": .string(next.basis.rawValue), "sampleCount": .int(next.sampleCount)])
                    } ?? .null,
                ])
            }
            // Ties in when a part was last done are in no order: what is newer than what is compared by day.
            let order = tracked.map { key in items.filter { $0.componentKey == key }.map(\.occurredAt).max() ?? .distantPast }
            return .object([
                "name": .string(item.name), "now": seconds(now), "currentMetric": number(item.current),
                "items": .array(item.items.map { key, name, day, metric in
                    .object(["componentKey": text(key), "name": .string(name), "occurredAt": seconds(noonOf(day)), "metricReading": number(metric)])
                }),
                "readings": .array(item.readings.map { at, metric, starts in
                    .object(["at": .string(at), "metric": .number(metric), "startsCounter": .bool(starts)])
                }),
                "trackedNewestFirst": .bool(zip(order, order.dropFirst()).allSatisfy { $0 >= $1 }),
                "tracked": .array(Set(tracked).sorted().map(JSONValue.string)),
                "monthlyRate": number(MaintenanceLog.monthlyRate(readings)),
                "components": .array(per),
            ])
        }
        return Vectors(
            name: "maintenance-log",
            rule: "MaintenanceLog: trackedComponents, occurrences, lastOccurrence, typicalInterval, monthlyRate, nextEstimate",
            source: "ios/DosarCuSina/Services/History/MaintenanceLog.swift",
            shape: "items: a section's line items, each its part's key (null: none), name, when its record happened (seconds) and the counter then. readings: the section's counter readings (UTC moments), whether each starts a counter. currentMetric: the counter now; now: the clock (seconds), days counted in Bucharest. tracked: the parts with history, by key; trackedNewestFirst: whether trackedComponents gave them newest activity first. monthlyRate: how far the counter moves in 30 days. components: for each part, how many times it was done, its last occurrence (name, when, the counter then, how far it moved since, days since), the typical interval (median counter distance and days, how many gaps) and the next estimate (day, counter, distance or time, gaps), each null when none.",
            cases: cases
        )
    }

    // MARK: Actions

    typealias Action = [String: JSONValue]

    struct Section {
        var category: String
        var name: String
        var values: [(String, FieldValue)] = []
        var readings: [(String, Double)] = []
    }

    struct ActionCase {
        var name: String
        var section: Section
        var firms: [String] = []
        /// A deadline of the section's category: its blueprint and first due day.
        var deadline: (String, String)?
        var before: [Action] = []
        var action: Action
    }

    /// What a run keeps beside the context: the section, its firms and deadline, and the records the steps made.
    final class State {
        let context: ModelContext
        let asset: Asset
        let firms: [Provider]
        let deadline: Obligation?
        var entries: [HistoryEntry] = []

        init(context: ModelContext, asset: Asset, firms: [Provider], deadline: Obligation?) {
            self.context = context
            self.asset = asset
            self.firms = firms
            self.deadline = deadline
        }
    }

    static func make(_ item: ActionCase) throws -> State {
        let context = try makeContext()
        let asset = Asset(name: item.section.name, templateKey: item.section.category, values: RecurrenceVectorsTests.values(item.section.values))
        context.insert(asset)
        for (at, value) in item.section.readings {
            let log = MeasurementLog(kind: .odometer, name: "", value: value, unit: .kilometres, recordedAt: RecurrenceVectorsTests.moment(at))
            context.insert(log)
            log.asset = asset
        }
        try UnitOfWork.save(context)
        let clock = now
        let firms = try item.firms.map { try ProviderActions(context: context, now: { clock }).create(name: $0, trades: [.mechanic], linkedTo: [asset]) }
        var deadline: Obligation?
        if let start = item.deadline {
            let (key, firstDue) = start
            let template = try #require(try TemplateStore(context: context).template(forKey: item.section.category))
            let blueprint = try #require(template.definition.blueprints.first { $0.key == key })
            deadline = try ObligationActions(context: context, calendar: calendar, now: { clock }).create(from: blueprint, for: asset, firstDue: CalendarDay(firstDue))
        }
        return State(context: context, asset: asset, firms: firms, deadline: deadline)
    }

    /// A value of an action, read as its kind.
    struct Reading {
        let action: Action

        func string(_ key: String) -> String? { if case .string(let value)? = action[key] { return value } else { return nil } }
        func integer(_ key: String) -> Int? { if case .int(let value)? = action[key] { return value } else { return nil } }
        func double(_ key: String) -> Double? {
            switch action[key] {
            case .number(let value)?: return value
            case .int(let value)?: return Double(value)
            default: return nil
            }
        }
        func decimal(_ key: String) -> Decimal? { string(key).flatMap { Decimal(string: $0) } }
        func money(_ key: String) -> Money? { decimal(key).map { Money($0) } }
        func list(_ key: String) -> [Action] {
            guard case .array(let items)? = action[key] else { return [] }
            return items.compactMap { if case .object(let item) = $0 { item } else { nil } }
        }
        var on: Date? { integer("on").map(HistoryVectorsTests.date) }
        var lowerReading: LowerReadingAnswer? {
            switch string("lowerReading") {
            case "newCounter": .newCounter
            case "wasEstimate": .wasEstimate
            case "correctOld": .correctOld
            case "keepAside": .keepAside
            default: nil
            }
        }
        var items: [LineItemDraft] {
            list("items").map { item in
                let line = Reading(action: item)
                return LineItemDraft(name: line.string("name") ?? "", componentKey: line.string("componentKey"),
                                     cost: line.money("cost"), laborCost: line.money("laborCost"), partsCost: line.money("partsCost"))
            }
        }
    }

    /// Runs `action`: the record it made, if any, and its receipt when it gives one.
    static func run(_ action: Action, in state: State) async throws -> UndoReceipt? {
        let clock = now
        let history = HistoryActions(context: state.context, now: { clock })
        let read = Reading(action: action)
        let entry = read.integer("entry").map { state.entries[$0] }
        switch read.string("do") {
        case "recordVisit":
            let checklist = read.list("checklist").map { part in
                let line = Reading(action: part)
                return HistoryActions.ChecklistItem(componentKey: line.string("componentKey") ?? "", cost: line.money("cost"), partBrandOrCode: line.string("brand"))
            }
            let visit = try history.recordVisit(
                on: state.asset, kind: read.string("kind").flatMap(HistoryKind.init(rawValue:)) ?? .maintenance, title: read.string("title"),
                occurredAt: read.on, checklist: checklist, extraItems: read.items, totalCost: read.money("total"), odometer: read.double("odometer"),
                provider: read.integer("provider").map { state.firms[$0] }, note: read.string("note"), reference: read.string("reference"),
                rating: read.integer("rating"), calendar: calendar, lowerReading: read.lowerReading
            )
            state.entries.append(visit.value)
            return visit.receipt
        case "record":
            let made = try history.record(
                on: state.asset, kind: try #require(read.string("kind").flatMap(HistoryKind.init(rawValue:))), title: read.string("title") ?? "",
                occurredAt: read.on, metricReading: read.double("metricReading"), totalCost: read.money("total"), note: read.string("note"),
                reference: read.string("reference"), items: read.items, providers: read.integer("provider").map { [state.firms[$0]] } ?? [],
                rating: read.integer("rating"), lowerReading: read.lowerReading
            )
            state.entries.append(made)
            return nil
        case "file":
            return try await file(read, in: state)
        case "addNote":
            let note = try history.addNote(on: state.asset, read.string("text") ?? "", occurredAt: read.on)
            state.entries.append(note.value)
            return note.receipt
        case "setNote": return try history.setNote(try #require(entry), read.string("text"))
        case "rate":
            try history.rate(try #require(entry), read.integer("rating"))
            return nil
        case "delete":
            try history.delete(try #require(entry))
            return nil
        case "addItems":
            try history.addItems(read.items, to: try #require(entry))
            return nil
        case "complete":
            let done = try ObligationActions(context: state.context, calendar: calendar, now: { clock }).complete(
                try #require(state.deadline), on: read.on, cost: read.money("cost"), metricReading: read.double("metricReading"), items: read.items
            )
            state.entries.append(done.value)
            return done.receipt
        default:
            Issue.record("No action \(String(describing: read.string("do")))")
            return nil
        }
    }

    /// Files a visit from its form, as the visit form does: the draft the case fills, kept as its kind asks.
    static func file(_ read: Reading, in state: State) async throws -> UndoReceipt? {
        let template = try #require(try TemplateStore(context: state.context).template(forKey: state.asset.templateKey))
        let form = try #require(VisitForm.make(for: template.definition))
        var draft = VisitDraft(date: read.on ?? now)
        for key in read.list("ticked").compactMap({ Reading(action: $0).string("componentKey") }) { draft.toggle(key) }
        for part in read.list("ticked") {
            let line = Reading(action: part)
            guard let key = line.string("componentKey") else { continue }
            draft.parts[key] = VisitDraft.Part(cost: line.decimal("cost"), brand: line.string("brand") ?? "")
        }
        draft.extras = read.list("extras").map { VisitDraft.Extra(name: Reading(action: $0).string("name") ?? "", cost: Reading(action: $0).decimal("cost")) }
        draft.odometer = read.double("odometer")
        draft.total = read.decimal("total")
        draft.note = read.string("note") ?? ""
        draft.rating = read.integer("rating")
        draft.reference = read.string("reference")
        let provider: CaptureFiler.Visit.ProviderChoice
        if let index = read.integer("provider") {
            provider = .existing(state.firms[index])
        } else if let name = read.string("named") {
            provider = .named(name, trade: form.shape.provider?.trade ?? .other, taxID: read.string("taxID"))
        } else {
            provider = .none
        }
        let visit = draft.filing(on: state.asset, form: form, provider: provider)
        let clock = now
        let outcome = try await CaptureFiler(context: state.context, calendar: calendar, now: { clock }).file(.visit(visit))
        if let made = outcome.visit { state.entries.append(made) }
        return outcome.receipt
    }

    /// What a step refused, by its kind.
    static func refusal(_ error: Error) throws -> String {
        if error is LowerReadingQuestion { return "lowerReading" }
        if error is HistoryNoteError { return "noteEmpty" }
        if error is ExampleSectionQuestion { return "example" }
        throw error
    }

    // MARK: What a case compares

    static func history(in context: ModelContext) throws -> JSONValue {
        let entries = try context.fetch(FetchDescriptor<HistoryEntry>()).sorted { ($0.occurredAt, $0.title) < ($1.occurredAt, $1.title) }
        return .array(try entries.map { entry in
            let items = (entry.items ?? []).sorted { ($0.name, $0.componentKey ?? "") < ($1.name, $1.componentKey ?? "") }
            return .object([
                "kind": .string(entry.kindRaw), "title": .string(entry.title), "occurredAt": seconds(entry.occurredAt),
                "metricReading": number(entry.metricReading), "cost": try money(entry.totalCost), "note": text(entry.note),
                "reference": text(entry.reference), "rating": int(entry.rating), "cycleDueDay": text(entry.cycleDueDay?.isoString),
                "isExample": .bool(entry.isExample), "providers": .array(entry.providerNames.map(JSONValue.string)),
                "items": .array(items.map { item in
                    .object([
                        "name": .string(item.name), "componentKey": text(item.componentKey), "group": text(item.group),
                        "cost": amount(item.costAmount), "laborCost": amount(item.laborCostAmount), "partsCost": amount(item.partsCostAmount),
                        "currency": .string(item.currency), "brand": text(item.partBrandOrCode),
                    ])
                }),
            ])
        })
    }

    static func readings(in context: ModelContext) throws -> JSONValue {
        let logs = try context.fetch(FetchDescriptor<MeasurementLog>()).sorted { ($0.recordedAt, $0.value) < ($1.recordedAt, $1.value) }
        return .array(logs.map { .object(["at": seconds($0.recordedAt), "value": .number($0.value), "startsCounter": .bool($0.startsCounter)]) })
    }

    static func deadline(_ obligation: Obligation?, in context: ModelContext) throws -> JSONValue {
        guard let id = obligation?.id else { return .null }
        let found = try context.fetch(FetchDescriptor<Obligation>()).first { $0.id == id }
        guard let found else { return .null }
        return .object(["dueDay": .string(found.dueDay.isoString), "status": .string(found.statusRaw), "dueMetric": number(found.dueMetric)])
    }

    static func firms(in context: ModelContext) throws -> JSONValue {
        let providers = try context.fetch(FetchDescriptor<Provider>()).sorted { $0.name < $1.name }
        return .array(providers.map { provider in
            .object(["name": .string(provider.name), "taxID": text(provider.taxID), "trades": .array(provider.trades.sorted().map(JSONValue.string)),
                     "sections": .int((provider.assets ?? []).count)])
        })
    }

    /// The section's hero value and the parts its history follows, as the maintenance log reads them.
    static func section(_ asset: Asset, in context: ModelContext) throws -> JSONValue {
        let template = try TemplateStore(context: context).template(forKey: asset.templateKey)
        let hero = template.flatMap { HouseholdMutations.heroMetricValue(values: asset.values, template: $0.definition) }
        let items = HistoryItemSnapshot.items(of: asset)
        let tracked = Set(MaintenanceLog.trackedComponents(in: items)).sorted()
        return .object([
            "hero": number(hero),
            "tracked": .array(tracked.map { key in
                let last = MaintenanceLog.lastOccurrence(of: key, in: items, now: now, calendar: calendar)
                return .object(["key": .string(key), "name": text(last?.name), "date": last.map { seconds($0.date) } ?? .null,
                                "metricAtTime": number(last?.metricAtTime)])
            }),
        ])
    }

    static func state(_ state: State) throws -> JSONValue {
        .object([
            "history": try history(in: state.context), "readings": try readings(in: state.context),
            "deadline": try deadline(state.deadline, in: state.context), "firms": try firms(in: state.context),
            "section": try section(state.asset, in: state.context),
        ])
    }

    static let car = Section(category: BuiltInTemplates.Key.vehicle, name: "VW Golf 2018",
                             values: [(VehicleFields.plate, .text("B-123-ABC")), (VehicleFields.year, .number(2018))],
                             readings: [("2026-06-01T09:00:00Z", 100_000), ("2026-09-01T09:00:00Z", 104_500)])
    static let plant = Section(category: BuiltInTemplates.Key.plants, name: "Ficus")
    static let fridge = Section(category: BuiltInTemplates.Key.purchase, name: "Frigider Exemplu")
    static let firm = "Service Exemplu SRL"
    static let nov20 = JSONValue.int(Int(noonOf("2026-11-20").timeIntervalSince1970))
    static let nov10 = JSONValue.int(Int(noonOf("2026-11-10").timeIntervalSince1970))

    static func part(_ key: String, _ cost: String? = nil, brand: String? = nil) -> JSONValue {
        var part: [String: JSONValue] = ["componentKey": .string(key)]
        if let cost { part["cost"] = .string(cost) }
        if let brand { part["brand"] = .string(brand) }
        return .object(part)
    }

    static func line(_ name: String, _ cost: String? = nil, componentKey: String? = nil, labour: String? = nil) -> JSONValue {
        var line: [String: JSONValue] = ["name": .string(name)]
        if let cost { line["cost"] = .string(cost) }
        if let componentKey { line["componentKey"] = .string(componentKey) }
        if let labour { line["laborCost"] = .string(labour) }
        return .object(line)
    }

    static let service: Action = [
        "do": "recordVisit", "on": nov20,
        "checklist": [part("engine.oil", "420"), part("filters.cabin"), part("brakes.padsFront", "380", brand: "Bosch")],
        "items": [line("Odorizant", "20"), line("Manoperă 1,5 ore", "200")],
        "total": "1100", "odometer": .number(108_000), "provider": .int(0), "note": "  Revizia anuală ", "reference": "SRV 0000001", "rating": .int(9),
    ]

    /// One visit of every kind a built-in has, filed from its form with everything filled in: the form keeps
    /// only what its kind asks.
    static var filingCases: [ActionCase] {
        BuiltInTemplates.all.compactMap { definition -> ActionCase? in
            guard let form = VisitForm.make(for: definition) else { return nil }
            var action: Action = [
                "do": "file", "on": nov20, "extras": [line("Altceva făcut", "50"), line("Manoperă", "80")], "total": "500",
                "note": "O notă", "named": "Firma Exemplu SRL", "rating": .int(4), "reference": "NR 0001", "odometer": .number(1_000),
            ]
            if let first = form.components.first { action["ticked"] = [part(first.key, "100", brand: "Marca Exemplu")] }
            return ActionCase(name: "a visit of \(definition.key) (\(definition.behavior.visit.rawValue)) filed from its form",
                              section: Section(category: definition.key, name: "\(definition.name) exemplu"), action: action)
        }
    }

    static var actionCases: [ActionCase] {
        [
            ActionCase(name: "a car's service: parts with a price and a brand, a row of one's own and its labour", section: car, firms: [firm], action: service),
            ActionCase(name: "a visit named by what was done", section: car,
                       action: ["do": "recordVisit", "on": nov20, "checklist": [part("engine.oil")], "items": [line("Manoperă", "150")]]),
            ActionCase(name: "a visit of labour alone keeps its name", section: car, action: ["do": "recordVisit", "on": nov20, "items": [line("Manoperă", "150")]]),
            ActionCase(name: "a visit with nothing listed", section: car, action: ["do": "recordVisit", "on": nov20]),
            ActionCase(name: "a visit with a lower kilometres asks first", section: car, action: ["do": "recordVisit", "on": nov20, "odometer": .number(90_000)]),
            ActionCase(name: "a lower kilometres kept as a new counter", section: car,
                       action: ["do": "recordVisit", "on": nov20, "odometer": .number(2_000), "lowerReading": "newCounter"]),
            ActionCase(name: "a repair of something bought", section: fridge,
                       action: ["do": "record", "kind": "repair", "title": "Compresor înlocuit", "on": nov10, "total": "350", "note": "În garanție",
                                "items": [line("Compresor", "300"), line("Mână de lucru", "50")]]),
            ActionCase(name: "a purchase for the car", section: car, firms: [firm],
                       action: ["do": "record", "kind": "purchase", "title": "Anvelope de iarnă", "on": nov10, "total": "1600", "reference": "FCT 0001",
                                "items": [line("Anvelope de iarnă", "1600")], "provider": .int(0)]),
            ActionCase(name: "a purchase with a lower kilometres asks first", section: car,
                       action: ["do": "record", "kind": "purchase", "title": "Ștergătoare", "on": nov10, "metricReading": .number(50_000)]),
            ActionCase(name: "a note on a plant", section: plant, action: ["do": "addNote", "text": "  Udat și fertilizat\nCu îngrășământ lichid ", "on": nov10]),
            ActionCase(name: "a note of nothing", section: plant, action: ["do": "addNote", "text": "   \n "]),
            ActionCase(name: "a record's note", section: car, before: [["do": "recordVisit", "on": nov10, "items": [line("Spălare")]]],
                       action: ["do": "setNote", "entry": .int(0), "text": "  Totul în regulă "]),
            ActionCase(name: "a note's title follows its first line", section: plant, before: [["do": "addNote", "text": "Prima notă", "on": nov10]],
                       action: ["do": "setNote", "entry": .int(0), "text": "\n  Altă primă linie\nRestul"]),
            ActionCase(name: "a note cleared", section: car, before: [["do": "recordVisit", "on": nov10, "note": "Ceva"]],
                       action: ["do": "setNote", "entry": .int(0), "text": "   "]),
            ActionCase(name: "a job rated keeps five stars at most", section: car, before: [["do": "recordVisit", "on": nov10]],
                       action: ["do": "rate", "entry": .int(0), "rating": .int(7)]),
            ActionCase(name: "a job rated keeps one star at least", section: car, before: [["do": "recordVisit", "on": nov10]],
                       action: ["do": "rate", "entry": .int(0), "rating": .int(0)]),
            ActionCase(name: "a rating cleared", section: car, before: [["do": "recordVisit", "on": nov10, "rating": .int(4)]],
                       action: ["do": "rate", "entry": .int(0)]),
            ActionCase(name: "deleting a visit takes its reading", section: car, firms: [firm], before: [service], action: ["do": "delete", "entry": .int(0)]),
            ActionCase(name: "parts added to a record, each found in the category's parts", section: car,
                       before: [["do": "record", "kind": "repair", "title": "Frâne", "on": nov10]],
                       action: ["do": "addItems", "entry": .int(0), "items": [line("Plăcuțe de frână spate", "380"), line("Manoperă", "120")]]),
            ActionCase(name: "a completion's parts and jobs", section: car, deadline: ("vehicle.service", "2026-12-01"),
                       action: ["do": "complete", "on": nov20, "cost": "600", "metricReading": .number(108_000),
                                "items": [line("Ulei", "300", componentKey: "engine.oil"), line("Manoperă", "150"), line("Filtru polen", "40")]]),
            ActionCase(name: "deleting the latest completion moves its deadline back", section: car, deadline: ("vehicle.service", "2026-12-01"),
                       before: [["do": "complete", "on": nov20, "metricReading": .number(108_000), "items": [line("Ulei", "300", componentKey: "engine.oil")]]],
                       action: ["do": "delete", "entry": .int(0)]),
            ActionCase(name: "deleting an older completion leaves the deadline", section: car, deadline: ("vehicle.service", "2026-12-01"),
                       before: [["do": "complete", "on": nov10], ["do": "complete", "on": nov20]], action: ["do": "delete", "entry": .int(0)]),
        ] + filingCases
    }

    static func actions() async throws -> Vectors {
        var cases: [JSONValue] = []
        for item in actionCases {
            let state = try make(item)
            for step in item.before { _ = try await run(step, in: state) }
            let before = try Self.state(state)
            var refused: String?
            var receipt: UndoReceipt?
            do {
                receipt = try await run(item.action, in: state)
            } catch {
                refused = try refusal(error)
            }
            let after = try Self.state(state)
            var undone: JSONValue = .null
            let canUndo = receipt?.canUndo ?? false
            if let receipt, canUndo {
                try receipt.undo()
                undone = .bool(try Self.state(state) == before)
            }
            cases.append(.object([
                "name": .string(item.name),
                "section": .object([
                    "category": .string(item.section.category), "name": .string(item.section.name),
                    "values": try RecurrenceVectorsTests.encoded(RecurrenceVectorsTests.values(item.section.values)),
                    "readings": .array(item.section.readings.map { .object(["at": .string($0.0), "value": .number($0.1)]) }),
                ]),
                "firms": .array(item.firms.map(JSONValue.string)),
                "deadline": item.deadline.map { .object(["blueprint": .string($0.0), "firstDue": .string($0.1)]) } ?? .null,
                "before": .array(item.before.map { .object($0) }), "action": .object(item.action), "now": seconds(now),
                "refused": text(refused), "after": after, "receipt": .bool(receipt != nil), "canUndo": .bool(canUndo), "undoRestores": undone,
            ]))
        }
        return Vectors(
            name: "actions",
            rule: "HistoryActions: recordVisit, record, addNote, setNote, rate, delete, addItems; a visit filed from its form (VisitDraft.filing through CaptureFiler, its firm by ProviderActions.findOrCreate); ObligationActions.complete with its parts and jobs",
            source: "ios/DosarCuSina/Services/History/HistoryActions.swift, HistoryDeletion.swift, ios/DosarCuSina/Views/Add/Visit/VisitDraft.swift, ios/DosarCuSina/Views/Capture/Filing/CaptureFiler.swift",
            shape: "section: the section (its category, name, values in the archive's form, kilometre readings at UTC moments). firms: firms made first (a mechanic each, linked to it), by index. deadline: a deadline of its category made first (its blueprint and first due day), or null. before: actions taken first; action: the one compared. Each action's 'do' and its parts: 'on' a moment in seconds; amounts as text in lei; checklist: ticked parts (componentKey, cost, brand); items and extras: rows (name, cost, laborCost, componentKey); provider: a firm by index; named and taxID: a firm named on the form; entry: a record an earlier action made, by index; lowerReading: the answer to a lower counter. 'file' fills the visit form's draft with all of it and files what the form keeps. now: every action's clock, days counted in Bucharest. refused: the kind of refusal (lowerReading, noteEmpty, example), or null. after: the binder after it: every record of history by when, then title (its kind, title, when, counter, cost, note, number, rating, the cycle it closed, firms by name, its rows by name: part key, group, amounts as text, currency, brand), the section's readings by when, the deadline (due day, status, counter) or null, every firm by name (CUI, trades, sections it is linked to), and the section's hero value with the parts its history follows (each by key: its last name, when and counter). receipt: whether the action gives an undo receipt; canUndo: whether it has anything to take back. undoRestores: for one that has, whether undo gives the binder back as before it; null otherwise.",
            cases: cases
        )
    }
}
