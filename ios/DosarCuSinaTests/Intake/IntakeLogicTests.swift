import Foundation
import SwiftData
import Testing
@testable import DosarCuSina

// MARK: - Fixtures

private func field(_ key: CaptureFieldKey, _ value: CaptureValue, confidence: Double = 0.9) -> CaptureField {
    CaptureField(key: key, value: value, confidence: confidence, sourceText: nil, tier: .heuristic)
}

private func day(_ iso: String) -> CaptureValue {
    let parts = iso.split(separator: "-").compactMap { Int($0) }
    return .day(CaptureDay(year: parts[0], month: parts[1], day: parts[2])!)
}

private func ron(_ amount: Decimal) -> CaptureValue {
    .money(CaptureMoney(amount: amount, currencyCode: "RON"))
}

/// A capture result routed the way the engine routes it.
private func capture(_ kind: CaptureDocumentKind, _ fields: [CaptureField], documentID: UUID? = nil) -> CaptureResult {
    let routing = CaptureRouter.route(kind: kind, kindConfidence: 0.9, fields: fields)
    return CaptureResult(kind: kind, kindConfidence: 0.9, fields: fields, suggestions: routing.suggestions, reminder: routing.reminder,
                         recognizedText: "", barcodes: [], documentID: documentID, notices: [])
}

@MainActor
private func makeCar(_ context: ModelContext, rcaDue: String? = nil, odometer: Double = 142_500) throws -> Asset {
    let template = try #require(try TemplateStore(context: context).template(forKey: BuiltInTemplates.Key.vehicle))
    var values = FieldValues()
    values["vehicle.plate"] = .text("B-123-ABC")
    values["vehicle.odometer"] = .number(odometer)
    let actions = AssetActions(context: context, calendar: .bucharest, now: { noon("2026-01-10") })
    let planned = actions.plannedObligations(for: template, values: values).map { planned -> PlannedObligation in
        var planned = planned
        planned.isSelected = planned.blueprint.key == "vehicle.rca" && rcaDue != nil
        if planned.isSelected, let rcaDue { planned.firstDue = CalendarDay(rcaDue) }
        return planned
    }
    return try actions.create(name: "VW Golf", template: template, values: values, obligations: planned)
}

// MARK: - Reminder presets

@Suite("Reminder presets in plain words")
struct ReminderPresetTests {
    @Test func leadsReadInNaturalUnits() {
        #expect(ReminderWording.phrase(days: 1) == "o zi")
        #expect(ReminderWording.phrase(days: 3) == "3 zile")
        #expect(ReminderWording.phrase(days: 7) == "o săptămână")
        #expect(ReminderWording.phrase(days: 14) == "două săptămâni")
        #expect(ReminderWording.phrase(days: 30) == "o lună")
        #expect(ReminderWording.phrase(days: 60) == "două luni")
        #expect(ReminderWording.phrase(days: 180) == "6 luni")
        #expect(ReminderWording.phrase(days: 270) == "9 luni")
        #expect(ReminderWording.phrase(days: 365) == "un an")
        #expect(ReminderWording.phrase(days: 25) == "25 de zile")
    }

    @Test func theSentenceListsLeadsLargestFirst() {
        #expect(ReminderWording.sentence(leadDays: [7, 30]) == "Te anunț cu o lună și cu o săptămână înainte.")
        #expect(ReminderWording.sentence(leadDays: [30, 7, 0]) == "Te anunț cu o lună și cu o săptămână înainte și în ziua termenului.")
        #expect(ReminderWording.sentence(leadDays: [0]) == "Te anunț în ziua termenului.")
        #expect(ReminderWording.sentence(leadDays: []) == "Nu te anunț dinainte.")
        #expect(ReminderWording.rowTitle(days: 14) == "Cu două săptămâni înainte")
    }

    @Test func presetsKeepTheEnginesOwnValues() {
        #expect(ReminderPreset.rows(for: [180, 60]) == [180, 60, 30, 14, 7, 1, 0], "A passport's 6 months stays a row of its own")
        #expect(ReminderPreset.toggling(7, in: [30, 0]) == [30, 7, 0])
        #expect(ReminderPreset.toggling(30, in: [30, 7, 0]) == [7, 0])
    }

    @Test func dueLinesSayWhenInPlainWords() {
        let today = CalendarDay("2026-11-02")
        #expect(DueWording.line(kind: .legal, due: CalendarDay("2026-11-07"), today: today, calendar: .bucharest) == "Expiră în 5 zile · 7 noiembrie")
        #expect(DueWording.line(kind: .payment, due: today, today: today, calendar: .bucharest) == "De plătit azi · 2 noiembrie")
        #expect(DueWording.line(kind: .insurance, due: CalendarDay("2026-11-01"), today: today, calendar: .bucharest) == "A expirat ieri · 1 noiembrie")
        #expect(DueWording.line(kind: .maintenance, due: CalendarDay("2027-03-01"), today: today, calendar: .bucharest).hasSuffix("1 martie 2027"))
    }
}

// MARK: - Review to save

@MainActor
@Suite("Capture review to save")
struct CaptureFilingTests {
    @Test func valuesLandInTheTemplatesFields() throws {
        let review = CaptureReview(result: capture(.rcaPolicy, [
            field(.licensePlate, .text("B 123 ABC")),
            field(.policyNumber, .text("RO/00/EX0001")),
            field(.claimsPhone, .text("0700 000 001")),
            field(.provider, .text("Asigurare Exemplu SA")),
            field(.expiryDate, day("2027-11-09")),
            field(.personalNumber, .text("0000000000000")),
        ]), assets: [], context: try makeContext())
        let values = CaptureFiler.values(from: review, for: try #require(BuiltInTemplates.definition(for: BuiltInTemplates.Key.vehicle)))
        #expect(values["vehicle.policyNumber"] == .text("RO/00/EX0001"))
        #expect(values["vehicle.claimsPhone"] == .text("0700 000 001"))
        #expect(values["vehicle.insurer"] == .text("Asigurare Exemplu SA"))
        #expect(values["vehicle.plate"] == .text("B 123 ABC"))
        #expect(!values.keys.contains { $0.contains("personal") }, "Personal identifiers are never written")
        // The engine never lets a personal identifier onto a policy in the first place.
        #expect(!CaptureDocumentKind.rcaPolicy.allows(.personalNumber))
    }

    @Test func aNewPolicyClosesTheOldCycleAndSetsTheNewDate() async throws {
        let context = try makeContext()
        let car = try makeCar(context, rcaDue: "2026-11-10")
        let result = capture(.rcaPolicy, [
            field(.licensePlate, .text("B 123 ABC")),
            field(.policyNumber, .text("RO/00/EX0002")),
            field(.expiryDate, day("2027-11-09")),
            field(.total, ron(1_200)),
        ])
        let review = CaptureReview(result: result, assets: [car], context: context)
        #expect(review.destination == .asset(car.id), "The plate finds the car")
        #expect(review.blueprintKey == "vehicle.rca")
        #expect(review.reminderDay == CalendarDay("2027-11-09"))

        let filer = CaptureFiler(context: context, calendar: .bucharest, now: { noon("2026-11-02") })
        #expect(filer.touchesReminders(review))
        let outcome = try await filer.save(review)
        let rca = try #require(outcome.obligation)
        #expect(rca.blueprintKey == "vehicle.rca")
        #expect(rca.dueDay(in: .bucharest) == CalendarDay("2027-11-09"))
        #expect(outcome.completion?.totalCost == Money(1_200), "The premium goes into the history")
        #expect(car.value("vehicle.policyNumber") == .text("RO/00/EX0002"))
        #expect(car.value("vehicle.plate") == .text("B-123-ABC"), "The plate as the person wrote it stays")
        #expect(car.activeObligations.filter { $0.blueprintKey == "vehicle.rca" }.count == 1, "Never a second RCA")
    }

    @Test func aPassportBecomesADocumentWithItsRenewal() async throws {
        let context = try makeContext()
        let result = capture(.passport, [
            field(.documentNumber, .text("050000000")),
            field(.expiryDate, day("2031-08-12")),
        ])
        let review = CaptureReview(result: result, assets: [], context: context)
        #expect(review.destination == .newAsset(templateKey: BuiltInTemplates.Key.documents))
        #expect(review.newAssetName == "Pașaport")

        let templates = try TemplateStore(context: context).templatesByKey()
        let preview = try #require(CaptureReminderPreview.text(for: review, templates: templates, assets: [], calendar: .bucharest, today: CalendarDay("2026-11-02")))
        #expect(preview == "Expiră pe 12 august 2031. Te anunț cu 6 luni și cu două luni înainte.")

        let outcome = try await CaptureFiler(context: context, calendar: .bucharest, now: { noon("2026-11-02") }).save(review)
        let passport = try #require(outcome.asset)
        #expect(passport.value("document.type") == .text(DocumentType.passport))
        #expect(passport.value("document.number") == .text("050000000"))
        let renewal = try #require(passport.activeObligations.first { $0.blueprintKey == "document.renew" })
        #expect(renewal.dueDay(in: .bucharest) == CalendarDay("2031-08-12"))
        #expect(renewal.reminderLeadDays == [180, 60], "The passport's own profile")
    }

    @Test func aBillCanRemindToPayWithoutASection() async throws {
        let context = try makeContext()
        var review = CaptureReview(result: capture(.utilityInvoice, [
            field(.provider, .text("ENGIE Romania S.A.")),
            field(.dueDate, day("2026-11-20")),
            field(.total, ron(250)),
            field(.invoiceNumber, .text("EX-123")),
        ]), assets: [], context: context)
        review.destination = .none
        #expect(review.remindsToPay)
        let outcome = try await CaptureFiler(context: context, calendar: .bucharest, now: { noon("2026-11-02") }).save(review)
        let bill = try #require(outcome.obligation)
        #expect(bill.title == "Factură ENGIE Romania S.A.")
        #expect(bill.kind == .payment)
        #expect(bill.dueDay(in: .bucharest) == CalendarDay("2026-11-20"))
        #expect(bill.estimatedCost == Money(250))
        #expect(bill.reference == "EX-123")

        review.remindsToPay = false
        #expect(!CaptureFiler(context: context).touchesReminders(review))
    }

    @Test func theOnlySectionOfAKindIsSuggestedAndExamplesNever() throws {
        let context = try makeContext()
        let car = try makeCar(context)
        let itp = capture(.itpReport, [field(.expiryDate, day("2028-11-01"))])
        #expect(CaptureReview.suggestDestination(result: itp, assets: [car]) == .asset(car.id))
        car.isExample = true
        #expect(CaptureReview.suggestDestination(result: itp, assets: [car]) == .newAsset(templateKey: BuiltInTemplates.Key.vehicle))
    }

    @Test func invoicesWithPartsOpenTheVisitFlow() {
        #expect(CaptureMapping.opensVisitFlow(.serviceInvoice))
        #expect(CaptureMapping.opensVisitFlow(.veterinaryRecord))
        #expect(!CaptureMapping.opensVisitFlow(.rcaPolicy))
        #expect(CaptureMapping.blueprintKey("passportRenewal") == "document.renew")
        #expect(CaptureMapping.templateKey("warranties") == BuiltInTemplates.Key.purchase)
    }

    @Test func completingWithANewDocumentTakesItsDate() async throws {
        let context = try makeContext()
        let car = try makeCar(context, rcaDue: "2026-11-10")
        let rca = try #require(car.activeObligations.first)
        let document = capture(.rcaPolicy, [field(.expiryDate, day("2027-11-12"))])
        let outcome = try await ObligationCompletion(context: context, calendar: .bucharest, now: { noon("2026-11-02") })
            .complete(rca, on: noon("2026-11-02"), cost: Money(1_150), document: document, title: nil)
        #expect(outcome.entry?.totalCost == Money(1_150))
        #expect(outcome.nextDue == CalendarDay("2027-11-12"))
        #expect(rca.dueDay(in: .bucharest) == CalendarDay("2027-11-12"))
    }
}

// MARK: - Checklist to visit

@MainActor
@Suite("Visit checklist")
struct VisitDraftTests {
    let components = BuiltInComponents.vehicle

    @Test func anInvoiceTicksRowsAndKeepsTheRest() throws {
        var draft = VisitDraft(date: noon("2026-11-02"))
        let lines: [CaptureLineItem] = [
            CaptureLineItem(description: "Placute frana fata Bosch", amount: CaptureMoney(amount: 380, currencyCode: "RON")),
            CaptureLineItem(description: "Schimb ulei 5W-30", amount: CaptureMoney(amount: 300, currencyCode: "RON")),
            CaptureLineItem(description: "Filtru ulei", amount: CaptureMoney(amount: 120, currencyCode: "RON")),
            CaptureLineItem(description: "Manopera", amount: CaptureMoney(amount: 200, currencyCode: "RON")),
        ]
        draft.apply(capture(.serviceInvoice, [
            field(.lineItems, .lineItems(lines)),
            field(.total, ron(1_000)),
            field(.provider, .text("Service Exemplu SRL")),
            field(.issueDate, day("2026-10-30")),
        ], documentID: UUID()), components: components, calendar: .bucharest)

        #expect(draft.ticked == ["brakes.padsFront", "engine.oil"])
        #expect(draft.parts["engine.oil"]?.cost == 420, "Oil and its filter add up on one row")
        #expect(draft.extras.map(\.name) == ["Manopera"])
        #expect(draft.total == 1_000)
        #expect(draft.provider == .new("Service Exemplu SRL"))
        #expect(CalendarDay(draft.date, calendar: .bucharest) == CalendarDay("2026-10-30"))
        #expect(draft.documentID != nil)
        #expect(draft.partsSum == 1_000)
    }

    @Test func theDraftBecomesOneVisitAndUndoTakesItAllBack() throws {
        let context = try makeContext()
        let car = try makeCar(context)
        var draft = VisitDraft(date: noon("2026-11-02"))
        draft.toggle("brakes.padsFront")
        draft.parts["brakes.padsFront"] = .init(cost: 380, brand: " Bosch ")
        draft.toggle("filters.cabin")
        draft.toggle("filters.cabin")
        draft.extras = [.init(name: "Odorizant", cost: 15), .init(name: "  ", cost: nil)]
        draft.odometer = 150_000
        #expect(draft.checklistItems.map(\.componentKey) == ["brakes.padsFront"])
        #expect(draft.checklistItems.first?.partBrandOrCode == "Bosch")
        #expect(draft.extraItems.map(\.name) == ["Odorizant"])

        let history = HistoryActions(context: context, now: { noon("2026-11-02") })
        let entry = try history.recordVisit(on: car, occurredAt: draft.date, checklist: draft.checklistItems, extraItems: draft.extraItems,
                                            totalCost: draft.totalMoney, odometer: draft.odometer, calendar: .bucharest)
        #expect(car.value("vehicle.odometer") == .number(150_000))
        let changes = VisitChange.changes(of: entry, on: car)
        #expect(changes.map(\.name) == ["Odorizant", "Plăcuțe frână față"], "Free-text jobs show too")
        #expect(changes.allSatisfy { $0.previous == nil })

        try history.undoVisit(entry)
        #expect(car.history?.isEmpty == true)
        #expect(car.value("vehicle.odometer") == .number(142_500), "The counter goes back to the last real reading")
        #expect(car.measurements?.contains { $0.value == 150_000 } == false)
    }

    @Test func theCounterEstimateNeverGoesBelowTheLastReading() {
        let readings = [
            CadenceCalculator.TelemetryReading(date: noon("2026-07-01"), metric: 140_000),
            CadenceCalculator.TelemetryReading(date: noon("2026-10-01"), metric: 143_000),
        ]
        let estimate = OdometerEstimate.value(readings: readings, fallback: nil, now: noon("2026-11-01"))
        #expect(estimate.map { $0 >= 143_000 && $0 <= 144_200 } == true, "About 1 000 km a month")
        #expect(OdometerEstimate.value(readings: [readings[1]], fallback: nil, now: noon("2026-11-01")) == 143_000)
        #expect(OdometerEstimate.value(readings: [], fallback: 90_000, now: noon("2026-11-01")) == 90_000)
    }

    @Test func wordingFollowsTheKindOfSection() {
        #expect(VisitWording.forTemplate(key: "vehicle", heroStyle: .vehicle).trade == .mechanic)
        #expect(VisitWording.forTemplate(key: "pet", heroStyle: .pet).title == "Am fost la veterinar")
        #expect(VisitWording.forTemplate(key: "home", heroStyle: .home).kind == .repair)
        #expect(VisitWording.forTemplate(key: "custom.x", heroStyle: .standard).trade == .other)
    }
}

// MARK: - What to bring

@MainActor
@Suite("Obligation requirements")
struct ObligationRequirementTests {
    @Test func itpNeedsAValidRCA() throws {
        let context = try makeContext()
        let car = try makeCar(context, rcaDue: "2026-11-10")
        let list = ObligationRequirements.list(forBlueprint: "vehicle.itp")
        let rca = try #require(list.first { $0.id == "rca" })
        #expect(ObligationRequirements.isInDosar(rca, asset: car, on: CalendarDay("2026-11-05"), calendar: .bucharest) == true)
        #expect(ObligationRequirements.isInDosar(rca, asset: car, on: CalendarDay("2026-12-01"), calendar: .bucharest) == false)
        #expect(ObligationRequirements.isInDosar(list[0], asset: car, on: CalendarDay("2026-11-05")) == nil)
    }

    @Test func documentsDependOnTheirType() {
        var values = FieldValues()
        values["document.type"] = .text(DocumentType.passport)
        #expect(ObligationRequirements.list(forBlueprint: "document.renew", values: values).contains { $0.id == "oldPassport" })
        #expect(ObligationRequirements.list(forBlueprint: "document.renew").isEmpty)
        #expect(ObligationRequirements.list(forBlueprint: nil).isEmpty)
    }
}
