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

    /// A deadline found by its section's name said „VW Golf · 3 martie”, then „VW Golf” again
    /// under it. For every kind of result, the preview is never what the row already says.
    @Test("The preview line never repeats the title or the subtitle")
    func previewAddsSomething() {
        let deadline = SearchDocument(id: "d", kind: .obligation, title: "RCA", subtitle: "VW Golf · 3 martie", route: .home, fields: [
            SearchField("RCA", weight: SearchField.Weight.title),
            SearchField("VW Golf", weight: SearchField.Weight.label),
            SearchField("Golful din garaj", weight: SearchField.Weight.note),
        ])
        let part = SearchDocument(id: "e", kind: .component, title: "Plăcuțe frână față", subtitle: "VW Golf · 3 martie", route: .home, fields: [
            SearchField("Plăcuțe frână față", weight: SearchField.Weight.title),
            SearchField("VW Golf", weight: SearchField.Weight.label),
        ])
        let index = SearchIndex([deadline, part])
        #expect(index.search("golf").first { $0.id == "d" }?.snippet == "Golful din garaj", "The next field that matched, which says something new")
        #expect(index.search("golf").first { $0.id == "e" }?.snippet == nil, "The subtitle already says it")
        #expect(index.search("rca").first?.snippet == nil, "The title already says it")
        #expect(index.search("garaj").first?.snippet == "Golful din garaj")
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

/// What Caută says of a locked section away from its page: only that it is locked, by the one
/// answer for each record it reaches.
@MainActor
@Suite("Search and locked sections")
struct SearchLockedSectionsTests {
    /// A car (open here) and a person's passport, its category locked.
    private func household() throws -> (context: ModelContext, car: Asset, passport: Asset) {
        let context = try makeContext()
        let store = TemplateStore(context: context)
        let vehicles = try #require(try store.template(forKey: BuiltInTemplates.Key.vehicle))
        let documents = try #require(try store.template(forKey: BuiltInTemplates.Key.documents))
        try store.setSensitive(documents, true)
        let assets = AssetActions(context: context, calendar: .bucharest, now: { noon("2026-11-03") })
        let car = try assets.create(name: "VW Golf", template: vehicles, values: FieldValues())
        let passport = try assets.create(name: "Pașaport Ana", template: documents, values: FieldValues())
        #expect(!car.isSensitive(template: vehicles) && passport.isSensitive(template: documents))
        return (context, car, passport)
    }

    private func index(_ context: ModelContext) throws -> SearchIndex {
        try SearchIndexBuilder(context: PersistenceController.context(in: context.container)).build()
    }

    @Test("A firm's result never names a locked section")
    func aFirmNamesOnlyOpenSections() throws {
        let (context, car, passport) = try household()
        let firm = Provider(name: "Service Exemplu S.R.L.", trades: [.mechanic])
        context.insert(firm)
        firm.assets = [car, passport]
        try UnitOfWork.save(context)

        let index = try index(context)
        let result = try #require(index.documents.first { $0.kind == .provider })
        #expect(!result.fields.contains { $0.text.contains("Pașaport") }, "The locked section isn't kept with the firm")
        #expect(result.fields.contains { $0.text.contains("VW Golf") }, "The open one is")
        #expect(!index.search("pasaport ana").contains { $0.document.kind == .provider })
        #expect(index.search("golf").contains { $0.document.kind == .provider })
    }

    @Test("A document is locked in Caută by every section it belongs to")
    func aDocumentIsLockedByEverySection() throws {
        let (context, car, passport) = try household()
        let renewal = Obligation(title: "Reînnoire pașaport", kind: .legal, dueDay: CalendarDay("2028-05-05"))
        context.insert(renewal)
        renewal.asset = passport
        let receipt = DosarCuSina.Attachment(fileName: "chitanta.pdf", contentType: "com.adobe.pdf", data: nil, kind: .receipt)
        context.insert(receipt)
        receipt.title = "Chitanță taxă"
        receipt.extractedText = "Taxă pașaport achitată"
        receipt.asset = car
        receipt.obligation = renewal
        try UnitOfWork.save(context)

        let index = try index(context)
        let result = try #require(index.documents.first { $0.kind == .document })
        #expect(result.isSensitive, "Its own section is open, its deadline's is locked")
        #expect(!result.fields.contains { $0.text.contains("achitată") }, "What was read off it isn't kept")
        #expect(index.search("achitata").isEmpty)
        #expect(index.search("chitanta").first?.document.isSensitive == true, "Its title still finds it")
        // Nor does the iPhone's search show it.
        let outside = try SpotlightCatalog.entries(obligations: [], in: context)
        #expect(!outside.contains { $0.kind == .document })
    }

    @Test("A section's subtitle shows as its page shows it, with what search never keeps masked")
    func aSensitiveSubtitleShowsMasked() throws {
        let context = try makeContext()
        let definition = TemplateDefinition(
            key: "search.gear", name: "Echipamente", symbol: "wrench", tint: .gray,
            sections: [FieldSection(key: "main", title: "Date", fields: [
                FieldDefinition(key: "gear.brand", label: "Marcă", type: .text, role: .subtitle),
                FieldDefinition(key: "gear.code", label: "Cod", type: .text, role: .subtitle, isSensitive: true),
                FieldDefinition(key: "gear.year", label: "An", type: .year, role: .subtitle),
            ])],
            behavior: CategoryBehavior(visit: .none, singular: nil)
        )
        let template = CategoryTemplate(definition: definition, isBuiltIn: false, homeOrder: 0)
        context.insert(template)
        let values = FieldValues(["gear.brand": .text("Exemplu"), "gear.code": .text("AB-000000"), "gear.year": .number(2020)])
        context.insert(Asset(name: "Drujbă", templateKey: definition.key, values: values))
        try UnitOfWork.save(context)

        #expect(HeroFacts.subtitle(values, definition: definition) == "Exemplu AB-000000 · 2020", "Its page shows it")
        let result = try #require(try index(context).documents.first { $0.kind == .asset && $0.title == "Drujbă" })
        #expect(result.subtitle == "Exemplu \(SecretFields.mask) · 2020")
        #expect(!result.fields.contains { $0.text.contains("000000") })
    }

    @Test("A result's line never shows a CNP, and keeps what is already masked as its page shows it")
    func aResultsLineIsRedactedAsItsFields() throws {
        let context = try makeContext()
        let definition = TemplateDefinition(
            key: "search.copies", name: "Copii", symbol: "doc", tint: .gray,
            sections: [FieldSection(key: "main", title: "Date", fields: [
                FieldDefinition(key: "copy.note", label: "Exemplar", type: .text, role: .subtitle),
            ])],
            behavior: CategoryBehavior(visit: .none, singular: nil)
        )
        context.insert(CategoryTemplate(definition: definition, isBuiltIn: false, homeOrder: 0))
        let values = FieldValues(["copy.note": .text("Copie 1800101990006 · card •••• 1111")])
        let section = Asset(name: "Dosar Exemplu", templateKey: definition.key, values: values)
        context.insert(section)
        let deadline = Obligation(title: "Termen", kind: .routine, dueDay: CalendarDay("2027-01-10"))
        context.insert(deadline)
        deadline.asset = section
        try UnitOfWork.save(context)

        #expect(HeroFacts.subtitle(section.values, definition: definition) == "Copie 1800101990006 · card •••• 1111", "Its page is unchanged")
        let index = try index(context)
        let result = try #require(index.documents.first { $0.kind == .asset && $0.title == "Dosar Exemplu" })
        #expect(result.subtitle == "Copie · card •••• 1111", "The CNP goes, the card's mask and last four stay")
        #expect(!result.fields.contains { $0.text.contains("1800101990006") || $0.text.contains("1111") }, "Neither is searched")
        #expect(index.search("1111").isEmpty)
        // Every kind of result: a deadline's line names its section the same way.
        let line = try #require(index.documents.first { $0.kind == .obligation }?.subtitle)
        #expect(line.hasPrefix("Dosar Exemplu ·") && !line.contains("1800101990006"))
    }

    @Test("A section named with a CNP-shaped number shows without it in Caută")
    func aTitleIsShownByTheSameRule() throws {
        let context = try makeContext()
        let vehicles = try #require(try TemplateStore(context: context).template(forKey: BuiltInTemplates.Key.vehicle))
        let assets = AssetActions(context: context, calendar: .bucharest, now: { noon("2026-11-03") })
        let named = try assets.create(name: "Certificat 1800101990006", template: vehicles, values: FieldValues())
        _ = try assets.create(name: "VW Golf 2018", template: vehicles, values: FieldValues())
        let deadline = Obligation(title: "ITP 1800101990006", kind: .legal, dueDay: CalendarDay("2027-03-01"))
        context.insert(deadline)
        deadline.asset = named
        try UnitOfWork.save(context)

        let index = try index(context)
        #expect(index.documents.contains { $0.kind == .asset && $0.title == "Certificat" })
        #expect(index.documents.contains { $0.kind == .asset && $0.title == "VW Golf 2018" }, "A title with nothing taken out stays as it is")
        let itp = try #require(index.documents.first { $0.kind == .obligation })
        #expect(itp.title == "ITP" && itp.subtitle?.hasPrefix("Certificat ·") == true)
        #expect(!index.documents.contains { ($0.title + ($0.subtitle ?? "")).contains("1800101990006") })
        #expect(index.search("1800101990006").isEmpty, "Nor is it matched")
        #expect(index.search("certificat").contains { $0.document.kind == .asset })
    }

    @Test("A section whose category hasn't arrived reads again the documents that name no section")
    func aSectionWhoseCategoryIsMissingReadsTheUnfiledDocuments() async throws {
        // Nothing locked yet: no built-in categories, one open category of one's own.
        let container = try makeInMemoryContainer()
        let context = PersistenceController.context(in: container)
        let open = TemplateDefinition(key: "search.open", name: "Deschise", symbol: "folder", tint: .gray, sections: [],
                                      behavior: CategoryBehavior(visit: .none, singular: nil))
        context.insert(CategoryTemplate(definition: open, isBuiltIn: false, homeOrder: 0))
        for name in ["Raft", "Dulap", "Sertar"] { context.insert(Asset(name: name, templateKey: open.key)) }
        let unfiled = DosarCuSina.Attachment(fileName: "scan.pdf", contentType: "com.adobe.pdf", data: nil, kind: .other)
        unfiled.extractedText = "Pagina întâi"
        context.insert(unfiled)
        try UnitOfWork.save(context)

        let indexer = SearchIndexer(container: container)
        var index = try await indexer.rebuild()
        let everything = await indexer.lastRecordsRead
        #expect(index.search("pagina").first?.document.isSensitive == false)

        // A section arrives before its category (from another device): locked, so the document is too.
        let arriving = Asset(name: "Sosește", templateKey: "custom.0b6c6f43-0000-4000-8000-0000000000bb")
        context.insert(arriving)
        try UnitOfWork.save(context)
        index = try await indexer.apply(SearchChanges(changed: [arriving.persistentModelID]))
        #expect(await indexer.lastRecordsRead < everything, "Only what it can reach is read again")
        #expect(index.search("pagina").isEmpty, "What was read off it isn't kept while something may be locked")
        #expect(index.search("scan").first?.document.isSensitive == true)

        // It goes: nothing of the binder is locked again.
        let id = arriving.persistentModelID
        context.delete(arriving)
        try UnitOfWork.save(context)
        index = try await indexer.apply(SearchChanges(deleted: [id]))
        #expect(index.search("pagina").first?.document.isSensitive == false)
        #expect(index.count == (try SearchIndexBuilder(context: PersistenceController.context(in: container)).build().count))
    }
}
