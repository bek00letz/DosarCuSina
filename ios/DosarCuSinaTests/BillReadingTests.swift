import Foundation
import SwiftData
import Testing
@testable import DosarCuSina

private func field(_ key: CaptureFieldKey, _ value: CaptureValue, confidence: Double = 0.9) -> CaptureField {
    CaptureField(key: key, value: value, confidence: confidence, sourceText: nil, tier: .heuristic)
}

private func day(_ iso: String) -> CaptureValue {
    let parts = iso.split(separator: "-").compactMap { Int($0) }
    return .day(CaptureDay(year: parts[0], month: parts[1], day: parts[2])!)
}

private func index(_ value: Decimal) -> CaptureValue { .number(value) }

/// A capture result routed the way the engine routes it.
private func capture(_ kind: CaptureDocumentKind, _ fields: [CaptureField], document: CapturedDocumentRef? = nil) -> CaptureResult {
    let routing = CaptureRouter.route(kind: kind, kindConfidence: 0.9, fields: fields)
    return CaptureResult(kind: kind, kindConfidence: 0.9, fields: fields, suggestions: routing.suggestions, reminder: routing.reminder,
                         recognizedText: "", barcodes: [], document: document, notices: [])
}

/// A utility bill with its meter index. Placeholder provider and codes.
private func bill(service: String = ServiceKind.gas, provider: String = "ENGIE Romania S.A.", meter: Decimal?,
                  meterConfidence: Double = 0.9, issued: String, due: String, document: CapturedDocumentRef? = nil) -> CaptureResult {
    var fields = [
        field(.provider, .text(provider)),
        field(.serviceKind, .text(service)),
        field(.clientCode, .text("1000000000")),
        field(.issueDate, day(issued)),
        field(.dueDate, day(due)),
        field(.total, .money(CaptureMoney(amount: 245, currencyCode: "RON"))),
    ]
    if service == ServiceKind.gas { fields.append(field(.clcCode, .text("DEG0000000000001"))) }
    if let meter { fields.append(field(.meterIndex, index(meter), confidence: meterConfidence)) }
    return capture(.utilityInvoice, fields, document: document)
}

/// A bill's meter index becomes a reading on the subscription it is filed under: through the
/// one reading path, in the unit the service gives, dated by the bill, once per document,
/// taken back with the filing.
@Suite("A bill's meter index as a reading")
@MainActor
struct BillReadingTests {

    private let today = "2026-11-06"

    private func filer(_ context: ModelContext, store: CaptureDocumentStore = CaptureDocumentStore(), on iso: String? = nil,
                       lowerReading: LowerReadingAnswer? = nil) -> CaptureFiler {
        let date = noon(iso ?? today)
        var filer = CaptureFiler(context: context, store: store, calendar: .bucharest, now: { date })
        filer.lowerReading = lowerReading
        return filer
    }

    private func home(_ context: ModelContext) throws -> Asset {
        let template = try #require(try TemplateStore(context: context).template(forKey: BuiltInTemplates.Key.home))
        var values = FieldValues()
        values["home.address"] = .text("Strada Exemplu nr. 1")
        return try AssetActions(context: context).create(name: "Casa Exemplu", template: template, values: values)
    }

    private func review(_ result: CaptureResult, _ context: ModelContext, edit: (inout CaptureReview) -> Void = { _ in }) throws -> CaptureReview {
        var review = CaptureReview(result: result, assets: try context.fetch(FetchDescriptor<Asset>()), context: context)
        edit(&review)
        return review
    }

    private func save(_ result: CaptureResult, _ context: ModelContext, store: CaptureDocumentStore = CaptureDocumentStore(),
                      on iso: String? = nil, lowerReading: LowerReadingAnswer? = nil,
                      edit: (inout CaptureReview) -> Void = { _ in }) async throws -> CaptureFiler.Outcome {
        try await filer(context, store: store, on: iso, lowerReading: lowerReading).save(try review(result, context, edit: edit))
    }

    private func plan(_ result: CaptureResult, _ context: ModelContext, edit: (inout CaptureReview) -> Void = { _ in }) throws -> CaptureFilingPlan {
        try filer(context).plan(for: try review(result, context, edit: edit))
    }

    private func readings(of asset: Asset) -> [MeasurementLog] {
        (asset.measurements ?? []).filter { !$0.isDeleted }.sorted { $0.recordedAt < $1.recordedAt }
    }

    private func newPhoto(_ store: CaptureDocumentStore, seed: UInt8) async throws -> CapturedDocumentRef {
        try await store.store(.init(pages: [CaptureDocumentStoreTests.page(width: 900, height: 640, seed: seed)], kind: .utilityInvoice)).ref
    }

    // MARK: The meter a service has

    @Test func theServiceSaysWhatTheMeterMeasuresAndItsUnit() {
        #expect(ServiceKind.meterKind(for: ServiceKind.gas) == .gas)
        #expect(ServiceKind.meterKind(for: ServiceKind.electricity) == .electricity)
        #expect(ServiceKind.meterKind(for: ServiceKind.water) == .coldWater)
        #expect(ServiceKind.meterKind(for: ServiceKind.gas)?.defaultUnit == .cubicMetres)
        #expect(ServiceKind.meterKind(for: ServiceKind.electricity)?.defaultUnit == .kilowattHours)
        #expect(ServiceKind.meterKind(for: ServiceKind.water)?.defaultUnit == .cubicMetres)
        for service in [ServiceKind.internetTV, ServiceKind.mobile, ServiceKind.other] {
            #expect(ServiceKind.meterKind(for: service) == nil, "No meter: \(service)")
        }
        #expect(ServiceKind.meterKind(for: nil) == nil)
    }

    // MARK: Filing

    @Test("Filing a bill records one reading, from the document, in its service's unit", arguments: [
        (ServiceKind.gas, MeasurementKind.gas, MeasurementUnit.cubicMetres),
        (ServiceKind.electricity, MeasurementKind.electricity, MeasurementUnit.kilowattHours),
        (ServiceKind.water, MeasurementKind.coldWater, MeasurementUnit.cubicMetres),
    ])
    func aBillRecordsItsIndex(_ service: String, _ kind: MeasurementKind, _ unit: MeasurementUnit) async throws {
        let context = try makeContext()
        let house = try home(context)
        let store = CaptureDocumentStore()
        let photo = try await newPhoto(store, seed: 41)
        let result = bill(service: service, meter: 12_345, issued: "2026-10-05", due: "2026-11-20", document: photo)

        let planned = try plan(result, context)
        let reading = try #require(planned.meter?.reading)
        #expect(reading == SubscriptionMeter.Reading(value: 12_345, kind: kind, unit: unit, day: CalendarDay("2026-10-05")))

        let outcome = try await save(result, context, store: store)
        let subscription = try #require(outcome.asset)
        #expect(subscription.parent?.id == house.id, "The meter belongs to the supply point, under its home")
        let kept = readings(of: subscription)
        #expect(kept.count == 1, "One reading")
        let log = try #require(kept.first)
        #expect(log.value == 12_345)
        #expect(log.measurementUnit == unit)
        #expect(log.kind == kind)
        #expect(CalendarDay(log.recordedAt, calendar: .bucharest) == CalendarDay("2026-10-05"), "From the document: dated by the bill")
        let document = try #require(outcome.attachment)
        #expect(log.attachments?.map(\.id) == [document.id], "Linked to the bill it was read from")
        #expect(outcome.reading?.id == log.id)
        #expect(readings(of: house).isEmpty, "Never on the home, where gas and water would mix")

        let last = try #require(SubscriptionMeter.last(on: subscription, calendar: .bucharest))
        #expect(last == SubscriptionMeter.Last(value: 12_345, unit: unit, day: CalendarDay("2026-10-05"), isFromDocument: true))
    }

    @Test func theReviewSaysWhereTheIndexGoes() throws {
        let context = try makeContext()
        _ = try home(context)
        let planned = try plan(bill(meter: 12_345, issued: "2026-10-05", due: "2026-11-20"), context)
        let meter = try #require(planned.meter)
        #expect(CaptureReviewView.meterText(meter) == "Indexul 12.345 m³ se trece la „Gaz – ENGIE Romania S.A.”.")
        #expect(CaptureReviewView.meterText(.unknownService) == "Indexul nu-l trec: nu știu dacă e de gaz, de curent sau de apă.")
    }

    @Test func anIndexGoesNowhereWithoutAMeter() throws {
        let context = try makeContext()
        _ = try home(context)
        // No service read, and a new subscription: what the index measures isn't known.
        var unknown = bill(meter: 12_345, issued: "2026-10-05", due: "2026-11-20")
        unknown = capture(.utilityInvoice, unknown.fields.filter { $0.key != .serviceKind && $0.key != .clcCode })
        #expect(try plan(unknown, context).meter == .unknownService)
        // A phone plan has no meter.
        let mobile = bill(service: ServiceKind.mobile, provider: "Orange Romania S.A.", meter: 120, issued: "2026-10-05", due: "2026-11-20")
        #expect(try plan(mobile, context).meter == nil)
        // No place chosen yet.
        let unplaced = try plan(bill(meter: 12_345, issued: "2026-10-05", due: "2026-11-20"), context) { $0.destination = .none }
        #expect(unplaced.meter == nil)
        // No index read.
        #expect(try plan(bill(meter: nil, issued: "2026-10-05", due: "2026-11-20"), context).meter == nil)
    }

    @Test func aCheckedIndexIsRecordedAsThePersonLeftIt() async throws {
        let context = try makeContext()
        _ = try home(context)
        let result = bill(meter: 12_345, meterConfidence: 0.4, issued: "2026-10-05", due: "2026-11-20")
        let shown = try review(result, context)
        #expect(shown.fields.first { $0.key == .meterIndex }?.needsCheck == true, "Marked Verifică")
        #expect(shown.visibleFields.contains { $0.key == .meterIndex }, "Shown in the review like any other value")

        let outcome = try await save(result, context) { review in
            let at = review.fields.firstIndex { $0.key == .meterIndex }!
            review.fields[at].confirm(.number(12_346))
        }
        let subscription = try #require(outcome.asset)
        #expect(readings(of: subscription).map(\.value) == [12_346], "The corrected value, not the one read")
    }

    @Test func aClearedIndexIsNotRecorded() async throws {
        let context = try makeContext()
        _ = try home(context)
        let outcome = try await save(bill(meter: 12_345, meterConfidence: 0.4, issued: "2026-10-05", due: "2026-11-20"), context) { review in
            let at = review.fields.firstIndex { $0.key == .meterIndex }!
            review.fields[at].confirm(nil)
        }
        #expect(readings(of: try #require(outcome.asset)).isEmpty)
    }

    @Test func aLowerIndexAsksAndSavesNothingUntilAnswered() async throws {
        let context = try makeContext()
        _ = try home(context)
        let first = try await save(bill(meter: 12_345, issued: "2026-10-05", due: "2026-10-25"), context, on: "2026-10-06")
        let gas = try #require(first.asset)
        let lower = bill(meter: 12_000, issued: "2026-11-05", due: "2026-11-25")

        await #expect(throws: LowerReadingQuestion.self) { _ = try await save(lower, context) }
        if let home = gas.parent { readEveryRelationship(of: home) }
        readEveryRelationship(of: gas)
        #expect(context.hasChanges == false)
        #expect(readings(of: gas).map(\.value) == [12_345], "Nothing saved before an answer")
        #expect((gas.history ?? []).filter { $0.kind == .payment }.count == 1, "Not even the bill")
        do {
            _ = try await save(lower, context)
        } catch let question as LowerReadingQuestion {
            #expect(question.previous == 12_345)
            #expect(question.value == 12_000)
            #expect(question.unit == .cubicMetres)
            #expect(question.question == "Citirea e mai mică decât ultima dată. Corectez citirea veche?")
        }

        let kept = try await save(lower, context, lowerReading: .keepAside)
        #expect(kept.asset?.id == gas.id)
        #expect(readings(of: gas).map(\.value) == [12_345, 12_000], "Kept aside")
        #expect(SubscriptionMeter.last(on: gas, calendar: .bucharest)?.value == 12_345, "The aside one doesn't count")
    }

    @Test func correctingTheOldIndexKeepsTheNewOne() async throws {
        let context = try makeContext()
        _ = try home(context)
        let gas = try #require(try await save(bill(meter: 12_345, issued: "2026-10-05", due: "2026-10-25"), context, on: "2026-10-06").asset)
        _ = try await save(bill(meter: 12_000, issued: "2026-11-05", due: "2026-11-25"), context, lowerReading: .correctOld)
        #expect(readings(of: gas).map(\.value) == [12_000])
        #expect(SubscriptionMeter.last(on: gas, calendar: .bucharest)?.day == CalendarDay("2026-11-05"))
    }

    @Test func anOlderBillFiledLateNeverAsks() async throws {
        let context = try makeContext()
        _ = try home(context)
        let gas = try #require(try await save(bill(meter: 12_345, issued: "2026-10-05", due: "2026-10-25"), context, on: "2026-10-06").asset)
        _ = try await save(bill(meter: 12_100, issued: "2026-09-05", due: "2026-09-25"), context)
        #expect(readings(of: gas).map(\.value) == [12_100, 12_345], "Its own day, before the newer one")
        #expect(SubscriptionMeter.last(on: gas, calendar: .bucharest)?.value == 12_345)
    }

    // MARK: Undo

    @Test func undoingTheFilingTakesTheReadingBack() async throws {
        let context = try makeContext()
        _ = try home(context)
        let gas = try #require(try await save(bill(meter: 12_345, issued: "2026-10-05", due: "2026-10-25"), context, on: "2026-10-06").asset)
        let next = try await save(bill(meter: 12_500, issued: "2026-11-05", due: "2026-11-25"), context)
        #expect(readings(of: gas).map(\.value) == [12_345, 12_500])

        try #require(next.receipt).undo()
        #expect(readings(of: gas).map(\.value) == [12_345], "Only this bill's reading goes")
        #expect(try context.fetchCount(FetchDescriptor<MeasurementLog>()) == 1)
    }

    @Test func undoingTheFirstBillTakesTheSubscriptionAndItsReading() async throws {
        let context = try makeContext()
        _ = try home(context)
        let outcome = try await save(bill(meter: 12_345, issued: "2026-10-05", due: "2026-10-25"), context)
        try #require(outcome.receipt).undo()
        #expect(try context.fetchCount(FetchDescriptor<MeasurementLog>()) == 0)
    }

    // MARK: Once per document

    @Test func refilingTheSameBillRecordsItOnce() async throws {
        let context = try makeContext()
        _ = try home(context)
        let store = CaptureDocumentStore()
        let photo = try await newPhoto(store, seed: 42)
        let first = try await save(bill(meter: 12_345, issued: "2026-10-05", due: "2026-11-20", document: photo), context, store: store)
        let gas = try #require(first.asset)
        let document = try #require(first.attachment)

        // The same photo again: capture finds the kept copy.
        let again = bill(meter: 12_345, issued: "2026-10-05", due: "2026-11-20", document: .kept(attachmentID: document.id))
        let planned = try #require(try plan(again, context).meter)
        let reading = try #require(planned.reading)
        #expect(planned == .alreadyKept(reading, subscription: gas.name))
        #expect(CaptureReviewView.meterText(planned) == "Indexul 12.345 m³ e deja trecut la „\(gas.name)”.")
        let second = try await save(again, context)
        #expect(second.asset?.id == gas.id)
        #expect(readings(of: gas).count == 1, "Not recorded twice")
        #expect(second.reading?.id == first.reading?.id)

        // Filed again with the index corrected: still one reading, the corrected one.
        let corrected = bill(meter: 12_354, issued: "2026-10-05", due: "2026-11-20", document: .kept(attachmentID: document.id))
        _ = try await save(corrected, context)
        #expect(readings(of: gas).map(\.value) == [12_354])
        #expect(document.measurement?.value == 12_354)
    }

    @Test func theSameIndexOnTheSameDayIsTheSameReading() async throws {
        let context = try makeContext()
        _ = try home(context)
        // The same bill read from two different photos: two documents, one reading.
        let store = CaptureDocumentStore()
        let one = try await newPhoto(store, seed: 43)
        let other = try await newPhoto(store, seed: 44)
        let gas = try #require(try await save(bill(meter: 12_345, issued: "2026-10-05", due: "2026-11-20", document: one), context, store: store).asset)
        let second = try await save(bill(meter: 12_345, issued: "2026-10-05", due: "2026-11-20", document: other), context, store: store)
        #expect(readings(of: gas).count == 1)
        #expect(second.attachment?.measurement?.id == readings(of: gas).first?.id, "Both bills point at it")
    }

    @Test func aBillMovedOffItsSubscriptionTakesItsReading() async throws {
        let context = try makeContext()
        _ = try home(context)
        let store = CaptureDocumentStore()
        let photo = try await newPhoto(store, seed: 45)
        let first = try await save(bill(meter: 12_345, issued: "2026-10-05", due: "2026-11-20", document: photo), context, store: store)
        let gas = try #require(first.asset)
        let document = try #require(first.attachment)
        _ = try await save(bill(meter: 12_345, issued: "2026-10-05", due: "2026-11-20", document: .kept(attachmentID: document.id)), context) {
            $0.destination = .none
        }
        #expect(readings(of: gas).isEmpty, "The reading follows the bill as filed now")
        #expect(document.measurement == nil)
    }

    // MARK: The page

    @Test func thePageShowsTheLastIndexInTheServicesUnit() throws {
        let context = try makeContext()
        let template = try #require(try TemplateStore(context: context).template(forKey: BuiltInTemplates.Key.subscription))
        var values = FieldValues()
        values[SubscriptionFields.service] = .text(ServiceKind.electricity)
        let power = try AssetActions(context: context).create(name: "Curent – Furnizor Exemplu", template: template, values: values)
        #expect(SubscriptionMeter.last(on: power) == nil, "Nothing before the first reading")

        let actions = AssetActions(context: context)
        try actions.recordMeasurement(on: power, kind: .electricity, value: 4_100, unit: .kilowattHours, at: noon("2026-09-05"))
        try actions.recordMeasurement(on: power, kind: .electricity, value: 4_350, unit: .kilowattHours, at: noon("2026-10-05"))
        try actions.recordMeasurement(on: power, kind: .gas, value: 9_000, unit: .cubicMetres, at: noon("2026-10-06"))
        let last = try #require(SubscriptionMeter.last(on: power, calendar: .bucharest))
        #expect(last == SubscriptionMeter.Last(value: 4_350, unit: .kilowattHours, day: CalendarDay("2026-10-05"), isFromDocument: false),
                "The service's unit only")
        #expect(last.written == "4.350 kWh")
        #expect(SubscriptionMeter.written(1_234.567, in: .cubicMetres) == "1.234,567 m³", "A meter's decimals are kept")
    }
}
