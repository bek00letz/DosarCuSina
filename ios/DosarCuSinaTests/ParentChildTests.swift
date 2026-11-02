import Foundation
import SwiftData
import Testing
@testable import DosarCuSina

@MainActor
@Suite("Assets filed under other assets")
struct ParentChildTests {
    private func setup() throws -> (ModelContext, AssetActions, Asset, Asset, Asset) {
        let context = try makeContext()
        let actions = AssetActions(context: context, calendar: .bucharest, now: { noon("2026-11-02") })
        let store = TemplateStore(context: context)
        let home = try actions.create(name: "Apartament", template: try #require(try store.template(forKey: BuiltInTemplates.Key.home)), values: FieldValues())
        let other = try #require(try store.template(forKey: BuiltInTemplates.Key.other))
        let hood = try actions.create(name: "Hotă", template: other, values: FieldValues(), parent: home)
        let filter = try actions.create(name: "Filtru hotă", template: other, values: FieldValues(), parent: hood)
        return (context, actions, home, hood, filter)
    }

    @Test func childrenAreCountedForTheDeleteQuestion() throws {
        let (_, _, home, hood, _) = try setup()
        #expect(home.childCount == 1)
        #expect(hood.parent?.id == home.id)
        #expect(hood.childCount == 1)
    }

    @Test func deletingAParentKeepsOrDeletesChildrenAsAsked() throws {
        let (context, actions, home, _, _) = try setup()
        try actions.delete(home, children: .keep)
        let kept = try context.fetch(FetchDescriptor<Asset>()).map(\.name).sorted()
        #expect(kept == ["Filtru hotă", "Hotă"])
        #expect(try context.fetch(FetchDescriptor<Asset>()).allSatisfy { $0.name != "Hotă" || $0.parent == nil })

        let (context2, actions2, home2, _, _) = try setup()
        try actions2.delete(home2, children: .delete)
        #expect(try context2.fetchCount(FetchDescriptor<Asset>()) == 0, "Grandchildren go too")
    }

    @Test func loopsAreRefused() throws {
        let (_, actions, home, _, filter) = try setup()
        #expect(throws: AssetActionError.wouldCreateLoop) { try actions.setParent(home, filter) }
        #expect(throws: AssetActionError.wouldCreateLoop) { try actions.setParent(home, home) }
        try actions.setParent(filter, nil)
        #expect(filter.parent == nil)
    }

    @Test func archivesKeepTheLink() throws {
        let source = try makeInMemoryContainer()
        let context = ModelContext(source)
        try TemplateStore(context: context).installBuiltIns()
        let actions = AssetActions(context: context, calendar: .bucharest)
        let other = try #require(try TemplateStore(context: context).template(forKey: BuiltInTemplates.Key.other))
        let home = try actions.create(name: "Casa", template: other, values: FieldValues())
        try actions.create(name: "Centrală", template: other, values: FieldValues(), parent: home)

        let data = try DossierArchiveService(container: source, calendar: .bucharest).exportData()
        let target = try makeInMemoryContainer()
        try DossierArchiveService(container: target, calendar: .bucharest).importArchive(data, mode: .replace)
        let boiler = try #require(try ModelContext(target).fetch(FetchDescriptor<Asset>()).first { $0.name == "Centrală" })
        #expect(boiler.parent?.name == "Casa")
    }
}
