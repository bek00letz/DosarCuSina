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
        #expect(CategoryBehavior(offerTitle: "").offerTitle(name: "Bărci") == "Bărci", "An empty title shows the name")
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

    // MARK: Visit wording

    @Test("Each built-in words its visits as it did when code chose the wording")
    func builtInVisitWording() throws {
        let service = VisitWording(title: "Am fost la service", checklistTitle: "Ce s-a făcut", providerTitle: "Service-ul",
                                   kind: .maintenance, trade: .mechanic)
        let plain = VisitWording(title: "Am făcut o lucrare", checklistTitle: "Ce s-a făcut", providerTitle: "Cine a lucrat",
                                 kind: .repair, trade: .other)
        let expected: [String: VisitWording] = [
            BuiltInTemplates.Key.vehicle: service,
            BuiltInTemplates.Key.bike: service,
            BuiltInTemplates.Key.pet: VisitWording(title: "Am fost la veterinar", checklistTitle: "Ce i s-a făcut", providerTitle: "Veterinarul",
                                                   kind: .visit, trade: .vet),
            BuiltInTemplates.Key.home: VisitWording(title: "Am chemat un meseriaș", checklistTitle: "Ce a lucrat", providerTitle: "Meseriașul",
                                                    kind: .repair, trade: .handyman),
            BuiltInTemplates.Key.health: VisitWording(title: "Am fost la medic", checklistTitle: "Ce s-a făcut", providerTitle: "Medicul",
                                                      kind: .visit, trade: .doctor),
        ]
        #expect(VisitWording.standard == plain)
        let store = TemplateStore(context: try makeContext())
        for definition in BuiltInTemplates.all {
            let installed = try #require(try store.template(forKey: definition.key))
            #expect(installed.behavior.visitWording == (expected[definition.key] ?? plain), "\(definition.key)")
            #expect(installed.definition.behavior.visitWording == installed.behavior.visitWording, "The page's button reads like the flow")
        }
    }

    @Test("A category of one's own words its visits plainly, whatever it keeps")
    func customVisitWording() throws {
        let store = TemplateStore(context: try makeContext())
        let service = CategorySwitches.Service(.engineHours, every: 100)
        for switches in [CategorySwitches.defaults, CategorySwitches(hasBills: true), CategorySwitches(service: service)] {
            let made = try store.createCustom(name: "Bărci", symbol: "sailboat.fill", switches: switches)
            #expect(made.behavior.visit == nil)
            #expect(made.behavior.visitWording == .standard)
            #expect(made.behavior.visitWording.title == "Am făcut o lucrare")
            #expect(made.behavior.visitWording.providerTitle == "Cine a lucrat")
        }
    }

    @Test("Visit wording is kept with the category and read back; what can't be read is the plain one")
    func visitWordingIsStoredAndTolerant() throws {
        let behavior = BuiltInTemplates.pet.behavior
        let data = try JSONEncoder().encode(behavior)
        #expect(try JSONDecoder().decode(CategoryBehavior.self, from: data) == behavior)

        let fromBefore = Data(#"{"box":"perSection"}"#.utf8)
        #expect(try JSONDecoder().decode(CategoryBehavior.self, from: fromBefore).visitWording == .standard)

        let fromNewer = Data(#"{"visit":{"title":"Am fost la atelier","kind":"overhaul","trade":"shipwright"}}"#.utf8)
        let read = try JSONDecoder().decode(CategoryBehavior.self, from: fromNewer).visitWording
        #expect(read.title == "Am fost la atelier")
        #expect(read.checklistTitle == VisitWording.standard.checklistTitle)
        #expect(read.kind == .repair && read.trade == .other)
    }

    // MARK: The catalog upgrade

    @Test("An install from catalog 14 gets the visit wording and the offers, and keeps its preferences")
    func catalogUpgrade() throws {
        let context = ModelContext(try makeInMemoryContainer())
        let store = TemplateStore(context: context)
        let before = BuiltInTemplates.all.map { definition -> TemplateDefinition in
            var older = definition
            older.version = 14
            older.behavior.visit = nil
            older.behavior.offerTitle = nil
            older.behavior.shortlistOrder = nil
            return older
        }
        try store.installBuiltIns(catalog: before)
        let vehicle = try #require(try store.template(forKey: BuiltInTemplates.Key.vehicle))
        #expect(vehicle.behavior.visit == nil)
        #expect(try store.sectionOffers().shortlist.isEmpty)
        try store.setOnHome(vehicle, false)

        #expect(TemplateDefinition.builtInCatalogVersion > 14)
        #expect(try store.installBuiltIns())
        for definition in BuiltInTemplates.all {
            let installed = try #require(try store.template(forKey: definition.key))
            #expect(installed.builtInVersion == TemplateDefinition.builtInCatalogVersion)
            #expect(installed.behavior == definition.behavior)
        }
        #expect(vehicle.behavior.visitWording.title == "Am fost la service")
        #expect(try store.sectionOffers().shortlist.count == 6)
        #expect(vehicle.isOnHome == false, "Preferences survive the upgrade")
        #expect(try store.installBuiltIns() == false, "Upgraded once")
    }
}
