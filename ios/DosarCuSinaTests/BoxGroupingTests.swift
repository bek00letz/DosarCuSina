import CoreData
import Foundation
import SwiftData
import Testing
@testable import DosarCuSina

/// One box for a category's sections, or one each: the person's choice per category, over the
/// catalog's default; and plants, one "Plante" box by default, each in a home or on its own.
@MainActor
@Suite("Grouped boxes and plants")
struct BoxGroupingTests {
    let calendar = Calendar.bucharest
    let today = noon("2026-11-02")

    private func template(_ key: String, in context: ModelContext) throws -> CategoryTemplate {
        try #require(try TemplateStore(context: context).template(forKey: key))
    }

    private func add(_ name: String, _ key: String, under parent: Asset? = nil, isExample: Bool = false, in context: ModelContext) throws -> Asset {
        try AssetActions(context: context, calendar: calendar, now: { noon("2026-11-02") })
            .create(name: name, template: try template(key, in: context), values: FieldValues(), parent: parent, isExample: isExample)
    }

    // MARK: The choice

    @Test func groupingIsOfferedFromTwoSectionsAndTheWayBackAlways() {
        let cars = CategoryBehavior(visit: .service, singular: nil)
        #expect(BoxGrouping.offer(for: cars, now: .separate, sections: 1) == nil, "One car has nothing to group")
        #expect(BoxGrouping.offer(for: cars, now: .separate, sections: 2) == .grouped)
        #expect(BoxGrouping.offer(for: cars, now: .grouped, sections: 1) == .separate)
        #expect(BoxGrouping.offer(for: cars, now: .grouped, sections: 5) == .separate)
        #expect(BoxGrouping.offer(for: CategoryBehavior(box: .wholeCategory, visit: .none, singular: nil), now: .separate, sections: 5) == nil, "Acte has one box already")
        #expect(BoxGrouping.offer(for: CategoryBehavior(box: .insideOther, visit: .none, singular: nil), now: .separate, sections: 5) == nil, "Tenants have none")
    }

    @Test func theCatalogSaysWhereEachStartsAndThePersonsChoiceWins() throws {
        let context = try makeContext()
        let cars = try template(BuiltInTemplates.Key.vehicle, in: context)
        let homes = try template(BuiltInTemplates.Key.home, in: context)
        let plants = try template(BuiltInTemplates.Key.plants, in: context)
        #expect(cars.grouping == .separate, "A box for each car, as before")
        #expect(homes.grouping == .separate)
        #expect(plants.grouping == .grouped, "One Plante box")
        #expect(cars.chosenGrouping == nil && plants.chosenGrouping == nil, "Nobody chose yet")

        let store = TemplateStore(context: context)
        try store.setGrouping(cars, .grouped)
        try store.setGrouping(plants, .separate)
        #expect(cars.groupsSections)
        #expect(!plants.groupsSections)
        #expect(!homes.groupsSections, "Per category: the homes keep a box each")

        // Reversible, and kept even when it is what the catalog says.
        try store.setGrouping(cars, .separate)
        #expect(cars.chosenGrouping == .separate)
        #expect(!cars.groupsSections)
    }

    @Test func aCategoryWithOneBoxOrNoneHasNoChoice() throws {
        let context = try makeContext()
        let documents = try template(BuiltInTemplates.Key.documents, in: context)
        let tenancy = try template(BuiltInTemplates.Key.tenancy, in: context)
        try TemplateStore(context: context).setGrouping(documents, .grouped)
        try TemplateStore(context: context).setGrouping(tenancy, .grouped)
        #expect(documents.chosenGrouping == nil && tenancy.chosenGrouping == nil)
        #expect(documents.grouping == .separate && tenancy.grouping == .separate)
    }

    @Test func theChoiceIsThePersonsChangeAndANewerCatalogKeepsIt() throws {
        let context = try makeContext()
        let cars = try template(BuiltInTemplates.Key.vehicle, in: context)
        #expect(cars.updatedAt == ChangeTime.unknown, "Installed by the catalog, changed by nobody")
        #expect(cars.changeCounts("boxGroupingRaw"), "One of a built-in's own choices, like its place")
        #expect(!cars.changeCounts("sectionsData"))
        try TemplateStore(context: context).setGrouping(cars, .grouped)
        #expect(cars.updatedAt > ChangeTime.unknown, "So the newer choice wins when a backup or another phone brings the category")

        // A newer catalog upgrades the definition and leaves the choice.
        cars.builtInVersion -= 1
        try UnitOfWork.save(context)
        try TemplateStore(context: context).installBuiltIns()
        #expect(cars.builtInVersion == TemplateDefinition.builtInCatalogVersion)
        #expect(cars.chosenGrouping == .grouped)
    }

    @Test func aChoiceFromANewerBuildIsKeptAsWritten() throws {
        let context = try makeContext()
        let cars = try template(BuiltInTemplates.Key.vehicle, in: context)
        cars.boxGroupingRaw = "byColour"
        #expect(cars.chosenGrouping == nil)
        #expect(cars.grouping == .separate, "Read as the catalog's until the person chooses here")
        #expect(cars.boxGroupingRaw == "byColour")
    }

    // MARK: The binder

    @Test func groupedSectionsShareOneBoxWhereTheCategoryIs() {
        let car1 = UUID(), car2 = UUID(), flat = UUID(), fern = UUID(), basil = UUID()
        let templates: [BinderLayout.TemplateInfo] = [
            .init(key: "vehicle", homeOrder: 0, isOnHome: true, groupsSections: true),
            .init(key: "home", homeOrder: 1, isOnHome: true),
            .init(key: "plants", homeOrder: 2, isOnHome: true, groupsSections: true),
            .init(key: "bike", homeOrder: 3, isOnHome: true, groupsSections: true),
        ]
        let assets: [BinderLayout.AssetInfo] = [
            .init(id: car1, templateKey: "vehicle", isTopLevel: true, createdAt: noon("2026-01-01")),
            .init(id: car2, templateKey: "vehicle", isTopLevel: true, createdAt: noon("2026-02-01")),
            .init(id: flat, templateKey: "home", isTopLevel: true, createdAt: noon("2026-01-01")),
            .init(id: fern, templateKey: "plants", isTopLevel: false, createdAt: noon("2026-03-01")),
            .init(id: basil, templateKey: "plants", isTopLevel: true, createdAt: noon("2026-03-02")),
        ]
        let order = BinderLayout.defaultOrder(templates: templates, assets: assets, hasContacts: true)
        #expect(order == [.category("vehicle"), .asset(flat), .category("plants"), .agenda],
                "One box per grouped category, a plant in a home counted too; none for a category with nothing in it")

        var separate = templates
        separate[0].groupsSections = false
        #expect(Array(BinderLayout.defaultOrder(templates: separate, assets: assets, hasContacts: true).prefix(2)) == [.asset(car1), .asset(car2)])
    }

    @Test func theOneBoxStandsWhereTheFirstOfItsSectionsStoodAndGivesThemBack() {
        let car1 = UUID(), car2 = UUID(), flat = UUID()
        let saved: [BinderBoxID] = [.asset(flat), .agenda, .asset(car2), .category("documents"), .asset(car1)]
        let grouped = BinderLayout.regrouped(saved, category: "vehicle", members: [.asset(car1), .asset(car2)], grouped: true)
        #expect(grouped == [.asset(flat), .agenda, .category("vehicle"), .category("documents")])
        let split = BinderLayout.regrouped(grouped, category: "vehicle", members: [.asset(car1), .asset(car2)], grouped: false)
        #expect(split == [.asset(flat), .agenda, .asset(car1), .asset(car2), .category("documents")])
        #expect(BinderLayout.regrouped([.agenda], category: "vehicle", members: [.asset(car1)], grouped: true) == [.agenda],
                "An order without them stays; the defaults place the new box")
    }

    @Test func theGroupedBoxShowsHowManyAndTheMostPressingOfThem() {
        let golf = UUID(), logan = UUID()
        let obligations = [
            snapshot("Revizie", kind: .maintenance, due: "2027-03-05", asset: (golf, "VW Golf 2018"), offsets: [14], consequence: .comfort),
            snapshot("ITP", kind: .legal, due: "2026-11-11", asset: (logan, "Dacia Logan"), offsets: [30, 7], consequence: .legal),
            snapshot("RCA", kind: .insurance, due: "2026-12-30", asset: (golf, "VW Golf 2018"), offsets: [30, 7], consequence: .legal),
        ]
        let status = BoxStatus.make(forAssets: [golf, logan], in: obligations, now: today, calendar: calendar)
        let worst = [golf, logan].map { BoxStatus.make(forAsset: $0, in: obligations, now: today, calendar: calendar) }
        #expect(status.entry?.obligation.title == "ITP")
        #expect(worst.contains { $0.entry == status.entry }, "The worst of the boxes they would have each")
        #expect(status.line(counting: 3, of: .car, isSensitive: false, now: today, calendar: calendar) == "3 mașini · ITP · în 9 zile")
        #expect(status.line(counting: 3, of: .car, isSensitive: true, now: today, calendar: calendar) == "3 mașini · Un termen · în 9 zile")
        let calm = BoxStatus.make(forAssets: [golf], in: [], now: today, calendar: calendar)
        #expect(calm.line(counting: 1, of: .plant, isSensitive: false) == "o plantă · totul e în regulă")
    }

    @Test("Counted in the category's words", arguments: [
        (1, SectionNoun?.some(.car), "o mașină"), (2, .car, "2 mașini"), (20, .car, "20 de mașini"),
        (1, .home, "o locuință"), (3, .plant, "3 plante"), (1, .pet, "un animal"), (21, .bike, "21 de biciclete"),
        (2, .espressoMachine, "2 espressoare"), (1, nil, "o secțiune"), (4, nil, "4 secțiuni"),
    ])
    func counts(count: Int, noun: SectionNoun?, text: String) {
        #expect(BoxStatus.count(count, of: noun) == text)
    }

    // MARK: Plants

    @Test func plantsShareABoxAndMayStandInAHome() {
        let plants = BuiltInTemplates.plants.behavior
        #expect(plants.box == .perSection)
        #expect(plants.defaultGrouping == .grouped)
        #expect(plants.mayBelongTo == .home)
        #expect(plants.goesUnderTheOnlyOne)
        #expect(plants.parentPocket == .plants)
        #expect(BuiltInTemplates.home.pockets.contains(.plants), "A home's page lists its plants")
        #expect(BuiltInTemplates.subscription.behavior.mayBelongTo == .home, "As a subscription may")
        #expect(!BuiltInTemplates.subscription.behavior.goesUnderTheOnlyOne, "A phone plan stays on its own")
        #expect(BuiltInTemplates.vehicle.behavior.defaultGrouping == nil)
        #expect(TemplateDefinition.builtInCatalogVersion >= 17)
    }

    @Test func aNewPlantGoesIntoTheOnlyHomeAndStaysInThePlanteBox() throws {
        let context = try makeContext()
        let flat = try add("Apartament Exemplu", BuiltInTemplates.Key.home, in: context)
        _ = try add("Casa exemplu", BuiltInTemplates.Key.home, isExample: true, in: context)
        let plants = try template(BuiltInTemplates.Key.plants, in: context)
        #expect(!plants.isOnHome)
        let model = AddSectionModel(request: .topLevel)
        model.choose(plants)
        #expect(model.parentID == flat.id, "The only home of the person's own, examples apart")
        #expect(model.possibleParents(in: context).map(\.id) == [flat.id])
        model.name = "Ficus"
        let ficus = try model.create(context: context)
        #expect(ficus.parent?.id == flat.id)
        #expect(plants.isOnHome, "It shows in the Plante box, so the category comes back to the binder")
        #expect(AssetActions.offersStandalone(for: ficus), "It can stand on its own again")
        #expect(AssetActions.canMove(ficus))
    }

    @Test func withSeveralHomesOrNoneANewPlantStandsOnItsOwn() throws {
        let context = try makeContext()
        let plants = try template(BuiltInTemplates.Key.plants, in: context)
        let alone = AddSectionModel(request: .topLevel)
        alone.choose(plants)
        #expect(alone.parentID == nil, "No home")

        let flat = try add("Apartament Exemplu", BuiltInTemplates.Key.home, in: context)
        let house = try add("Casa de la țară", BuiltInTemplates.Key.home, in: context)
        let model = AddSectionModel(request: .topLevel)
        model.choose(plants)
        #expect(model.parentID == nil, "Two homes: the person picks one, or none")
        model.name = "Busuioc"
        let basil = try model.create(context: context)
        #expect(basil.parent == nil)
        let all = try context.fetch(FetchDescriptor<Asset>())
        #expect(Set(AssetActions.moveDestinations(for: basil, among: all).map(\.id)) == [flat.id, house.id])
        #expect(!AssetActions.offersStandalone(for: basil), "It already stands on its own")

        let receipt = try AssetActions(context: context).move(basil, to: .asset(house.id))
        #expect(basil.parent?.id == house.id)
        #expect(AssetActions.moveDestinations(for: basil, among: all).map(\.id) == [flat.id])
        try receipt.undo()
        #expect(basil.parent == nil)
    }

    @Test func aCarIsNeverPutUnderAHome() throws {
        let context = try makeContext()
        _ = try add("Apartament Exemplu", BuiltInTemplates.Key.home, in: context)
        let model = AddSectionModel(request: .topLevel)
        model.choose(try template(BuiltInTemplates.Key.vehicle, in: context))
        #expect(model.parentID == nil)
        #expect(model.possibleParents(in: context).isEmpty)
    }

    // MARK: Plants kept before

    @Test func plantsOnTheirOwnAreOfferedToTheOnlyHomeAndMovedOnceApproved() throws {
        let context = try makeContext()
        let flat = try add("Apartament Exemplu", BuiltInTemplates.Key.home, in: context)
        let fern = try add("Ferigă", BuiltInTemplates.Key.plants, in: context)
        let basil = try add("Busuioc", BuiltInTemplates.Key.plants, in: context)
        _ = try add("Plantă exemplu", BuiltInTemplates.Key.plants, isExample: true, in: context)
        var scan = DataRepairScan(context: context, calendar: calendar)
        let findings = try SectionsIntoTheirHomeStep().findings(&scan)
        #expect(findings.count == 2, "One for each plant of the person's own, examples left as they are")
        #expect(!findings.contains { !$0.isFixable }, "Each one can be moved")
        #expect(findings.contains { $0.message == "Trec „Ferigă” la „Apartament Exemplu”? Apare pe pagina locuinței și rămâne în „Plante”." })

        let changed = fern.updatedAt
        try DataRepairs(context: context, calendar: calendar).apply(findings.filter { $0.message.contains("Ferigă") })
        #expect(fern.parent?.id == flat.id)
        #expect(basil.parent == nil, "Only what was approved")
        #expect(fern.updatedAt == changed, "The app's own step gives no change time")
        var again = DataRepairScan(context: context, calendar: calendar)
        #expect(try SectionsIntoTheirHomeStep().findings(&again).map(\.message) == ["Trec „Busuioc” la „Apartament Exemplu”? Apare pe pagina locuinței și rămâne în „Plante”."])
    }

    @Test func withSeveralHomesTheRepairOnlySaysHowAndWithNoneSaysNothing() throws {
        let context = try makeContext()
        let fern = try add("Ferigă", BuiltInTemplates.Key.plants, in: context)
        var none = DataRepairScan(context: context, calendar: calendar)
        #expect(try SectionsIntoTheirHomeStep().findings(&none).isEmpty)

        _ = try add("Apartament Exemplu", BuiltInTemplates.Key.home, in: context)
        _ = try add("Casa de la țară", BuiltInTemplates.Key.home, in: context)
        var scan = DataRepairScan(context: context, calendar: calendar)
        let findings = try SectionsIntoTheirHomeStep().findings(&scan)
        #expect(findings.count == 1)
        #expect(findings.first?.isFixable == false, "Which home is the person's to say")
        #expect(findings.first?.message.contains("Mută la…") == true)
        try DataRepairs(context: context, calendar: calendar).apply(findings)
        #expect(fern.parent == nil)
    }

    @Test func theRepairComesLastWithItsOwnStoredID() {
        let ids = DataRepairs.steps.map { type(of: $0).id }
        let index = ids.firstIndex(of: .sectionsIntoTheirHome)
        #expect(index.map { ids[$0 - 1] } == .estimatedBillReadings, "A new repair is a new step at the end")
        #expect(DataRepairStepID.sectionsIntoTheirHome.rawValue == "sections-into-their-home")
    }

    // MARK: Database version 15

    @Test func versionFifteenOnlyAddsTheChoiceToCategories() throws {
        let fourteen = try #require(NSManagedObjectModel.makeManagedObjectModel(for: DosarSchemaV14.models))
        let fifteen = try #require(NSManagedObjectModel.makeManagedObjectModel(for: DosarSchemaV15.models))
        for (entity, hash) in fourteen.entityVersionHashesByName where entity != "CategoryTemplate" {
            #expect(fifteen.entityVersionHashesByName[entity] == hash, "\(entity) is as version 14 shipped it")
        }
        let before = Set(fourteen.entitiesByName["CategoryTemplate"]?.attributesByName.keys.map { $0 } ?? [])
        let after = try #require(fifteen.entitiesByName["CategoryTemplate"]?.attributesByName)
        #expect(Set(after.keys).subtracting(before) == ["boxGroupingRaw"])
        #expect(after["boxGroupingRaw"]?.isOptional == true, "Optional, as CloudKit needs")
        // The frozen version 14 is version 13 with how a reading was taken, nothing more.
        let thirteen = try #require(NSManagedObjectModel.makeManagedObjectModel(for: DosarSchemaV13.models))
        for (entity, description) in fourteen.entitiesByName {
            let added = Set(description.attributesByName.keys).subtracting(thirteen.entitiesByName[entity]?.attributesByName.keys.map { $0 } ?? [])
            let expected: Set<String> = entity == "MeasurementLog" ? ["basisRaw"] : []
            #expect(added == expected, "\(entity)")
        }
    }

    @Test func aStoreFromVersionFourteenOpensWithEveryCategoryAsTheCatalogSays() throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: "migration-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appending(path: "Dosar-v14.store")
        let edited = noon("2026-10-01")

        // Written by version 14: the cars' category, moved first, and a car with a reading.
        do {
            let schema = Schema(versionedSchema: DosarSchemaV14.self)
            let container = try ModelContainer(for: schema, configurations: [ModelConfiguration(schema: schema, url: url, cloudKitDatabase: .none)])
            let context = ModelContext(container)
            let cars = DosarSchemaV14.CategoryTemplate(key: BuiltInTemplates.Key.vehicle)
            cars.isBuiltIn = true
            cars.homeOrder = 3
            cars.updatedAt = edited
            let car = DosarSchemaV14.Asset(name: "VW Golf 2018", templateKey: BuiltInTemplates.Key.vehicle)
            let reading = DosarSchemaV14.MeasurementLog(name: "Kilometraj", value: 45_724)
            reading.basisRaw = ReadingBasis.read.rawValue
            for model in [cars, car, reading] as [any PersistentModel] { context.insert(model) }
            reading.asset = car
            try context.save()
        }

        let context = ModelContext(try PersistenceController.makeContainer(storeURL: url))
        let cars = try #require(try context.fetch(FetchDescriptor<CategoryTemplate>()).first)
        #expect(cars.homeOrder == 3)
        #expect(cars.updatedAt == edited, "An upgrade isn't a change")
        #expect(cars.boxGroupingRaw == nil, "Nobody chose: the catalog's, a box for each car")
        #expect(try context.fetch(FetchDescriptor<MeasurementLog>()).first?.basis == .read)
        #expect(try context.fetch(FetchDescriptor<Asset>()).first?.name == "VW Golf 2018")
    }
}
