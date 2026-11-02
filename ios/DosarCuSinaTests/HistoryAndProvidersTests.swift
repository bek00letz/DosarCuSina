import Foundation
import SwiftData
import Testing
@testable import DosarCuSina

@Suite("Component catalog")
struct ComponentCatalogTests {
    let car = BuiltInComponents.vehicle

    @Test("Bill wording maps to one component", arguments: [
        ("Plăcuțe frână față Bosch", "brakes.padsFront"),
        ("placute de frana spate", "brakes.padsRear"),
        ("Schimb uleiul și filtrul", "engine.oil"),
        ("Kit distribuție complet", "engine.timing"),
        ("Filtru polen", "filters.cabin"),
        ("Discurile față", "brakes.discsFront"),
    ])
    func matchesWhatPeopleWrite(text: String, key: String) {
        #expect(ComponentCatalog.match(text, in: car)?.key == key)
    }

    @Test func unknownWorkGetsAStableCustomKey() {
        let key = ComponentCatalog.key(for: "Reparație Oglindă Stânga", in: car)
        #expect(key == "custom.reparatie-oglinda-stanga")
        #expect(ComponentCatalog.key(for: "reparatie oglinda stanga", in: car) == key)
    }

    @Test func homeAndPetCatalogsCoverTheUsualQuestions() {
        #expect(ComponentCatalog.match("Robinet nou la baie", in: BuiltInComponents.home)?.key == "plumbing.taps")
        #expect(ComponentCatalog.match("Hotă Exemplu 60", in: BuiltInComponents.home)?.key == "kitchen.hood")
        #expect(ComponentCatalog.match("Bravecto 1000mg", in: BuiltInComponents.pet)?.key == "parasites.external")
        for catalog in [BuiltInComponents.vehicle, BuiltInComponents.home, BuiltInComponents.pet, BuiltInComponents.bike, BuiltInComponents.espresso] {
            #expect(Set(catalog.map(\.key)).count == catalog.count)
        }
    }

    @Test func searchTextFoldsRomanianDiacritics() {
        #expect(SearchText.normalize("Poliță RCA — Ştefan") == "polita rca stefan")
        #expect(SearchText.containsPhrase("uleiul motor", "ulei"))
        #expect(!SearchText.containsPhrase("ulei", "uleiul"))
    }
}

@Suite("Maintenance log")
struct MaintenanceLogTests {
    let calendar = Calendar.bucharest

    private var items: [HistoryItemSnapshot] {
        [
            HistoryItemSnapshot(componentKey: "brakes.padsFront", name: "Plăcuțe față", occurredAt: noon("2023-04-10"), metricReading: 92_000,
                                cost: Money(300), partBrandOrCode: "Marca A", supplierName: "Magazin 1", providerNames: ["Service 1"]),
            HistoryItemSnapshot(componentKey: "brakes.padsFront", name: "Plăcuțe față", occurredAt: noon("2025-03-15"), metricReading: 124_300,
                                cost: Money(380), partBrandOrCode: "Marca B", supplierName: "Magazin 2", providerNames: ["Service 2"]),
            HistoryItemSnapshot(componentKey: "engine.oil", name: "Ulei", occurredAt: noon("2025-03-15"), metricReading: 124_300, cost: Money(420)),
            HistoryItemSnapshot(componentKey: "brakes.padsFront", name: "Plăcuțe față", occurredAt: noon("2021-05-01"), metricReading: 61_000),
        ]
    }

    @Test("When did I last change the brake pads")
    func lastOccurrenceAnswersEverything() throws {
        let last = try #require(MaintenanceLog.lastOccurrence(of: "brakes.padsFront", in: items, currentMetric: 142_500, now: noon("2026-11-02"), calendar: calendar))
        #expect(CalendarDay(last.date, calendar: calendar) == CalendarDay("2025-03-15"))
        #expect(last.metricAtTime == 124_300)
        #expect(last.metricSince == 18_200)
        #expect(last.daysSince == 597)
        #expect(last.cost == Money(380))
        #expect(last.partBrandOrCode == "Marca B")
        #expect(last.supplierName == "Magazin 2")
        #expect(last.providerNames == ["Service 2"])
        #expect(MaintenanceLog.occurrences(of: "brakes.padsFront", in: items).count == 3)
        #expect(MaintenanceLog.lastOccurrence(of: "brakes.discsFront", in: items) == nil)
    }

    @Test func typicalIntervalIsTheMedianGap() throws {
        let interval = try #require(MaintenanceLog.typicalInterval(of: "brakes.padsFront", in: items, calendar: calendar))
        #expect(interval.sampleCount == 2)
        #expect(interval.metric == 31_650.0)
        #expect(interval.days.map { (680...710).contains($0) } == true)
        #expect(MaintenanceLog.typicalInterval(of: "engine.oil", in: items) == nil, "One replacement is not a pattern")
    }

    @Test func trackedComponentsAreNewestFirst() {
        #expect(MaintenanceLog.trackedComponents(in: items).first.map { ["brakes.padsFront", "engine.oil"].contains($0) } == true)
        #expect(Set(MaintenanceLog.trackedComponents(in: items)) == ["brakes.padsFront", "engine.oil"])
    }
}

@MainActor
@Suite("History and providers")
struct HistoryAndProvidersTests {
    let calendar = Calendar.bucharest

    private func setup() throws -> (ModelContext, Asset) {
        let context = try makeContext()
        let template = try #require(try TemplateStore(context: context).template(forKey: BuiltInTemplates.Key.vehicle))
        var values = FieldValues()
        values["vehicle.odometer"] = .number(100_000)
        let car = try AssetActions(context: context, calendar: calendar, now: { noon("2026-01-10") }).create(name: "Mașina", template: template, values: values)
        return (context, car)
    }

    @Test func loggingARepairKeysItemsByComponentAndUpdatesTheOdometer() throws {
        let (context, car) = try setup()
        let mechanic = try ProviderActions(context: context).create(name: "Service exemplu", trades: [.mechanic])
        let shop = try ProviderActions(context: context).create(name: "Piese exemplu", trades: [.other])
        let entry = try HistoryActions(context: context, now: { noon("2026-02-01") }).record(
            on: car, kind: .repair, title: "Frâne", metricReading: 103_000,
            items: [
                LineItemDraft(name: "Plăcuțe frână față", partBrandOrCode: "Marca", cost: Money(300), supplier: shop),
                LineItemDraft(name: "Manoperă", laborCost: Money(150)),
            ],
            providers: [mechanic], rating: 5
        )
        #expect(entry.items?.compactMap(\.componentKey).sorted() == ["brakes.padsFront", "custom.manopera"])
        #expect(entry.effectiveCost.amount(in: "RON") == 450)
        #expect(car.value("vehicle.odometer") == .number(103_000))

        let last = try #require(MaintenanceLog.lastOccurrence(of: "brakes.padsFront", in: HistoryItemSnapshot.items(of: car), currentMetric: 110_000))
        #expect(last.metricSince == 7_000)
        #expect(last.supplierName == "Piese exemplu")
        #expect(last.providerNames == ["Service exemplu"])
        #expect(ProviderDirectory(context: context).whoDid("brakes.padsFront", on: car).map(\.name) == ["Service exemplu"])
    }

    @Test func completingAnObligationCanCarryLineItemsAndProviders() throws {
        let (context, car) = try setup()
        let station = try ProviderActions(context: context).create(name: "Stație ITP exemplu", trades: [.inspectionStation])
        let actions = ObligationActions(context: context, calendar: calendar, now: { noon("2026-03-01") })
        let itp = try actions.create(title: "ITP", kind: .legal, dueDay: CalendarDay("2026-03-05"), for: car, recurrence: .legal(.vehicleITP))
        let entry = try actions.complete(itp, cost: Money(180), items: [LineItemDraft(name: "Lamele ștergătoare")], providers: [station])
        #expect(entry.kind == .inspection)
        #expect(car.timeline.count == 1)
        #expect(entry.items?.first?.componentKey == "body.wipers")
        #expect(ProviderDirectory(context: context).providers(for: car).map(\.name) == ["Stație ITP exemplu"])

        try actions.undo(entry)
        #expect(car.timeline.isEmpty, "Undo removes the history entry too")
    }

    @Test func providersByTradePutTrustedOnesFirst() throws {
        let context = try makeContext()
        let providers = ProviderActions(context: context)
        let a = try providers.create(name: "Ana Instalații", trades: [.plumber])
        let b = try providers.create(name: "Bogdan Instalator", trades: [.plumber, .gasTechnician])
        _ = try providers.create(name: "Electrician exemplu", trades: [.electrician])
        try providers.setRating(a, 3)
        try providers.setRating(b, 5)
        #expect(try ProviderDirectory(context: context).providers(withTrade: .plumber).map(\.name) == ["Bogdan Instalator", "Ana Instalații"])
        try providers.setWouldCallAgain(a, true)
        #expect(try ProviderDirectory(context: context).providers(withTrade: .plumber).first?.name == "Ana Instalații")
        #expect(try ProviderDirectory(context: context).providers(withTrade: .gasTechnician).map(\.name) == ["Bogdan Instalator"])
    }

    @Test func jobRatingsAverageIntoTheProvider() throws {
        let (context, car) = try setup()
        let mechanic = try ProviderActions(context: context).create(name: "Service", trades: [.mechanic])
        try ProviderActions(context: context).setRating(mechanic, 2)
        #expect(mechanic.rating == 2)
        let history = HistoryActions(context: context)
        try history.record(on: car, kind: .visit, title: "Diagnoză", providers: [mechanic], rating: 5)
        let second = try history.record(on: car, kind: .repair, title: "Reparație", providers: [mechanic], rating: 4)
        #expect(mechanic.rating == 4.5)
        try history.rate(second, nil)
        #expect(mechanic.rating == 5)
    }

    @Test func deletingAnObligationKeepsItsHistory() throws {
        let (context, car) = try setup()
        let actions = ObligationActions(context: context, calendar: calendar, now: { noon("2026-03-01") })
        let rca = try actions.create(title: "RCA", kind: .insurance, dueDay: CalendarDay("2026-03-05"), for: car, recurrence: .interval(.years(1), anchor: .dueDate))
        try actions.complete(rca, cost: Money(1_100))
        try actions.delete(rca)
        #expect(car.timeline.count == 1)
        #expect(car.timeline.first?.obligation == nil)
    }
}
