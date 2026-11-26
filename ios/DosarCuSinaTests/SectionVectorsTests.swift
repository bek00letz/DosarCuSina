import Foundation
import SwiftData
import Testing
@testable import DosarCuSina

/// What a person does to a section, and the firms in the binder, run over cases chosen to bite and
/// written to `shared/test-vectors/sections/`, one file per rule, each input with the answer this
/// app gives: which deadlines a new section starts with ticked (`PlannedObligation.startsSelected`,
/// over `AssetActions.plannedObligations`, with the values as saving keeps them,
/// `FieldValues.applyingRules`), making a section with its deadlines (`AssetActions.create`), where
/// a section can move and moving it (`AssetActions+Move.swift`), where a new section goes when
/// nobody said (`automaticParent`), a document's name (`DocumentNaming`, `DocumentType`) and a firm
/// found by its CUI or its name (`ProviderActions.findOrCreate`, `ProviderTaxID`). The Android app's
/// tests run the same cases through its own store (android/store, `store.sections`,
/// `store.providers`) and its catalog (android/catalog) and must give the same answers
/// (docs/ANDROID_PLAN.md, "How parity is kept"). A sibling of `ReadingVectorsTests`.
///
/// Nothing depends on the machine: the calendar is the app's in Bucharest (`Calendar.dosar(in:)`)
/// and today is fixed, so `TEST_RUNNER_TZ=UTC` writes the same files. Placeholder data only.
@MainActor
@Suite("Section vectors")
struct SectionVectorsTests {
    static var folder: URL {
        URL(filePath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appending(path: "shared/test-vectors/sections")
    }

    /// How to bring the files up to date, said when one isn't.
    static let regenerate = """
    is out of date with the section rules. Bring shared/test-vectors/sections up to date: a failed \
    run on GitHub keeps them made afresh in its test-results artifact, test-vectors/sections/ (copy \
    them over), or TEST_RUNNER_SECTION_VECTORS_WRITE=1 ./tests/run_tests.sh (or run \
    SectionVectorsTests in Xcode with SECTION_VECTORS_WRITE=1 in the scheme's environment); review \
    the diff and commit it, then run the Android tests (./gradlew :catalog:test :store:test in \
    android/), which read the same files.
    """

    typealias Vectors = ValueVectorsTests.Vectors

    /// The day every case is run on.
    static let today = "2026-11-26"

    /// The app's calendar in Bucharest, whatever the machine's time zone.
    static var calendar: Calendar { Calendar.dosar(in: TimeZone(identifier: "Europe/Bucharest") ?? .gmt) }

    static func now() -> Date { noon(today) }

    @Test("shared/test-vectors/sections is up to date with the section rules")
    func vectorsAreUpToDate() throws {
        let files = try Self.all()
        let environment = ProcessInfo.processInfo.environment
        let writes = environment["SECTION_VECTORS_WRITE"] == "1"
        let manager = FileManager.default
        if writes { try manager.createDirectory(at: Self.folder, withIntermediateDirectories: true) }
        var fresh: [String: String] = [:]
        var outOfDate: [String] = []
        for file in files {
            let name = "\(file.name).json"
            let text = try ValueVectorsTests.render(file)
                .replacingOccurrences(of: "ios/DosarCuSinaTests/ValueVectorsTests.swift", with: "ios/DosarCuSinaTests/SectionVectorsTests.swift")
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
            let folder = URL(filePath: out, directoryHint: .isDirectory).appending(path: "sections")
            try manager.createDirectory(at: folder, withIntermediateDirectories: true)
            for (name, text) in fresh { try text.write(to: folder.appending(path: name), atomically: true, encoding: .utf8) }
        }
        for name in outOfDate.sorted() {
            Issue.record(Comment(rawValue: "\(name) " + Self.regenerate))
        }
    }

    static func all() throws -> [Vectors] {
        try [planned(), creating(), moving(), automaticParent(), documentNames(), firms()]
    }

    // MARK: Helpers

    static func makeActions(_ context: ModelContext) -> AssetActions {
        AssetActions(context: context, calendar: calendar, now: { now() }, sealer: .ephemeral())
    }

    static func category(_ key: String, in context: ModelContext) throws -> CategoryTemplate {
        try #require(try TemplateStore(context: context).template(forKey: key))
    }

    /// Values as machine JSON, the way a backup writes them.
    static func json(_ values: FieldValues) throws -> JSONValue {
        try ValueVectorsTests.json(ValueVectorsTests.compact(values))
    }

    static func json<Value: Encodable>(encoding value: Value) throws -> JSONValue {
        try ValueVectorsTests.json(ValueVectorsTests.compact(value))
    }

    static func day(_ iso: String) -> FieldValue { .date(ValueVectorsTests.day(iso)) }

    static func typed(_ pairs: [String: FieldValue]) -> FieldValues { FieldValues(pairs) }

    // MARK: Which deadlines start ticked

    /// Each built-in with nothing typed, and with every date field on one day; then values chosen
    /// to bite: a value worked out from others, a label kept from an earlier version, a day passed.
    static func plannedInputs() -> [(String, String, FieldValues)] {
        var inputs: [(String, String, FieldValues)] = []
        for definition in BuiltInTemplates.all {
            inputs.append(("\(definition.key), nothing typed", definition.key, FieldValues()))
            var dated = FieldValues()
            for field in definition.allFields where field.type == .date || field.type == .expiryDate {
                dated[field.key] = day("2027-03-15")
            }
            inputs.append(("\(definition.key), every date field on 2027-03-15", definition.key, dated))
        }
        inputs += [
            ("a purchase's warranty from its day and months", BuiltInTemplates.Key.purchase,
             typed(["purchase.date": day("2026-11-01"), "purchase.warrantyMonths": .number(24)])),
            ("a purchase's warranty from its day and the usual months", BuiltInTemplates.Key.purchase,
             typed(["purchase.date": day("2026-08-31")])),
            ("a cazier judiciar valid six months from its issue", BuiltInTemplates.Key.documents,
             typed([DocumentType.typeFieldKey: .text(DocumentType.criminalRecord),
                     DocumentType.variantFieldKey: .text(DocumentType.Variant.criminalRecordJudicial),
                     "document.issueDate": day("2026-08-31")])),
            ("a cazier fiscal has no validity of its own", BuiltInTemplates.Key.documents,
             typed([DocumentType.typeFieldKey: .text(DocumentType.criminalRecord),
                     DocumentType.variantFieldKey: .text(DocumentType.Variant.criminalRecordFiscal),
                     "document.issueDate": day("2026-08-31")])),
            ("a passport stored by its label", BuiltInTemplates.Key.documents,
             typed([DocumentType.typeFieldKey: .text("Pasaport"), "document.expiry": day("2031-05-10")])),
            ("a variant left behind when the type changed", BuiltInTemplates.Key.documents,
             typed([DocumentType.typeFieldKey: .text(DocumentType.passport),
                     DocumentType.variantFieldKey: .text(DocumentType.Variant.idCardElectronic)])),
            ("an identity card already expired", BuiltInTemplates.Key.documents,
             typed([DocumentType.typeFieldKey: .text(DocumentType.idCard), "document.expiry": day("2026-01-10")])),
            ("a yearly subscription renews on its day", BuiltInTemplates.Key.subscription,
             typed(["subscription.cycle": .text("billing.yearly"), "subscription.renewalDate": day("2027-02-01")])),
            ("a monthly subscription has no renewal", BuiltInTemplates.Key.subscription,
             typed(["subscription.renewalDate": day("2027-02-01")])),
            ("a gas subscription's group and its minimum period", BuiltInTemplates.Key.subscription,
             typed(["subscription.service": .text("service.gas"), "subscription.startDate": day("2026-01-31"),
                     "subscription.minimumMonths": .number(13)])),
            ("a tenancy that ends", BuiltInTemplates.Key.tenancy,
             typed(["tenancy.start": day("2026-01-01"), "tenancy.end": day("2027-12-31")])),
        ]
        return inputs
    }

    static func planned() throws -> Vectors {
        let context = try makeContext()
        var cases: [JSONValue] = []
        for (name, key, values) in plannedInputs() {
            let template = try category(key, in: context)
            let planned = makeActions(context).plannedObligations(for: template, values: values)
            let kept = values.normalizingChoices(for: template.definition)
                .applyingRules(of: template.definition, previous: nil, calendar: calendar)
            cases.append(.object([
                "name": .string(name),
                "category": .string(key),
                "values": try json(values),
                "kept": try json(kept),
                "planned": .array(planned.map { plan in
                    .object([
                        "key": .string(plan.blueprint.key),
                        "firstDue": ValueVectorsTests.iso(plan.firstDue),
                        "isSelected": .bool(plan.isSelected),
                        "asksFirstDate": .bool(plan.asksFirstDate),
                        "startsSelected": .bool(PlannedObligation.startsSelected(plan.blueprint, firstDue: plan.firstDue)),
                    ])
                }),
            ]))
        }
        return Vectors(
            name: "starts-selected",
            rule: "AssetActions.plannedObligations(for:values:) and PlannedObligation.startsSelected(_:firstDue:), over FieldValues.applyingRules(of:previous:calendar:)",
            source: "ios/DosarCuSina/Services/Obligations/AssetActions.swift, ios/DosarCuSina/Models/Fields/FieldValue.swift, ios/DosarCuSina/Models/Fields/FieldDefinition.swift",
            shape: "today is 2026-11-26 in Bucharest. category: a built-in's key; values: what the form holds, as a backup writes them. kept: the values as saving a new section keeps them (defaults, values that no longer belong taken out, derived values worked out), with choices as keys. planned: each deadline that applies, in the category's order: its blueprint's key, its first day (null when it is to be asked), whether it starts ticked and whether its day had to be asked, and the rule's own answer (startsSelected).",
            cases: cases
        )
    }

    // MARK: Making a section

    /// A plan as a case writes it: each blueprint's key, ticked or not, and its day.
    struct Plan {
        let key: String
        let isSelected: Bool
        let firstDue: String?

        var json: JSONValue {
            .object(["key": .string(key), "isSelected": .bool(isSelected), "firstDue": firstDue.map { .string($0) } ?? .null])
        }
    }

    /// A section to make: its name, category, values, its parent's name among those made before, and
    /// the plan it is made with (none: the usual plan, as the add flow offers it).
    struct Making {
        let name: String
        let category: String
        let values: FieldValues
        var parent: String?
        var plan: [Plan]?
    }

    static let creatingInputs: [(String, [Making])] = [
        ("a car with its odometer: the deadlines it starts with, and its first reading", [
            Making(name: "VW Golf 2018", category: BuiltInTemplates.Key.vehicle,
                   values: typed([VehicleFields.plate: .text("B-123-ABC"), VehicleFields.odometer: .number(145_000)])),
        ]),
        ("a car with its ITP ticked and dated by the person", [
            Making(name: "VW Golf 2018", category: BuiltInTemplates.Key.vehicle,
                   values: typed([VehicleFields.odometer: .number(145_000)]),
                   plan: [Plan(key: "vehicle.itp", isSelected: true, firstDue: "2027-01-20"),
                          Plan(key: "vehicle.service", isSelected: true, firstDue: nil),
                          Plan(key: "vehicle.tyres", isSelected: false, firstDue: nil)]),
        ]),
        ("a passport under its holder: its renewal by its expiry, reminding before the travel cut-off", [
            Making(name: "Manole Corina", category: BuiltInTemplates.Key.member, values: FieldValues()),
            Making(name: "Pașaport – Manole Corina", category: BuiltInTemplates.Key.documents,
                   values: typed([DocumentType.typeFieldKey: .text(DocumentType.passport), "document.expiry": day("2031-05-10")]),
                   parent: "Manole Corina"),
        ]),
        ("a tenancy brings the household's rental income declaration", [
            Making(name: "Apartament Exemplu", category: BuiltInTemplates.Key.home, values: FieldValues()),
            Making(name: "Chiriaș etaj 2", category: BuiltInTemplates.Key.tenancy,
                   values: typed(["tenancy.start": day("2026-01-01"), "tenancy.end": day("2027-12-31")]),
                   parent: "Apartament Exemplu"),
        ]),
        ("a dog's weight is its first reading", [
            Making(name: "Rex", category: BuiltInTemplates.Key.pet,
                   values: typed(["pet.species": .text("species.dog"), "pet.weight": .number(18.5)])),
        ]),
        ("a purchase's warranty is worked out and remembered", [
            Making(name: "Mașină de spălat", category: BuiltInTemplates.Key.purchase,
                   values: typed(["purchase.date": day("2026-11-01")])),
        ]),
    ]

    static func creating() throws -> Vectors {
        var cases: [JSONValue] = []
        for (name, sections) in creatingInputs {
            let context = try makeContext()
            let actions = makeActions(context)
            var made: [String: Asset] = [:]
            for section in sections {
                let template = try category(section.category, in: context)
                var plan = actions.plannedObligations(for: template, values: section.values)
                if let chosen = section.plan {
                    plan = plan.map { planned in
                        guard let choice = chosen.first(where: { $0.key == planned.blueprint.key }) else { return planned }
                        var changed = planned
                        changed.isSelected = choice.isSelected
                        if let firstDue = choice.firstDue { changed.firstDue = ValueVectorsTests.day(firstDue) }
                        return changed
                    }
                }
                made[section.name] = try actions.create(name: section.name, template: template, values: section.values,
                                                        obligations: plan, parent: section.parent.flatMap { made[$0] })
            }
            let household = try context.fetch(FetchDescriptor<Obligation>()).filter { $0.asset == nil }
            cases.append(.object([
                "name": .string(name),
                "sections": .array(sections.map { section in
                    .object([
                        "name": .string(section.name), "category": .string(section.category),
                        "values": (try? json(section.values)) ?? .null, "parent": section.parent.map { .string($0) } ?? .null,
                        "plan": section.plan.map { .array($0.map(\.json)) } ?? .null,
                    ])
                }),
                "made": .array(try sections.map { section throws -> JSONValue in
                    let asset = try #require(made[section.name])
                    return .object([
                        "name": .string(asset.name),
                        "values": try json(asset.values),
                        "parent": asset.parent.map { .string($0.name) } ?? .null,
                        "obligations": .array(try (asset.obligations ?? []).sorted { ($0.blueprintKey ?? "") < ($1.blueprintKey ?? "") }
                            .map { try Self.obligation($0) }),
                        "readings": .array((asset.measurements ?? []).sorted { $0.value < $1.value }.map { log in
                            .object(["value": .number(log.value), "unit": .string(log.unit), "kind": .string(log.kind.rawValue)])
                        }),
                    ])
                }),
                "household": .array(try household.sorted { ($0.blueprintKey ?? "") < ($1.blueprintKey ?? "") }.map { try Self.obligation($0) }),
            ]))
        }
        return Vectors(
            name: "create",
            rule: "AssetActions.create(name:template:values:notes:obligations:parent:newParent:isExample:), with HouseholdMutations.makeObligation and HouseholdRules.reconcile",
            source: "ios/DosarCuSina/Services/Obligations/AssetActions.swift, ios/DosarCuSina/Services/Templates/HouseholdRules.swift",
            shape: "today is 2026-11-26 in Bucharest. sections: made in order, each its name, category, values, the name of its parent among those made before (null for none) and the plan it is made with (null: the usual plan; else each blueprint's key, ticked or not, and the day the person gave, null to keep the planned one). made: each section as saved: its values, its parent's name, its deadlines by blueprint key (title, kind, due day, the counter it is due at, its reminders, note, how it repeats as stored, estimated cost) and its readings. household: the deadlines that belong to no section, after the last one was made.",
            cases: cases
        )
    }

    static func obligation(_ obligation: Obligation) throws -> JSONValue {
        let reminders = obligation.reminders
        return .object([
            "blueprintKey": obligation.blueprintKey.map { .string($0) } ?? .null,
            "title": .string(obligation.title),
            "kind": .string(obligation.kind.rawValue),
            "dueDay": .string(obligation.dueDay.isoString),
            "dueMetric": obligation.dueMetric.map { .number($0) } ?? .null,
            "leadDays": .array(reminders.leadDays.map { .int($0) }),
            "consequence": .string(reminders.consequence.rawValue),
            "graceDays": .int(reminders.graceDays),
            "followUpAfterLapse": .bool(reminders.followUpAfterLapse),
            "travelMarginDays": .int(reminders.travelMarginDays),
            "notes": obligation.notes.map { .string($0) } ?? .null,
            "recurrence": try json(encoding: obligation.recurrence),
            "estimatedCost": try obligation.estimatedCost.map { try json(encoding: $0) } ?? .null,
            "isExample": .bool(obligation.isExample),
        ])
    }

    // MARK: Moving

    static func moving() throws -> Vectors {
        func household() throws -> (ModelContext, AssetActions, [String: Asset]) {
            let context = try makeContext()
            let actions = makeActions(context)
            var made: [String: Asset] = [:]
            func add(_ name: String, _ key: String, _ values: FieldValues = FieldValues(), under parent: String? = nil, example: Bool = false) throws {
                made[name] = try actions.create(name: name, template: try category(key, in: context), values: values,
                                                parent: parent.flatMap { made[$0] }, isExample: example)
            }
            try add("Manole Corina", BuiltInTemplates.Key.member)
            try add("Popescu Ion", BuiltInTemplates.Key.member)
            try add("Exemplu Persoană", BuiltInTemplates.Key.member, example: true)
            try add("Carte de identitate – Manole Corina", BuiltInTemplates.Key.documents,
                    typed([DocumentType.typeFieldKey: .text(DocumentType.idCard)]), under: "Manole Corina")
            try add("Buletinul vechi", BuiltInTemplates.Key.documents,
                    typed([DocumentType.typeFieldKey: .text(DocumentType.idCard)]))
            try add("Apartament", BuiltInTemplates.Key.home)
            try add("Casa de la țară", BuiltInTemplates.Key.home)
            try add("Chiriaș etaj 2", BuiltInTemplates.Key.tenancy, under: "Apartament")
            try add("Gaz", BuiltInTemplates.Key.subscription, typed(["subscription.service": .text("service.gas")]), under: "Apartament")
            try add("Ferigă", BuiltInTemplates.Key.plants)
            try add("VW Golf 2018", BuiltInTemplates.Key.vehicle)
            return (context, actions, made)
        }
        var cases: [JSONValue] = []
        let (context, _, _) = try household()
        let all = try context.fetch(FetchDescriptor<Asset>())
        for asset in all.sorted(by: { $0.name < $1.name }) {
            cases.append(.object([
                "section": .string(asset.name),
                "parentKeys": .array(AssetActions.parentKeys(for: asset).sorted().map { .string($0) }),
                "canMove": .bool(AssetActions.canMove(asset)),
                "offersNewMember": .bool(AssetActions.offersNewMember(for: asset)),
                "offersStandalone": .bool(AssetActions.offersStandalone(for: asset)),
                "destinations": .array(AssetActions.moveDestinations(for: asset, among: all).map { .string($0.name) }),
                "renamedFor": .object(["Popescu Ion": AssetActions.renamedForHolder(asset, newHolder: "Popescu Ion").map { .string($0) } ?? .null]),
            ]))
        }
        // Moves, each from the household as it was made.
        let moves: [(String, String, String?, String?, String?)] = [
            // (what moves, to which section, to a new person, renamed to, the case's name)
            ("Carte de identitate – Manole Corina", "Popescu Ion", nil, "Carte de identitate – Popescu Ion", "a document to another person, renamed"),
            ("Carte de identitate – Manole Corina", "", "Manole Ana", "Carte de identitate – Manole Ana", "a document to a new person"),
            ("Chiriaș etaj 2", "Casa de la țară", nil, nil, "a tenancy to the other home, its name kept"),
            ("Gaz", "", nil, nil, "a subscription out of its home"),
            ("Ferigă", "Apartament", nil, nil, "a plant into a home"),
        ]
        for (moved, to, member, renamed, name) in moves {
            let (context, actions, made) = try household()
            let child = try #require(made[moved])
            let target: AssetActions.MoveTarget
            if let member {
                target = .newMember(name: member)
            } else if let destination = made[to] {
                target = .asset(destination.id)
            } else {
                target = .standalone
            }
            try actions.move(child, to: target, renamingTo: renamed)
            let people = try context.fetch(FetchDescriptor<Asset>()).filter { $0.templateKey == BuiltInTemplates.Key.member }
            cases.append(.object([
                "move": .string(name),
                "section": .string(moved),
                "to": member == nil ? (to.isEmpty ? .null : .string(to)) : .null,
                "newMember": member.map { .string($0) } ?? .null,
                "renamingTo": renamed.map { .string($0) } ?? .null,
                "name": .string(child.name),
                "parent": child.parent.map { .string($0.name) } ?? .null,
                "parentCategory": child.parent.map { .string($0.templateKey) } ?? .null,
                "people": .array(people.map(\.name).sorted().map { .string($0) }),
            ]))
        }
        return Vectors(
            name: "move",
            rule: "AssetActions.parentKeys(for:), canMove, offersNewMember, offersStandalone, moveDestinations(for:among:), renamedForHolder(_:newHolder:) and move(_:to:renamingTo:)",
            source: "ios/DosarCuSina/Services/Obligations/AssetActions+Move.swift, ios/DosarCuSina/Services/Documents/DocumentNaming.swift",
            shape: "One household, each section made in this order: Manole Corina, Popescu Ion, Exemplu Persoană (an example) (people); Carte de identitate – Manole Corina (an identity card under Manole Corina) and Buletinul vechi (one under no one); Apartament and Casa de la țară (homes); Chiriaș etaj 2 (a tenancy under Apartament); Gaz (a gas subscription under Apartament); Ferigă (a plant on its own); VW Golf 2018 (a car). section: each, by name, with the categories it can be filed under, whether it can move, whether a new person and standing on its own are offered, the sections it can move to in order, and the name it would take under Popescu Ion (null: it isn't named after its holder). move: one move from the household as made: the section, the section it goes to (to; null for none), or a new person (newMember), the name it takes (renamingTo), then its name, its parent and its parent's category after, and the people in the binder.",
            cases: cases
        )
    }

    // MARK: Where a new section goes

    static func automaticParent() throws -> Vectors {
        let inputs: [(String, [(String, Bool)])] = [
            ("no home", []),
            ("one home", [("Apartament Exemplu", false)]),
            ("two homes", [("Apartament Exemplu", false), ("Casa de la țară", false)]),
            ("one home and an example home", [("Apartament Exemplu", false), ("Casă exemplu", true)]),
            ("only an example home", [("Casă exemplu", true)]),
        ]
        var cases: [JSONValue] = []
        for (name, homes) in inputs {
            let context = try makeContext()
            let actions = makeActions(context)
            let home = try category(BuiltInTemplates.Key.home, in: context)
            for (homeName, example) in homes {
                _ = try actions.create(name: homeName, template: home, values: FieldValues(), isExample: example)
            }
            var answers: [String: JSONValue] = [:]
            for key in [BuiltInTemplates.Key.plants, BuiltInTemplates.Key.subscription, BuiltInTemplates.Key.tenancy, BuiltInTemplates.Key.vehicle] {
                let behavior = try category(key, in: context).behavior
                var answer: [String: JSONValue] = [:]
                for example in [false, true] {
                    let side = example ? "example" : "real"
                    answer[side] = .object([
                        "possibleParents": .array(AssetActions.possibleParents(for: behavior, isExample: example, in: context).map { .string($0.name) }),
                        "automaticParent": AssetActions.automaticParent(for: behavior, isExample: example, in: context).map { .string($0.name) } ?? .null,
                    ])
                }
                answers[key] = .object(answer)
            }
            cases.append(.object([
                "name": .string(name),
                "homes": .array(homes.map { .object(["name": .string($0.0), "isExample": .bool($0.1)]) }),
                "categories": .object(answers),
            ]))
        }
        return Vectors(
            name: "automatic-parent",
            rule: "AssetActions.possibleParents(for:isExample:in:) and automaticParent(for:isExample:in:), by CategoryBehavior.mayBelongTo and goesUnderTheOnlyOne",
            source: "ios/DosarCuSina/Services/Obligations/AssetActions+Move.swift",
            shape: "homes: the homes made, in order, each an example or not. categories: for a plant, a subscription, a tenancy and a car (by key), for a real new section and an example one, the sections it can stand in, by name, and where it goes when nobody said (null: on its own).",
            cases: cases
        )
    }

    // MARK: A document's name

    static func documentNames() throws -> Vectors {
        var cases: [JSONValue] = []
        for option in DocumentType.options {
            cases.append(.object(["type": .string(option.key), "variant": .null,
                                  "documentName": .string(DocumentType.documentName(type: option.key, variant: nil)),
                                  "keepsBackSide": .bool(DocumentType.keepsBackSide(option.key)),
                                  "travelMarginDays": .int(DocumentType.travelMarginDays(for: option.key)),
                                  "validityMonths": DocumentType.validityMonths(type: option.key, variant: nil).map { .int($0) } ?? .null,
                                  "isDatedByIssue": .bool(DocumentType.isDatedByIssue(option.key))]))
            for variant in DocumentType.variants(of: option.key) {
                cases.append(.object(["type": .string(option.key), "variant": .string(variant.key),
                                      "documentName": .string(DocumentType.documentName(type: option.key, variant: variant.key)),
                                      "validityMonths": DocumentType.validityMonths(type: option.key, variant: variant.key).map { .int($0) } ?? .null]))
            }
        }
        for type in ["Pasaport", "buletin", "CEASS", "documentType.somethingNewer", ""] {
            cases.append(.object(["typeText": .string(type),
                                  "keepsBackSide": .bool(DocumentType.keepsBackSide(type)),
                                  "travelMarginDays": .int(DocumentType.travelMarginDays(for: type))]))
        }
        let typed: [[String: FieldValue]] = [
            [DocumentType.typeFieldKey: .text("Pasaport")],
            [DocumentType.typeFieldKey: .text(DocumentType.criminalRecord), DocumentType.variantFieldKey: .text("Fiscal")],
            [DocumentType.typeFieldKey: .text(DocumentType.bankCard), DocumentType.variantFieldKey: .text(DocumentType.Variant.bankCardCredit)],
            [DocumentType.typeFieldKey: .text("documentType.somethingNewer")],
            [:],
        ]
        for values in typed {
            cases.append(.object(["values": try json(FieldValues(values)),
                                  "nameFromValues": AssetActions.documentName(FieldValues(values)).map { .string($0) } ?? .null]))
        }
        cases.append(.object(["validUntil": .object([
            "issued": "2026-08-31", "type": .string(DocumentType.criminalRecord), "variant": .string(DocumentType.Variant.criminalRecordJudicial),
            "until": ValueVectorsTests.iso(DocumentType.validUntil(issued: ValueVectorsTests.day("2026-08-31"), type: DocumentType.criminalRecord,
                                                                    variant: DocumentType.Variant.criminalRecordJudicial, calendar: calendar)),
        ])]))
        let names: [(String, String?)] = [("Cazier judiciar", "Manole Corina"), ("  Pașaport ", "  "), ("Carte de identitate", nil), ("Permis", " Popescu Ion ")]
        for (document, holder) in names {
            cases.append(.object(["nameOf": .object(["document": .string(document), "holder": holder.map { .string($0) } ?? .null]),
                                  "name": .string(DocumentNaming.name(document: document, holder: holder))]))
        }
        let renames: [(String, String?, String)] = [
            ("Carte de identitate – Manole Corina", "Manole Corina", "Popescu Ion"),
            ("Pașaport – manole corina", "Manole Corina", "Popescu Ion"),
            ("Pașaport – Popescu Ion", "Popescu Ion", "Popescu Ion"),
            ("Buletinul vechi", "Manole Corina", "Popescu Ion"),
            ("Pașaport – Manole Corina", nil, "Popescu Ion"),
            ("Pașaport – Manole Corina", "Manole Corina", "  "),
            (" – Manole Corina", "Manole Corina", "Popescu Ion"),
            ("Cazier – fiscal – Manole Corina", "Manole Corina", "Popescu Ion"),
        ]
        for (name, from, to) in renames {
            cases.append(.object(["renamed": .object(["name": .string(name), "from": from.map { .string($0) } ?? .null, "to": .string(to)]),
                                  "result": DocumentNaming.renamed(name, from: from, to: to).map { .string($0) } ?? .null]))
        }
        let retypes: [(String, String?, String)] = [
            ("Alt document – Manole Corina", "Alt document", "Pașaport"),
            ("alt document", "Alt document", "Pașaport"),
            ("Buletinul vechi", "Carte de identitate", "Pașaport"),
            ("Pașaport – Manole Corina", "Pașaport", "pasaport"),
            ("Cazier – Manole Corina", nil, "Cazier judiciar"),
            ("Cazier – Manole Corina", "Cazier", " "),
        ]
        for (name, from, to) in retypes {
            cases.append(.object(["retyped": .object(["name": .string(name), "from": from.map { .string($0) } ?? .null, "to": .string(to)]),
                                  "result": DocumentNaming.retyped(name, from: from, to: to).map { .string($0) } ?? .null]))
        }
        return Vectors(
            name: "document-names",
            rule: "DocumentType (documentName, keepsBackSide, travelMarginDays, validityMonths, isDatedByIssue, validUntil), AssetActions.documentName(_:) and DocumentNaming (name, renamed, retyped)",
            source: "ios/DosarCuSina/Models/Fields/ChoiceOptions.swift, ios/DosarCuSina/Services/Documents/DocumentNaming.swift, ios/DosarCuSina/Services/Obligations/AssetActions+Document.swift",
            shape: "type: every type, with no variant (its name, whether it keeps a back, its travel margin, its validity after issue, whether it is dated by its issue) and with each of its variants (the name and validity). typeText: a type as text stored by an earlier version. values: a document's values and the name they give it (null: no type this build knows). validUntil: the last valid day of a cazier judiciar issued on a day. nameOf, renamed, retyped: DocumentNaming's inputs and its answer (null: the name isn't rewritten).",
            cases: cases
        )
    }

    // MARK: Firms

    struct Firm {
        let name: String
        let taxID: String?
    }

    static func firms() throws -> Vectors {
        let inputs: [(String, [Firm], String, String?)] = [
            ("found by its CUI, whatever its name says", [Firm(name: "ENGIE Romania S.A.", taxID: "12345678")], "Furnizor Gaz Exemplu", "RO 12345678"),
            ("found by its name, keeping the CUI it lacked", [Firm(name: "Service Exemplu SRL", taxID: nil)], "  SERVICE exemplu   srl ", "RO12345678"),
            ("a name with another CUI is another firm", [Firm(name: "Service Exemplu SRL", taxID: "87654321")], "Service Exemplu SRL", "12345678"),
            ("the CUI wins over a firm with the same name", [Firm(name: "Firma Exemplu", taxID: nil), Firm(name: "Altă firmă", taxID: "12345678")], "Firma Exemplu", "12345678"),
            ("by name, with no CUI read", [Firm(name: "Firma Exemplu", taxID: "12345678")], "firma exemplu", nil),
            ("a CUI that isn't one is read as none", [Firm(name: "Firma Exemplu", taxID: nil)], "Firma Exemplu", "RO1"),
            ("a new firm, with its CUI", [], "Instal Exemplu SRL", "0012345678"),
            ("nothing in the name finds nothing", [Firm(name: "Firma Exemplu", taxID: nil)], "   ", "12345678"),
        ]
        var cases: [JSONValue] = []
        for (name, existing, wanted, taxID) in inputs {
            let context = try makeContext()
            let providers = ProviderActions(context: context, now: { now() })
            var made: [Provider] = []
            for firm in existing {
                let provider = try providers.create(name: firm.name, trades: [.other])
                provider.taxID = firm.taxID
                made.append(provider)
            }
            try UnitOfWork.save(context, now: now())
            let found = try providers.findOrCreate(name: wanted, taxID: taxID, trade: .mechanic)
            let all = try context.fetch(FetchDescriptor<Provider>())
            let foundIndex: JSONValue
            if let found {
                foundIndex = made.firstIndex(where: { $0.id == found.id }).map { JSONValue.int($0) } ?? .string("new")
            } else {
                foundIndex = .null
            }
            cases.append(.object([
                "name": .string(name),
                "firms": .array(existing.map { .object(["name": .string($0.name), "taxID": $0.taxID.map { .string($0) } ?? .null]) }),
                "find": .object(["name": .string(wanted), "taxID": taxID.map { .string($0) } ?? .null, "trade": "mechanic"]),
                "found": foundIndex,
                "after": .array(all.sorted { $0.createdAt == $1.createdAt ? $0.name < $1.name : $0.createdAt < $1.createdAt }.map { firm in
                    .object(["name": .string(firm.name), "taxID": firm.taxID.map { .string($0) } ?? .null,
                             "trades": .array(firm.trades.map { .string($0) })])
                }),
            ]))
        }
        for text in ["RO12345678", "ro 1234 5678", "0012345678", "12.345.678", "12-345-678", "1", "12345678901", "RO", "ABC", "  98765432  "] {
            cases.append(.object(["taxIDText": .string(text), "normalized": ProviderTaxID.normalized(text).map { .string($0) } ?? .null]))
        }
        return Vectors(
            name: "firms",
            rule: "ProviderActions.findOrCreate(name:taxID:trade:phone:linkedTo:) and ProviderTaxID.normalized(_:)",
            source: "ios/DosarCuSina/Services/History/ProviderDirectory.swift, ios/DosarCuSina/Services/History/ProviderTaxID.swift",
            shape: "firms: the firms in the binder before, in the order they were made, each its name and CUI as stored. find: who issued a document, as capture reads it. found: the index of the firm found among firms, \"new\" for a firm made, null for none. after: every firm then, in the order they were made (a new one last), with its CUI and trades. taxIDText: a CUI as read or typed, and its stored form (null: it isn't one).",
            cases: cases
        )
    }
}
