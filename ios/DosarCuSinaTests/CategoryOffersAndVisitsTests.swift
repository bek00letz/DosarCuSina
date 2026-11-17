import Foundation
import SwiftData
import Testing
@testable import DosarCuSina

/// "Adaugă o secțiune" and the visit flow read what a category says about itself
/// (`CategoryBehavior`: its shortlist place, its option's title, its visit wording), so no
/// screen names a built-in and a category of one's own is offered and worded like any other.
@MainActor
@Suite("Category offers and visit wording")
struct CategoryOffersAndVisitsTests {
    // MARK: Adaugă o secțiune

    @Test("The shortlist is the six most households start with, in their order, each as one thing")
    func shortlistOfBuiltIns() throws {
        let offers = try TemplateStore(context: try makeContext()).sectionOffers()
        #expect(offers.shortlist.map(\.key) == [
            BuiltInTemplates.Key.vehicle, BuiltInTemplates.Key.home, BuiltInTemplates.Key.pet,
            BuiltInTemplates.Key.member, BuiltInTemplates.Key.purchase, BuiltInTemplates.Key.subscription,
        ])
        #expect(offers.shortlist.map(SectionOffers.title(for:)) == [
            "Mașină", "Casă sau apartament", "Animal de companie", "Actele unei persoane", "Produs cu garanție", "Abonament",
        ])
    }

    @Test("Every other category follows in the binder's order; a tenancy is only added under a home")
    func othersOfBuiltIns() throws {
        let offers = try TemplateStore(context: try makeContext()).sectionOffers()
        #expect(offers.others.map(\.key) == [
            BuiltInTemplates.Key.documents, BuiltInTemplates.Key.health, BuiltInTemplates.Key.other,
            BuiltInTemplates.Key.bike, BuiltInTemplates.Key.plants, BuiltInTemplates.Key.espresso,
        ])
        #expect(offers.others.map(SectionOffers.title(for:)) == [
            "Un act (buletin, pașaport, permis)", "Sănătate", "Altele", "Biciclete", "Plante", "Espressoare",
        ])
        let everything = Set((offers.shortlist + offers.others).map(\.key))
        #expect(!everything.contains(BuiltInTemplates.Key.tenancy))
        #expect(everything.count == BuiltInTemplates.all.count - 1, "Nothing else is left out")
    }

    @Test("A category of one's own is offered after the ready-made ones, by its own name")
    func customCategoryIsOfferedByName() throws {
        let context = try makeContext()
        let store = TemplateStore(context: context)
        let boats = try store.createCustom(name: "Bărci", symbol: "sailboat.fill", switches: CategorySwitches(hasBills: true))
        let offers = try store.sectionOffers()
        #expect(!offers.shortlist.contains { $0.key == boats.key })
        #expect(offers.others.last?.key == boats.key)
        #expect(SectionOffers.title(for: boats) == "Bărci")
    }

    @Test("A category that says so is shortlisted and titled its own way, built-in or not")
    func offersComeFromTheBehaviour() throws {
        let context = try makeContext()
        let store = TemplateStore(context: context)
        let boats = try store.createCustom(name: "Bărci", symbol: "sailboat.fill", switches: .defaults)
        boats.behavior.offerTitle = "Barcă"
        boats.behavior.shortlistOrder = 7
        let offers = try store.sectionOffers()
        #expect(offers.shortlist.last?.key == boats.key)
        #expect(SectionOffers.title(for: boats) == "Barcă")
        #expect(CategoryBehavior(visit: .none, offerTitle: "", singular: nil).offerTitle(name: "Bărci") == "Bărci", "An empty title shows the name")
    }

    @Test("Adding a document asks whose it is from the people documents are filed under")
    func holdersAreFoundByRole() throws {
        let store = TemplateStore(context: try makeContext())
        #expect(try store.keys(playing: .holder) == [BuiltInTemplates.Key.member])
        #expect(try store.keys(playing: .subscription) == [BuiltInTemplates.Key.subscription])
        #expect(try store.template(forKey: BuiltInTemplates.Key.documents)?.behavior.role == .personalDocument)
    }

    // MARK: Urmează

    @Test("The missing-bill notes read the sections of every category that plays a subscription's part")
    func subscriptionsAreFoundByRole() throws {
        let context = try makeContext()
        let store = TemplateStore(context: context)
        let actions = AssetActions(context: context)
        let subscription = try #require(try store.template(withRole: .subscription))
        let vehicle = try #require(try store.template(forKey: BuiltInTemplates.Key.vehicle))
        let plan = try actions.create(name: "Abonament telefon", template: subscription, values: FieldValues())
        _ = try actions.create(name: "VW Golf 2018", template: vehicle, values: FieldValues())
        #expect(try BillWatchSnapshot.fetchAll(in: context).map(\.id) == [plan.id])

        let lines = try store.createCustom(name: "Linii", symbol: "antenna.radiowaves.left.and.right", switches: .defaults)
        lines.behavior.role = .subscription
        try UnitOfWork.save(context)
        let line = try actions.create(name: "Linie fixă", template: lines, values: FieldValues())
        #expect(Set(try BillWatchSnapshot.fetchAll(in: context).map(\.id)) == [plan.id, line.id])
        #expect(try store.keys(playing: .subscription) == [BuiltInTemplates.Key.subscription, lines.key])
    }

    // MARK: Visit kinds

    @Test("Each built-in states its visits; the page's button and the form read the same kind")
    func builtInVisitKinds() throws {
        let expected: [String: VisitKind] = [
            BuiltInTemplates.Key.vehicle: .service, BuiltInTemplates.Key.bike: .service,
            BuiltInTemplates.Key.home: .job, BuiltInTemplates.Key.other: .job,
            BuiltInTemplates.Key.purchase: .repair, BuiltInTemplates.Key.espresso: .upkeep,
            BuiltInTemplates.Key.health: .doctor, BuiltInTemplates.Key.pet: .vet,
            BuiltInTemplates.Key.plants: .note,
            BuiltInTemplates.Key.subscription: .none, BuiltInTemplates.Key.documents: .none,
            BuiltInTemplates.Key.member: .none, BuiltInTemplates.Key.tenancy: .none,
        ]
        #expect(Set(expected.keys) == Set(BuiltInTemplates.all.map(\.key)), "Every built-in is named here")
        let store = TemplateStore(context: try makeContext())
        for definition in BuiltInTemplates.all {
            #expect(definition.behavior.visit == expected[definition.key], "\(definition.key)")
            let installed = try #require(try store.template(forKey: definition.key))
            #expect(installed.behavior.visit == definition.behavior.visit, "\(definition.key) is installed with its kind")
        }
    }

    @Test("A category of one's own logs visits only with „Are revizii sau lucrări”: a job by time, a service by a counter")
    func customVisitKinds() throws {
        let store = TemplateStore(context: try makeContext())
        let cases: [(CategorySwitches, VisitKind)] = [
            (.defaults, .none),
            (CategorySwitches(hasBills: true), .none),
            (CategorySwitches(service: .init(.time)), .job),
            (CategorySwitches(service: .init(.kilometres)), .service),
            (CategorySwitches(service: .init(.engineHours, every: 100)), .service),
        ]
        for (switches, kind) in cases {
            let made = try store.createCustom(name: "Bărci", symbol: "sailboat.fill", switches: switches)
            #expect(made.behavior.visit == kind, "\(switches)")
            #expect(made.behavior.visit.offersVisit == (switches.service != nil))
            // Turning the switch off takes the visits away; on again by kilometres gives a service.
            var off = switches
            off.service = nil
            #expect(off.applied(to: made.definition).behavior.visit == .none)
            var byKilometres = switches
            byKilometres.service = .init(.kilometres)
            #expect(byKilometres.applied(to: made.definition).behavior.visit == .service)
            // Applying what it answers changes nothing.
            #expect(CategorySwitches(reading: made).applied(to: made.definition) == made.definition)
        }
        // How often alone leaves a stated kind as it is.
        var definition = CategorySwitches(service: .init(.time)).definition(key: "custom.pian", name: "Pian", symbol: "pianokeys", tint: .gray)
        definition.behavior.visit = .repair
        #expect(CategorySwitches(service: .init(.time, every: 6)).applied(to: definition).behavior.visit == .repair)
    }

    @Test("The kind is kept with the category and read back; an older or newer value reads by one rule")
    func visitKindIsStoredAndTolerant() throws {
        let behavior = BuiltInTemplates.pet.behavior
        let data = try JSONEncoder().encode(behavior)
        #expect(String(decoding: data, as: UTF8.self).contains(#""visit":"vet""#), "Stored as its kind's name")
        #expect(try JSONDecoder().decode(CategoryBehavior.self, from: data) == behavior)

        let fromBefore = Data(#"{"box":"perSection"}"#.utf8)
        #expect(try JSONDecoder().decode(CategoryBehavior.self, from: fromBefore).visit == .none, "No kind stated: no visits")

        let fromNewer = Data(#"{"visit":"overhaul"}"#.utf8)
        #expect(try JSONDecoder().decode(CategoryBehavior.self, from: fromNewer).visit == .job, "A newer kind reads as a job done, which hides nothing")

        // The earlier form, an object of words, reads as the kind its trade names.
        let words: [(String, VisitKind)] = [("mechanic", .service), ("vet", .vet), ("doctor", .doctor), ("handyman", .job), ("shipwright", .job)]
        for (trade, kind) in words {
            let earlier = Data(#"{"visit":{"title":"Am fost","kind":"visit","trade":"\#(trade)"}}"#.utf8)
            #expect(try JSONDecoder().decode(CategoryBehavior.self, from: earlier).visit == kind, "\(trade)")
        }
    }

    @Test("A category of one's own an earlier version made with a service gets its switch's visits, by itself")
    func ownCategoryVisitsStep() throws {
        let context = try makeContext()
        let store = TemplateStore(context: context)
        let boats = try store.createCustom(name: "Bărci", symbol: "sailboat.fill", switches: CategorySwitches(service: .init(.engineHours)))
        let notes = try store.createCustom(name: "Caiete", symbol: "book", switches: .defaults)
        let stated = try store.createCustom(name: "Unelte", symbol: "hammer", switches: CategorySwitches(service: .init(.time)))
        boats.behavior.visit = .none   // as an earlier version stored it: no kind
        stated.behavior.visit = .repair
        try context.save()

        #expect(try OwnCategoryVisitsStep().migrate(in: context) == 1)
        #expect(boats.behavior.visit == .service)
        #expect(notes.behavior.visit == .none, "Without the switch, no visits")
        #expect(stated.behavior.visit == .repair, "A kind already stated stays")
        #expect(try OwnCategoryVisitsStep().migrate(in: context) == 0, "Twice is once")
        #expect(DataRepairs.step(.ownCategoryVisits).runsByItself)
        let order = DataRepairs.steps.map { type(of: $0).id }
        #expect((order.firstIndex(of: .ownCategoryVisits) ?? 0) > (order.firstIndex(of: .ownCategoryBoxes) ?? 0), "A new repair is a new step at the end")
    }

    // MARK: The catalog upgrade

    @Test("An install from catalog 14 gets the visit kinds and the offers, and keeps its preferences")
    func catalogUpgrade() throws {
        let context = ModelContext(try makeInMemoryContainer())
        let store = TemplateStore(context: context)
        let before = BuiltInTemplates.all.map { definition -> TemplateDefinition in
            var older = definition
            older.version = 14
            older.behavior.visit = .none
            older.behavior.offerTitle = nil
            older.behavior.shortlistOrder = nil
            return older
        }
        try store.installBuiltIns(catalog: before)
        let vehicle = try #require(try store.template(forKey: BuiltInTemplates.Key.vehicle))
        #expect(vehicle.behavior.visit == .none)
        #expect(try store.sectionOffers().shortlist.isEmpty)
        try store.setOnHome(vehicle, false)

        #expect(TemplateDefinition.builtInCatalogVersion > 14)
        #expect(try store.installBuiltIns())
        for definition in BuiltInTemplates.all {
            let installed = try #require(try store.template(forKey: definition.key))
            #expect(installed.builtInVersion == TemplateDefinition.builtInCatalogVersion)
            #expect(installed.behavior == definition.behavior)
        }
        #expect(vehicle.behavior.visit.shape?.title == "Am fost la service")
        #expect(try store.sectionOffers().shortlist.count == 6)
        #expect(vehicle.isOnHome == false, "Preferences survive the upgrade")
        #expect(try store.installBuiltIns() == false, "Upgraded once")
    }
}
