import Foundation
import SwiftData
import Testing
@testable import DosarCuSina

/// A visit's form comes from its category's kind (`VisitKind`, `VisitShape`), never from a
/// default: what each kind asks and says, that a category with no visits is offered none
/// anywhere, a plant's dated note, a doctor's visit saved with its day alone, and capture
/// filing a paper as the section's kind says.
@MainActor
@Suite("Visit kinds")
struct VisitKindsTests {
    private func form(_ definition: TemplateDefinition) throws -> VisitForm {
        try #require(VisitForm.make(for: definition), "\(definition.key)")
    }

    private func section(_ key: String, named name: String, in context: ModelContext) -> Asset {
        let asset = Asset(name: name, templateKey: key)
        context.insert(asset)
        return asset
    }

    private func paper(_ kind: CaptureDocumentKind, _ fields: [CaptureField]) -> CaptureResult {
        CaptureResult(kind: kind, kindConfidence: 0.9, fields: fields, suggestions: [], reminder: nil,
                      recognizedText: "", barcodes: [], document: .pending(id: UUID(), claim: UUID()), notices: [])
    }

    private func field(_ key: CaptureFieldKey, _ value: CaptureValue) -> CaptureField {
        CaptureField(key: key, value: value, confidence: 0.9, sourceText: nil, tier: .heuristic)
    }

    /// A service invoice as capture reads it: two lines, a total, a firm, the day and the kilometres.
    private var serviceInvoice: CaptureResult {
        paper(.serviceInvoice, [
            field(.lineItems, .lineItems([
                CaptureLineItem(description: "Schimb ulei 5W-30", amount: Money(300, currency: "RON")),
                CaptureLineItem(description: "Consultație", amount: Money(150, currency: "RON")),
            ])),
            field(.total, .money(Money(450, currency: "RON"))),
            field(.provider, .text("Clinica Exemplu")),
            field(.issueDate, .day(CalendarDay("2026-10-30"))),
            field(.odometer, .metric(value: 150_000, unit: .kilometres)),
        ])
    }

    // MARK: Each kind's description

    @Test("Each kind asks what the owner's table says, in its own words")
    func eachKindsShape() throws {
        let service = try #require(VisitKind.service.shape)
        #expect(service.title == "Am fost la service" && service.paper == .invoice && service.asksBrand && service.asksCounter)
        #expect(service.costLabel == "Total plătit" && service.provider?.header == "Service-ul" && service.save == "Salvează vizita")
        #expect(service.requirement?.fields == [.work, .cost, .paper])

        let job = try #require(VisitKind.job.shape)
        #expect(job.title == "Am chemat un meseriaș" && job.paper == .invoice && !job.asksBrand && !job.asksCounter)
        #expect(job.work?.header == "Ce s-a lucrat" && job.provider?.header == "Cine a lucrat" && job.save == "Salvează lucrarea")

        let repair = try #require(VisitKind.repair.shape)
        #expect(repair.title == "Am dus la reparat" && repair.work == nil && repair.note?.label == "Ce s-a reparat")
        #expect(repair.checksWarranty && repair.provider?.header == "Cine a reparat" && repair.toast == "Reparația e în istoric.")

        let upkeep = try #require(VisitKind.upkeep.shape)
        #expect(upkeep.title == "Am făcut o revizie" && upkeep.paper == nil && upkeep.provider == nil && upkeep.work != nil)

        let doctor = try #require(VisitKind.doctor.shape)
        #expect(doctor.title == "Am fost la medic" && doctor.paper == .medical && doctor.work == nil && !doctor.asksBrand && !doctor.asksCounter)
        #expect(doctor.note?.label == "Pentru ce" && doctor.provider?.header == "Medicul sau clinica" && doctor.requirement == nil)

        let vet = try #require(VisitKind.vet.shape)
        #expect(vet.title == "Am fost la veterinar" && vet.paper == .veterinary && vet.work?.header == "Ce i s-a făcut" && !vet.asksBrand)
        #expect(vet.requirement == nil && vet.provider?.trade == .vet)

        #expect(VisitKind.note.shape == nil && VisitKind.note.addsNote)
        #expect(VisitKind.none.shape == nil && !VisitKind.none.addsNote)
        #expect(VisitShape.formsByKind, "The kinds are on; the one form of before is the way back")
    }

    @Test("Laid over a category: a checklist only where it lists parts, a counter only where one goes up")
    func formsOverCategories() throws {
        let car = try form(BuiltInTemplates.vehicle)
        #expect(car.hasChecklist && car.counterField?.key == VehicleFields.odometer)
        #expect(car.paperHint == "Bifez singur ce scrie pe ea și trec sumele.")
        #expect(car.requirementNote == "Bifează ce s-a făcut sau scrie totalul ca să poți salva.")

        let other = try form(BuiltInTemplates.other)
        #expect(!other.hasChecklist && other.hasRows, "Altele lists no parts: rows of one's own, no empty checklist")
        #expect(other.rowsHeader == "Ce s-a lucrat" && other.addRow == "Adaugă un rând")
        #expect(other.requirementNote == "Scrie ce s-a lucrat sau cât a costat ca să poți salva.")

        let pet = try form(BuiltInTemplates.pet)
        #expect(pet.hasChecklist && pet.counterField == nil, "A pet's weight is no counter")
        #expect(pet.rowsHeader == "Altceva")

        let health = try form(BuiltInTemplates.health)
        #expect(!health.hasChecklist && !health.hasRows && health.counterField == nil)
        #expect(health.paperHint == "Sau biletul de trimitere. Le păstrez cu vizita.")
        #expect(health.fields == [.paper, .note, .cost, .provider])

        let purchase = try form(BuiltInTemplates.purchase)
        #expect(purchase.warrantyField?.key == PurchaseFieldKeys.warrantyUntil)
        let values = FieldValues([PurchaseFieldKeys.warrantyUntil: .date(CalendarDay("2027-05-03"))])
        #expect(purchase.warrantyNote(on: CalendarDay("2026-11-02"), values: values) == VisitFormWording.underWarranty(until: DosarFormat.longDay(CalendarDay("2027-05-03"))))
        #expect(purchase.warrantyNote(on: CalendarDay("2027-06-01"), values: values) == VisitFormWording.warrantyEnded(on: DosarFormat.longDay(CalendarDay("2027-05-03"))))
    }

    // MARK: No visits where the kind has none

    @Test("A category with no visits is offered none: not on its page, not in „Scriu eu”, not for capture's invoice")
    func noVisitsWhereNone() throws {
        for definition in BuiltInTemplates.all {
            let kind = definition.behavior.visit
            let addition = PocketAddition.history(of: definition.behavior)
            switch kind {
            case .none:
                #expect(addition == nil, "\(definition.key): Istoric adds nothing")
                #expect(VisitForm.make(for: definition) == nil)
            case .note:
                #expect(addition == .note, "\(definition.key): Istoric takes a note")
                #expect(VisitForm.make(for: definition) == nil)
            default:
                #expect(addition == .visit(kind), "\(definition.key)")
                #expect(addition?.title == kind.shape?.title)
            }
            #expect(CaptureDocumentKind.serviceInvoice.profile.opensVisit(into: kind) == (kind.shape?.paper != nil), "\(definition.key)")
        }
        let plants = BuiltInTemplates.plants
        #expect(PocketAddition.history(of: plants.behavior)?.title == "Adaugă o notă")
        #expect(CaptureDocumentKind.veterinaryRecord.profile.opensVisit(into: .vet))
        #expect(!CaptureDocumentKind.serviceInvoice.profile.opensVisit(into: .upkeep), "No paper asked: filed as a document")
        #expect(!CaptureDocumentKind.utilityInvoice.profile.opensVisit(into: .service), "A bill never opens the visit form")
    }

    @Test("On a section's page, a subscription's Istoric adds nothing and a plant's adds a note")
    func pageAdditions() throws {
        let context = try makeContext()
        let store = TemplateStore(context: context)
        let templates = try store.all()
        let plan = section(BuiltInTemplates.Key.subscription, named: "Abonament Exemplu", in: context)
        let orchid = section(BuiltInTemplates.Key.plants, named: "Orhidee", in: context)
        try context.save()
        for (asset, expected) in [(plan, nil), (orchid, PocketAddition.note)] as [(Asset, PocketAddition?)] {
            let definition = try #require(try store.template(forKey: asset.templateKey)).definition
            let contents = PocketContents(asset: asset, definition: definition, templates: templates, providers: [])
            let layout = contents.layout(pockets: definition.pockets, folds: true)
            #expect(!layout.additions.contains { if case .visit = $0 { true } else { false } }, "\(asset.name): no visit")
            #expect(layout.additions.contains(.note) == (expected == .note), "\(asset.name)")
        }
    }

    // MARK: A plant's note

    @Test("A plant's note is a dated record of its own in Istoric, its first line its title, and Anulează takes it back")
    func plantsNote() throws {
        let context = try makeContext()
        let orchid = section(BuiltInTemplates.Key.plants, named: "Orhidee", in: context)
        try context.save()
        let history = HistoryActions(context: context, now: { noon("2026-11-02") })
        let note = try history.addNote(on: orchid, "  Are un boboc nou.\nO mut lângă fereastră. ", occurredAt: noon("2026-10-30"))
        let entry = note.value
        #expect(entry.kind == .note && entry.title == "Are un boboc nou.")
        #expect(entry.note == "Are un boboc nou.\nO mut lângă fereastră.")
        #expect(CalendarDay(entry.occurredAt, calendar: .bucharest) == CalendarDay("2026-10-30"))
        #expect(orchid.history?.count == 1)

        // Its page's "Schimbă nota" keeps its title in step, and its own Anulează puts both back.
        let edited = try history.setNote(entry, "Înflorește.")
        #expect(entry.title == "Înflorește.")
        try edited.undo()
        #expect(entry.title == "Are un boboc nou.")

        #expect(throws: HistoryNoteError.self) { try history.addNote(on: orchid, "   ") }
        try note.receipt.undo()
        #expect(orchid.history?.isEmpty == true)
    }

    // MARK: A doctor's visit

    @Test("A doctor's visit saves with its day alone, and keeps only what its kind asks")
    func doctorsVisitWithItsDayAlone() async throws {
        let context = try makeContext()
        let ana = section(BuiltInTemplates.Key.health, named: "Ana", in: context)
        try context.save()
        // Sănătate starts locked; filing into it would ask for Face ID first.
        let store = TemplateStore(context: context)
        try store.setSensitive(try #require(try store.template(forKey: BuiltInTemplates.Key.health)), false, lowering: try await faceIDConfirmed())
        let health = try form(BuiltInTemplates.health)
        var draft = VisitDraft(date: noon("2026-10-30"))
        #expect(draft.satisfies(health), "Nothing else is needed")
        #expect(!draft.hasContent)

        // What a car's form would keep never reaches a doctor's visit.
        draft.odometer = 150_000
        draft.extras = [.init(name: "Ulei", cost: 10)]
        draft.toggle("engine.oil")
        draft.note = "Control anual"
        let visit = draft.filing(on: ana, form: health, provider: .none)
        #expect(visit.odometer == nil && visit.checklist.isEmpty && visit.extraItems.isEmpty)
        #expect(visit.kind == .visit && visit.title == "Vizită la medic" && visit.note == "Control anual")

        let outcome = try await CaptureFiler(context: context, calendar: .bucharest, now: { noon("2026-11-02") }).file(.visit(visit))
        let entry = try #require(outcome.visit)
        #expect(entry.title == "Vizită la medic" && entry.note == "Control anual" && entry.metricReading == nil)
        #expect((entry.items ?? []).isEmpty)
        #expect(ana.measurements?.isEmpty ?? true)
    }

    @Test("Each kind's requirement: a car's waits for something done, a total or the invoice; a repair for a note")
    func requirements() throws {
        let car = try form(BuiltInTemplates.vehicle)
        var draft = VisitDraft(date: noon("2026-11-02"))
        #expect(!draft.satisfies(car))
        draft.total = 120
        #expect(draft.satisfies(car))

        let purchase = try form(BuiltInTemplates.purchase)
        var repair = VisitDraft(date: noon("2026-11-02"))
        repair.toggle("engine.oil")
        #expect(!repair.satisfies(purchase), "A repair has no checklist: ticking can't count")
        repair.note = "Ecranul"
        #expect(repair.satisfies(purchase))
    }

    // MARK: Capture follows the kind

    @Test("A paper read for a doctor's visit fills the day, the total and who; never parts or kilometres")
    func captureFollowsTheKind() throws {
        var forDoctor = VisitDraft(date: noon("2026-11-02"))
        forDoctor.apply(serviceInvoice, form: try form(BuiltInTemplates.health), calendar: .bucharest)
        #expect(forDoctor.ticked.isEmpty && forDoctor.extras.isEmpty && forDoctor.odometer == nil)
        #expect(forDoctor.total == 450 && forDoctor.provider == .new("Clinica Exemplu") && forDoctor.document != nil)
        #expect(CalendarDay(forDoctor.date, calendar: .bucharest) == CalendarDay("2026-10-30"))

        var forCar = VisitDraft(date: noon("2026-11-02"))
        forCar.apply(serviceInvoice, form: .car, calendar: .bucharest)
        #expect(forCar.ticked == ["engine.oil"] && forCar.extras.map(\.name) == ["Consultație"] && forCar.odometer == 150_000)

        // A home's job takes the lines, never the kilometres.
        var forHome = VisitDraft(date: noon("2026-11-02"))
        forHome.apply(serviceInvoice, form: try form(BuiltInTemplates.home), calendar: .bucharest)
        #expect(forHome.odometer == nil && !forHome.extras.isEmpty)
    }

    @Test("A doctor's paper is filed as a report, known again only as the same document")
    func doctorsPaperIsAReport() throws {
        #expect(VisitShape.Paper.medical.documentKind == .report)
        #expect(VisitShape.Paper.invoice.documentKind == .invoice)
        #expect(!VisitShape.Paper.medical.isInvoice && VisitShape.Paper.invoice.isInvoice)
    }
}
