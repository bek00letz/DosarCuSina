import Foundation
import SwiftData
import Testing
@testable import DosarCuSina

@Suite("Search index")
struct SearchIndexTests {
    private let index = SearchIndex([
        SearchDocument(id: "a", kind: .document, title: "Poliță RCA 2026", subtitle: nil, route: .home,
                       fields: [SearchField("Poliță RCA 2026", weight: SearchField.Weight.title), SearchField("Daune: 021 000 0000", weight: SearchField.Weight.extracted)]),
        SearchDocument(id: "b", kind: .provider, title: "Ștefan Instalații", subtitle: nil, route: .home,
                       fields: [SearchField("Ștefan Instalații", weight: SearchField.Weight.title), SearchField("Instalator", weight: SearchField.Weight.label)]),
        SearchDocument(id: "c", kind: .historyEntry, title: "Revizie", subtitle: nil, route: .home,
                       fields: [SearchField("Revizie", weight: SearchField.Weight.title), SearchField("polița veche e în torpedou", weight: SearchField.Weight.note)]),
    ])

    @Test func ignoresDiacriticsAndCase() {
        #expect(index.search("polita").map(\.id) == ["a", "c"], "The title match outranks a note")
        #expect(index.search("STEFAN").map(\.id) == ["b"])
        #expect(index.search("instalator").first?.id == "b")
    }

    @Test func everyWordMustMatchAndPrefixesCount() {
        #expect(index.search("polita rca").map(\.id) == ["a"])
        #expect(index.search("pol daune").map(\.id) == ["a"])
        #expect(index.search("polita lipsa").isEmpty)
        #expect(index.search("   ").isEmpty)
    }

    @Test func snippetShowsWhatMatchedAndKindsFilter() {
        #expect(index.search("torpedou").first?.snippet == "polița veche e în torpedou")
        #expect(index.search("polita", kinds: [.historyEntry]).map(\.id) == ["c"])
    }
}

@MainActor
@Suite("Search over the binder")
struct BinderSearchTests {
    private func exampleIndex() throws -> SearchIndex {
        let context = try makeContext()
        try ExampleDataService(context: context, calendar: .bucharest, now: { noon("2026-11-02") }).loadExamples()
        return try SearchIndexBuilder(context: context).build()
    }

    @Test("știi un service bun?")
    func findsProvidersByTrade() throws {
        let results = try exampleIndex().search("mecanic")
        #expect(results.first?.document.kind == .provider)
        #expect(results.first?.document.title == "Service auto exemplu")
    }

    @Test("cine ți-a schimbat robinetul?")
    func findsWhoDidAJob() throws {
        let results = try exampleIndex().search("robinet")
        let job = try #require(results.first { $0.document.kind == .historyEntry })
        if case .historyEntry = job.document.route {} else { Issue.record("A job opens its history entry") }
        #expect(try exampleIndex().search("instalator").contains { $0.document.kind == .provider })
    }

    @Test("când am luat hota?")
    func findsPurchasesAndComponents() throws {
        let results = try exampleIndex().search("hota")
        #expect(results.contains { $0.document.kind == .component && $0.document.title == "Hotă" })
        #expect(results.contains { $0.document.kind == .historyEntry })
    }

    @Test("când mi-am schimbat plăcuțele?")
    func findsComponentsByBillWording() throws {
        let results = try exampleIndex().search("placute")
        let component = try #require(results.first { $0.document.kind == .component })
        #expect(component.document.title == "Plăcuțe frână față")
        #expect(component.document.subtitle?.hasPrefix("VW Golf") == true)
    }

    @Test func platesMatchWithOrWithoutDashes() throws {
        let index = try exampleIndex()
        #expect(index.search("B-123-ABC").first?.document.title == "VW Golf")
        #expect(index.search("b123abc").first?.document.title == "VW Golf")
    }

    @Test func sensitiveCategoriesAreFlagged() throws {
        let results = try exampleIndex().search("pasaport")
        #expect(results.contains { $0.document.kind == .asset && $0.document.isSensitive })
    }

    @Test("unde e polița veche?")
    func findsOldPoliciesInTheGoldenArchive() throws {
        let container = try makeInMemoryContainer()
        try DossierArchiveService(container: container, calendar: .bucharest).importArchive(try Fixtures.archive("dosar-v3/household"), mode: .replace)
        let index = try SearchIndexBuilder(context: ModelContext(container)).build()
        let results = index.search("polita rca", kinds: [.document])
        #expect(results.count == 2)
        #expect(index.search("POL-000000").first?.document.title == "Poliță RCA 2025")
        #expect(index.search("POL-000000").first?.document.subtitle?.contains("arhivat") == true)
    }
}

/// Caută keeps its index off the main thread and reads again only what a save touched.
@MainActor
@Suite("Search index kept up to date")
struct SearchIndexerTests {
    private final class Captured: @unchecked Sendable {
        var changes: [SearchChanges] = []
    }

    @Test func aSaveReadsOnlyWhatItTouched() async throws {
        let context = try makeContext()
        let template = try #require(try TemplateStore(context: context).template(forKey: BuiltInTemplates.Key.vehicle))
        let assets = AssetActions(context: context, calendar: .bucharest, now: { noon("2026-11-03") })
        let car = try assets.create(name: "VW Golf", template: template, values: FieldValues())
        let other = try assets.create(name: "Dacia Logan", template: template, values: FieldValues())
        let obligations = ObligationActions(context: context, calendar: .bucharest, now: { noon("2026-11-03") })
        _ = try obligations.create(title: "Rovinietă", kind: .legal, dueDay: CalendarDay("2027-01-10"), for: other)

        let indexer = SearchIndexer(container: context.container)
        let first = try await indexer.rebuild()
        let everything = await indexer.lastRecordsRead
        #expect(first.search("golf").contains { $0.document.title == "VW Golf" })

        // A new deadline: only it is read.
        let itp = try obligations.create(title: "Inspecția tehnică", kind: .legal, dueDay: CalendarDay("2027-03-01"), for: car)
        var index = try await indexer.apply(SearchChanges(changed: [itp.persistentModelID]))
        #expect(await indexer.lastRecordsRead == 1)
        #expect(index.search("inspectia").first?.document.subtitle?.hasPrefix("VW Golf") == true)

        // A rename: the car and what shows its name, never the other car's records.
        try assets.update(car, name: "Golf de familie", values: car.values, notes: car.notes)
        index = try await indexer.apply(SearchChanges(changed: [car.persistentModelID]))
        #expect(await indexer.lastRecordsRead < everything)
        #expect(index.search("inspectia").first?.document.subtitle?.hasPrefix("Golf de familie") == true)
        #expect(index.search("rovinieta").first?.document.subtitle?.hasPrefix("Dacia Logan") == true)

        // A deletion takes its documents out, and the index matches a full read.
        let id = itp.persistentModelID
        try obligations.delete(itp)
        index = try await indexer.apply(SearchChanges(deleted: [id]))
        #expect(index.search("inspectia").isEmpty)
        #expect(index.count == (try SearchIndexBuilder(context: ModelContext(context.container)).build().count))
    }

    @Test func savesSayWhatTheyChanged() throws {
        let context = try makeContext()
        let captured = Captured()
        let token = NotificationCenter.default.addObserver(forName: ModelContext.didSave, object: context, queue: nil) { note in
            captured.changes.append(SearchChanges(note))
        }
        defer { NotificationCenter.default.removeObserver(token) }
        let template = try #require(try TemplateStore(context: context).template(forKey: BuiltInTemplates.Key.vehicle))
        let car = try AssetActions(context: context).create(name: "VW Golf", template: template, values: FieldValues())
        #expect(captured.changes.contains { $0.changed.contains(car.persistentModelID) })
    }
}
