#if DEBUG
import Foundation
import SwiftData

/// The App Store's screenshots, in development builds only (never in a release build): the
/// `DosarCuSinaScreenshots` UI tests launch the app with `-DosarScreenshots <scene>` and
/// `-DosarScreenshotsRun <run>`, and the app opens on a binder of its own for that run
/// (`BuildInfo.screenshotStoreName`: its own store, which never syncs), filled at the run's first
/// launch with a made-up household through the same actions a person's steps take, at the
/// scene's screen. `scripts/app-store-screenshots.sh` runs them for every size App Store Connect
/// asks for, in light and dark.
@MainActor
enum ScreenshotStage {
    /// Each screen the App Store shows, by the name the UI tests launch it with.
    enum Scene: String, CaseIterable {
        case binder, upcoming, car, document, capture, trip, search
    }

    /// The launch argument, followed by the scene's name.
    nonisolated static let argument = "-DosarScreenshots"

    /// The launch argument naming the run, which every launch of one run shares.
    nonisolated static let runArgument = "-DosarScreenshotsRun"

    /// The scene this launch is for; nil in every other launch.
    nonisolated static var scene: Scene? { value(after: argument).flatMap(Scene.init(rawValue:)) }

    /// The store of this run's household; nil in every other launch. A run without a name (a
    /// launch by hand) shares one.
    nonisolated static var storeName: String? {
        guard scene != nil else { return nil }
        let run = value(after: runArgument)?.filter { $0.isLetter || $0.isNumber } ?? ""
        return run.isEmpty ? "Screenshots.store" : "Screenshots-\(run).store"
    }

    private nonisolated static func value(after name: String) -> String? {
        let arguments = ProcessInfo.processInfo.arguments
        guard let index = arguments.firstIndex(of: name), arguments.indices.contains(index + 1) else { return nil }
        return arguments[index + 1]
    }

    /// Fills the screenshots' binder at the run's first launch, with its trip, and opens the
    /// scene's screen. Does nothing in any other launch.
    static func prepare(in context: ModelContext, navigator: AppNavigator, calendar: Calendar = .dosar, now: Date = Date()) {
        guard let scene else { return }
        do {
            if try context.fetchCount(FetchDescriptor<Asset>()) == 0 {
                let household = ScreenshotHousehold(context: context, calendar: calendar, now: now)
                try household.fill()
                household.keepTrip()
            }
        } catch {
            PersistenceLog.failed("screenshot household", error)
        }
        if let route = route(for: scene, in: context) { navigator.open(route) }
    }

    /// Where the scene opens. The capture review opens from Adaugă (`captureInput`).
    private static func route(for scene: Scene, in context: ModelContext) -> AppRoute? {
        func section(_ name: String) -> UUID? {
            var descriptor = FetchDescriptor<Asset>(predicate: #Predicate { $0.name == name })
            descriptor.fetchLimit = 1
            return (try? context.fetch(descriptor))?.first?.id
        }
        switch scene {
        case .binder: return .home
        case .upcoming: return .upcoming
        case .car: return section(ScreenshotHousehold.carName).map(AppRoute.asset)
        case .document: return section(ScreenshotHousehold.passportName).map(AppRoute.asset)
        case .capture: return .intake
        case .trip: return .readiness(.trip(holderID: nil))
        case .search: return .search
        }
    }

    /// The practice invoice (`SampleInvoice`, placeholder data), read as if just picked, for
    /// the capture scene's review; nil in every other launch, and after the first time.
    static func captureInput() -> CaptureFlowInput? {
        guard scene == .capture, !hasOpenedCapture,
              let url = try? SampleInvoice.writePDF(), let data = try? Data(contentsOf: url) else { return nil }
        hasOpenedCapture = true
        return CaptureFlowInput(payload: .pdf(data))
    }

    private static var hasOpenedCapture = false
}

/// The screenshots' household: two people with their documents, a car, a home with its
/// subscriptions and guarantees, a cat and a health profile. Every value is made up
/// (placeholder plates, firms and numbers, as AGENTS.md asks); dates are counted from the
/// day the screenshots are taken, so every run shows the same picture.
@MainActor
struct ScreenshotHousehold {
    static let carName = "VW Golf"
    static let passportName = DocumentNaming.name(document: "Pașaport", holder: firstPerson)
    static let firstPerson = "Ana"
    static let secondPerson = "Mihai"
    static let tripDestination = "Grecia"

    let context: ModelContext
    let calendar: Calendar
    let now: Date

    private var today: CalendarDay { CalendarDay(now, calendar: calendar) }
    private func day(_ offset: Int) -> CalendarDay { today.adding(days: offset, calendar: calendar) }
    private func daysAgo(_ days: Int) -> Date { calendar.date(byAdding: .day, value: -days, to: now) ?? now }

    /// Adds the household in one save, as `ExampleDataService` does, but as the person's own
    /// (no example marks), so the screens show what a person's binder shows.
    func fill() throws {
        let store = TemplateStore(context: context)
        try store.installBuiltIns()
        try UnitOfWork.perform(in: context, now: now) { try addHousehold(templates: try store.templatesByKey()) }
    }

    /// The trip the trip checklist opens on, kept on this phone like a person's, in place of
    /// any an earlier run kept (its people are another run's).
    func keepTrip() {
        let trips = TripPlanStore()
        trips.clear()
        let sections = (try? context.fetch(FetchDescriptor<Asset>())) ?? []
        let people = sections.filter { $0.templateKey == BuiltInTemplates.Key.member }
        let cars = sections.filter { $0.templateKey == BuiltInTemplates.Key.vehicle }
        trips.save(TripPlan(
            start: day(24), end: day(34), region: .europeanUnion, destination: Self.tripDestination,
            travellers: Set(people.map { .member($0.id) }), vehicles: Set(cars.map(\.id))
        ))
    }

    private func addHousehold(templates: [String: CategoryTemplate]) throws {
        let assets = AssetActions(context: context, calendar: calendar, now: { now })
        let history = HistoryActions(context: context, now: { now })
        let providers = ProviderActions(context: context, now: { now })
        func plan(_ template: CategoryTemplate, _ values: FieldValues, dues: [String: Int] = [:]) -> [PlannedObligation] {
            assets.plannedObligations(for: template, values: values).map { planned in
                var planned = planned
                if let offset = dues[planned.blueprint.key] { planned.firstDue = day(offset) }
                planned.isSelected = PlannedObligation.startsSelected(planned.blueprint, firstDue: planned.firstDue)
                    || (dues[planned.blueprint.key] != nil && planned.firstDue != nil)
                return planned
            }
        }

        // The people, with their documents.
        var people: [Asset] = []
        if let member = templates[BuiltInTemplates.Key.member], let documents = templates[BuiltInTemplates.Key.documents] {
            var citizen = FieldValues()
            citizen[MemberFields.citizenship] = .choices([Citizenship.key("RO")])
            let ana = try assets.create(name: Self.firstPerson, template: member, values: citizen)
            let mihai = try assets.create(name: Self.secondPerson, template: member, values: citizen)
            people = [ana, mihai]

            var passport = FieldValues()
            passport["document.type"] = .text(DocumentType.passport)
            passport[DocumentFields.number] = .text("050000000")
            passport[DocumentFields.issueDate] = .date(day(-1_650))
            passport[DocumentFields.expiry] = .date(day(1_410))
            try assets.create(name: Self.passportName, template: documents, values: passport, obligations: plan(documents, passport), parent: ana)

            var anaCard = FieldValues()
            anaCard["document.type"] = .text(DocumentType.idCard)
            anaCard[DocumentFields.expiry] = .date(day(1_210))
            try assets.create(name: DocumentNaming.name(document: "Carte de identitate", holder: Self.firstPerson), template: documents,
                              values: anaCard, obligations: plan(documents, anaCard), parent: ana)

            var licence = FieldValues()
            licence["document.type"] = .text(DocumentType.drivingLicence)
            licence[DocumentFields.expiry] = .date(day(2_300))
            try assets.create(name: DocumentNaming.name(document: "Permis de conducere", holder: Self.firstPerson), template: documents,
                              values: licence, obligations: plan(documents, licence), parent: ana)

            var mihaiCard = FieldValues()
            mihaiCard["document.type"] = .text(DocumentType.idCard)
            mihaiCard[DocumentFields.expiry] = .date(day(1_830))
            try assets.create(name: DocumentNaming.name(document: "Carte de identitate", holder: Self.secondPerson), template: documents,
                              values: mihaiCard, obligations: plan(documents, mihaiCard), parent: mihai)
        }

        // The car, with its service history.
        if let template = templates[BuiltInTemplates.Key.vehicle] {
            var values = FieldValues()
            values[VehicleFields.plate] = .text("B-123-ABC")
            values[VehicleFields.make] = .text("Volkswagen")
            values[VehicleFields.model] = .text("Golf")
            values[VehicleFields.year] = .number(2018)
            values["vehicle.fuel"] = .text(FuelType.petrol)
            values[VehicleFields.usage] = .text(VehicleUse.personal)
            values[VehicleFields.odometer] = .number(142_500)
            let car = try assets.create(
                name: Self.carName, template: template, values: values,
                obligations: plan(template, values, dues: ["vehicle.vignette": 6, "vehicle.itp": 23, "vehicle.rca": 58, "vehicle.service": 112])
            )
            if let itp = (car.obligations ?? []).first(where: { $0.blueprintKey == "vehicle.itp" }) {
                try ObligationActions(context: context, calendar: calendar, now: { now }).recordPastCompletion(of: itp, on: daysAgo(707), cost: Money(170))
            }
            let mechanic = try providers.create(name: "Service Auto Nord", trades: [.mechanic, .tyreShop], phone: "0700 000 001", linkedTo: [car])
            try providers.setWouldCallAgain(mechanic, true)
            try history.record(
                on: car, kind: .maintenance, title: "Revizie anuală", occurredAt: daysAgo(380),
                metricReading: 124_800, totalCost: Money(1_150),
                items: [
                    LineItemDraft(name: "Schimb ulei și filtru", partBrandOrCode: "5W-30", cost: Money(420)),
                    LineItemDraft(name: "Plăcuțe frână față", cost: Money(380)),
                    LineItemDraft(name: "Filtru de aer", cost: Money(120)),
                ],
                providers: [mechanic], rating: 5
            )
            try history.record(
                on: car, kind: .maintenance, title: "Revizie", occurredAt: daysAgo(95),
                metricReading: 138_900, totalCost: Money(690),
                items: [LineItemDraft(name: "Schimb ulei și filtru", partBrandOrCode: "5W-30", cost: Money(450))],
                providers: [mechanic], rating: 4
            )
        }

        // The home, with what lives in it.
        var home: Asset?
        if let template = templates[BuiltInTemplates.Key.home] {
            var values = FieldValues()
            values["home.address"] = .text("Str. Teilor nr. 7, Cluj-Napoca")
            values["home.area"] = .number(74)
            home = try assets.create(
                name: "Apartament", template: template, values: values,
                obligations: plan(template, values, dues: ["home.pad": 31, "home.boilerCheck": 140, "home.gasCheck": 410])
            )
        }
        if let home {
            let plumber = try providers.create(name: "Instalații Rapid", trades: [.plumber], phone: "0700 000 002", linkedTo: [home])
            try history.record(
                on: home, kind: .repair, title: "Baterie nouă la bucătărie", occurredAt: daysAgo(210), totalCost: Money(340),
                items: [LineItemDraft(name: "Baterie bucătărie", cost: Money(240))],
                providers: [plumber], rating: 5
            )
        }

        if let template = templates[BuiltInTemplates.Key.subscription] {
            var internet = FieldValues()
            internet["subscription.provider"] = .text("FibraNet")
            internet[SubscriptionFields.service] = .text(ServiceKind.internetTV)
            internet["subscription.price"] = .money(Money(55))
            internet["subscription.cycle"] = .text(BillingCycle.monthly)
            internet["subscription.contractEnd"] = .date(day(48))
            try assets.create(name: "Internet și TV", template: template, values: internet, obligations: plan(template, internet), parent: home)

            var power = FieldValues()
            power["subscription.provider"] = .text("Energia Casei S.A.")
            power[SubscriptionFields.service] = .text(ServiceKind.electricity)
            power["subscription.price"] = .money(Money(180))
            power["subscription.cycle"] = .text(BillingCycle.monthly)
            try assets.create(name: "Curent", template: template, values: power, obligations: plan(template, power), parent: home)

            var music = FieldValues()
            music["subscription.provider"] = .text("Muzică online")
            music[SubscriptionFields.service] = .text(ServiceKind.streaming)
            music["subscription.price"] = .money(Money(Decimal(string: "59.99") ?? 60))
            music["subscription.cycle"] = .text(BillingCycle.yearly)
            music["subscription.renewalDate"] = .date(day(12))
            try assets.create(name: "Muzică", template: template, values: music, obligations: plan(template, music))
        }

        if let template = templates[BuiltInTemplates.Key.purchase] {
            var washer = FieldValues()
            washer["purchase.brand"] = .text("Mașină de spălat rufe")
            washer["purchase.retailer"] = .text("Magazinul de electrocasnice")
            washer["purchase.price"] = .money(Money(2_199))
            washer["purchase.date"] = .date(day(-640))
            try assets.create(name: "Mașină de spălat", template: template, values: washer, obligations: plan(template, washer), parent: home)

            var laptop = FieldValues()
            laptop["purchase.retailer"] = .text("Magazinul de electrocasnice")
            laptop["purchase.price"] = .money(Money(4_850))
            laptop["purchase.date"] = .date(day(-150))
            try assets.create(name: "Laptop", template: template, values: laptop, obligations: plan(template, laptop))
        }

        // PawPaw: a grey tabby with green eyes, a white belly and large paws.
        if let template = templates[BuiltInTemplates.Key.pet] {
            var values = FieldValues()
            values["pet.species"] = .text(PetSpecies.cat)
            values["pet.breed"] = .text("Europeană, tabby gri")
            values["pet.birthDate"] = .date(CalendarDay(year: 2021, month: 4, day: 18))
            values[PetFields.microchip] = .text("642000000000002")
            values["pet.weight"] = .number(5.4)
            let cat = try assets.create(
                name: "PawPaw", template: template, values: values,
                obligations: plan(template, values, dues: ["pet.vaccine": 34, "pet.rabies": 34, "pet.dewormInternal": 4, "pet.dewormExternal": 15])
            )
            let vet = try providers.create(name: "Cabinet veterinar Lăbuța", trades: [.vet], phone: "0700 000 003", linkedTo: [cat])
            try providers.setRating(vet, 5)
        }

        if let template = templates[BuiltInTemplates.Key.health], !people.isEmpty {
            var values = FieldValues()
            values["health.bloodType"] = .text("bloodType.aPositive")
            values["health.allergies"] = .text("Fără alergii cunoscute")
            try assets.create(
                name: "Profil medical", template: template, values: values,
                obligations: plan(template, values, dues: ["health.checkup": 45, "health.dentist": 9])
            )
        }
    }
}
#endif
