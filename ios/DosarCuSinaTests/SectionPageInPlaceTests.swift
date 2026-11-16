import Foundation
import SwiftData
import Testing
@testable import DosarCuSina

/// A section's page shows what it holds and adds from where the person is: empty pockets fold
/// into one "Adaugă…" menu, each paper is shown once, adding a car never stops on dates, and the
/// Acte box adds a document photo first.
@MainActor
@Suite("Section page in place")
struct SectionPageInPlaceTests {
    let calendar = Calendar.bucharest

    private func template(_ key: String, in context: ModelContext) throws -> CategoryTemplate {
        try #require(try TemplateStore(context: context).template(forKey: key))
    }

    private func actions(_ context: ModelContext) -> AssetActions {
        AssetActions(context: context, calendar: calendar, now: { noon("2026-11-02") })
    }

    private func pocketContents(of asset: Asset, in context: ModelContext) throws -> PocketContents {
        let templates = try context.fetch(FetchDescriptor<CategoryTemplate>())
        let definition = try #require(templates.first { $0.key == asset.templateKey }).definition
        return PocketContents(asset: asset, definition: definition, templates: templates,
                              providers: ProviderDirectory(context: context).providers(for: asset))
    }

    private func carValues() -> FieldValues {
        var values = FieldValues()
        values[VehicleFields.plate] = .text("B-123-ABC")
        values[VehicleFields.make] = .text("Volkswagen")
        values[VehicleFields.model] = .text("Golf")
        return values
    }

    // MARK: Empty pockets fold

    @Test func emptyPocketsFoldIntoOneMenuInTheirOrderAndBaniWaitsForMoney() {
        let filled: Set<PagePocket> = [.listed(.history)]
        let layout = SectionPageLayout.make(
            pockets: PagePocket.ordered(listed: [.keyFacts, .upcoming, .documents, .history, .money, .plants], categories: []),
            folds: true,
            fill: { pocket in
                if pocket == .listed(.plants) { return PocketFill.notOffered }
                return filled.contains(pocket) ? PocketFill.filled : PocketFill.empty
            },
            addition: { pocket in
                switch pocket {
                case .listed(.upcoming): PocketAddition.deadline
                case .listed(.documents): PocketAddition.paper(besidePersonal: false)
                case .listed(.keyFacts): PocketAddition.keyFact
                default: nil
                }
            }
        )
        #expect(layout.shown == [.listed(.history)], "Only what holds something is drawn")
        #expect(layout.additions == [.deadline, .paper(besidePersonal: false), .keyFact], "The rest, in the pockets' own order")
        #expect(!layout.shown.contains(.listed(.money)) && !layout.additions.map(\.pocket).contains(.listed(.money)), "Bani adds nothing itself: it waits for money")
        #expect(!layout.shown.contains(.listed(.plants)) && !layout.additions.map(\.pocket).contains(.listed(.plants)), "A pocket not offered is neither")

        let adding = SectionPageLayout.make(pockets: [.listed(.upcoming), .listed(.keyFacts)], revealed: [.listed(.keyFacts)], folds: true,
                                            fill: { _ in PocketFill.empty }, addition: { $0 == .listed(.upcoming) ? PocketAddition.deadline : PocketAddition.keyFact })
        #expect(adding.shown == [.listed(.keyFacts)], "A first row being added shows its pocket in its place")
        #expect(adding.additions == [.deadline])

        let wayBack = SectionPageLayout.make(pockets: [.listed(.upcoming), .listed(.money), .listed(.plants)], folds: false,
                                             fill: { $0 == .listed(.plants) ? PocketFill.notOffered : PocketFill.empty }, addition: { _ in PocketAddition.deadline })
        #expect(wayBack.shown == [.listed(.upcoming), .listed(.money)], "Switched off, every pocket shows as before")
        #expect(wayBack.additions.isEmpty)
        #expect(SectionPageLayout.foldsEmptyPockets, "On, until the owner says otherwise")
    }

    @Test func aNewCarShowsWhatItHoldsAndOffersTheRest() throws {
        let context = try makeContext()
        let cars = try template(BuiltInTemplates.Key.vehicle, in: context)
        let values = carValues()
        let car = try actions(context).create(name: "VW Golf 2018", template: cars, values: values,
                                              obligations: actions(context).plannedObligations(for: cars, values: values))
        #expect(!car.activeObligations.isEmpty, "Its service and tyres start by themselves")

        let contents = try pocketContents(of: car, in: context)
        let layout = contents.layout(pockets: cars.definition.pockets, folds: true)
        #expect(layout.shown == [.listed(.upcoming), .listed(.keyFacts)], "Urmează and its plate under Date importante")
        #expect(layout.additions == [.paper(besidePersonal: false), .visit(cars.behavior.visit), .person])
        #expect(layout.additions.map(\.title) == ["Adaugă un act", "Am fost la service", "Adaugă o persoană"])
        #expect(!layout.additions.map(\.pocket).contains(.listed(.money)), "No Bani until something cost money")
    }

    @Test func aNewHomeFoldsItsEmptyPocketsAndEachComesBackWhenItHoldsSomething() throws {
        let context = try makeContext()
        let homes = try template(BuiltInTemplates.Key.home, in: context)
        let home = try actions(context).create(name: "Apartamentul", template: homes, values: FieldValues())
        let pockets = homes.definition.pockets

        var contents = try pocketContents(of: home, in: context)
        var layout = contents.layout(pockets: pockets, folds: true)
        #expect(!layout.shown.contains { [.tenants, .products, .subscriptions, .documents, .history, .people, .money, .keyFacts].map(PagePocket.listed).contains($0) },
                "No empty card on a new home")
        let offered = layout.additions.compactMap(\.pocket.listedPocket)
        #expect(offered.count == layout.additions.count, "No category of one's own belongs to a home here")
        #expect(offered == SectionPocket.ordered(offered), "The menu follows the pockets' order")
        for pocket in [SectionPocket.tenants, .products, .subscriptions, .documents, .history, .people, .keyFacts] {
            #expect(offered.contains(pocket), "\(pocket) is offered in the menu")
        }
        // The menu's items are the pockets' own additions: one list for both.
        for addition in layout.additions {
            #expect(contents.addition(addition.pocket) == addition)
        }
        #expect(contents.addition(.listed(.money)) == nil)
        #expect(layout.additions.first { $0.pocket == .listed(.tenants) } == .child(.listed(.tenants), templateKey: BuiltInTemplates.Key.tenancy))
        let plants = try template(BuiltInTemplates.Key.plants, in: context)
        #expect(offered.contains(.plants) == !(plants.behavior.hasSectionBoxes && !plants.isOnHome), "Plants only once the household keeps them")
        let accounted = layout.shown.count + layout.additions.count + 1 /* Bani */ + (offered.contains(.plants) ? 0 : 1)
        #expect(accounted == pockets.count, "Every pocket is shown, in the menu, or waits for something to hold")

        // A row of the person's own: Date importante takes its usual place, and leaves the menu.
        _ = try actions(context).setCustomFacts(home, [CustomFact(label: "Număr contract apă", value: "12345")])
        contents = try pocketContents(of: home, in: context)
        layout = contents.layout(pockets: pockets, folds: true)
        #expect(layout.shown.last == .listed(.keyFacts))
        #expect(!layout.additions.map(\.pocket).contains(.listed(.keyFacts)))
    }

    @Test func aPersonsPageAddsTheirOwnDocument() throws {
        let context = try makeContext()
        let people = try template(BuiltInTemplates.Key.member, in: context)
        let ana = try actions(context).create(name: "Ana", template: people, values: FieldValues())
        let contents = try pocketContents(of: ana, in: context)
        #expect(contents.addition(.listed(.documents)) == .personalDocument, "A person adds one of their own, photo first")
        #expect(PocketAddition.paper(besidePersonal: true).title != PocketAddition.personalDocument.title, "Beside it, a paper is named apart")
    }

    // MARK: Each paper once

    @Test func aVisitsInvoiceOpensFromItsVisitAndAPolicyStaysInActe() throws {
        let context = try makeContext()
        let cars = try template(BuiltInTemplates.Key.vehicle, in: context)
        let car = try actions(context).create(name: "VW Golf 2018", template: cars, values: carValues())
        let policy = try AttachmentActions(context: context, calendar: calendar)
            .file(DocumentDraft(title: "Poliță RCA", fileName: "rca.pdf", kind: .policy, contentType: "com.adobe.pdf", originalData: Data([1])), asset: car)
        let entry = try HistoryActions(context: context, now: { noon("2026-06-01") }).recordVisit(
            on: car,
            checklist: [.init(componentKey: "engine.oil", cost: Money(420))],
            documents: [DocumentDraft(title: "Factură service", fileName: "factura.pdf", kind: .invoice, contentType: "com.adobe.pdf", originalData: Data([2]))],
            calendar: calendar
        ).value
        let invoice = try #require(entry.attachments?.first)
        #expect(invoice.asset?.id == car.id, "Filed under the car, as before: nothing stored changes")

        #expect(SectionPapers.listed(car).map(\.id) == [policy.id], "The invoice is the visit's: it opens from Istoric")
        #expect(try pocketContents(of: car, in: context).fill(.listed(.documents)) == .filled)

        // A paper valid until a day filed with a record (a policy renewed with "Am rezolvat") stays in Acte too.
        invoice.validUntil = CalendarDay("2027-06-01")
        #expect(Set(SectionPapers.listed(car).map(\.id)) == [policy.id, invoice.id])

        // A section whose only paper is a visit's has nothing in Acte: the pocket folds.
        let other = try actions(context).create(name: "Dacia Logan", template: try template(BuiltInTemplates.Key.vehicle, in: context), values: FieldValues())
        _ = try HistoryActions(context: context, now: { noon("2026-06-02") }).recordVisit(
            on: other, checklist: [.init(componentKey: "engine.oil")],
            documents: [DocumentDraft(title: "Bon", fileName: "bon.pdf", kind: .receipt, contentType: "com.adobe.pdf", originalData: Data([3]))],
            calendar: calendar
        )
        #expect(SectionPapers.listed(other).isEmpty && SectionPapers.archived(other).isEmpty)
        #expect(try pocketContents(of: other, in: context).fill(.listed(.documents)) == .empty)
        #expect(try pocketContents(of: other, in: context).fill(.listed(.history)) == .filled)
    }

    // MARK: Adding a car doesn't stop on dates

    @Test func deadlinesWhoseDateMustBeAskedStartUntickedForEveryCategory() throws {
        let context = try makeContext()
        let assets = actions(context)
        for template in try context.fetch(FetchDescriptor<CategoryTemplate>()) {
            for plan in assets.plannedObligations(for: template, values: FieldValues()) {
                #expect(plan.isSelected == (plan.blueprint.isSuggested && plan.firstDue != nil), "\(plan.blueprint.key)")
                #expect(plan.asksFirstDate == (plan.firstDue == nil), "\(plan.blueprint.key)")
            }
        }
    }

    @Test func addingACarNeverStopsOnDates() throws {
        let context = try makeContext()
        let model = AddSectionModel(request: .topLevel)
        model.choose(try template(BuiltInTemplates.Key.vehicle, in: context))
        model.values = carValues()
        model.planObligations(context: context)

        for key in [BuiltInBlueprints.vehicleITP, BuiltInBlueprints.vehicleRCA, BuiltInBlueprints.vehicleVignette] {
            let plan = try #require(model.planned.first { $0.blueprint.key == key })
            #expect(!plan.isSelected && plan.asksFirstDate, "\(key) asks its date: it starts unticked")
        }
        #expect(model.planned.first { $0.blueprint.key == "vehicle.service" }?.isSelected == true, "A date worked out by itself stays ticked")
        #expect(model.missingDates.isEmpty, "Nothing stops „Adaugă în dosar”")
        #expect(model.offersDatesForLater, "The step says they can be added later")

        // Ticked by the person, a row still asks its date.
        let itp = try #require(model.planned.firstIndex { $0.blueprint.key == BuiltInBlueprints.vehicleITP })
        model.planned[itp].isSelected = true
        #expect(model.missingDates.map(\.blueprint.key) == [BuiltInBlueprints.vehicleITP])
        model.planned[itp].firstDue = CalendarDay("2027-05-01")
        #expect(model.missingDates.isEmpty)

        // Back to the essentials and on again: the person's ticks stay.
        model.planObligations(context: context)
        #expect(model.planned[itp].isSelected && model.planned[itp].firstDue == CalendarDay("2027-05-01"))
        let car = try model.create(context: context)
        #expect(Set(car.activeObligations.compactMap(\.blueprintKey)).isSuperset(of: [BuiltInBlueprints.vehicleITP, "vehicle.service"]))
        #expect(!car.activeObligations.contains { $0.blueprintKey == BuiltInBlueprints.vehicleRCA })
    }

    @Test func aDateTypedLaterTicksTheRowItWorksOut() throws {
        let context = try makeContext()
        let model = AddSectionModel(request: .topLevel)
        model.choose(try template(BuiltInTemplates.Key.documents, in: context))
        model.values["document.type"] = .text("Pașaport")
        model.planObligations(context: context)
        let renewal = try #require(model.planned.first)
        #expect(!renewal.isSelected, "No expiry yet: nothing to remind of")

        model.values[DocumentFields.expiry] = .date(CalendarDay("2031-08-12"))
        model.planObligations(context: context)
        #expect(model.planned.first?.isSelected == true, "Once the expiry is typed, its renewal is on")
        #expect(model.planned.first?.firstDue == CalendarDay("2031-08-12"))
    }

    // MARK: The Acte box adds a document photo first

    @Test func theActeBoxAddsADocumentForWhoeverItIs() throws {
        #expect(ShellSheet.addPersonalDocument(holderID: nil).id == "personalDocument.", "One sheet, whoever it is for")
        let id = UUID()
        #expect(ShellSheet.addPersonalDocument(holderID: id).id == "personalDocument.\(id.uuidString)")

        let context = try makeContext()
        let people = try template(BuiltInTemplates.Key.member, in: context)
        let ana = try actions(context).create(name: "Popescu Ana", template: people, values: FieldValues())
        let templates = try context.fetch(FetchDescriptor<CategoryTemplate>())
        let members = PersonalDocumentHolder.members(in: try context.fetch(FetchDescriptor<Asset>()), templates: templates)
        #expect(members.map(\.id) == [ana.id])

        // "Al cui e?": a member, or someone new with a name.
        #expect(PersonalDocumentHolder.chosen(nil, newName: "", among: members) == nil)
        #expect(PersonalDocumentHolder.chosen(.someoneNew, newName: "  ", among: members) == nil, "Someone new needs a name")
        #expect(PersonalDocumentHolder.chosen(.member(ana.id), newName: "", among: members)?.name == "Popescu Ana")

        var draft = PersonalDocumentDraft()
        draft.choose(type: try #require(DocumentType.options.first).key)
        let holder = try #require(PersonalDocumentHolder.chosen(.someoneNew, newName: " Manole Corina ", among: members))
        let document = try PersonalDocumentFiling.save(draft, holder: holder, context: context, calendar: calendar, now: { noon("2026-11-02") })
        let corina = try #require(document.parent)
        #expect(corina.name == "Manole Corina", "The person is made with their document, in one step")
        #expect(corina.templateKey == people.key)
        #expect(!context.hasChanges, "Saved together")
    }

    // MARK: Ways back

    @Test func theListsOldSuggestionRowsAreSwitchedOff() {
        #expect(!ObligationListScreen.offersSuggestionRows, "One form for a new deadline: the list's own rows and date sheet are kept off")
    }
}
