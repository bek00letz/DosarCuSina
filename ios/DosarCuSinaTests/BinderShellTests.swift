import Foundation
import Testing
@testable import DosarCuSina

@Suite("Shell routing")
struct ShellRoutingTests {
    let id = UUID()

    @Test func tabsOpenAtTheirRoot() {
        #expect(ShellRouting.plan(for: .home) == ShellRoutePlan(tab: .dosar, path: []))
        #expect(ShellRouting.plan(for: .upcoming) == ShellRoutePlan(tab: .upcoming, path: []))
        #expect(ShellRouting.plan(for: .search) == ShellRoutePlan(tab: .search, path: []))
        #expect(ShellRouting.plan(for: .intake) == ShellRoutePlan(tab: .add, path: []))
    }

    @Test func recordsOpenOnTheRightTab() {
        #expect(ShellRouting.plan(for: .asset(id)) == ShellRoutePlan(tab: .dosar, path: [.asset(id)]))
        #expect(ShellRouting.plan(for: .obligation(id)) == ShellRoutePlan(tab: .upcoming, path: [.obligation(id)]))
        #expect(ShellRouting.plan(for: .historyEntry(id)) == ShellRoutePlan(tab: .dosar, path: [.historyEntry(id)]))
        #expect(ShellRouting.plan(for: .document(id)) == ShellRoutePlan(tab: .dosar, path: [.document(id)]))
        #expect(ShellRouting.plan(for: .category("documents")) == ShellRoutePlan(tab: .dosar, path: [.category("documents")]))
    }

    @Test func providersOpenInsideTheAgenda() {
        #expect(ShellRouting.plan(for: .agenda) == ShellRoutePlan(tab: .dosar, path: [.agenda]))
        #expect(ShellRouting.plan(for: .provider(id)) == ShellRoutePlan(tab: .dosar, path: [.agenda, .provider(id)]))
    }

    @Test func visitsAndSettingsAreSheets() {
        #expect(ShellRouting.plan(for: .addVisit(id)) == ShellRoutePlan(tab: .dosar, path: [.asset(id)], sheet: .addVisit(id)))
        #expect(ShellRouting.plan(for: .settings(.backup)) == ShellRoutePlan(tab: .dosar, path: [], sheet: .settings(.backup)))
        #expect(ShellRouting.plan(for: .settings(nil)).sheet == .settings(nil))
    }

    @Test func deepLinksReachTheSamePlans() throws {
        let url = DeepLink.url(for: .provider(id))
        let route = try #require(DeepLink.route(from: url))
        #expect(ShellRouting.plan(for: route).path == [.agenda, .provider(id)])
        let link = try #require(URL(string: "dosarcusina://obligation/\(id.uuidString.lowercased())"))
        let widget = try #require(DeepLink.route(from: link))
        #expect(ShellRouting.plan(for: widget).tab == .upcoming)
    }

    @MainActor
    @Test func routerReplacesThePathAndSelectingTheSameTabPopsToRoot() {
        let router = ShellRouter()
        router.open(.provider(id))
        #expect(router.tab == .dosar)
        #expect(router.dosarPath.count == 2)
        router.select(.dosar)
        #expect(router.dosarPath.isEmpty)
        router.open(.obligation(id))
        #expect(router.tab == .upcoming)
        #expect(router.upcomingPath.count == 1)
        #expect(router.dosarPath.isEmpty)
    }

    @MainActor
    @Test func routesWithoutSheetsCloseTheOpenSheet() {
        let router = ShellRouter()
        router.open(.settings(.notifications))
        #expect(router.sheet == .settings(.notifications))
        router.open(.asset(id))
        #expect(router.sheet == nil)
    }
}

@Suite("Binder grid layout")
struct BinderLayoutTests {
    let car = UUID(), flat = UUID(), cat = UUID(), tenancy = UUID(), member = UUID(), orphan = UUID()

    var templates: [BinderLayout.TemplateInfo] {
        [
            .init(key: "vehicle", homeOrder: 0, isOnHome: true),
            .init(key: "home", homeOrder: 1, isOnHome: true),
            .init(key: "documents", homeOrder: 2, isOnHome: true, box: BuiltInTemplates.documents.behavior.box),
            .init(key: "pet", homeOrder: 3, isOnHome: true),
            .init(key: "purchase", homeOrder: 4, isOnHome: true, box: BuiltInTemplates.purchase.behavior.box),
            .init(key: "subscription", homeOrder: 5, isOnHome: true, box: BuiltInTemplates.subscription.behavior.box),
            .init(key: "bike", homeOrder: 6, isOnHome: false),
            .init(key: "tenancy", homeOrder: 7, isOnHome: false, box: BuiltInTemplates.tenancy.behavior.box),
            .init(key: "member", homeOrder: 8, isOnHome: false, box: BuiltInTemplates.member.behavior.box),
        ]
    }

    var assets: [BinderLayout.AssetInfo] {
        [
            .init(id: flat, templateKey: "home", isTopLevel: true, createdAt: Date(timeIntervalSince1970: 2)),
            .init(id: car, templateKey: "vehicle", isTopLevel: true, createdAt: Date(timeIntervalSince1970: 1)),
            .init(id: cat, templateKey: "pet", isTopLevel: true, createdAt: Date(timeIntervalSince1970: 3)),
            .init(id: tenancy, templateKey: "tenancy", isTopLevel: false, createdAt: Date(timeIntervalSince1970: 4)),
            .init(id: member, templateKey: "member", isTopLevel: true, createdAt: Date(timeIntervalSince1970: 5)),
            .init(id: orphan, templateKey: "custom.gone", isTopLevel: true, createdAt: Date(timeIntervalSince1970: 6)),
        ]
    }

    @Test func defaultOrderFollowsHomeOrderWithCategoryBoxesAndAgendaLast() {
        let order = BinderLayout.defaultOrder(templates: templates, assets: assets)
        #expect(order == [
            .asset(car), .asset(flat), .category("documents"), .asset(cat),
            .category("purchase"), .category("subscription"), .asset(orphan), .agenda,
        ])
    }

    @Test func hiddenCategoriesAndNestedRecordsGetNoBox() {
        let bike = UUID()
        let order = BinderLayout.defaultOrder(templates: templates, assets: assets + [.init(id: bike, templateKey: "bike", isTopLevel: true, createdAt: .now)])
        #expect(!order.contains(.asset(bike)))
        #expect(!order.contains(.asset(tenancy)))
        #expect(!order.contains(.asset(member)))
    }

    @Test func savedOrderWinsAndNewBoxesSlotInNextToTheirNeighbours() {
        let defaults: [BinderBoxID] = [.asset(car), .asset(flat), .category("documents"), .agenda]
        let saved: [BinderBoxID] = [.agenda, .asset(flat), .asset(car), .asset(orphan)]
        let merged = BinderLayout.merge(saved: saved, defaults: defaults)
        // The deleted box drops out; Acte follows the flat, its default neighbour.
        #expect(merged == [.agenda, .asset(flat), .category("documents"), .asset(car)])
        #expect(BinderLayout.merge(saved: [], defaults: defaults) == defaults)
    }

    @Test func movingABoxOntoAnotherTakesItsPlace() {
        let order: [BinderBoxID] = [.asset(car), .asset(flat), .asset(cat), .agenda]
        #expect(BinderLayout.move(.agenda, onto: .asset(car), in: order) == [.agenda, .asset(car), .asset(flat), .asset(cat)])
        #expect(BinderLayout.move(.asset(car), onto: .asset(cat), in: order) == [.asset(flat), .asset(cat), .asset(car), .agenda])
        #expect(BinderLayout.move(.asset(car), by: -1, in: order) == order)
        #expect(BinderLayout.move(.asset(flat), by: 1, in: order) == [.asset(car), .asset(cat), .asset(flat), .agenda])
    }

    @Test func storageKeysRoundTrip() {
        for id in [BinderBoxID.asset(car), .category("documents"), .agenda] {
            #expect(BinderBoxID(storageKey: id.storageKey) == id)
        }
        #expect(BinderBoxID(storageKey: "category:") == nil)
        #expect(BinderBoxID(storageKey: "asset:nope") == nil)
    }

    @MainActor
    @Test func theStoreKeepsTheOrderOnThisDevice() throws {
        let defaults = try #require(UserDefaults(suiteName: "binder.layout.\(UUID().uuidString)"))
        let store = BinderLayoutStore(defaults: defaults)
        store.update([.agenda, .asset(car)])
        store.persist()
        let reopened = BinderLayoutStore(defaults: defaults)
        #expect(reopened.saved == [.agenda, .asset(car)])
        reopened.reset()
        #expect(BinderLayoutStore(defaults: defaults).saved.isEmpty)
    }
}

@Suite("Agenda grouping")
struct AgendaGroupingTests {
    func person(_ name: String, trades: [ProviderTrade], sections: [String] = [], again: Bool? = nil, rating: Double? = nil) -> AgendaGroups.Person {
        AgendaGroups.Person(id: UUID(), name: name, trades: trades.map(\.rawValue), sections: sections, wouldCallAgain: again, rating: rating)
    }

    @Test func byTradeInCatalogOrderBestFirstAndOthersLast() {
        let mechanicA = person("Service Exemplu SRL", trades: [.mechanic], rating: 4)
        let mechanicB = person("Atelier Beta", trades: [.mechanic], again: true, rating: 3)
        let plumber = person("Ion Exemplu", trades: [.plumber, .handyman])
        let nobody = person("Vecinul", trades: [])
        let groups = AgendaGroups.byTrade([mechanicA, plumber, nobody, mechanicB])
        #expect(groups.map(\.title) == [ProviderTrade.mechanic.title, ProviderTrade.plumber.title, ProviderTrade.handyman.title, ProviderTrade.other.title])
        // Would call again beats a higher rating.
        #expect(groups[0].providerIDs == [mechanicB.id, mechanicA.id])
        #expect(groups[2].providerIDs == [plumber.id])
        #expect(groups[3].providerIDs == [nobody.id])
    }

    @Test func bySectionAlphabeticalWithLooseOnesLast() {
        let vet = person("Clinica Exemplu", trades: [.vet], sections: ["PawPaw"])
        let mechanic = person("Service Exemplu SRL", trades: [.mechanic], sections: ["VW Golf", "Casa"])
        let loose = person("Ion Exemplu", trades: [.accountant])
        let groups = AgendaGroups.bySection([vet, mechanic, loose])
        #expect(groups.map(\.title) == ["Casa", "PawPaw", "VW Golf", "Fără secțiune"])
        #expect(groups.last?.providerIDs == [loose.id])
    }
}
