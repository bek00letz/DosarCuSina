import Foundation
import SwiftData
import Testing
@testable import DosarCuSina

/// Every object the database keeps as JSON keeps what a newer build wrote inside it: a key this
/// build doesn't know, at any depth, and a value it reads as something else (the loudest, the
/// default), written back exactly as stored through an edit of what this build reads, and
/// carried through a backup both ways.
@MainActor
@Suite("Stored objects keep what a newer version wrote")
struct StoredObjectsTests {
    // MARK: Every stored object goes through the wrapper

    /// What the database keeps as data that isn't JSON: pictures and files.
    static let files: Set<String> = ["Asset.photoData", "Attachment.fileData", "Attachment.thumbnailData", "AttachmentPage.imageData"]

    /// A new JSON property fails this until it has its case below, and its case fails until the
    /// property is read and written through `KeptObject` or `KeptList`.
    @Test func everyStoredJSONPropertyIsKept() {
        let stored = Set(Schema(versionedSchema: DosarSchemaV11.self).entities.flatMap { entity in
            entity.attributes.filter { $0.valueType == Data.self || $0.valueType == Data?.self }.map { "\(entity.name).\($0.name)" }
        })
        #expect(stored == Self.files.union(StoredObject.allCases.map(\.property)))
    }

    /// One stored JSON property: what a newer build wrote there, an edit through the model's own
    /// accessor, and what the edit must leave exactly as stored.
    enum StoredObject: String, CaseIterable, CustomTestStringConvertible, Sendable {
        case values, customFacts, sections, blueprints, components, behavior, recurrence, framing

        var testDescription: String { property }

        var property: String {
            switch self {
            case .values: "Asset.valuesData"
            case .customFacts: "Asset.customFactsData"
            case .sections: "CategoryTemplate.sectionsData"
            case .blueprints: "CategoryTemplate.blueprintsData"
            case .components: "CategoryTemplate.componentsData"
            case .behavior: "CategoryTemplate.behaviorData"
            case .recurrence: "Obligation.recurrenceData"
            case .framing: "Attachment.framingData"
            }
        }

        /// As a newer build wrote it: keys this build doesn't know beside known ones, inside
        /// nested objects and list entries, and values it can't read.
        var written: String {
            switch self {
            case .values:
                #"{"car.mooring":{"lat":44.4,"lon":26.1,"type":"location"},"car.plate":{"script":"latin","type":"text","value":"B-123-ABC"},"car.price":{"amount":"350.00","currency":"RON","rate":{"day":"2026-11-10","source":"BNR"},"type":"money"}}"#
            case .customFacts:
                #"[{"colour":"blue","id":"c0ffee00-0000-4000-8000-000000000001","label":"Contract apă","source":{"kind":"scan","page":2},"value":"EXM 0000001"},{"id":"c0ffee00-0000-4000-8000-000000000002","label":"Cheie","value":"Sub preș"}]"#
            case .sections:
                #"[{"collapsed":true,"fields":[{"isEssential":false,"isSensitive":false,"key":"boat.fuel","label":"Combustibil","maxLength":20,"options":[{"hint":{"en":"Petrol","ro":"Benzină"},"icon":"drop","key":"fuel.petrol","label":"Benzină"},{"key":"fuel.diesel","label":"Motorină"}],"role":"newRole","type":"choice"}],"key":"boat.main","title":"Barcă"}]"#
            case .blueprints:
                #"[{"colour":"red","facts":{"agent":"boat.agent","insurer":"boat.insurer"},"firstDue":{"every":1,"type":"afterInterval","unit":"decade"},"isSuggested":true,"key":"boat.check","kind":"ceremonial","recurrence":{"anchor":"completion","every":1,"type":"interval","unit":"year","until":"2030-01-01"},"reminderVariants":{"field":"boat.kind","variants":{"boat.kind.sail":{"channel":"sms","consequence":"legal","followUpAfterLapse":true,"graceDays":0,"leadDays":[60]}}},"reminders":{"consequence":"existential","followUpAfterLapse":true,"graceDays":0,"leadDays":[30,7,0],"quietHours":{"from":22,"to":7}},"title":"Verificare"}]"#
            case .components:
                #"[{"group":"Punte","key":"boat.sail","lifetime":{"months":60},"name":"Velă","synonyms":["vela"]}]"#
            case .behavior:
                #"{"box":"carousel","listing":"plain","shelf":"top","visit":{"checklistTitle":"Ce s-a făcut","icon":"anchor","kind":"mooring","providerTitle":"Portul","title":"Am fost la port","trade":"other"}}"#
            case .recurrence:
                #"{"anchor":"completion","every":1,"skipWeekends":true,"type":"interval","unit":"year","until":{"day":"2030-01-01"}}"#
            case .framing:
                #"{"pages":[{"choice":{"by":"person","quarterTurns":1},"crop":[{"x":0.1,"y":0.1,"z":0.5},{"x":0.9,"y":0.1},{"x":0.9,"y":0.9},{"x":0.1,"y":0.9}],"filter":"mono","prefersWholePhoto":false,"quarterTurns":0}],"source":"scanner","version":1}"#
            }
        }

        /// The parts the edit leaves as stored, byte for byte.
        var kept: [String] {
            switch self {
            case .values: ["car.plate/script", "car.price/rate", "car.mooring"]
            case .customFacts: ["0/colour", "0/source", "1"]
            case .sections: ["0/collapsed", "0/fields/0/maxLength", "0/fields/0/role", "0/fields/0/options/0/icon", "0/fields/0/options/0/hint"]
            case .blueprints:
                ["0/colour", "0/kind", "0/firstDue", "0/reminders/consequence", "0/reminders/quietHours", "0/reminderVariants",
                 "0/facts/agent", "0/recurrence/until"]
            case .components: ["0/lifetime"]
            case .behavior: ["box", "shelf", "visit"]
            case .recurrence: ["until", "skipWeekends"]
            case .framing: ["source", "pages/0/filter", "pages/0/crop", "pages/0/choice/by"]
            }
        }

        /// The edit, as the app makes it, and the part it changed with what it now says.
        func edit(_ records: Records) -> (path: String, now: JSONValue) {
            switch self {
            case .values:
                var values = records.boat.values
                values["car.plate"] = .text("B-456-XYZ")
                records.boat.values = values
                return ("car.plate/value", "B-456-XYZ")
            case .customFacts:
                var facts = records.boat.customFacts
                facts[0].label = "Contract apă rece"
                records.boat.customFacts = facts
                return ("0/label", "Contract apă rece")
            case .sections:
                var sections = records.boats.sections
                sections[0].fields[0].label = "Carburant"
                records.boats.sections = sections
                return ("0/fields/0/label", "Carburant")
            case .blueprints:
                var blueprints = records.boats.blueprints
                blueprints[0].title = "Verificare anuală"
                blueprints[0].reminders = blueprints[0].reminders.withLeadDays([45, 7])
                records.boats.blueprints = blueprints
                return ("0/reminders/leadDays", [.int(45), .int(7)])
            case .components:
                var components = records.boats.components
                components[0].name = "Vela mare"
                records.boats.components = components
                return ("0/name", "Vela mare")
            case .behavior:
                var behavior = records.boats.behavior
                behavior.offerTitle = "Barcă"
                records.boats.behavior = behavior
                return ("offerTitle", "Barcă")
            case .recurrence:
                records.check.recurrence = .interval(.years(2), anchor: .completion)
                return ("every", .int(2))
            case .framing:
                var framing = records.paper.framing
                framing[page: 0] = framing[page: 0].turned()
                records.paper.framing = framing
                return ("pages/0/choice/quarterTurns", .int(2))
            }
        }

        func data(_ records: Records) -> Data? {
            switch self {
            case .values: records.boat.valuesData
            case .customFacts: records.boat.customFactsData
            case .sections: records.boats.sectionsData
            case .blueprints: records.boats.blueprintsData
            case .components: records.boats.componentsData
            case .behavior: records.boats.behaviorData
            case .recurrence: records.check.recurrenceData
            case .framing: records.paper.framingData
            }
        }

        func store(_ data: Data, in records: Records) {
            switch self {
            case .values: records.boat.valuesData = data
            case .customFacts: records.boat.customFactsData = data
            case .sections: records.boats.sectionsData = data
            case .blueprints: records.boats.blueprintsData = data
            case .components: records.boats.componentsData = data
            case .behavior: records.boats.behaviorData = data
            case .recurrence: records.check.recurrenceData = data
            case .framing: records.paper.framingData = data
            }
        }
    }

    /// A category of one's own, a section, a deadline and a document, each holding one stored object.
    struct Records {
        let boats: CategoryTemplate
        let boat: Asset
        let check: Obligation
        let paper: DosarCuSina.Attachment

        init() {
            boats = CategoryTemplate(definition: TemplateDefinition(
                key: "custom.0b6c6f43-0000-4000-8000-00000000b0a7", name: "Bărci", symbol: "sailboat.fill", tint: .teal, sections: []
            ), isBuiltIn: false, homeOrder: 50)
            boat = Asset(name: "Barca de pe lac", templateKey: boats.key)
            check = Obligation(title: "Verificare", kind: .maintenance, dueDay: CalendarDay("2027-05-01"))
            paper = DosarCuSina.Attachment(fileName: "polita.jpg", contentType: "public.jpeg", data: nil, kind: .policy)
        }

        /// Every stored object as a newer build wrote it.
        static func written() -> Records {
            let records = Records()
            for object in StoredObject.allCases { object.store(Data(object.written.utf8), in: records) }
            return records
        }

        func insert(into context: ModelContext) {
            context.insert(boats)
            context.insert(boat)
            context.insert(check)
            context.insert(paper)
            check.asset = boat
            paper.asset = boat
        }
    }

    @Test(arguments: StoredObject.allCases)
    func editingWhatThisBuildReadsKeepsWhatItDoesnt(_ object: StoredObject) throws {
        let records = Records.written()
        let before = try Self.json(object.data(records))
        let (path, now) = object.edit(records)
        let after = try Self.json(object.data(records))

        #expect(Self.part(path, of: after) == now, "The edit is written")
        for kept in object.kept {
            let stored = try #require(Self.part(kept, of: before), "\(kept) is in the fixture")
            #expect(StoredJSON.encode(Self.part(kept, of: after)) == StoredJSON.encode(stored), "\(kept) stays exactly as stored")
        }
    }

    @Test(arguments: StoredObject.allCases)
    func readingAndWritingBackWithoutAnEditChangesNothing(_ object: StoredObject) throws {
        let records = Records.written()
        let before = try Self.json(object.data(records))
        switch object {
        case .values: records.boat.values = records.boat.values
        case .customFacts: records.boat.customFacts = records.boat.customFacts
        case .sections: records.boats.sections = records.boats.sections
        case .blueprints: records.boats.blueprints = records.boats.blueprints
        case .components: records.boats.components = records.boats.components
        case .behavior: records.boats.behavior = records.boats.behavior
        case .recurrence: records.check.recurrence = records.check.recurrence
        case .framing: records.paper.framing = records.paper.framing
        }
        #expect(try Self.json(object.data(records)) == before)
    }

    // MARK: Values this build can't read

    @Test func anUnknownValueInsideAnObjectReadsAsTheLoudestAndStaysAsWritten() throws {
        let records = Records.written()
        let check = try #require(records.boats.blueprints.first)
        #expect(check.kind == .legal, "An unknown kind of deadline reads as the loudest")
        #expect(check.reminders.consequence == .legal, "An unknown consequence reads as the loudest")
        #expect(check.firstDue == .ask, "An interval in a unit this build doesn't know asks for the date")
        #expect(records.boats.behavior.box == .perSection, "An unknown box reads as a box per section, which hides nothing")
        #expect(records.boats.behavior.visitWording.kind == .repair)
        #expect(records.boats.sections.first?.fields.first?.role == nil)

        // Setting what this build reads writes it; a value it read as something else stays only
        // while it isn't set.
        var blueprints = records.boats.blueprints
        blueprints[0].kind = .insurance
        records.boats.blueprints = blueprints
        let written = try Self.json(records.boats.blueprintsData)
        #expect(Self.part("0/kind", of: written) == "insurance")
        #expect(Self.part("0/reminders/consequence", of: written) == "existential")
        var behavior = records.boats.behavior
        behavior.box = .wholeCategory
        records.boats.behavior = behavior
        #expect(Self.part("box", of: try Self.json(records.boats.behaviorData)) == "wholeCategory")
        #expect(Self.part("shelf", of: try Self.json(records.boats.behaviorData)) == "top")
    }

    // MARK: The rule itself

    @Test func aValueThatBecameAnotherKindKeepsNothingOfTheOldOne() throws {
        let records = Records.written()
        records.check.recurrence = .metric(every: 500, unit: .kilometres, fallback: nil)
        let rule = try Self.json(records.check.recurrenceData)
        #expect(rule["type"] == "metric")
        #expect(rule["until"] == nil && rule["skipWeekends"] == nil && rule["anchor"] == nil, "Another kind of rule is another rule")

        records.check.recurrence = .none
        #expect(try Self.json(records.check.recurrenceData) == ["type": "none"])
    }

    @Test func aListsEntriesKeepWhatTheyHoldWhereverTheyMove() throws {
        let records = Records.written()
        let facts = records.boat.customFacts
        records.boat.customFacts = [facts[1], CustomFact(label: "Vâsle", value: "În magazie"), facts[0]]
        let written = try Self.json(records.boat.customFactsData)
        #expect(Self.part("0/label", of: written) == "Cheie")
        #expect(Self.part("2/colour", of: written) == "blue", "A row moved keeps what it holds")
        #expect(Self.part("1/colour", of: written) == nil, "A new row holds only what it says")

        // A row taken out goes, with what it kept.
        records.boat.customFacts = [facts[1]]
        let fewer = try Self.json(records.boat.customFactsData)
        #expect(fewer.array?.count == 1)
        #expect(!fewer.containsString { $0 == "blue" || $0 == "scan" })
    }

    @Test func aChoiceAddedBesideTheOthersLeavesThemAsStored() throws {
        let records = Records.written()
        var sections = records.boats.sections
        sections[0].fields[0].options?.append(ChoiceOption(key: "fuel.electric", label: "Electric"))
        records.boats.sections = sections
        let written = try Self.json(records.boats.sectionsData)
        #expect(Self.part("0/fields/0/options/0/icon", of: written) == "drop")
        #expect(Self.part("0/fields/0/options/2/key", of: written) == "fuel.electric")
    }

    @Test func aValueMadeHereWritesAsItAlwaysDid() throws {
        let rule = RecurrenceRule.interval(.years(1), anchor: .dueDate)
        #expect(StoredJSON.encode(KeptObject(rule)) == StoredJSON.encode(rule))
        let paper = DosarCuSina.Attachment(fileName: "act.jpg", contentType: "public.jpeg", data: nil, kind: .other)
        paper.framing = DocumentFraming(pages: [PageFraming(quarterTurns: 1)])
        #expect(paper.framingData == StoredJSON.encode(DocumentFraming(pages: [PageFraming(quarterTurns: 1)])))
        paper.framing = DocumentFraming()
        #expect(paper.framingData == nil, "A plain framing with nothing more stores nothing")

        let records = Records.written()
        records.paper.framing = DocumentFraming()
        #expect(records.paper.framingData != nil, "What a newer build wrote stays though the framing is plain here")
        records.boats.behavior = .standard
        #expect(Self.part("shelf", of: try Self.json(records.boats.behaviorData)) == "top")
    }

    // MARK: Backups

    @Test func aBackupCarriesWhatANewerBuildWroteBothWays() throws {
        let source = try makeInMemoryContainer()
        let context = ModelContext(source)
        try TemplateStore(context: context).installBuiltIns()
        let records = Records.written()
        records.insert(into: context)
        try UnitOfWork.save(context)
        let first = try DossierArchiveService(container: source, calendar: .bucharest).exportData(exportedAt: noon("2026-11-10"))

        let target = try makeInMemoryContainer()
        let service = DossierArchiveService(container: target, calendar: .bucharest)
        try service.importArchive(first, mode: .replace)
        let restored = ModelContext(target)
        let boats = try #require(CategoryTemplate.find(records.boats.key, in: restored))
        let boat = try #require(Asset.find(records.boat.recordKey, in: restored))
        let check = try #require(Obligation.find(records.check.recordKey, in: restored))
        let paper = try #require(DosarCuSina.Attachment.find(records.paper.recordKey, in: restored))
        let back = Records(boats: boats, boat: boat, check: check, paper: paper)
        for object in StoredObject.allCases {
            #expect(try Self.json(object.data(back)) == Self.json(Data(object.written.utf8)), "\(object.property) comes back as written")
        }

        // Out again from the other phone, the same.
        let second = try DossierArchiveReader.read(try service.exportData(exportedAt: noon("2026-11-11")))
        let firstPackage = try DossierArchiveReader.read(first)
        let outTemplate = try #require(second.templates.first { $0.key == boats.key })
        let inTemplate = try #require(firstPackage.templates.first { $0.key == boats.key })
        #expect(outTemplate.sections == inTemplate.sections && outTemplate.blueprints == inTemplate.blueprints)
        #expect(outTemplate.components == inTemplate.components && outTemplate.behavior == inTemplate.behavior)
        #expect(second.assets.first { $0.id == DossierV3.id(boat.id) }?.values == firstPackage.assets.first { $0.id == DossierV3.id(boat.id) }?.values)
        #expect(second.obligations.first { $0.id == DossierV3.id(check.id) }?.recurrence == firstPackage.obligations.first { $0.id == DossierV3.id(check.id) }?.recurrence)
        #expect(second.attachments.first { $0.id == DossierV3.id(paper.id) }?.framing == firstPackage.attachments.first { $0.id == DossierV3.id(paper.id) }?.framing)
    }

    @Test func aSealedCodeANewerBuildKeptInsideARecordNeverLeaves() throws {
        let source = try makeInMemoryContainer()
        let context = ModelContext(source)
        try TemplateStore(context: context).installBuiltIns()
        let boat = Asset(name: "Barca de pe lac", templateKey: BuiltInTemplates.Key.other)
        boat.valuesData = Data(#"{"car.plate":{"note":"sealed:v1:AAAA","type":"text","value":"B-123-ABC"}}"#.utf8)
        boat.customFactsData = Data(#"[{"code":"sealed:v1:AAAA","id":"c0ffee00-0000-4000-8000-000000000005","label":"Poartă","value":"Sus"}]"#.utf8)
        context.insert(boat)
        try UnitOfWork.save(context)

        let package = try DossierArchiveReader.read(try DossierArchiveService(container: source, calendar: .bucharest).exportData(exportedAt: noon("2026-11-10")))
        let out = try #require(package.assets.first { $0.id == DossierV3.id(boat.id) })
        let values = try #require(JSONValue(encoding: out.values))
        #expect(Self.part("car.plate/value", of: values) == "B-123-ABC", "The value this build reads goes out")
        #expect(!values.containsString(where: SecretSealer.isSealed), "What it doesn't read, sealed, stays on the phone")
        let rows = try #require(out.customFacts)
        let facts = try #require(JSONValue(encoding: rows))
        #expect(Self.part("0/label", of: facts) == "Poartă")
        #expect(!facts.containsString(where: SecretSealer.isSealed))
    }

    @Test func aCardNumberANewerBuildWroteInsideARecordIsMasked() throws {
        let context = try makeContext()
        let number = "4111 1111 1111 1111"
        let records = Records()
        records.boat.valuesData = Data(#"{"car.plate":{"card":"\#(number)","type":"text","value":"B-123-ABC"}}"#.utf8)
        records.boat.customFactsData = Data(#"[{"card":{"number":"\#(number)"},"id":"c0ffee00-0000-4000-8000-000000000006","label":"Poartă","value":"Sus"}]"#.utf8)
        records.check.recurrenceData = Data(#"{"every":1,"note":"\#(number)","type":"interval","unit":"year"}"#.utf8)
        records.paper.framingData = Data(#"{"pages":[],"source":"\#(number)","version":1}"#.utf8)
        records.insert(into: context)
        try UnitOfWork.save(context)

        let saved = ModelContext(context.container)
        let back = Records(
            boats: try #require(CategoryTemplate.find(records.boats.key, in: saved)), boat: try #require(Asset.find(records.boat.recordKey, in: saved)),
            check: try #require(Obligation.find(records.check.recordKey, in: saved)), paper: try #require(DosarCuSina.Attachment.find(records.paper.recordKey, in: saved))
        )
        let masked = "\(PaymentCardNumbers.mask) 1111"
        #expect(Self.part("car.plate/card", of: try Self.json(back.boat.valuesData)) == .string(masked))
        #expect(Self.part("car.plate/value", of: try Self.json(back.boat.valuesData)) == "B-123-ABC")
        #expect(Self.part("0/card/number", of: try Self.json(back.boat.customFactsData)) == .string(masked))
        #expect(Self.part("note", of: try Self.json(back.check.recurrenceData)) == .string(masked))
        #expect(Self.part("source", of: try Self.json(back.paper.framingData)) == .string(masked))
    }

    // MARK: Helpers

    static func json(_ data: Data?) throws -> JSONValue {
        try JSONDecoder().decode(JSONValue.self, from: try #require(data))
    }

    /// The part of `json` at `path`: keys and list places, split by "/".
    static func part(_ path: String, of json: JSONValue) -> JSONValue? {
        path.split(separator: "/").reduce(Optional(json)) { value, step in
            guard let value else { return nil }
            if let index = Int(step), value.array != nil { return value[index] }
            return value[String(step)]
        }
    }
}

extension StoredObjectsTests.Records {
    init(boats: CategoryTemplate, boat: Asset, check: Obligation, paper: DosarCuSina.Attachment) {
        self.boats = boats
        self.boat = boat
        self.check = check
        self.paper = paper
    }
}
