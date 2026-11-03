import Foundation
import SwiftData
import Testing
@testable import DosarCuSina

@MainActor
@Suite("Binder flows")
struct BinderFlowTests {
    @Test func providerDetailsAreUpdatedAndCleaned() throws {
        let context = try makeContext()
        let actions = ProviderActions(context: context)
        let provider = try actions.create(name: "Service Exemplu SRL", trades: [.mechanic], phone: "0700 000 000")
        var details = provider.details
        details.name = "  Service Exemplu SRL  "
        details.phone = "0040 700 111 222"
        details.email = "   "
        details.notes = "Program 8–17"
        details.trades = [ProviderTrade.mechanic.rawValue, ProviderTrade.tyreShop.rawValue]
        try actions.update(provider, with: details)
        #expect(provider.name == "Service Exemplu SRL")
        #expect(provider.phone == "+40700111222")
        #expect(provider.email == nil)
        #expect(provider.notes == "Program 8–17")
        #expect(provider.knownTrades == [.mechanic, .tyreShop])
    }

    @Test func aPhotoIsSetAndRemovedThroughTheEngine() throws {
        let context = try makeContext()
        let template = try #require(try TemplateStore(context: context).template(forKey: BuiltInTemplates.Key.pet))
        let pet = try AssetActions(context: context).create(name: "PawPaw", template: template, values: FieldValues())
        try AssetActions(context: context).setPhoto(pet, Data([1, 2, 3]))
        #expect(pet.photoData == Data([1, 2, 3]))
        try AssetActions(context: context).setPhoto(pet, nil)
        #expect(pet.photoData == nil)
    }

    @Test func suggestedNamesComeFromWhatWasTyped() {
        var values = FieldValues()
        values["vehicle.make"] = .text("Volkswagen")
        values["vehicle.model"] = .text("Golf")
        values["vehicle.year"] = .number(2018)
        #expect(AddSectionModel.suggestedName(values: values, definition: BuiltInTemplates.vehicle) == "Volkswagen Golf")
        var plateOnly = FieldValues()
        plateOnly["vehicle.plate"] = .text("B-123-ABC")
        #expect(AddSectionModel.suggestedName(values: plateOnly, definition: BuiltInTemplates.vehicle) == "B-123-ABC")
        #expect(AddSectionModel.suggestedName(values: FieldValues(), definition: BuiltInTemplates.vehicle) == BuiltInTemplates.vehicle.name)
    }

    @Test func addingACarCreatesItWithTheChosenObligations() throws {
        let context = try makeContext()
        let model = AddSectionModel(request: .topLevel)
        model.choose(try #require(try TemplateStore(context: context).template(forKey: BuiltInTemplates.Key.vehicle)))
        model.values["vehicle.make"] = .text("Volkswagen")
        model.values["vehicle.model"] = .text("Golf")
        model.planObligations(context: context)
        #expect(!model.planned.isEmpty)
        // ITP asks for a date: until one is given, it blocks finishing.
        #expect(model.missingDates.contains { $0.blueprint.key == "vehicle.itp" })
        for index in model.planned.indices where model.planned[index].firstDue == nil {
            model.planned[index].isSelected = model.planned[index].blueprint.key == "vehicle.itp"
            if model.planned[index].isSelected { model.planned[index].firstDue = CalendarDay("2027-05-01") }
        }
        #expect(model.missingDates.isEmpty)
        let car = try model.create(context: context)
        #expect(car.name == "Volkswagen Golf")
        #expect(car.obligations?.contains { $0.blueprintKey == "vehicle.itp" } == true)
    }

    @Test func aCustomSectionCreatesItsCategoryOnlyWhenFinished() throws {
        let context = try makeContext()
        let before = try TemplateStore(context: context).all().count
        let model = AddSectionModel(request: .topLevel)
        model.chooseCustom(CustomSectionDraft(name: "Barca", symbol: "sailboat.fill", switches: CategorySwitches(hasDocuments: false, hasBills: true)))
        #expect(try TemplateStore(context: context).all().count == before)
        let boat = try model.create(context: context)
        let template = try #require(try TemplateStore(context: context).template(forKey: boat.templateKey))
        #expect(template.isCustom)
        #expect(template.name == "Barca")
        #expect(template.symbol == "sailboat.fill")
        #expect(template.pockets == SectionPocket.ordered(CategorySwitches.basePockets + [.subscriptions]), "What its switches say")
        #expect(template.behavior.role == .home)
        #expect(boat.name == "Barca")
    }

    @Test func aSectionOfAHiddenCategoryBringsItBackHome() throws {
        let context = try makeContext()
        let bike = try #require(try TemplateStore(context: context).template(forKey: BuiltInTemplates.Key.bike))
        #expect(!bike.isOnHome)
        let model = AddSectionModel(request: .topLevel)
        model.choose(bike)
        model.name = "Bicicleta"
        _ = try model.create(context: context)
        #expect(bike.isOnHome)
    }

    @Test func childrenAreFiledUnderTheirParent() throws {
        let context = try makeContext()
        let store = TemplateStore(context: context)
        let home = try AssetActions(context: context).create(name: "Apartament", template: try #require(try store.template(forKey: BuiltInTemplates.Key.home)), values: FieldValues())
        let model = AddSectionModel(request: AddSectionRequest(parentID: home.id, templateKey: BuiltInTemplates.Key.tenancy))
        model.choose(try #require(try store.template(forKey: BuiltInTemplates.Key.tenancy)))
        model.name = "Chiriaș Exemplu"
        let tenancy = try model.create(context: context)
        #expect(tenancy.parent?.id == home.id)
        #expect(home.childCount == 1)
        // A tenancy never gets a box of its own, so its category stays off the home screen.
        #expect(try store.template(forKey: BuiltInTemplates.Key.tenancy)?.isOnHome == false)
    }

    @Test func savingRejectsTextItsFieldTypeRefuses() {
        var values = FieldValues()
        values["vehicle.claimsPhone"] = .text("123")
        #expect(!FieldValuesCheck.canSave(values, fields: BuiltInTemplates.vehicle.allFields))
        // Warnings (a VIN that looks short) never block saving.
        values["vehicle.claimsPhone"] = .text("0700 000 000")
        values["vehicle.vin"] = .text("123")
        #expect(FieldValuesCheck.canSave(values, fields: BuiltInTemplates.vehicle.allFields))
    }

    @Test func historyLinesShowTheLastTimeOfEachPart() throws {
        let context = try makeContext()
        let template = try #require(try TemplateStore(context: context).template(forKey: BuiltInTemplates.Key.vehicle))
        var values = FieldValues()
        values["vehicle.odometer"] = .number(142_500)
        let car = try AssetActions(context: context).create(name: "VW Golf", template: template, values: values)
        let key = try #require(template.components.first?.key)
        _ = try HistoryActions(context: context).recordVisit(
            on: car,
            occurredAt: noon("2025-03-14"),
            checklist: [.init(componentKey: key, cost: Money(420))],
            odometer: 124_300,
            calendar: .bucharest
        )
        let lines = HistoryLines.make(asset: car, definition: template.definition, now: noon("2026-11-02"))
        let line = try #require(lines.first)
        #expect(line.title == template.components.first?.name)
        // Digit grouping follows the phone's region; the distance is the same.
        #expect(line.detail.hasPrefix("acum 18"))
        #expect(line.detail.contains("200 km · "))
    }
}
