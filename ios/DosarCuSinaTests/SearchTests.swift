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
