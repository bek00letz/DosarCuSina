import Foundation
import SwiftData
import Testing
@testable import DosarCuSina

/// What a newer build wrote that this one can't read comes in raw, stays through edits and
/// goes back out unchanged: a recurrence, a category's sections, deadlines and fields, a row
/// under Date importante, a field value.
@MainActor
@Suite("Values from a newer version")
struct NewerVersionTests {
    let calendar = Calendar.bucharest


    /// The golden household as a newer build would write it: a recurrence, a category's
    /// section, deadline and field, a row under Date importante and a field value this
    /// build can't read.
    static func futureArchive() throws -> Data {
        try Fixtures.archive("dosar-v3/household") { files in
            Self.rewrite(&files, DossierV3.Path.obligations) { obligations in
                obligations[0].set("recurrence", ["type": "seasonal", "season": "spring", "every": .int(1)])
                obligations[1].set("recurrence", ["type": "interval", "every": .int(2), "unit": "fortnight", "anchor": "dueDate"])
            }
            Self.rewrite(&files, DossierV3.Path.templates) { templates in
                var boats = templates[1]
                var sections = boats["sections"]?.array ?? []
                var main = sections[0]
                var fields = main["fields"]?.array ?? []
                fields.append(["key": "boat.colour", "label": "Culoare", "type": "colour", "isEssential": false, "isSensitive": false,
                               "derivation": ["type": "paintCode", "from": "boat.registration"]])
                main.set("fields", .array(fields))
                sections[0] = main
                sections.insert(["key": "boat.future", "title": ["ro": "Viitor", "en": "Future"], "fields": []], at: 0)
                boats.set("sections", .array(sections))
                var blueprints = boats["blueprints"]?.array ?? []
                blueprints.append(["key": "boat.antifouling", "title": "Vopsea", "kind": "maintenance",
                                   "recurrence": ["type": "seasonal", "season": "spring"]])
                blueprints.append(["key": "boat.unknown", "title": ["ro": "Necunoscut"]])
                boats.set("blueprints", .array(blueprints))
                templates[1] = boats
            }
            Self.rewrite(&files, DossierV3.Path.assets) { assets in
                var boat = assets[1]
                var facts = boat["customFacts"]?.array ?? []
                facts.insert(["id": "c0ffee00-0000-4000-8000-000000000002", "label": ["ro": "Cheie"], "value": "Sub preș"], at: 0)
                facts.append(["id": "c0ffee00-0000-4000-8000-000000000003", "label": "Card", "value": ["number": "4111 1111 1111 1111"]])
                facts.append(["id": "c0ffee00-0000-4000-8000-000000000004", "label": ["ro": "Cod"], "value": "sealed:v1:AAAA", "isSecret": true])
                boat.set("customFacts", .array(facts))
                var values = boat["values"] ?? [:]
                values.set("boat.mooring", ["type": "location", "lat": .number(44.4), "lon": .number(26.1)])
                boat.set("values", values)
                assets[1] = boat
            }
        }
    }

    @Test("What a newer build wrote and this one can't read comes in raw and goes out unchanged")
    func valuesFromANewerVersionGoBackOutUnchanged() throws {
        let input = try DossierArchiveReader.read(try Self.futureArchive())
        let container = try makeInMemoryContainer()
        let service = DossierArchiveService(container: container, calendar: calendar)
        try service.importPackage(input, mode: .replace)
        let context = ModelContext(container)

        // Read as this build understands them.
        let obligations = try context.fetch(FetchDescriptor<Obligation>())
        let itp = try #require(obligations.first { $0.title == "ITP" })
        #expect(!itp.recurrence.repeats, "A rule this build can't read behaves as one-off")
        let boats = try #require(try context.fetch(FetchDescriptor<CategoryTemplate>()).first { $0.isCustom })
        #expect(boats.sections.map(\.key) == ["boat.main"])
        #expect(boats.sections[0].fields.last?.type == .text, "A field type this build doesn't know reads as text")
        #expect(boats.blueprints.map(\.key) == ["boat.engine", "boat.antifouling"])
        let boat = try #require(try context.fetch(FetchDescriptor<Asset>()).first { $0.name == "Barca de pe lac" })
        #expect(boat.customFacts.map(\.label) == ["Loc în port"])

        // Written back exactly as they came, but for what never leaves a phone.
        let output = try DossierArchiveReader.read(try service.exportData())
        func obligation(_ package: DossierV3.Package, _ title: String) throws -> RecurrenceRule {
            try #require(package.obligations.first { $0.title == title }).recurrence
        }
        for title in ["ITP", "RCA"] {
            #expect(try obligation(output, title) == obligation(input, title), "\(title)'s rule is written back as it came")
        }
        let inTemplate = try #require(input.templates.first { !$0.isBuiltIn })
        let outTemplate = try #require(output.templates.first { $0.key == inTemplate.key })
        #expect(outTemplate.sections == inTemplate.sections)
        #expect(outTemplate.sections.unreadable.map(\.position) == [0], "An unreadable section keeps its place")
        #expect(outTemplate.blueprints == inTemplate.blueprints)
        let inField = try #require(inTemplate.sections.items[0].fields.last)
        let outField = try #require(outTemplate.sections.items[0].fields.last)
        #expect(Self.json(outField) == Self.json(inField), "A field keeps its type and derivation as written")
        #expect(Self.json(outField)["type"] == "colour")

        let inBoat = try #require(input.assets.first { $0.name == "Barca de pe lac" })
        let outBoat = try #require(output.assets.first { $0.id == inBoat.id })
        #expect(outBoat.values == inBoat.values, "A value this build can't read goes back out")
        let outFacts = try #require(outBoat.customFacts)
        #expect(outFacts.items == inBoat.customFacts?.items)
        #expect(outFacts.unreadable.map(\.position) == [0, 2], "The rows it can't read keep their places")
        #expect(outFacts.unreadable[0].raw == inBoat.customFacts?.unreadable[0].raw)
        let card = outFacts.unreadable[1].raw
        #expect(card["value"]?["number"]?.string?.contains("4111") == false, "A card number in a row it can't read is masked")
        #expect(!outFacts.unreadable.contains { $0.raw["isSecret"]?.bool == true }, "A secret row never comes in or goes out")
    }

    @Test("Editing what this build reads never drops what it can't")
    func editingKeepsWhatCantBeRead() throws {
        let container = try makeInMemoryContainer()
        let service = DossierArchiveService(container: container, calendar: calendar)
        try service.importArchive(try Self.futureArchive(), mode: .replace)
        let context = ModelContext(container)

        let boat = try #require(try context.fetch(FetchDescriptor<Asset>()).first { $0.name == "Barca de pe lac" })
        _ = try AssetActions(context: context, calendar: calendar).setCustomFacts(boat, boat.customFacts + [CustomFact(label: "Vâsle", value: "În magazie")])
        let boats = try #require(try context.fetch(FetchDescriptor<CategoryTemplate>()).first { $0.isCustom })
        var sections = boats.sections
        sections[0].fields[sections[0].fields.count - 1].label = "Culoarea bărcii"
        boats.sections = sections
        let itp = try #require(try context.fetch(FetchDescriptor<Obligation>()).first { $0.title == "ITP" })
        try ObligationActions(context: context, calendar: calendar).snooze(itp, days: 3)
        try UnitOfWork.save(context)

        let output = try DossierArchiveReader.read(try service.exportData())
        let outBoat = try #require(output.assets.first { $0.name == "Barca de pe lac" })
        #expect(outBoat.customFacts?.items.map(\.label) == ["Loc în port", "Vâsle"])
        #expect(outBoat.customFacts?.unreadable.count == 2)
        #expect(outBoat.values.keys.contains("boat.registration"))
        let outTemplate = try #require(output.templates.first { !$0.isBuiltIn })
        #expect(outTemplate.sections.unreadable.count == 1)
        let field = try #require(outTemplate.sections.items[0].fields.last)
        #expect(field.label == "Culoarea bărcii")
        #expect(Self.json(field)["type"] == "colour", "Renaming a field keeps the type it was written with")
        #expect(Self.json(field)["derivation"]?["type"] == "paintCode")
        #expect(outTemplate.blueprints.unreadable.count == 1)
        guard case .unreadable(let rule)? = output.obligations.first(where: { $0.title == "ITP" })?.recurrence else {
            Issue.record("The rule a newer build wrote is kept through a snooze")
            return
        }
        #expect(rule["type"] == "seasonal")

        // Setting a part this build reads replaces what it couldn't.
        sections[0].fields[sections[0].fields.count - 1].type = .longText
        boats.sections = sections
        #expect(Self.json(try #require(boats.sections[0].fields.last))["type"] == "longText")
    }

    // MARK: Helpers

    static func json<T: Encodable>(_ value: T) -> JSONValue {
        (try? JSONDecoder().decode(JSONValue.self, from: JSONEncoder().encode(value))) ?? .null
    }

    /// Rewrites one data file of a fixture as JSON, and its checksum with it.
    static func rewrite(_ files: inout [String: Data], _ path: String, _ edit: (inout [JSONValue]) -> Void) {
        var records = (try? JSONDecoder().decode([JSONValue].self, from: files[path] ?? Data())) ?? []
        edit(&records)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        files[path] = try? encoder.encode(records)
        guard let manifestData = files[DossierV3.Path.manifest],
              var manifest = try? JSONDecoder().decode(JSONValue.self, from: manifestData).object,
              var checksums = manifest["checksums"]?.object, let data = files[path] else { return }
        checksums[path] = .string(DossierArchiveReader.sha256(data))
        manifest["checksums"] = .object(checksums)
        files[DossierV3.Path.manifest] = try? encoder.encode(JSONValue.object(manifest))
    }
}

extension JSONValue {
    /// The same object with `key` set, for writing a test's archive by hand.
    mutating func set(_ key: String, _ value: JSONValue) {
        var fields = self.object ?? [:]
        fields[key] = value
        self = .object(fields)
    }
}
