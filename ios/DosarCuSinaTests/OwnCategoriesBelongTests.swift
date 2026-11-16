import Foundation
import SwiftData
import Testing
@testable import DosarCuSina

/// A category of one's own: „O cutie pentru toate” is the category's grouping, the one choice a
/// box's menu makes too; and „Ține de…” files its sections under a home, a car or a person, as
/// plants stand in a home: a pocket named after it on that page, added from there, moved with
/// „Mută la…”, still in its own box.
@MainActor
@Suite("Categories of one's own that belong somewhere")
struct OwnCategoriesBelongTests {
    let calendar = Calendar.bucharest

    private func template(_ key: String, in context: ModelContext) throws -> CategoryTemplate {
        try #require(try TemplateStore(context: context).template(forKey: key))
    }

    private func actions(_ context: ModelContext) -> AssetActions {
        AssetActions(context: context, calendar: calendar, now: { noon("2026-11-16") })
    }

    private func add(_ name: String, _ key: String, under parent: Asset? = nil, in context: ModelContext) throws -> Asset {
        try actions(context).create(name: name, template: try template(key, in: context), values: FieldValues(), parent: parent)
    }

    private func contents(of asset: Asset, in context: ModelContext) throws -> PocketContents {
        let templates = try context.fetch(FetchDescriptor<CategoryTemplate>())
        let definition = try #require(templates.first { $0.key == asset.templateKey }).definition
        return PocketContents(asset: asset, definition: definition, templates: templates, providers: [])
    }

    /// The built-in category that plays each part a category of one's own can belong to.
    private func parentKey(_ role: CategoryBehavior.Role) -> String {
        switch role {
        case .home: BuiltInTemplates.Key.home
        case .vehicle: BuiltInTemplates.Key.vehicle
        default: BuiltInTemplates.Key.member
        }
    }

    // MARK: One box is the grouping

    @Test func oneBoxForAllIsTheCategorysGroupingBothWays() throws {
        let context = try makeContext()
        let store = TemplateStore(context: context)
        let boats = try store.createCustom(name: "Bărci", symbol: "sailboat.fill", switches: CategorySwitches(grouping: .grouped))
        #expect(boats.behavior.box == .perSection, "Never a box of the whole category's again")
        #expect(boats.chosenGrouping == .grouped && boats.groupsSections)
        #expect(CategorySwitches(reading: boats).grouping == .grouped)

        // A box's menu changes the same choice the form reads.
        try store.setGrouping(boats, .separate)
        #expect(CategorySwitches(reading: boats).grouping == .separate)

        // The form changes the same choice a box's menu reads, as one step with its undo.
        let receipt = try store.editCustom(boats, name: "Bărci", symbol: "sailboat.fill", switches: CategorySwitches(grouping: .grouped), changingDeadlines: false)
        #expect(boats.chosenGrouping == .grouped)
        #expect(boats.groupingOffer(sections: 3) == .separate, "Split again from the box, as any other")
        try receipt.undo()
        #expect(boats.chosenGrouping == .separate)

        let alone = try store.createCustom(name: "Piane", symbol: "music.note", switches: .defaults)
        #expect(alone.chosenGrouping == nil && alone.grouping == .separate, "One each, nothing chosen yet")
    }

    @Test func anOlderOneBoxBecomesTheGroupingAndLooksTheSame() throws {
        let context = try makeContext()
        let store = TemplateStore(context: context)
        let tools = try store.createCustom(name: "Unelte", symbol: "hammer", switches: .defaults)
        let split = try store.createCustom(name: "Rulote", symbol: "car.side.rear.open", switches: CategorySwitches(hasBills: true))
        let likeWarranties = try store.createCustom(name: "Scule", symbol: "wrench.and.screwdriver.fill", switches: .defaults)
        try UnitOfWork.perform(in: context) {
            // As an earlier version kept „O cutie pentru toate”.
            tools.behavior.box = .wholeCategory
            split.behavior.box = .wholeCategory
            split.chosenGrouping = .separate
            // As a backup brings one that behaves like Garanții.
            likeWarranties.behavior = CategoryBehavior(box: .wholeCategory, listing: .byWarranty, visit: .none)
            try UnitOfWork.save(context)
        }
        #expect(CategorySwitches(reading: tools).grouping == .grouped, "Read as one box until it is moved")
        _ = try add("Bormașina", tools.key, in: context)
        let changed = tools.updatedAt

        _ = try DataRepairs(context: context, calendar: calendar).detect()
        #expect(tools.behavior.box == .perSection && tools.chosenGrouping == .grouped && tools.groupsSections, "The same one box")
        #expect(split.behavior.box == .perSection && split.chosenGrouping == .separate, "A grouping chosen already stays")
        #expect(split.behavior.role == .home, "Its bills' part stays")
        #expect(likeWarranties.behavior.box == .wholeCategory, "One that behaves like Garanții keeps its box")
        #expect(CategorySwitches(reading: likeWarranties).grouping == .grouped)
        try store.editCustom(likeWarranties, name: "Scule", symbol: "wrench.and.screwdriver.fill", switches: CategorySwitches(grouping: .grouped), changingDeadlines: false)
        #expect(likeWarranties.behavior.box == .wholeCategory, "Asked for one box, it keeps the one it has")
        try store.editCustom(likeWarranties, name: "Scule", symbol: "wrench.and.screwdriver.fill", switches: CategorySwitches(grouping: .separate), changingDeadlines: false)
        #expect(likeWarranties.behavior.box == .perSection && !likeWarranties.groupsSections, "Asked for a box each, it gets them")
        #expect(tools.updatedAt == changed, "Nothing anyone sees changed: no change time")
        let documents = try template(BuiltInTemplates.Key.documents, in: context)
        #expect(documents.behavior.box == .wholeCategory, "A built-in keeps the catalog's box")
        #expect(DataRepairs.step(.ownCategoryBoxes).runsByItself)
        #expect(DataRepairStepID.ownCategoryBoxes.rawValue == "own-category-boxes")
        #expect(DataRepairs.steps.map { type(of: $0).id }.contains(.ownCategoryBoxes))
        #expect(try OwnCategoryBoxesStep().migrate(in: context) == 0, "Twice is once")

        let info = BinderLayout.TemplateInfo(tools)
        let boxes = BinderLayout.defaultOrder(templates: [info], assets: try context.fetch(FetchDescriptor<Asset>()).map(BinderLayout.AssetInfo.init), hasContacts: false)
        #expect(boxes == [.category(tools.key)], "One box for the category, as before")
    }

    // MARK: Ține de…

    @Test func theChoicesAreThePartsTheBinderPlays() throws {
        let context = try makeContext()
        let all = try TemplateStore(context: context).all()
        #expect(CategorySwitches.belongingChoices(among: all) == [.home, .vehicle, .holder])
        let homesOnly = all.filter { $0.behavior.role == .home }
        #expect(CategorySwitches.belongingChoices(among: homesOnly) == [.home])
        #expect(CategorySwitches.belongingChoices(among: homesOnly, current: .vehicle) == [.home, .vehicle], "What it says stays offered")
        #expect(try template(BuiltInTemplates.Key.vehicle, in: context).behavior.role == .vehicle, "A car plays a car's part")
        #expect(BelongingWording.option(.home) == "O locuință")
        #expect(BelongingWording.option(.vehicle) == "O mașină")
        #expect(BelongingWording.option(.holder) == "O persoană")
    }

    @Test(arguments: CategoryBehavior.Role.parents)
    func itsSectionsShowAddAndMoveOnTheParentsPage(_ role: CategoryBehavior.Role) throws {
        let context = try makeContext()
        let tyres = try TemplateStore(context: context).createCustom(
            name: "Anvelope", symbol: "circle.circle", switches: CategorySwitches(belongsTo: role, grouping: .grouped))
        let first = try add("Primul", parentKey(role), in: context)
        let pocket = PagePocket.category(key: tyres.key, name: "Anvelope")

        // Empty: folded into „Adaugă…”, with its own words.
        var layout = try contents(of: first, in: context).layout(pockets: try template(parentKey(role), in: context).definition.pockets, folds: true)
        let addition = try #require(layout.additions.first { $0.pocket == pocket })
        #expect(addition == .child(pocket, templateKey: tyres.key))
        #expect(addition.title == "Adaugă în „Anvelope”")
        #expect(addition.menuDetail == nil, "Its title names the pocket already")
        #expect(!layout.shown.contains(pocket))

        // Added from there: filed under this page's section, in one step.
        let model = AddSectionModel(request: AddSectionRequest(parentID: first.id, templateKey: tyres.key))
        model.choose(tyres)
        model.name = "Anvelope de iarnă"
        let winter = try model.create(context: context)
        #expect(winter.parent?.id == first.id)

        layout = try contents(of: first, in: context).layout(pockets: try template(parentKey(role), in: context).definition.pockets, folds: true)
        #expect(layout.shown.contains(pocket), "A pocket named after the category, once it holds something")
        let listed = layout.shown.compactMap(\.listedPocket)
        if let documents = layout.shown.firstIndex(of: .listed(.documents)) {
            #expect(layout.shown.firstIndex(of: pocket).map { $0 < documents } == true, "Before Acte, after the catalog's own")
        }
        #expect(listed == SectionPocket.ordered(listed))

        // Still in its own box, wherever it is filed.
        #expect(tyres.hasBox(forSectionUnder: first))
        let assets = try context.fetch(FetchDescriptor<Asset>())
        let order = BinderLayout.defaultOrder(templates: [BinderLayout.TemplateInfo(tyres)],
                                              assets: assets.filter { $0.templateKey == tyres.key }.map(BinderLayout.AssetInfo.init), hasContacts: false)
        #expect(order == [.category(tyres.key)])

        // „Mută la…”: another of the same part, or on its own.
        let second = try add("Al doilea", parentKey(role), in: context)
        let everything = try context.fetch(FetchDescriptor<Asset>())
        #expect(AssetActions.moveDestinations(for: winter, among: everything).map(\.id) == [second.id])
        #expect(AssetActions.offersStandalone(for: winter))
        let receipt = try actions(context).move(winter, to: .asset(second.id))
        #expect(winter.parent?.id == second.id)
        try receipt.undo()
        #expect(winter.parent?.id == first.id)
        try actions(context).move(winter, to: .standalone)
        #expect(winter.parent == nil)
    }

    @Test(arguments: CategoryBehavior.Role.parents)
    func withTheOnlyOneANewSectionGoesUnderIt(_ role: CategoryBehavior.Role) throws {
        let context = try makeContext()
        var draft = CustomSectionDraft()
        draft.name = "Anvelope"
        draft.switches.belongsTo = role
        let none = AddSectionModel(request: .topLevel)
        none.chooseCustom(draft, in: context)
        #expect(none.parentID == nil, "None to go under")

        let only = try add("Singurul", parentKey(role), in: context)
        let model = AddSectionModel(request: .topLevel)
        model.chooseCustom(draft, in: context)
        #expect(model.parentID == only.id)
        #expect(model.possibleParents(in: context).map(\.id) == [only.id])
        #expect(model.belongsTo == role)
        let made = try model.create(context: context)
        #expect(made.parent?.id == only.id)

        // A second category's section, once it exists, is offered the only one too.
        let category = try #require(try TemplateStore(context: context).template(forKey: made.templateKey))
        let again = AddSectionModel(request: .topLevel)
        again.choose(category)
        #expect(again.parentID == only.id)

        _ = try add("Încă unul", parentKey(role), in: context)
        let several = AddSectionModel(request: .topLevel)
        several.choose(category)
        #expect(several.parentID == nil, "With several, the person picks")
    }

    @Test func belongingToNothingAgainBringsItsSectionsBackOnTheirOwn() throws {
        let context = try makeContext()
        let store = TemplateStore(context: context)
        let tyres = try store.createCustom(name: "Anvelope", symbol: "circle.circle", switches: CategorySwitches(belongsTo: .vehicle))
        let car = try add("VW Golf 2018", BuiltInTemplates.Key.vehicle, in: context)
        let winter = try add("Anvelope de iarnă", tyres.key, under: car, in: context)

        let receipt = try store.editCustom(tyres, name: "Anvelope", symbol: "circle.circle", switches: CategorySwitches(), changingDeadlines: false)
        #expect(winter.parent == nil, "Nowhere would list it under the car now")
        #expect(try contents(of: car, in: context).categoryPockets.isEmpty)
        try receipt.undo()
        #expect(winter.parent?.id == car.id)
        #expect(tyres.behavior.mayBelongTo == .vehicle)

        // Another part: off the car, ready for a home.
        try store.editCustom(tyres, name: "Anvelope", symbol: "circle.circle", switches: CategorySwitches(belongsTo: .home), changingDeadlines: false)
        #expect(winter.parent == nil)
    }

    @Test func standingSectionsAreSuggestedTheOnlyOneInItsWords() throws {
        let context = try makeContext()
        let store = TemplateStore(context: context)
        let tyres = try store.createCustom(name: "Anvelope", symbol: "circle.circle", switches: .defaults)
        let winter = try add("Anvelope de iarnă", tyres.key, in: context)
        let car = try add("VW Golf 2018", BuiltInTemplates.Key.vehicle, in: context)
        try store.editCustom(tyres, name: "Anvelope", symbol: "circle.circle", switches: CategorySwitches(belongsTo: .vehicle), changingDeadlines: false)

        var scan = DataRepairScan(context: context, calendar: calendar)
        let findings = try SectionsIntoTheirHomeStep().findings(&scan)
        #expect(findings.map(\.message) == ["Trec „Anvelope de iarnă” la „VW Golf 2018”? Apare pe pagina mașinii și rămâne în „Anvelope”."])
        try DataRepairs(context: context, calendar: calendar).apply(findings)
        #expect(winter.parent?.id == car.id)
    }

    // MARK: Built-ins as they were

    @Test func plantsAndSubscriptionsKeepTheCatalogsPockets() throws {
        let context = try makeContext()
        let home = try add("Apartament Exemplu", BuiltInTemplates.Key.home, in: context)
        let car = try add("VW Golf 2018", BuiltInTemplates.Key.vehicle, in: context)
        let homePockets = try contents(of: home, in: context)
        #expect(homePockets.categoryPockets.isEmpty, "Plants and subscriptions show in the catalog's pockets")
        #expect(homePockets.pockets(listing: BuiltInTemplates.home.pockets) == BuiltInTemplates.home.pockets.map(PagePocket.listed))
        #expect(try contents(of: car, in: context).categoryPockets.isEmpty)
        let plants = BuiltInTemplates.plants.behavior
        #expect(plants.parentPocket == .plants && plants.mayBelongTo == .home && !plants.hasPocketOfItsOwn)
        #expect(!BuiltInTemplates.subscription.behavior.hasPocketOfItsOwn)

        let fern = try add("Ferigă", BuiltInTemplates.Key.plants, under: home, in: context)
        let layout = try contents(of: home, in: context).layout(pockets: BuiltInTemplates.home.pockets, folds: true)
        #expect(layout.shown.contains(.listed(.plants)))
        #expect(AssetActions.offersStandalone(for: fern))
        #expect(PagePocket.ordered(listed: [.documents, .plants, .upcoming], categories: [.category(key: "custom.x", name: "X")])
                == [.listed(.upcoming), .listed(.plants), .category(key: "custom.x", name: "X"), .listed(.documents)])
    }
}
