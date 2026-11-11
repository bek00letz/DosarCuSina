import Foundation
import SwiftData
import Testing
@testable import DosarCuSina

/// A form saves only what was changed in it (`ThreeWay`), so another device's change made
/// meanwhile stays.
@MainActor
@Suite("Forms save what changed in them")
struct FormsSaveWhatChangedTests {
    private let today = CalendarDay("2026-11-11")

    private func template(_ key: String, in context: ModelContext) throws -> CategoryTemplate {
        try #require(try TemplateStore(context: context).template(forKey: key))
    }

    private func declarations(in context: ModelContext) throws -> [Obligation] {
        let key = HouseholdRules.rentalDeclarationKey
        return try context.fetch(FetchDescriptor<Obligation>(predicate: #Predicate { $0.blueprintKey == key }))
    }

    private func declaration(in context: ModelContext) -> Obligation {
        let blueprint = HouseholdRules.rentalDeclaration
        let obligation = Obligation(title: blueprint.title, kind: blueprint.kind, dueDay: CalendarDay("2027-05-25"),
                                    recurrence: blueprint.recurrence, reminders: blueprint.reminders)
        obligation.blueprintKey = blueprint.key
        context.insert(obligation)
        return obligation
    }

    // MARK: A form saves what changed in it

    private func makeCar(in context: ModelContext) throws -> Asset {
        var values = FieldValues()
        values[VehicleFields.plate] = .text("B-123-ABC")
        values[VehicleFields.make] = .text("VW")
        values[VehicleFields.model] = .text("Golf")
        return try AssetActions(context: context, calendar: .bucharest, now: { noon("2026-11-02") })
            .create(name: "VW Golf 2018", template: try template(BuiltInTemplates.Key.vehicle, in: context), values: values)
    }

    /// Another device's change to the car, as iCloud leaves it in the store.
    private func elsewhere(_ car: Asset, in context: ModelContext, _ change: (Asset) -> Void) throws {
        change(car)
        try context.save()
    }

    @Test("A form opened before another device's change keeps that change and adds its own")
    func differentFieldsBothStay() throws {
        let context = try makeContext()
        let car = try makeCar(in: context)
        let start = AssetActions.SectionEditStart(car)
        var draft = car.values
        draft[VehicleFields.plate] = .text("B-456-DEF")

        try elsewhere(car, in: context) { car in
            var values = car.values
            values[VehicleFields.model] = .text("Golf Variant")
            values[VehicleFields.make] = nil
            car.values = values
            car.name = "VW Golf de familie"
            car.notes = "Garaj"
        }
        try AssetActions(context: context, calendar: .bucharest).update(car, name: start.name, values: draft, notes: start.notes, startedFrom: start)

        #expect(car.values[VehicleFields.plate]?.textValue == "B-456-DEF", "The person's change")
        #expect(car.values[VehicleFields.model]?.textValue == "Golf Variant", "The other device's change stays")
        #expect(car.values[VehicleFields.make] == nil, "A field cleared on the other device stays cleared")
        #expect(car.name == "VW Golf de familie", "A name the form didn't change keeps the other device's")
        #expect(car.notes == "Garaj")
    }

    @Test("The same field changed on both: the later save, the person's, wins")
    func theSameFieldTakesTheLaterSave() throws {
        let context = try makeContext()
        let car = try makeCar(in: context)
        let start = AssetActions.SectionEditStart(car)
        var draft = car.values
        draft[VehicleFields.plate] = .text("B-456-DEF")
        try elsewhere(car, in: context) { car in
            var values = car.values
            values[VehicleFields.plate] = .text("B-999-XYZ")
            car.values = values
        }
        try AssetActions(context: context, calendar: .bucharest).update(car, name: start.name, values: draft, notes: start.notes, startedFrom: start)
        #expect(car.values[VehicleFields.plate]?.textValue == "B-456-DEF")
    }

    @Test("Rows under Date importante: a row added elsewhere stays, and two values of one row both stay")
    func rowsMeetRowByRow() throws {
        let context = try makeContext()
        let car = try makeCar(in: context)
        let actions = AssetActions(context: context, calendar: .bucharest)
        let row = CustomFact(label: "Garaj", value: "Nivelul 1")
        try actions.setCustomFacts(car, [row])
        let start = car.customFacts

        try elsewhere(car, in: context) { car in
            var facts = car.customFacts
            facts[0].label = "Parcare"
            facts.append(CustomFact(label: "Cod portă", value: "Exemplu"))
            car.customFacts = facts
        }
        var edited = start
        edited[0].value = "Nivelul 2"
        try actions.setCustomFacts(car, edited, startedFrom: start)

        let facts = car.customFacts
        #expect(facts.count == 2, "The row added on the other device stays")
        #expect(facts.first { $0.id == row.id }?.label == "Parcare", "Its label from the other device")
        #expect(facts.first { $0.id == row.id }?.value == "Nivelul 2", "Its value from this form")
    }

    @Test("A firm's card saves only the details changed in it")
    func aFirmsDetailsMeet() throws {
        let context = try makeContext()
        let actions = ProviderActions(context: context)
        let firm = try actions.create(name: "Service Exemplu SRL", trades: [.mechanic])
        let start = firm.details
        // The other device adds the phone meanwhile.
        firm.phone = "0721 000 000"
        try context.save()

        var draft = start
        draft.email = "nume@exemplu.ro"
        try actions.update(firm, with: draft, startedFrom: start)
        #expect(firm.email == "nume@exemplu.ro")
        #expect(firm.phone == "0721 000 000", "The phone added on the other device stays")
    }

    @Test("A deadline's reminders change only in what the change made")
    func remindersMeetPartByPart() throws {
        let context = try makeContext()
        let car = try makeCar(in: context)
        let rca = try ObligationActions(context: context, calendar: .bucharest).create(
            title: "RCA", kind: .insurance, dueDay: CalendarDay("2027-07-15"), for: car)
        let start = rca.reminders
        try elsewhere(car, in: context) { _ in rca.followUpAfterLapse = !start.followUpAfterLapse }
        try ObligationActions(context: context, calendar: .bucharest).setReminders(rca, start.withLeadDays([60, 30, 7, 0]), startedFrom: start)
        #expect(rca.reminders.leadDays == [60, 30, 7, 0])
        #expect(rca.reminders.followUpAfterLapse == !start.followUpAfterLapse, "The other device's choice stays")
    }

    @Test("The three-way rule: what the edit left keeps what is stored now")
    func theRule() {
        #expect(ThreeWay.value("b", over: "c", startedFrom: "a") == "b")
        #expect(ThreeWay.value("a", over: "c", startedFrom: "a") == "c")
        var base = FieldValues(), edited = FieldValues(), stored = FieldValues()
        base["x"] = .text("1"); base["y"] = .text("1")
        edited = base; edited["x"] = .text("2")
        stored = base; stored["y"] = .text("3"); stored["z"] = .text("new")
        let laid = ThreeWay.laying(edited, over: stored, startedFrom: base)
        #expect(laid["x"]?.textValue == "2")
        #expect(laid["y"]?.textValue == "3")
        #expect(laid["z"]?.textValue == "new")
    }
}
