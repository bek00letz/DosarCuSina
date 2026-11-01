import Foundation
import SwiftData

/// "Explore with examples": a small household that shows every part of the app.
/// Everything it creates is tagged `isExample`, never schedules real reminders,
/// and goes away with `removeExamples()`. Data is made up; no real people,
/// plates or identifiers.
@MainActor
public struct ExampleDataService {
    public let context: ModelContext
    private let calendar: Calendar
    private let now: () -> Date

    public init(context: ModelContext, calendar: Calendar = .current, now: @escaping () -> Date = { Date() }) {
        self.context = context
        self.calendar = calendar
        self.now = now
    }

    public func hasExamples() throws -> Bool {
        var descriptor = FetchDescriptor<Asset>(predicate: #Predicate { $0.isExample })
        descriptor.fetchLimit = 1
        return try !context.fetch(descriptor).isEmpty
    }

    /// Adds the example household. Does nothing if examples are already there.
    public func loadExamples() throws {
        guard try !hasExamples() else { return }
        let store = TemplateStore(context: context)
        try store.installBuiltIns()
        let templates = try store.templatesByKey()
        let assets = AssetActions(context: context, calendar: calendar, now: now)
        let today = CalendarDay(now(), calendar: calendar)
        func day(_ offset: Int) -> CalendarDay { today.adding(days: offset, calendar: calendar) }
        func plan(_ template: CategoryTemplate, _ values: FieldValues, dues: [String: Int], extra: Set<String> = []) -> [PlannedObligation] {
            assets.plannedObligations(for: template, values: values).map { planned in
                var planned = planned
                if let offset = dues[planned.blueprint.key] { planned.firstDue = day(offset) }
                planned.isSelected = (planned.isSelected || extra.contains(planned.blueprint.key)) && planned.firstDue != nil
                return planned
            }
        }

        if let template = templates[BuiltInTemplates.Key.vehicle] {
            var values = FieldValues()
            values["vehicle.plate"] = .text("B-123-ABC")
            values["vehicle.make"] = .text("Volkswagen")
            values["vehicle.model"] = .text("Golf")
            values["vehicle.year"] = .number(2018)
            values["vehicle.fuel"] = .text(String(localized: "Benzină"))
            values["vehicle.usage"] = .text(VehicleUsage.personal)
            values["vehicle.odometer"] = .number(142_500)
            let car = try assets.create(
                name: "VW Golf",
                template: template,
                values: values,
                obligations: plan(template, values, dues: ["vehicle.itp": 9, "vehicle.rca": 41, "vehicle.vignette": -2, "vehicle.service": 120]),
                isExample: true
            )
            try addReadings(to: car, kind: .odometer, values: [(-180, 130_000), (-90, 136_200)])
            try addHistory(to: car, blueprintKey: "vehicle.itp", daysAgo: 721, cost: Money(170))
        }

        if let template = templates[BuiltInTemplates.Key.home] {
            var values = FieldValues()
            values["home.address"] = .text("Str. Exemplului nr. 12, București")
            values["home.area"] = .number(78.5)
            values["home.meterReadFrom"] = .number(20)
            values["home.meterReadTo"] = .number(25)
            try assets.create(
                name: String(localized: "Apartament Floreasca"),
                template: template,
                values: values,
                obligations: plan(template, values, dues: ["home.boilerCheck": 200, "home.gasCheck": 310, "home.pad": 25]),
                isExample: true
            )
        }

        if let template = templates[BuiltInTemplates.Key.pet] {
            var values = FieldValues()
            values["pet.species"] = .text(String(localized: "Câine"))
            values["pet.breed"] = .text("Golden Retriever")
            values["pet.birthDate"] = .date(CalendarDay(year: 2021, month: 5, day: 10))
            values["pet.microchip"] = .text("642000000000001")
            values["pet.weight"] = .number(31.5)
            let pet = try assets.create(
                name: "Max",
                template: template,
                values: values,
                obligations: plan(template, values, dues: ["pet.rabies": 60, "pet.vaccine": 60, "pet.dewormInternal": 3, "pet.dewormExternal": 12]),
                isExample: true
            )
            try addReadings(to: pet, kind: .bodyWeight, values: [(-120, 30.2), (-60, 31.0), (0, 31.5)])
        }

        if let template = templates[BuiltInTemplates.Key.documents] {
            var values = FieldValues()
            values["document.type"] = .text(String(localized: "Pașaport"))
            values["document.number"] = .text("050000000")
            values["document.holder"] = .text(String(localized: "Titular exemplu"))
            values["document.expiry"] = .date(day(150))
            try assets.create(name: String(localized: "Pașaport"), template: template, values: values, obligations: plan(template, values, dues: [:]), isExample: true)
        }

        if let template = templates[BuiltInTemplates.Key.health] {
            var values = FieldValues()
            values["health.bloodType"] = .text("A II+")
            values["health.allergies"] = .text(String(localized: "Fără alergii cunoscute"))
            try assets.create(
                name: String(localized: "Profil medical"),
                template: template,
                values: values,
                obligations: plan(template, values, dues: ["health.checkup": 45, "health.dentist": -1]),
                isExample: true
            )
        }

        if let template = templates[BuiltInTemplates.Key.warranty] {
            var values = FieldValues()
            values["warranty.brand"] = .text(String(localized: "Frigider combinat"))
            values["warranty.retailer"] = .text(String(localized: "Magazin exemplu"))
            values["warranty.price"] = .money(Money(2_499))
            values["warranty.purchaseDate"] = .date(day(-600))
            values["warranty.expiry"] = .date(day(130))
            try assets.create(name: String(localized: "Frigider"), template: template, values: values, obligations: plan(template, values, dues: [:]), isExample: true)
        }

        if let template = templates[BuiltInTemplates.Key.subscription] {
            var values = FieldValues()
            values["subscription.provider"] = .text("Digi")
            values["subscription.price"] = .money(Money(45))
            values["subscription.cycle"] = .text(BillingCycle.monthly)
            values["subscription.nextPayment"] = .date(day(6))
            try assets.create(name: String(localized: "Internet fibră"), template: template, values: values, obligations: plan(template, values, dues: [:]), isExample: true)

            var storage = FieldValues()
            storage["subscription.provider"] = .text(String(localized: "Serviciu exemplu"))
            storage["subscription.price"] = .money(Money(Decimal(string: "2.99") ?? 3, currency: "EUR"))
            storage["subscription.cycle"] = .text(BillingCycle.monthly)
            storage["subscription.nextPayment"] = .date(day(18))
            try assets.create(name: String(localized: "Stocare online"), template: template, values: storage, obligations: plan(template, storage, dues: [:]), isExample: true)
        }
    }

    /// Deletes everything created by `loadExamples()` in one save.
    public func removeExamples() throws {
        for asset in try context.fetch(FetchDescriptor<Asset>(predicate: #Predicate { $0.isExample })) {
            context.delete(asset)
        }
        // Example records left without an asset (should not happen, but never leave strays).
        for obligation in try context.fetch(FetchDescriptor<Obligation>(predicate: #Predicate { $0.isExample })) where obligation.asset == nil {
            context.delete(obligation)
        }
        do {
            try context.save()
        } catch {
            context.rollback()
            throw error
        }
    }

    // MARK: Helpers

    private func addReadings(to asset: Asset, kind: MeasurementKind, values: [(daysAgo: Int, value: Double)]) throws {
        let assets = AssetActions(context: context, calendar: calendar, now: now)
        for reading in values where reading.daysAgo != 0 {
            let date = calendar.date(byAdding: .day, value: reading.daysAgo, to: now()) ?? now()
            try assets.recordMeasurement(on: asset, kind: kind, value: reading.value, at: date)
        }
    }

    /// Adds a past completion for history without moving the obligation.
    private func addHistory(to asset: Asset, blueprintKey: String, daysAgo: Int, cost: Money) throws {
        guard let obligation = (asset.obligations ?? []).first(where: { $0.blueprintKey == blueprintKey }) else { return }
        let date = calendar.date(byAdding: .day, value: -daysAgo, to: now()) ?? now()
        let completion = Completion(completedAt: date, cycleDueDate: date)
        completion.cost = cost
        completion.isExample = true
        context.insert(completion)
        completion.obligation = obligation
        try context.save()
    }
}
