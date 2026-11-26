import Foundation
import SwiftData
import Testing
@testable import DosarCuSina

/// A deadline's whole life: its kinds and what closing it asks (`ObligationKind`, `CompletionKind`,
/// `CompletionShape`, `CompletionRecord`), what a category's usual deadlines say (`isWorthScheduling`,
/// `reminders(for:)`, `DeadlineFacts`), `DueDayValidity`, the reminders that follow a section's values
/// (`DeadlineReminders`), deadlines closed twice (`LikelyDoubleCompletions`), and what every
/// `ObligationActions` action leaves in the binder (completing each kind, a stale cycle, a snooze, a
/// reschedule, the reminders laid over what is stored, an edit, and what undo brings back), run over
/// cases chosen to bite and written to `shared/test-vectors/deadlines/`, one file per rule. The Android
/// app's tests read the same files and must give the same answers (docs/ANDROID_PLAN.md, "How parity is
/// kept"): `core.deadlines`, `catalog`'s blueprint rules and `store.obligations`, the actions run through
/// the real Room store. A sibling of `ValueVectorsTests`, with a folder of its own.
///
/// Every case counts days in Bucharest, at a fixed now; rules, profiles, values and money are written in
/// the archive's form, moments as seconds since 1970. No words: a kind is written by its raw value.
/// Placeholder data only.
@MainActor
@Suite("Deadline vectors")
struct DeadlineVectorsTests {
    static var folder: URL {
        URL(filePath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appending(path: "shared/test-vectors/deadlines")
    }

    /// How to bring the files up to date, said when one isn't.
    static let regenerate = """
    is out of date with the deadline rules. Bring shared/test-vectors/deadlines up to date: \
    TEST_RUNNER_DEADLINE_VECTORS_WRITE=1 ./tests/run_tests.sh (or run DeadlineVectorsTests in Xcode with \
    DEADLINE_VECTORS_WRITE=1 in the scheme's environment), review the diff and commit it, then run the \
    Android tests (./gradlew :core:test :catalog:test :store:test in android/), which read the same files.
    """

    typealias Vectors = ValueVectorsTests.Vectors

    @Test("shared/test-vectors/deadlines is up to date with the deadline rules")
    func vectorsAreUpToDate() throws {
        let files = try Self.all()
        let writes = ProcessInfo.processInfo.environment["DEADLINE_VECTORS_WRITE"] == "1"
        let manager = FileManager.default
        if writes { try manager.createDirectory(at: Self.folder, withIntermediateDirectories: true) }
        for file in files {
            let url = Self.folder.appending(path: "\(file.name).json")
            let fresh = try ValueVectorsTests.render(file)
                .replacingOccurrences(of: "ios/DosarCuSinaTests/ValueVectorsTests.swift", with: "ios/DosarCuSinaTests/DeadlineVectorsTests.swift")
            if writes {
                try fresh.write(to: url, atomically: true, encoding: .utf8)
                continue
            }
            let committed = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
            #expect(committed == fresh, Comment(rawValue: "\(file.name).json " + Self.regenerate))
            // The file as it should be, kept in the run's result bundle, so a run on GitHub hands it over too.
            if committed != fresh { Testing.Attachment.record(Data(fresh.utf8), named: "deadlines-\(file.name).json") }
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
        try [kinds(), blueprints(), validity(), facts(), doubleCompletions(), remindersFollowing(), actions()]
    }

    // MARK: Helpers

    static let calendar = Calendar.bucharest
    static func day(_ text: String) -> CalendarDay { ValueVectorsTests.day(text) }
    static func iso(_ day: CalendarDay?) -> JSONValue { ValueVectorsTests.iso(day) }
    static func encoded<Value: Encodable>(_ value: Value) throws -> JSONValue { try RecurrenceVectorsTests.encoded(value) }
    static func decoded<Value: Decodable>(_ type: Value.Type, _ json: JSONValue) throws -> Value { try RecurrenceVectorsTests.decoded(type, json) }
    static func number(_ value: Double?) -> JSONValue { value.map(JSONValue.number) ?? .null }
    static func int(_ value: Int?) -> JSONValue { value.map(JSONValue.int) ?? .null }
    static func text(_ value: String?) -> JSONValue { value.map(JSONValue.string) ?? .null }
    static func seconds(_ date: Date) -> JSONValue { .int(Int(date.timeIntervalSince1970.rounded())) }
    static func values(_ pairs: [(String, FieldValue)]) -> FieldValues { RecurrenceVectorsTests.values(pairs) }

    // MARK: Kinds

    static func shape(_ shape: CompletionShape) -> JSONValue {
        let cost: JSONValue = shape.cost.map { .string($0 == .cost ? "cost" : "paid") } ?? .null
        let counter: JSONValue = shape.counter.map { .string($0 == .section ? "section" : "countedOn") } ?? .null
        let newEnd: JSONValue = shape.newEnd.map { .string($0 == .expires ? "expires" : "ends") } ?? .null
        let paper: JSONValue = shape.paper.map {
            .object(["gender": .string($0.gender.rawValue), "use": .string($0.use.rawValue), "origin": .string($0.origin.rawValue)])
        } ?? .null
        let replacement: JSONValue = shape.replacement.map {
            .object(["replacesItsSection": .bool($0.replacesItsSection), "holdersDocumentType": text($0.holdersDocumentType)])
        } ?? .null
        return .object([
            "asksDate": .bool(shape.asksDate), "cost": cost, "paper": paper, "newEnd": newEnd, "asksNote": .bool(shape.asksNote),
            "counter": counter, "replacement": replacement, "closesOutsideTheApp": .bool(shape.closesOutsideTheApp),
            "isOneTap": .bool(shape.isOneTap), "replacesDocument": .bool(shape.replacesDocument), "replacesSection": .bool(shape.replacesSection),
            "asksNewExpiry": .bool(shape.asksNewExpiry), "asksReading": .bool(shape.asksReading), "offersNoteAfter": .bool(shape.offersNoteAfter),
        ])
    }

    static func kinds() throws -> Vectors {
        var cases: [JSONValue] = try ObligationKind.allCases.map { kind in
            .object([
                "obligationKind": .string(kind.rawValue), "missedCyclesStayOwed": .bool(kind.missedCyclesStayOwed),
                "defaultProfile": try encoded(kind.defaultProfile), "own": .string(CompletionKind.own(kind).rawValue),
                "historyKindOfOwn": .string(HistoryKind.forCompleting(.own(kind), importance: kind).rawValue),
            ])
        }
        for raw: String? in ["legal", "routine", "Routine", "chore", "", nil] {
            cases.append(.object(["storedKind": text(raw), "reads": .string(ObligationKind(stored: raw).rawValue)]))
        }
        for kind in CompletionKind.allCases {
            cases.append(.object([
                "completionKind": .string(kind.rawValue), "record": .string(kind.record.rawValue),
                "historyKind": .string(kind.record.historyKind.rawValue), "shape": shape(kind.shape),
            ]))
        }
        for raw: String? in ["itp", "policy", "ITP", "newer", "", nil] {
            cases.append(.object(["storedCompletion": text(raw), "reads": text(CompletionKind(stored: raw)?.rawValue)]))
        }
        return Vectors(
            name: "kinds",
            rule: "ObligationKind (stored, missedCyclesStayOwed, defaultProfile), CompletionKind (own, stored, shape, record), CompletionRecord.historyKind, HistoryKind.forCompleting",
            source: "ios/DosarCuSina/Models/Obligations/ObligationTypes.swift, CompletionKind.swift, CompletionShape.swift, ios/DosarCuSina/Models/Schema/HistoryModel.swift",
            shape: "obligationKind: a kind, whether its missed cycles stay owed, the reminders it starts from (archive form), what a deadline of one's own of it completes as, and the history kind that writes. storedKind: a stored text and the kind it reads as. completionKind: a kind, its record and history kind, and what closing it asks (asksDate; cost: cost or paid; paper: gender, use, origin; newEnd: expires or ends; asksNote; counter: section or countedOn; replacement: whether it is the section, the holder's document type), with what follows from it. storedCompletion: a stored text and the kind it reads as, null for none.",
            cases: cases
        )
    }

    // MARK: A category's usual deadlines

    static func blueprints() throws -> Vectors {
        var cases: [JSONValue] = []
        let today = day("2026-11-26")
        for template in BuiltInTemplates.all {
            for blueprint in template.blueprints {
                cases.append(.object([
                    "category": .string(template.key), "blueprint": .string(blueprint.key),
                    "completion": .string((blueprint.completion ?? .own(blueprint.kind)).rawValue),
                    "isFieldDriven": .bool(blueprint.isFieldDriven), "drivingField": text(blueprint.drivingField),
                    "facts": .object(Dictionary(blueprint.facts?.fields.map { ($0.role.rawValue, JSONValue.string($0.field)) } ?? [], uniquingKeysWith: { first, _ in first })),
                    "worthYesterday": .bool(blueprint.isWorthScheduling(on: day("2026-11-25"), today: today)),
                    "worthToday": .bool(blueprint.isWorthScheduling(on: today, today: today)),
                    "reminders": try encoded(blueprint.reminders(for: FieldValues())),
                ]))
            }
        }
        // Reminders by a section's values: a passport and an identity card, a value no variant names.
        let documents = try #require(BuiltInTemplates.all.first { $0.key == BuiltInTemplates.Key.documents })
        for type in [DocumentType.passport, DocumentType.idCard, "documentType.newer", "Pașaport"] {
            let pairs: [(String, FieldValue)] = [(DocumentType.typeFieldKey, .text(type))]
            for blueprint in documents.blueprints {
                cases.append(.object([
                    "category": .string(documents.key), "blueprint": .string(blueprint.key), "values": try encoded(values(pairs)),
                    "remindersFor": try encoded(blueprint.reminders(for: values(pairs))),
                    "worthYesterdayFor": .bool(blueprint.isWorthScheduling(on: day("2026-11-25"), today: today, values: values(pairs))),
                ]))
            }
        }
        return Vectors(
            name: "blueprints",
            rule: "ObligationBlueprint's completion, isFieldDriven, drivingField, facts, isWorthScheduling(on:today:values:) and reminders(for:), over every built-in category's usual deadlines",
            source: "ios/DosarCuSina/Models/Obligations/ObligationTypes.swift, DueDayValidity.swift, ios/DosarCuSina/Services/Templates/BuiltInTemplates.swift",
            shape: "category and blueprint: a built-in's usual deadline by key. completion: what closing it asks. isFieldDriven and drivingField: whether its day comes from a section's field, and which. facts: the field each fact role reads. worthYesterday and worthToday: whether a deadline due yesterday or today, made today, is worth making (no values). reminders: how it reminds with no values. values with remindersFor and worthYesterdayFor: the same for a section's values.",
            cases: cases
        )
    }

    static func validity() throws -> Vectors {
        let inputs: [(String, String)] = [("2027-08-12", "2027-08-11"), ("2027-08-12", "2027-08-12"), ("2027-08-12", "2027-08-13"), ("2028-02-29", "2028-03-01")]
        let cases: [JSONValue] = inputs.map { due, on in
            .object(["due": .string(due), "on": .string(on), "isValid": .bool(DueDayValidity.isValid(due: day(due), on: day(on))),
                     "covers": .bool(DueDayValidity.covers(through: day(on), due: day(due)))])
        }
        return Vectors(
            name: "validity",
            rule: "DueDayValidity.isValid(due:on:) and covers(through:due:)",
            source: "ios/DosarCuSina/Models/Obligations/DueDayValidity.swift",
            shape: "due: a due day. on: a day. isValid: whether what is due then is still valid that day (the due day is its last valid day). covers: whether it stays valid every day through it.",
            cases: cases
        )
    }

    static func facts() throws -> Vectors {
        let money = { (amount: String) in FieldValue.money(Money(Decimal(string: amount) ?? 0, currency: "RON")) }
        let car: [(String, FieldValue)] = [
            (VehicleFields.insurer, .text("Asigurator Exemplu S.A.")), (VehicleFields.policyNumber, .text("RO/25/AA/0001")),
            (VehicleFields.claimsPhone, .text("0700 000 000")), (VehicleFields.policyholder, .text("Ana Exemplu")),
            (VehicleFields.cascoInsurer, .text("Alt Asigurator S.A.")), (VehicleFields.cascoPolicyNumber, .text("CASCO-0002")),
            (VehicleFields.cascoInsuredSum, money("85000")),
        ]
        let home: [(String, FieldValue)] = [(HomeFields.insurer, .text("PAID")), (HomeFields.policyNumber, .text("PAD-0003")),
                                            (HomeFields.insuredSum, money("0")), (HomeFields.claimsPhone, .text(""))]
        let inputs: [(String, String?, [(String, FieldValue)], String?)] = [
            (BuiltInTemplates.Key.vehicle, BuiltInBlueprints.vehicleRCA, car, nil),
            (BuiltInTemplates.Key.vehicle, BuiltInBlueprints.vehicleCASCO, car, nil),
            (BuiltInTemplates.Key.vehicle, BuiltInBlueprints.vehicleRCA, car, "RO/26/BB/0009"),
            (BuiltInTemplates.Key.vehicle, BuiltInBlueprints.vehicleRCA, car, "   "),
            (BuiltInTemplates.Key.vehicle, BuiltInBlueprints.vehicleITP, car, "ITP-0001"),
            (BuiltInTemplates.Key.vehicle, nil, car, nil),
            (BuiltInTemplates.Key.vehicle, "vehicle.newer", car, nil),
            (BuiltInTemplates.Key.home, BuiltInBlueprints.homePAD, home, nil),
            (BuiltInTemplates.Key.home, BuiltInBlueprints.homeInsurance, home, nil),
        ]
        var cases: [JSONValue] = []
        for (category, key, pairs, reference) in inputs {
            let template = BuiltInTemplates.all.first { $0.key == category }
            let found = DeadlineFacts.of(blueprintKey: key, in: template, values: values(pairs), reference: reference)
            cases.append(.object([
                "category": .string(category), "blueprint": text(key), "values": try encoded(values(pairs)), "reference": text(reference),
                "facts": .object([
                    "insurer": text(found.insurer), "policyNumber": text(found.policyNumber), "claimsPhone": text(found.claimsPhone),
                    "policyholder": text(found.policyholder), "insuredSum": try found.insuredSum.map { try encoded($0) } ?? .null,
                ]),
            ]))
        }
        return Vectors(
            name: "facts",
            rule: "DeadlineFacts.of(blueprintKey:in:values:reference:)",
            source: "ios/DosarCuSina/Services/Obligations/DeadlineFacts.swift",
            shape: "category: a built-in. blueprint: the deadline's blueprint key, or null for one of the person's own. values: the section's values. reference: the number typed on the deadline. facts: what its page puts at hand, each null when it isn't there (empty text and a sum of nothing are none).",
            cases: cases
        )
    }

    static func doubleCompletions() throws -> Vectors {
        typealias C = LikelyDoubleCompletions.Completion
        let noon = { (text: String) in day(text).noonDate(in: calendar) }
        let inputs: [(String, (String, String?, String?), (String, String?, String?))] = [
            ("a stale tap the next day", ("2026-11-04", "2026-12-05", "2027-01-05"), ("2026-11-03", "2026-11-05", "2026-12-05")),
            ("a month apart is two real payments", ("2026-12-04", "2026-12-05", "2027-01-05"), ("2026-11-03", "2026-11-05", "2026-12-05")),
            ("only consecutive cycles", ("2026-11-04", "2026-12-20", "2027-01-20"), ("2026-11-03", "2026-11-05", "2026-12-05")),
            ("catching up on a late month is real", ("2026-11-04", "2026-11-05", "2026-12-05"), ("2026-11-03", "2026-10-05", "2026-11-05")),
            ("seven days apart", ("2026-11-10", "2026-12-05", "2027-01-05"), ("2026-11-03", "2026-11-05", "2026-12-05")),
            ("eight days apart", ("2026-11-11", "2026-12-05", "2027-01-05"), ("2026-11-03", "2026-11-05", "2026-12-05")),
            ("the cycle only a week ahead", ("2026-11-27", "2026-12-05", "2027-01-05"), ("2026-11-26", "2026-11-05", "2026-12-05")),
            ("the cycle eight days ahead", ("2026-11-27", "2026-12-05", "2027-01-05"), ("2026-11-27", "2026-11-05", "2026-12-05")),
            ("no cycle", ("2026-11-04", nil, "2027-01-05"), ("2026-11-03", "2026-11-05", "2026-12-05")),
        ]
        func written(_ item: C) -> JSONValue {
            .object(["occurredAt": seconds(item.occurredAt), "cycle": iso(item.cycle), "next": iso(item.next)])
        }
        var cases: [JSONValue] = []
        for (name, latest, previous) in inputs {
            let a = C(id: UUID(), occurredAt: noon(latest.0), cycle: latest.1.map(day), next: latest.2.map(day))
            let b = C(id: UUID(), occurredAt: noon(previous.0), cycle: previous.1.map(day), next: previous.2.map(day))
            cases.append(.object(["name": .string(name), "latest": written(a), "previous": written(b),
                                  "isLikely": .bool(LikelyDoubleCompletions.isLikely(latest: a, previous: b, calendar: calendar))]))
        }
        return Vectors(
            name: "double-completions",
            rule: "LikelyDoubleCompletions.isLikely(latest:previous:calendar:)",
            source: "ios/DosarCuSina/Intents/LikelyDoubleCompletions.swift",
            shape: "latest and previous: a deadline's two latest completions, newest first (when recorded, the cycle it closed, the day it moved to). isLikely: whether they look like one real tap and one stale one.",
            cases: cases
        )
    }

    // MARK: The binder

    /// Noon on 26 November 2026 in Bucharest: every action's now.
    static let now = day("2026-11-26").noonDate(in: Calendar.bucharest)

    /// A section a case keeps: its category, its values and its readings.
    struct Section {
        var category: String
        var name: String
        var values: [(String, FieldValue)] = []
        var readings: [(String, Double)] = []
    }

    /// The deadline a case starts from: one of its category's usual ones, or one of the person's own.
    enum Start {
        case blueprint(String, firstDue: String)
        case own(title: String, kind: ObligationKind, due: String, recurrence: JSONValue, reminders: JSONValue?)
    }

    /// One action, as a case writes it.
    typealias Action = [String: JSONValue]

    struct ActionCase {
        let name: String
        var section: Section?
        let start: Start
        var before: [Action] = []
        let action: Action
    }

    /// The section and its deadline, made in `context` as the case says.
    static func make(_ item: ActionCase, in context: ModelContext) throws -> Obligation {
        let clock = now
        let actions = ObligationActions(context: context, calendar: calendar, now: { clock })
        var asset: Asset?
        if let section = item.section {
            let made = Asset(name: section.name, templateKey: section.category, values: values(section.values))
            context.insert(made)
            for (at, value) in section.readings {
                let log = MeasurementLog(kind: .odometer, name: "", value: value, unit: .kilometres, recordedAt: RecurrenceVectorsTests.moment(at))
                context.insert(log)
                log.asset = made
            }
            try UnitOfWork.save(context)
            asset = made
        }
        switch item.start {
        case .blueprint(let key, let firstDue):
            let template = try #require(try TemplateStore(context: context).template(forKey: item.section?.category ?? ""))
            let blueprint = try #require(template.definition.blueprints.first { $0.key == key })
            return try actions.create(from: blueprint, for: try #require(asset), firstDue: day(firstDue))
        case .own(let title, let kind, let due, let recurrence, let reminders):
            return try actions.create(title: title, kind: kind, dueDay: day(due), for: asset,
                                      recurrence: try decoded(RecurrenceRule.self, recurrence),
                                      reminders: try reminders.map { try decoded(ReminderProfile.self, $0) })
        }
    }

    /// Runs `action` on `obligation`; its receipt when it gives one.
    static func run(_ action: Action, on obligation: Obligation, in context: ModelContext) throws -> UndoReceipt? {
        let clock = now
        let actions = ObligationActions(context: context, calendar: calendar, now: { clock })
        func string(_ key: String) -> String? { if case .string(let value)? = action[key] { return value } else { return nil } }
        func double(_ key: String) -> Double? {
            switch action[key] {
            case .number(let value)?: return value
            case .int(let value)?: return Double(value)
            default: return nil
            }
        }
        func integer(_ key: String) -> Int? { if case .int(let value)? = action[key] { return value } else { return nil } }
        func dayOf(_ key: String) -> CalendarDay? { string(key).map(day) }
        func money(_ key: String) throws -> Money? {
            guard let value = action[key], value != .null else { return nil }
            return try decoded(Money.self, value)
        }
        switch string("do") {
        case "complete":
            let cost = try money("cost")
            let on = integer("on").map { Date(timeIntervalSince1970: TimeInterval($0)) }
            return try actions.complete(obligation, on: on, cost: cost, metricReading: double("metricReading"), note: string("note"),
                                        rating: integer("rating"), cycle: dayOf("cycle"), continuingOn: dayOf("continuingOn")).receipt
        case "snooze": return try actions.snooze(obligation, days: integer("days") ?? 0)
        case "clearSnooze": return try actions.clearSnooze(obligation)
        case "reschedule": return try actions.reschedule(obligation, to: try #require(dayOf("day")))
        case "pause": return try actions.pause(obligation)
        case "resume": return try actions.resume(obligation)
        case "archive": return try actions.archive(obligation)
        case "delete": return try actions.delete(obligation)
        case "setRecurrence":
            return try actions.setRecurrence(obligation, try decoded(RecurrenceRule.self, try #require(action["rule"])),
                                             startedFrom: try action["startedFrom"].map { try decoded(RecurrenceRule.self, $0) })
        case "setReminders":
            try actions.setReminders(obligation, try decoded(ReminderProfile.self, try #require(action["reminders"])),
                                     startedFrom: try action["startedFrom"].map { try decoded(ReminderProfile.self, $0) })
            return nil
        case "setFollowUpAfterLapse":
            try actions.setFollowUpAfterLapse(obligation, action["isOn"] == .bool(true))
            return nil
        case "restoreUsualReminders": return try actions.restoreUsualReminders(obligation)?.receipt
        case "setReminderTime":
            return try actions.setReminderTime(obligation, minuteOfDay: integer("minuteOfDay"), startedFrom: integer("startedFrom"))
        case "rename": return try actions.rename(obligation, to: string("title") ?? "", startedFrom: string("startedFrom"))
        case "setImportance":
            let importance = try #require(string("importance").flatMap(DeadlineChoice.Importance.init(rawValue:)))
            return try actions.setImportance(obligation, importance, startedFrom: string("startedFrom").flatMap(DeadlineChoice.Importance.init(rawValue:)))
        case "setDetails":
            let cost = try money("estimatedCost")
            try actions.setDetails(obligation, estimatedCost: cost, reference: string("reference"))
            return nil
        case "edit":
            let start = DeadlineEdit(obligation)
            var edited = start
            if let title = string("title") { edited.title = title }
            if let importance = string("importance").flatMap(DeadlineChoice.Importance.init(rawValue:)) { edited.choose(importance) }
            if let due = dayOf("dueDay") { edited.dueDay = due }
            if let rule = action["recurrence"] { edited.recurrence = try decoded(RecurrenceRule.self, rule) }
            if case .array(let leads)? = action["leadDays"] {
                edited.reminders = edited.reminders.withLeadDays(leads.compactMap { value -> Int? in
                    if case .int(let n) = value { return n }
                    return nil
                })
            }
            if action["reminderMinuteOfDay"] != nil { edited.reminderMinuteOfDay = integer("reminderMinuteOfDay") }
            return try actions.edit(obligation, to: edited, startedFrom: start)
        default:
            Issue.record("No action \(String(describing: string("do")))")
            return nil
        }
    }

    /// What a step refused, by its kind.
    static func refusal(_ error: Error) -> String {
        if let error = error as? ObligationActionError {
            switch error {
            case .notActive: return "notActive"
            case .missingFirstDueDate: return "missingFirstDueDate"
            case .notPersonsOwn: return "notPersonsOwn"
            case .missingTitle: return "missingTitle"
            case .cycleClosed: return "cycleClosed"
            case .newDayHasPassed: return "newDayHasPassed"
            }
        }
        if error is LowerReadingQuestion { return "lowerReading" }
        return "other"
    }

    /// The deadline as stored, or null once it is gone.
    static func state(of id: UUID, in context: ModelContext) throws -> JSONValue {
        var descriptor = FetchDescriptor<Obligation>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        guard let obligation = try context.fetch(descriptor).first else { return .null }
        return .object([
            "title": .string(obligation.title), "kind": .string(obligation.kindRaw), "dueDay": .string(obligation.dueDay.isoString),
            "dueMetric": number(obligation.dueMetric), "status": .string(obligation.statusRaw), "snoozedUntil": iso(obligation.snoozedUntil),
            "recurrence": try encoded(obligation.recurrence), "reminders": try encoded(obligation.reminders),
            "reminderMinuteOfDay": int(obligation.reminderMinuteOfDay), "remindersCustomized": .bool(obligation.remindersCustomized),
            "blueprintKey": text(obligation.blueprintKey), "reference": text(obligation.reference),
            "estimatedCost": try obligation.estimatedCost.map { try encoded($0) } ?? .null,
        ])
    }

    /// The records of history of the section and the household, by the cycle they closed, then when.
    static func history(in context: ModelContext) throws -> JSONValue {
        let entries = try context.fetch(FetchDescriptor<HistoryEntry>()).sorted {
            ($0.cycleDueDay ?? .earliest, $0.occurredAt) < ($1.cycleDueDay ?? .earliest, $1.occurredAt)
        }
        return .array(try entries.map { entry in
            .object([
                "kind": .string(entry.kindRaw), "title": .string(entry.title), "occurredAt": seconds(entry.occurredAt),
                "cycleDueDay": iso(entry.cycleDueDay), "nextDueDay": iso(entry.nextDueDay), "previousStatus": text(entry.previousStatusRaw),
                "previousDueMetric": number(entry.previousDueMetric), "cost": try entry.totalCost.map { try encoded($0) } ?? .null,
                "metricReading": number(entry.metricReading), "note": text(entry.note), "rating": int(entry.rating),
                "hasDeadline": .bool(entry.obligation != nil),
            ])
        })
    }

    /// The section's readings, by when, then by value.
    static func readings(in context: ModelContext) throws -> JSONValue {
        let logs = try context.fetch(FetchDescriptor<MeasurementLog>()).sorted { ($0.recordedAt, $0.value) < ($1.recordedAt, $1.value) }
        return .array(logs.map { .object(["at": seconds($0.recordedAt), "value": .number($0.value), "unit": .string($0.unit)]) })
    }

    static func monthly(_ anchor: String = "dueDate") -> JSONValue { RecurrenceVectorsTests.interval(1, "month", anchor) }
    static let oneOffRule: JSONValue = .object(["type": "none"])
    static func profile(_ leads: [Int], _ consequence: String, grace: Int = 0, followUp: Bool? = nil) -> JSONValue {
        var object: [String: JSONValue] = ["leadDays": .array(leads.map(JSONValue.int)), "consequence": .string(consequence), "graceDays": .int(grace)]
        if let followUp { object["followUpAfterLapse"] = .bool(followUp) }
        return .object(object)
    }

    static let car = Section(category: BuiltInTemplates.Key.vehicle, name: "VW Golf 2018",
                             values: [(VehicleFields.year, .number(2013)), (VehicleFields.plate, .text("B-123-ABC"))],
                             readings: [("2026-06-01T09:00:00Z", 100_000), ("2026-09-01T09:00:00Z", 104_500)])
    static let passport = Section(category: BuiltInTemplates.Key.documents, name: "Pașaport",
                                  values: [(DocumentType.typeFieldKey, .text(DocumentType.passport)), (DocumentFields.expiry, .date(day("2027-08-12")))])
    static let healthFile = Section(category: BuiltInTemplates.Key.health, name: "Fișa medicală")
    static let rent = Start.own(title: "Chirie", kind: .payment, due: "2026-11-05", recurrence: monthly(), reminders: nil)
    static let chore = Start.own(title: "Udat plantele", kind: .routine, due: "2026-11-20", recurrence: RecurrenceVectorsTests.interval(3, "day"), reminders: nil)
    static let oneOff = Start.own(title: "Revizie centrală", kind: .maintenance, due: "2026-12-10", recurrence: oneOffRule, reminders: nil)
    static let ownLegal = Start.own(title: "Analize", kind: .legal, due: "2027-01-15", recurrence: RecurrenceVectorsTests.interval(1, "year"),
                               reminders: profile([30, 7, 0], "legal"))

    static let actionCases: [ActionCase] = [
        ActionCase(name: "rent paid on time", start: rent, action: ["do": "complete"]),
        ActionCase(name: "rent paid three months late closes one month", start: .own(title: "Chirie", kind: .payment, due: "2026-08-05", recurrence: monthly(), reminders: nil),
                   action: ["do": "complete"]),
        ActionCase(name: "a chore done late moves past the day", start: chore, action: ["do": "complete"]),
        ActionCase(name: "a chore done on a day of one's own", start: chore, action: ["do": "complete", "on": .int(1_795_000_000)]),
        ActionCase(name: "a cycle already closed is never closed again", start: rent, before: [["do": "complete"]],
                   action: ["do": "complete", "cycle": "2026-11-05"]),
        ActionCase(name: "the cycle the person saw is closed", start: rent, action: ["do": "complete", "cycle": "2026-11-05"]),
        ActionCase(name: "a paused deadline isn't completed", start: rent, before: [["do": "pause"]], action: ["do": "complete"]),
        ActionCase(name: "a one-off closes", start: oneOff, action: ["do": "complete", "cost": .object(["amount": "250", "currency": "RON"]),
                                                                      "note": "Filtru schimbat", "rating": .int(9)]),
        ActionCase(name: "a one-off goes on from a new day", start: oneOff, action: ["do": "complete", "continuingOn": "2027-12-10"]),
        ActionCase(name: "a new day that has passed", start: oneOff, action: ["do": "complete", "continuingOn": "2026-11-26"]),
        ActionCase(name: "completing lets go of a snooze", start: rent, before: [["do": "snooze", "days": .int(3)]], action: ["do": "complete"]),
        ActionCase(name: "an ITP of a car thirteen years old", section: car, start: .blueprint(BuiltInBlueprints.vehicleITP, firstDue: "2026-12-01"),
                   action: ["do": "complete", "cost": .object(["amount": "180", "currency": "RON"])]),
        ActionCase(name: "a car's service with the kilometres", section: car, start: .blueprint("vehicle.service", firstDue: "2026-12-01"),
                   action: ["do": "complete", "metricReading": .number(108_000)]),
        ActionCase(name: "a car's service with a lower kilometres asks first", section: car, start: .blueprint("vehicle.service", firstDue: "2026-12-01"),
                   action: ["do": "complete", "metricReading": .number(90_000)]),
        ActionCase(name: "a passport's renewal closes whatever its repeat", section: passport, start: .blueprint(BuiltInBlueprints.documentRenew, firstDue: "2027-05-12"),
                   action: ["do": "complete"]),
        ActionCase(name: "a European health card closes whatever its repeat", section: healthFile, start: .blueprint(BuiltInBlueprints.healthEUCard, firstDue: "2027-03-01"),
                   before: [["do": "setRecurrence", "rule": RecurrenceVectorsTests.interval(2, "year", "completion")]], action: ["do": "complete"]),
        ActionCase(name: "a tyre change on its fixed dates", section: car, start: .blueprint("vehicle.tyres", firstDue: "2026-11-01"), action: ["do": "complete"]),
        ActionCase(name: "a snooze of three days", start: rent, action: ["do": "snooze", "days": .int(3)]),
        ActionCase(name: "a snooze of no days is one", start: rent, action: ["do": "snooze", "days": .int(0)]),
        ActionCase(name: "a paused deadline isn't snoozed", start: rent, before: [["do": "pause"]], action: ["do": "snooze", "days": .int(3)]),
        ActionCase(name: "a snooze taken back", start: rent, before: [["do": "snooze", "days": .int(3)]], action: ["do": "clearSnooze"]),
        ActionCase(name: "a reschedule lets go of a snooze", start: rent, before: [["do": "snooze", "days": .int(3)]], action: ["do": "reschedule", "day": "2026-12-01"]),
        ActionCase(name: "a pause lets go of a snooze", start: rent, before: [["do": "snooze", "days": .int(3)]], action: ["do": "pause"]),
        ActionCase(name: "a resume", start: rent, before: [["do": "pause"]], action: ["do": "resume"]),
        ActionCase(name: "an archive", start: rent, action: ["do": "archive"]),
        ActionCase(name: "a delete keeps what it closed", start: rent, before: [["do": "complete"]], action: ["do": "delete"]),
        ActionCase(name: "a new repeat", start: rent, action: ["do": "setRecurrence", "rule": RecurrenceVectorsTests.interval(2, "month")]),
        ActionCase(name: "a repeat changed meanwhile stays where this edit left it", start: rent,
                   before: [["do": "setRecurrence", "rule": RecurrenceVectorsTests.interval(1, "month", "completion")]],
                   action: ["do": "setRecurrence", "rule": RecurrenceVectorsTests.interval(3, "month"), "startedFrom": monthly()]),
        ActionCase(name: "reminders of one's own", start: rent, action: ["do": "setReminders", "reminders": profile([5, 1], "financial")]),
        ActionCase(name: "the usual reminders by hand follow the document again", section: passport,
                   start: .blueprint(BuiltInBlueprints.documentRenew, firstDue: "2027-05-12"),
                   before: [["do": "setReminders", "reminders": profile([200], "legal")]],
                   action: ["do": "restoreUsualReminders"]),
        ActionCase(name: "reminders laid over a change made meanwhile", start: rent,
                   before: [["do": "setReminders", "reminders": profile([2, 0], "financial", followUp: false)]],
                   action: ["do": "setReminders", "reminders": profile([7, 2, 0], "financial"), "startedFrom": profile([2, 0], "financial")]),
        ActionCase(name: "the follow-up switched off", start: rent, action: ["do": "setFollowUpAfterLapse", "isOn": false]),
        ActionCase(name: "a reminder time of its own", start: rent, action: ["do": "setReminderTime", "minuteOfDay": .int(2_000), "startedFrom": .null]),
        ActionCase(name: "a reminder time left as it was keeps one set meanwhile", start: rent,
                   before: [["do": "setReminderTime", "minuteOfDay": .int(480), "startedFrom": .null]],
                   action: ["do": "setReminderTime", "minuteOfDay": .null, "startedFrom": .null]),
        ActionCase(name: "a deadline of one's own renamed", start: rent, action: ["do": "rename", "title": "  Chirie garsonieră  "]),
        ActionCase(name: "a blank name", start: rent, action: ["do": "rename", "title": "   "]),
        ActionCase(name: "a category's deadline keeps its name", section: car, start: .blueprint(BuiltInBlueprints.vehicleITP, firstDue: "2026-12-01"),
                   action: ["do": "rename", "title": "Inspecție"]),
        ActionCase(name: "a name left as it was keeps one set meanwhile", start: rent, before: [["do": "rename", "title": "Chiria lunii"]],
                   action: ["do": "rename", "title": "Chirie", "startedFrom": "Chirie"]),
        ActionCase(name: "importance moves the usual reminders", start: ownLegal, action: ["do": "setImportance", "importance": "money"]),
        ActionCase(name: "importance keeps reminders of one's own", start: .own(title: "Analize", kind: .legal, due: "2027-01-15", recurrence: oneOffRule,
                                                                                reminders: profile([45], "legal")),
                   action: ["do": "setImportance", "importance": "health"]),
        ActionCase(name: "a category's deadline keeps its importance", section: car, start: .blueprint(BuiltInBlueprints.vehicleITP, firstDue: "2026-12-01"),
                   action: ["do": "setImportance", "importance": "money"]),
        ActionCase(name: "details", start: rent, action: ["do": "setDetails", "estimatedCost": .object(["amount": "1500", "currency": "RON"]), "reference": "CTR-0001"]),
        ActionCase(name: "an edit of every part", start: ownLegal,
                   action: ["do": "edit", "title": "Analize anuale", "importance": "health", "dueDay": "2027-02-01",
                            "recurrence": RecurrenceVectorsTests.interval(6, "month"), "leadDays": .array([.int(14), .int(0)]), "reminderMinuteOfDay": .int(540)]),
        ActionCase(name: "an edit that changes nothing", start: ownLegal, action: ["do": "edit"]),
        ActionCase(name: "an edit of a category's deadline's name", section: car, start: .blueprint(BuiltInBlueprints.vehicleITP, firstDue: "2026-12-01"),
                   action: ["do": "edit", "title": "Inspecție"]),
        ActionCase(name: "an edit of a category's deadline's day", section: car, start: .blueprint(BuiltInBlueprints.vehicleITP, firstDue: "2026-12-01"),
                   action: ["do": "edit", "dueDay": "2027-01-10"]),
    ]

    static func sectionJSON(_ section: Section?) throws -> JSONValue {
        guard let section else { return .null }
        return .object([
            "category": .string(section.category), "name": .string(section.name), "values": try encoded(values(section.values)),
            "readings": .array(section.readings.map { .object(["at": .string($0.0), "value": .number($0.1)]) }),
        ])
    }

    static func startJSON(_ start: Start) -> JSONValue {
        switch start {
        case .blueprint(let key, let firstDue):
            return .object(["blueprint": .string(key), "firstDue": .string(firstDue)])
        case .own(let title, let kind, let due, let recurrence, let reminders):
            return .object(["title": .string(title), "kind": .string(kind.rawValue), "dueDay": .string(due), "recurrence": recurrence, "reminders": reminders ?? .null])
        }
    }

    static func actions() throws -> Vectors {
        var cases: [JSONValue] = []
        for item in actionCases {
            let context = try makeContext()
            let obligation = try make(item, in: context)
            for step in item.before { _ = try run(step, on: obligation, in: context) }
            let before = try state(of: obligation.id, in: context)
            let historyBefore = try history(in: context)
            var refused: String?
            var receipt: UndoReceipt?
            do {
                receipt = try run(item.action, on: obligation, in: context)
            } catch {
                refused = refusal(error)
            }
            let after = try state(of: obligation.id, in: context)
            let historyAfter = try history(in: context)
            let readingsAfter = try readings(in: context)
            var undone: JSONValue = .null
            // A step that changed nothing gives a receipt with nothing to take back.
            if let receipt, receipt.canUndo {
                try receipt.undo()
                let back = try state(of: obligation.id, in: context)
                let historyBack = try history(in: context)
                undone = .bool(back == before && historyBack == historyBefore)
            }
            cases.append(.object([
                "name": .string(item.name), "section": try sectionJSON(item.section), "start": startJSON(item.start),
                "before": .array(item.before.map { .object($0) }), "action": .object(item.action), "now": seconds(now),
                "refused": text(refused), "deadline": after, "history": historyAfter, "readings": readingsAfter,
                "receipt": .bool(receipt != nil), "canUndo": .bool(receipt?.canUndo ?? false), "undoRestores": undone,
            ]))
        }
        return Vectors(
            name: "actions",
            rule: "ObligationActions: complete (the cycle seen, a new day, closing a replaced document, the counter read), snooze, clearSnooze, reschedule, pause, resume, archive, delete, setRecurrence, setReminders, setFollowUpAfterLapse, restoreUsualReminders, setReminderTime, rename, setImportance, setDetails, edit; create(from:for:firstDue:) and create(title:kind:dueDay:for:recurrence:reminders:)",
            source: "ios/DosarCuSina/Services/Obligations/ObligationActions.swift, DeadlineEdit.swift, ios/DosarCuSina/Views/Add/DeadlineChoice.swift",
            shape: "section: the section the deadline is in (its category, name, values, and kilometre readings at UTC moments), or null for the household. start: the deadline made from a blueprint with its first due day, or one of the person's own (title, kind, due day, rule, reminders or null for its kind's). before: actions taken first. action: the action ('do' and its parts; 'on' a moment in seconds; days ISO; rules, profiles and money in the archive's form; 'edit' changes the parts it names over the deadline as it is). now: every action's clock (seconds), days counted in Bucharest. refused: the kind of refusal, or null. deadline: the deadline as stored after it, or null once deleted. history: every record of history after it, by the cycle closed, then when. readings: the section's readings after it. receipt: whether the action gives an undo receipt; canUndo: whether it has anything to take back (a step that changed nothing has not). undoRestores: for one that has, whether undo gives back the deadline and the history as they were before it; null otherwise.",
            cases: cases
        )
    }

    // MARK: Reminders that follow a section

    static func remindersFollowing() throws -> Vectors {
        let inputs: [(String, String, String, Bool, [Int]?)] = [
            ("a passport turned into an identity card", DocumentType.passport, DocumentType.idCard, false, nil),
            ("an identity card turned into a passport", DocumentType.idCard, DocumentType.passport, false, nil),
            ("a passport whose reminders the person set keeps them, without the cut-off", DocumentType.passport, DocumentType.idCard, true, [200]),
            ("an identity card whose reminders the person set gets the cut-off", DocumentType.idCard, DocumentType.passport, true, [200]),
            ("a value the profile doesn't read changes nothing", DocumentType.passport, DocumentType.passport, false, nil),
        ]
        var cases: [JSONValue] = []
        for (name, from, to, customized, leads) in inputs {
            let context = try makeContext()
            let documents = try #require(try TemplateStore(context: context).template(forKey: BuiltInTemplates.Key.documents))
            let start: [(String, FieldValue)] = [(DocumentType.typeFieldKey, .text(from)), (DocumentFields.expiry, .date(day("2027-08-12")))]
            let asset = Asset(name: "Act", templateKey: documents.key, values: values(start))
            context.insert(asset)
            try UnitOfWork.save(context)
            let blueprint = try #require(documents.definition.blueprints.first { $0.key == BuiltInBlueprints.documentRenew })
            let clock = now
            let actions = ObligationActions(context: context, calendar: calendar, now: { clock })
            let obligation = try actions.create(from: blueprint, for: asset, firstDue: day("2027-08-12"))
            if let leads, customized {
                try actions.setReminders(obligation, obligation.reminders.withLeadDays(leads))
            }
            let previous = asset.values
            var changed = previous
            changed[DocumentType.typeFieldKey] = .text(to)
            if to == from { changed["document.issuer"] = .text("SPCLEP Exemplu") }
            asset.values = changed
            let followed = DeadlineReminders.follow(asset, template: documents.definition, from: previous)
            try UnitOfWork.save(context)
            cases.append(.object([
                "name": .string(name), "from": try encoded(values(start)), "to": try encoded(changed),
                "setByThePerson": leads.map { .array($0.map(JSONValue.int)) } ?? .null,
                "changed": .int(followed.count), "reminders": try encoded(obligation.reminders),
                "remindersCustomized": .bool(obligation.remindersCustomized),
            ]))
        }
        return Vectors(
            name: "reminders-follow",
            rule: "DeadlineReminders.follow(_:template:from:) and expected(for:blueprint:values:), over a personal document's renewal",
            source: "ios/DosarCuSina/Services/Obligations/DeadlineReminders.swift",
            shape: "from and to: a personal document's values before and after a change. setByThePerson: the leads the person set on its renewal deadline first (setReminders), or null. changed: how many deadlines took another profile. reminders: the renewal's reminders after, in the archive's form; remindersCustomized: whether they are the person's own.",
            cases: cases
        )
    }
}
