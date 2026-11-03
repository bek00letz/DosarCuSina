import Foundation
import SwiftData
import Testing
@testable import DosarCuSina

/// A category of the person's own answers a few plain questions, and each answer is the
/// same data a built-in has: pockets, its box, its part for capture, a counter and a service.
@Suite("Category switches")
struct CategorySwitchesTests {
    private func definition(_ switches: CategorySwitches) -> TemplateDefinition {
        switches.definition(key: "custom.test", name: "Bărci", symbol: "sailboat.fill", tint: .gray)
    }

    @Test("With no changes, a category keeps documents and gets a box per section")
    func defaultsMakeASensibleCategory() {
        let made = definition(.defaults)
        #expect(CategorySwitches.defaults.hasDocuments)
        #expect(made.pockets == SectionPocket.standard, "The same pockets the first version's Altceva… started with")
        #expect(made.behavior == .standard)
        #expect(made.blueprints.isEmpty)
        #expect(made.sections.isEmpty)
    }

    @Test func documentsAreTheActePocket() {
        #expect(definition(CategorySwitches(hasDocuments: true)).pockets.contains(.documents))
        #expect(!definition(CategorySwitches(hasDocuments: false)).pockets.contains(.documents))
    }

    @Test("Bills and contracts: the Abonamente pocket, and a place they're filed under, like a home")
    func billsAreSubscriptionsUnderAHome() {
        let made = definition(CategorySwitches(hasBills: true))
        #expect(made.pockets.contains(.subscriptions))
        #expect(made.behavior.role == .home)
        #expect(BuiltInTemplates.home.pockets.contains(.subscriptions) && BuiltInTemplates.home.behavior.role == .home)
        let without = definition(CategorySwitches(hasBills: false))
        #expect(!without.pockets.contains(.subscriptions))
        #expect(without.behavior.role == nil)
    }

    @Test("A service by a counter is a hero counter and a service deadline, like a car's")
    func serviceByCounter() throws {
        let boat = definition(CategorySwitches(service: .engineHours))
        let counter = try #require(boat.fields(withRole: .heroMetric).first)
        #expect(counter.key == "custom.counter.h")
        #expect(counter.type == .metric && counter.unit == .engineHours && counter.isEssential)
        let service = try #require(boat.blueprints.first)
        #expect(service.key == "custom.service.engineHours")
        #expect(service.recurrence == .metric(every: 100, unit: .engineHours, fallback: .years(1)))

        let trailer = definition(CategorySwitches(service: .kilometres))
        #expect(trailer.fields(withRole: .heroMetric).first?.unit == .kilometres)
        let car = try #require(BuiltInTemplates.vehicle.blueprints.first { $0.key == "vehicle.service" })
        let byKilometres = try #require(trailer.blueprints.first)
        #expect(byKilometres.kind == car.kind && byKilometres.reminders == car.reminders && byKilometres.firstDue == car.firstDue)
        #expect(byKilometres.recurrence == .metric(every: 10_000, unit: .kilometres, fallback: .years(1)))
    }

    @Test func yearlyServiceHasNoCounter() {
        let piano = definition(CategorySwitches(service: .yearly))
        #expect(piano.fields(withRole: .heroMetric).isEmpty)
        #expect(piano.blueprints.map(\.recurrence) == [.interval(.years(1), anchor: .completion)])
    }

    @Test func oneBoxForAllIsAWholeCategoryBox() {
        #expect(definition(CategorySwitches(boxes: .oneForAll)).behavior.box == .wholeCategory)
        #expect(definition(CategorySwitches(boxes: .perSection)).behavior.hasSectionBoxes)
    }

    @Test("Every answer reads back from the data it wrote")
    func switchesReadBack() {
        for documents in [true, false] {
            for bills in [true, false] {
                for service in [nil] + CategorySwitches.Service.allCases.map(Optional.some) {
                    for boxes in [CategorySwitches.Boxes.perSection, .oneForAll] {
                        let switches = CategorySwitches(hasDocuments: documents, hasBills: bills, service: service, boxes: boxes)
                        #expect(CategorySwitches(reading: definition(switches)) == switches)
                    }
                }
            }
        }
    }

    @Test("Applying what a category answers changes nothing, built-ins included")
    func applyingTheSameAnswersIsNoChange() {
        let older = TemplateDefinition(key: "custom.old", name: "Unelte", symbol: "hammer", tint: .orange,
                                       sections: [FieldSection(key: "tool", title: "Unealtă", fields: [FieldDefinition(key: "tool.serial", label: "Serie", type: .text)])],
                                       pockets: [.upcoming, .products, .keyFacts])
        for definition in BuiltInTemplates.all + [older] {
            #expect(CategorySwitches(reading: definition).applied(to: definition) == definition, "\(definition.key)")
        }
    }

    @Test("A switch touches only what it owns")
    func otherDataStays() {
        let older = TemplateDefinition(key: "custom.old", name: "Unelte", symbol: "hammer", tint: .orange,
                                       sections: [FieldSection(key: "tool", title: "Unealtă", fields: [FieldDefinition(key: "tool.serial", label: "Serie", type: .text)])],
                                       blueprints: [ObligationBlueprint(key: "tool.check", title: "Verificare", kind: .maintenance, recurrence: .interval(.years(1), anchor: .completion))],
                                       pockets: [.upcoming, .products, .keyFacts])
        let changed = CategorySwitches(hasDocuments: true, hasBills: true, service: .kilometres, boxes: .oneForAll).applied(to: older)
        #expect(changed.pockets == [.upcoming, .products, .subscriptions, .documents, .keyFacts])
        #expect(changed.sections.map(\.key) == ["tool", CategorySwitches.counterSectionKey])
        #expect(changed.blueprints.map(\.key) == ["tool.check", "custom.service.kilometres"])
        let back = CategorySwitches(reading: older).applied(to: changed)
        #expect(back == older)
    }
}

@MainActor
@Suite("Categories of one's own, from switches")
struct CustomCategoryBehaviourTests {
    private let calendar = Calendar.bucharest
    private let today = "2026-11-03"

    private func actions(_ context: ModelContext) -> AssetActions {
        let date = noon(today)
        return AssetActions(context: context, calendar: calendar, now: { date })
    }

    private func builtIn(_ key: String, _ context: ModelContext) throws -> CategoryTemplate {
        try #require(try TemplateStore(context: context).template(forKey: key))
    }

    /// A section with its first service on `due`, as the add flow makes it.
    private func section(_ name: String, of template: CategoryTemplate, values: FieldValues, serviceKey: String, due: String, _ context: ModelContext) throws -> Asset {
        let plans = actions(context).plannedObligations(for: template, values: values).map { plan -> PlannedObligation in
            var plan = plan
            plan.isSelected = plan.blueprint.key == serviceKey
            plan.firstDue = CalendarDay(due)
            return plan
        }
        return try actions(context).create(name: name, template: template, values: values, obligations: plans)
    }

    @Test("The add flow suggests the service and asks for the counter, from the switches alone")
    func addFlowFollowsTheSwitches() throws {
        let context = try makeContext()
        var draft = CustomSectionDraft()
        draft.name = "Bărci"
        draft.switches.service = .engineHours
        let model = AddSectionModel(request: AddSectionRequest())
        model.chooseCustom(draft)
        #expect(model.essentialFields.map(\.key) == ["custom.counter.h"])
        model.values["custom.counter.h"] = .number(120)
        model.planObligations(context: context)
        #expect(model.planned.map(\.blueprint.key) == ["custom.service.engineHours"])
        #expect(model.planned.first?.isSelected == true)
        #expect(model.planned.first?.firstDue != nil, "A year from today, or sooner by the hours")

        model.name = "Barca"
        let boat = try model.create(context: context)
        let category = try #require(try TemplateStore(context: context).template(forKey: boat.templateKey))
        #expect(category.isCustom)
        #expect(CategorySwitches(reading: category.definition) == draft.switches)
        #expect(boat.activeObligations.map(\.blueprintKey) == ["custom.service.engineHours"])
        let reading = try #require(boat.measurements?.first)
        #expect(reading.value == 120 && reading.unit == MeasurementUnit.engineHours.key, "The hours are a reading, like a car's kilometres")
    }

    @Test("In Urmează, a trailer's service sits exactly where a car's would")
    func upcomingLikeACar() throws {
        let context = try makeContext()
        let trailers = try TemplateStore(context: context).createCustom(name: "Rulote", symbol: "car.side.rear.open", switches: CategorySwitches(service: .kilometres))
        var trailerValues = FieldValues()
        trailerValues["custom.counter.km"] = .number(42_000)
        let trailer = try section("Rulota", of: trailers, values: trailerValues, serviceKey: "custom.service.kilometres", due: "2026-11-15", context)

        var carValues = FieldValues()
        carValues[VehicleFields.plate] = .text("B-123-ABC")
        carValues[VehicleFields.odometer] = .number(42_000)
        let car = try section("VW Golf 2018", of: try builtIn(BuiltInTemplates.Key.vehicle, context), values: carValues, serviceKey: "vehicle.service", due: "2026-11-15", context)

        let digest = AttentionModel.digest(try ObligationSnapshot.fetchAll(in: context, calendar: calendar), now: noon(today), calendar: calendar)
        func placement(_ asset: Asset) -> String? {
            if let entry = digest.now.first(where: { $0.obligation.assetId == asset.id }) { return "now \(entry.urgency) \(entry.daysRemaining)" }
            if let entry = digest.soon.flatMap(\.entries).first(where: { $0.obligation.assetId == asset.id }) { return "soon \(entry.urgency) \(entry.daysRemaining)" }
            return digest.later.count > 0 ? "later" : nil
        }
        #expect(placement(trailer) != nil)
        #expect(placement(trailer) == placement(car))
        let trailerService = try #require(trailer.activeObligations.first)
        let carService = try #require(car.activeObligations.first { $0.blueprintKey == "vehicle.service" })
        #expect(trailerService.metricUnit == carService.metricUnit)
        #expect(trailerService.reminders == carService.reminders)
    }

    @Test("A bill read from a photo goes into a subscription under the place that has bills, like a home's")
    func captureFilesBillsUnderIt() async throws {
        let context = try makeContext()
        let cabins = try TemplateStore(context: context).createCustom(name: "Cabane", symbol: "tent.fill", switches: CategorySwitches(hasBills: true))
        let cabin = try actions(context).create(name: "Cabana de la munte", template: cabins, values: FieldValues())

        let fields = [
            CaptureField(key: .provider, value: .text("ENGIE Romania S.A."), confidence: 0.9, sourceText: nil, tier: .heuristic),
            CaptureField(key: .serviceKind, value: .text(ServiceKind.gas), confidence: 0.9, sourceText: nil, tier: .heuristic),
            CaptureField(key: .clcCode, value: .text("DEG0000000000001"), confidence: 0.9, sourceText: nil, tier: .heuristic),
            CaptureField(key: .total, value: .money(CaptureMoney(amount: 120, currencyCode: "RON")), confidence: 0.9, sourceText: nil, tier: .heuristic),
        ]
        let routing = CaptureRouter.route(kind: .utilityInvoice, kindConfidence: 0.9, fields: fields)
        let result = CaptureResult(kind: .utilityInvoice, kindConfidence: 0.9, fields: fields, suggestions: routing.suggestions, reminder: routing.reminder,
                                   recognizedText: "", barcodes: [], document: nil, notices: [])
        let review = CaptureReview(result: result, assets: try context.fetch(FetchDescriptor<Asset>()), context: context)
        #expect(review.destination == .asset(cabin.id), "The only place with bills, as with a single home")
        let date = noon(today)
        let outcome = try await CaptureFiler(context: context, calendar: calendar, now: { date }).save(review)
        let gas = try #require(outcome.asset)
        #expect(gas.parent?.id == cabin.id)
        #expect(try TemplateStore(context: context).template(forKey: gas.templateKey)?.behavior.role == .subscription)
    }

    @Test("Turning switches off hides; nothing goes, and it all comes back")
    func offAndOnKeepsTheData() throws {
        let context = try makeContext()
        let store = TemplateStore(context: context)
        let all = CategorySwitches(hasDocuments: true, hasBills: true, service: .engineHours)
        let boats = try store.createCustom(name: "Bărci", symbol: "sailboat.fill", switches: all)
        var values = FieldValues()
        values["custom.counter.h"] = .number(350)
        let boat = try section("Barca", of: boats, values: values, serviceKey: "custom.service.engineHours", due: "2027-05-01", context)
        let berth = try actions(context).create(name: "Loc în port", template: try builtIn(BuiltInTemplates.Key.subscription, context), values: FieldValues(), parent: boat)
        let paper = try AttachmentActions(context: context).file(
            DocumentDraft(title: "Certificat de înmatriculare", fileName: "certificat.pdf", kind: .other, contentType: "com.adobe.pdf",
                          originalData: Data("%PDF-1.7 test".utf8), pageImages: [], thumbnail: nil),
            asset: boat
        )
        let service = try #require(boat.activeObligations.first)

        // Off: the switches ask about the running service first.
        let none = CategorySwitches(hasDocuments: false, hasBills: false, service: nil)
        let effects = try store.effects(of: none, on: boats)
        #expect(effects.pausing.map(\.id) == [service.id])
        #expect(effects.resuming.isEmpty)
        let receipt = try store.editCustom(boats, name: "Bărci", symbol: "sailboat.fill", switches: none, changingDeadlines: true)
        #expect(!boats.pockets.contains(.documents) && !boats.pockets.contains(.subscriptions))
        #expect(boats.definition.fields(withRole: .heroMetric).isEmpty)
        #expect(service.status == .paused, "Paused, not deleted")
        #expect(boat.values["custom.counter.h"] == .number(350))
        #expect(berth.parent?.id == boat.id)
        #expect(boat.attachments?.contains { $0.id == paper.id } == true)
        #expect(boat.measurements?.isEmpty == false)

        // "Anulează" puts the category and the deadline back as they were.
        try receipt.undo()
        #expect(CategorySwitches(reading: boats.definition) == all)
        #expect(service.status == .active)

        // Off without touching deadlines, then on again: it asks to resume only what it paused.
        try store.editCustom(boats, name: "Bărci", symbol: "sailboat.fill", switches: none, changingDeadlines: false)
        #expect(service.status == .active, "Left as it was when the person says so")
        try ObligationActions(context: context).pause(service)
        let back = try store.effects(of: all, on: boats)
        #expect(back.resuming.map(\.id) == [service.id])
        try store.editCustom(boats, name: "Bărci", symbol: "sailboat.fill", switches: all, changingDeadlines: true)
        #expect(service.status == .active)
        #expect(CategorySwitches(reading: boats.definition) == all)
        #expect(HouseholdMutations.heroMetricValue(of: boat, template: boats.definition) == 350, "The same hours, under the same key")
    }

    @Test("Changing what a service counts by asks about the old one")
    func changingTheCounterAsks() throws {
        let context = try makeContext()
        let store = TemplateStore(context: context)
        let boats = try store.createCustom(name: "Bărci", symbol: "sailboat.fill", switches: CategorySwitches(service: .kilometres))
        let boat = try section("Barca", of: boats, values: FieldValues(), serviceKey: "custom.service.kilometres", due: "2027-05-01", context)
        let effects = try store.effects(of: CategorySwitches(service: .engineHours), on: boats)
        #expect(effects.pausing.map(\.id) == boat.activeObligations.map(\.id))
        #expect(try store.effects(of: CategorySwitches(service: .kilometres, boxes: .oneForAll), on: boats).isEmpty, "A box changes no deadline")
    }

    @Test func renamingKeepsTheKeyAndTheSections() throws {
        let context = try makeContext()
        let store = TemplateStore(context: context)
        let boats = try store.createCustom(name: "Barci", symbol: "sailboat.fill", switches: .defaults)
        let boat = try actions(context).create(name: "Barca", template: boats, values: FieldValues())
        let key = boats.key
        try store.editCustom(boats, name: "Bărci", symbol: "tent.fill", switches: .defaults, changingDeadlines: true)
        #expect(boats.key == key && boats.name == "Bărci" && boats.symbol == "tent.fill")
        #expect(boat.templateKey == key)
    }

    @Test("Built-in categories keep their fixed behaviour")
    func builtInsHaveNoSwitches() throws {
        let context = try makeContext()
        let vehicle = try builtIn(BuiltInTemplates.Key.vehicle, context)
        #expect(throws: TemplateStoreError.builtInBehaviourIsFixed) {
            try TemplateStore(context: context).editCustom(vehicle, name: "Mașini", symbol: "car.fill", switches: .defaults, changingDeadlines: false)
        }
        #expect(vehicle.definition == BuiltInTemplates.vehicle)
    }

    @Test("Backups carry what the switches wrote")
    func backupsRoundTrip() throws {
        let container = try makeInMemoryContainer()
        let context = ModelContext(container)
        try TemplateStore(context: context).installBuiltIns()
        let switches = CategorySwitches(hasDocuments: false, hasBills: true, service: .engineHours, boxes: .oneForAll)
        let boats = try TemplateStore(context: context).createCustom(name: "Bărci", symbol: "sailboat.fill", switches: switches)
        let data = try DossierArchiveService(container: container, calendar: calendar).exportData(exportedAt: noon(today))

        let copy = try makeInMemoryContainer()
        try DossierArchiveService(container: copy, calendar: calendar).importArchive(data, mode: .replace)
        let imported = try #require(try TemplateStore(context: ModelContext(copy)).template(forKey: boats.key))
        #expect(CategorySwitches(reading: imported.definition) == switches)
        #expect(imported.definition == boats.definition)
    }
}
