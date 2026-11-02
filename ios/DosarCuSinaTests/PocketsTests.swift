import Foundation
import SwiftData
import Testing
@testable import DosarCuSina

@Suite("Section pockets")
struct PocketsTests {
    @Test func pocketsAlwaysFollowTheGlobalOrder() {
        #expect(SectionPocket.ordered([.keyFacts, .upcoming, .history, .documents, .upcoming]) == [.upcoming, .documents, .history, .keyFacts])
        #expect(SectionPocket.allCases.first == .upcoming)
        #expect(SectionPocket.allCases.last == .keyFacts)
        let definition = TemplateDefinition(key: "x", name: "X", symbol: "star", tint: .gray, sections: [], pockets: [.money, .upcoming])
        #expect(definition.pockets == [.upcoming, .money])
    }

    @Test func everyBuiltInDeclaresItsPockets() {
        for template in BuiltInTemplates.all {
            #expect(!template.pockets.isEmpty, "\(template.key)")
            #expect(template.pockets == SectionPocket.ordered(template.pockets))
        }
        #expect(BuiltInTemplates.home.pockets.contains(.tenants))
        #expect(BuiltInTemplates.home.pockets.contains(.products))
    }

    @Test func factRowsCombineTemplateFactsAndFreeRows() {
        var values = FieldValues()
        values["vehicle.plate"] = .text("B-123-ABC")
        let rows = AssetFacts.factRows(values, customFacts: [CustomFact(label: "Cod alarmă", value: "1234", isSensitive: true)], template: BuiltInTemplates.vehicle)
        #expect(rows.map(\.label) == ["Număr de înmatriculare", "Cod alarmă"])
        #expect(rows.last?.isCustom == true && rows.last?.isSensitive == true)
        #expect(AssetFacts.factRows(FieldValues(), customFacts: [CustomFact(label: "A", value: "B")], template: nil).count == 1)
    }
}

@MainActor
@Suite("Custom sections")
struct CustomSectionTests {
    @Test("Altceva… needs only a name, a symbol and pockets")
    func customTemplateFromPockets() throws {
        let context = try makeContext()
        let store = TemplateStore(context: context)
        let boats = try store.createCustom(name: "Bărci", symbol: "sailboat.fill", pockets: [.keyFacts, .upcoming, .history])
        #expect(boats.isCustom)
        #expect(boats.sections.isEmpty)
        #expect(boats.pockets == [.upcoming, .history, .keyFacts])
        try store.setPockets(boats, [.documents, .upcoming])
        #expect(boats.pockets == [.upcoming, .documents])

        let boat = try AssetActions(context: context).create(name: "Barca", template: boats, values: FieldValues())
        try AssetActions(context: context).setCustomFacts(boat, [CustomFact(label: "Loc în port", value: "Ponton 3"), CustomFact(label: " ", value: "")])
        #expect(boat.customFacts.map(\.label) == ["Loc în port"], "Empty rows are dropped")
        let index = try SearchIndexBuilder(context: context).build()
        #expect(index.search("ponton").first?.document.title == "Barca")
    }

    @Test func archivesCarryPocketsAndFreeRows() throws {
        let container = try makeInMemoryContainer()
        try DossierArchiveService(container: container, calendar: .bucharest).importArchive(try Fixtures.archive("dosar-v3/household"), mode: .replace)
        let context = ModelContext(container)
        let boats = try #require(try TemplateStore(context: context).template(forKey: "custom.0b6c6f43-6c1e-4d1a-9c55-7d3b4f1f2a10"))
        #expect(boats.pockets == [.upcoming, .history, .keyFacts])
        let boat = try #require(try context.fetch(FetchDescriptor<Asset>()).first { $0.name == "Barca de pe lac" })
        #expect(boat.customFacts.map(\.value) == ["Ponton 3, locul 12"])

        let exported = try DossierArchiveService(container: container, calendar: .bucharest).exportData()
        let copy = try makeInMemoryContainer()
        try DossierArchiveService(container: copy, calendar: .bucharest).importArchive(exported, mode: .replace)
        let copied = try #require(try ModelContext(copy).fetch(FetchDescriptor<Asset>()).first { $0.name == "Barca de pe lac" })
        #expect(copied.customFacts == boat.customFacts)
    }
}
