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
        let history = HistoryActions(context: context, now: now)
        let providers = ProviderActions(context: context, now: now)
        let today = CalendarDay(now(), calendar: calendar)
        func daysAgo(_ days: Int) -> Date { calendar.date(byAdding: .day, value: -days, to: now()) ?? now() }
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
            values["vehicle.fuel"] = .text(FuelType.petrol)
            values["vehicle.usage"] = .text(VehicleUse.personal)
            values["vehicle.odometer"] = .number(142_500)
            let car = try assets.create(
                name: "VW Golf",
                template: template,
                values: values,
                obligations: plan(template, values, dues: ["vehicle.itp": 9, "vehicle.rca": 41, "vehicle.vignette": -2, "vehicle.service": 120]),
                isExample: true
            )
            try addHistory(to: car, blueprintKey: "vehicle.itp", daysAgo: 721, cost: Money(170))
            let mechanic = try providers.create(name: String(localized: "Service auto exemplu"), trades: [.mechanic, .tyreShop], phone: "0700 000 001", linkedTo: [car])
            try providers.setWouldCallAgain(mechanic, true)
            try history.record(
                on: car, kind: .maintenance, title: String(localized: "Revizie anuală"), occurredAt: daysAgo(400),
                metricReading: 121_300, totalCost: Money(1_150),
                items: [
                    LineItemDraft(name: String(localized: "Schimb ulei și filtru"), partBrandOrCode: "5W-30", cost: Money(420)),
                    LineItemDraft(name: String(localized: "Plăcuțe frână față"), partBrandOrCode: "Exemplu", cost: Money(380)),
                ],
                providers: [mechanic], rating: 5
            )
            try history.record(
                on: car, kind: .maintenance, title: String(localized: "Revizie"), occurredAt: daysAgo(120),
                metricReading: 136_200, totalCost: Money(690),
                items: [LineItemDraft(name: String(localized: "Schimb ulei și filtru"), partBrandOrCode: "5W-30", cost: Money(450))],
                providers: [mechanic], rating: 4
            )
        }

        var homeAsset: Asset?
        if let template = templates[BuiltInTemplates.Key.home] {
            var values = FieldValues()
            values["home.address"] = .text("Str. Exemplului nr. 12, București")
            values["home.area"] = .number(78.5)
            values["home.meterReadFrom"] = .number(20)
            values["home.meterReadTo"] = .number(25)
            homeAsset = try assets.create(
                name: String(localized: "Apartament Floreasca"),
                template: template,
                values: values,
                obligations: plan(template, values, dues: ["home.boilerCheck": 200, "home.gasCheck": 310, "home.pad": 25]),
                isExample: true
            )
        }

        if let home = homeAsset {
            let plumber = try providers.create(name: String(localized: "Instalator exemplu"), trades: [.plumber], phone: "0700 000 002", linkedTo: [home])
            try history.record(
                on: home, kind: .repair, title: String(localized: "Robinet nou la bucătărie"), occurredAt: daysAgo(210), totalCost: Money(340),
                items: [LineItemDraft(name: String(localized: "Baterie bucătărie"), partBrandOrCode: "Exemplu", cost: Money(240))],
                providers: [plumber], rating: 5
            )
            try history.record(
                on: home, kind: .purchase, title: String(localized: "Hotă nouă"), occurredAt: daysAgo(500), totalCost: Money(899),
                items: [LineItemDraft(name: String(localized: "Hotă"), partBrandOrCode: "Exemplu 60 cm", cost: Money(899))]
            )
        }

        if let template = templates[BuiltInTemplates.Key.pet] {
            var values = FieldValues()
            values["pet.species"] = .text(PetSpecies.dog)
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
            let vet = try providers.create(name: String(localized: "Cabinet veterinar exemplu"), trades: [.vet], phone: "0700 000 003", linkedTo: [pet])
            try providers.setRating(vet, 5)
        }

        if let template = templates[BuiltInTemplates.Key.documents], let memberTemplate = templates[BuiltInTemplates.Key.member] {
            // Documents are filed under the household member they belong to.
            let me = try assets.create(name: String(localized: "Eu", comment: "Example household member"), template: memberTemplate, values: FieldValues(), isExample: true)
            var passport = FieldValues()
            passport["document.type"] = .text(DocumentType.passport)
            passport["document.number"] = .text("050000000")
            passport["document.expiry"] = .date(day(150))
            try assets.create(name: String(localized: "Pașaport"), template: template, values: passport, obligations: plan(template, passport, dues: [:]), parent: me, isExample: true)
            var idCard = FieldValues()
            idCard["document.type"] = .text(DocumentType.idCard)
            idCard["document.expiry"] = .date(day(900))
            try assets.create(name: String(localized: "Carte de identitate"), template: template, values: idCard, obligations: plan(template, idCard, dues: [:]), parent: me, isExample: true)
        }

        if let template = templates[BuiltInTemplates.Key.health] {
            var values = FieldValues()
            values["health.bloodType"] = .text("bloodType.aPositive")
            values["health.allergies"] = .text(String(localized: "Fără alergii cunoscute"))
            try assets.create(
                name: String(localized: "Profil medical"),
                template: template,
                values: values,
                obligations: plan(template, values, dues: ["health.checkup": 45, "health.dentist": -1]),
                isExample: true
            )
        }

        if let template = templates[BuiltInTemplates.Key.purchase] {
            var fridge = FieldValues()
            fridge["purchase.brand"] = .text(String(localized: "Frigider combinat"))
            fridge["purchase.retailer"] = .text(String(localized: "Magazin exemplu"))
            fridge["purchase.price"] = .money(Money(2_499))
            fridge["purchase.date"] = .date(day(-600))
            try assets.create(name: String(localized: "Frigider"), template: template, values: fridge, obligations: plan(template, fridge, dues: [:]), parent: homeAsset, isExample: true)
            var cooker = FieldValues()
            cooker["purchase.retailer"] = .text(String(localized: "Magazin exemplu"))
            cooker["purchase.price"] = .money(Money(1_350))
            cooker["purchase.date"] = .date(day(-200))
            try assets.create(name: String(localized: "Aragaz"), template: template, values: cooker, obligations: plan(template, cooker, dues: [:]), parent: homeAsset, isExample: true)
        }

        if let template = templates[BuiltInTemplates.Key.tenancy], let home = homeAsset {
            var lease = FieldValues()
            lease["tenancy.start"] = .date(day(-300))
            lease["tenancy.end"] = .date(day(65))
            lease["tenancy.rent"] = .money(Money(450, currency: "EUR"))
            lease["tenancy.paymentDay"] = .number(5)
            lease["tenancy.deposit"] = .money(Money(450, currency: "EUR"))
            let tenancy = try assets.create(name: String(localized: "Chiriaș garsonieră"), template: template, values: lease,
                                            obligations: plan(template, lease, dues: [:]), parent: home, isExample: true)
            try providers.create(name: String(localized: "Chiriaș exemplu"), trades: [.tenant], phone: "0700 000 004", linkedTo: [tenancy])
            try assets.recordMeasurement(on: tenancy, kind: .coldWater, name: String(localized: "Apă rece la mutare"), value: 312, at: calendar.date(byAdding: .day, value: -300, to: now()))
        }

        if let template = templates[BuiltInTemplates.Key.subscription] {
            var values = FieldValues()
            values["subscription.provider"] = .text("Digi")
            values["subscription.price"] = .money(Money(45))
            values["subscription.cycle"] = .text(BillingCycle.monthly)
            values["subscription.contractEnd"] = .date(day(40))
            try assets.create(name: String(localized: "Internet fibră"), template: template, values: values, obligations: plan(template, values, dues: [:]), isExample: true)

            var storage = FieldValues()
            storage["subscription.provider"] = .text(String(localized: "Serviciu exemplu"))
            storage["subscription.price"] = .money(Money(Decimal(string: "29.99") ?? 30, currency: "EUR"))
            storage["subscription.cycle"] = .text(BillingCycle.yearly)
            storage["subscription.renewalDate"] = .date(day(18))
            try assets.create(name: String(localized: "Stocare online"), template: template, values: storage, obligations: plan(template, storage, dues: [:]), isExample: true)
        }
    }

    /// Deletes everything created by `loadExamples()` in one save.
    public func removeExamples() throws {
        for asset in try context.fetch(FetchDescriptor<Asset>(predicate: #Predicate { $0.isExample })) {
            context.delete(asset)
        }
        // Example records that don't hang off an asset.
        for provider in try context.fetch(FetchDescriptor<Provider>(predicate: #Predicate { $0.isExample })) {
            context.delete(provider)
        }
        for obligation in try context.fetch(FetchDescriptor<Obligation>(predicate: #Predicate { $0.isExample })) where obligation.asset == nil {
            context.delete(obligation)
        }
        try HouseholdRules.reconcile(in: context, today: CalendarDay(now(), calendar: calendar), calendar: calendar)
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

    /// Adds a past completion to the history without moving the obligation.
    private func addHistory(to asset: Asset, blueprintKey: String, daysAgo: Int, cost: Money) throws {
        guard let obligation = (asset.obligations ?? []).first(where: { $0.blueprintKey == blueprintKey }) else { return }
        let date = calendar.date(byAdding: .day, value: -daysAgo, to: now()) ?? now()
        let entry = HistoryEntry(kind: .forCompleting(obligation.kind), title: obligation.title, occurredAt: date)
        entry.cycleDueDate = date
        entry.nextDueDate = obligation.dueDate
        entry.previousStatusRaw = ObligationStatus.active.rawValue
        entry.totalCost = cost
        entry.isExample = true
        context.insert(entry)
        entry.obligation = obligation
        entry.asset = asset
        try context.save()
    }
}
