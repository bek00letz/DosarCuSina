import CoreGraphics
import Foundation
import SwiftData
import Testing
@testable import DosarCuSina

/// Reads every relationship of `asset` and of what it points at, the way a screen drawing
/// the section does. A record a unit of work took back after it wrote can't be read until
/// it is fetched again; reading it here would stop the test run.
@MainActor
func readEveryRelationship(of asset: Asset) {
    _ = asset.obligations?.map(\.title)
    _ = asset.attachments?.map(\.fileName)
    _ = asset.history?.map { ($0.title, $0.items?.count, $0.providers?.count, $0.attachments?.count) }
    _ = asset.measurements?.map(\.value)
    _ = asset.providers?.map(\.name)
    _ = asset.children?.map(\.name)
    _ = asset.parent?.children?.count
}

/// How many records of each kind the store holds, to show a question saved nothing.
@MainActor
private func counts(_ context: ModelContext) throws -> [Int] {
    [
        try context.fetchCount(FetchDescriptor<Asset>()),
        try context.fetchCount(FetchDescriptor<Obligation>()),
        try context.fetchCount(FetchDescriptor<HistoryEntry>()),
        try context.fetchCount(FetchDescriptor<ServiceItem>()),
        try context.fetchCount(FetchDescriptor<MeasurementLog>()),
        try context.fetchCount(FetchDescriptor<DosarCuSina.Attachment>()),
        try context.fetchCount(FetchDescriptor<Provider>()),
    ]
}

private struct Failure: Error {}

/// Every question a step asks (a lower counter, something of the person's in an example) is
/// asked before its unit of work writes anything: after the question, the section reads as
/// it did and nothing was written; answered, it saves. And a unit taken back for any other
/// reason leaves its records readable.
@Suite("Questions before saving")
@MainActor
struct QuestionsBeforeSavingTests {

    private let today = "2026-06-01"

    /// A car with 45.724 km read on 10 January, a visit and an oil change.
    private func car(_ context: ModelContext, isExample: Bool = false) throws -> Asset {
        let template = try #require(try TemplateStore(context: context).template(forKey: BuiltInTemplates.Key.vehicle))
        var values = FieldValues()
        values[VehicleFields.odometer] = .number(45_724)
        let car = try AssetActions(context: context, calendar: .bucharest, now: { noon("2026-01-10") })
            .create(name: "VW Golf 2018", template: template, values: values, isExample: isExample)
        if !isExample {
            try HistoryActions(context: context, now: { noon("2026-01-10") }).record(on: car, kind: .repair, title: "Plăcuțe frână față")
        }
        return car
    }

    private func oilChange(on car: Asset, _ context: ModelContext) throws -> Obligation {
        let oil = Obligation(title: "Schimb ulei", kind: .maintenance, dueDay: CalendarDay("2026-06-01"),
                             recurrence: .metric(every: 10_000, unit: .kilometres, fallback: .years(1)))
        context.insert(oil)
        oil.asset = car
        try UnitOfWork.save(context)
        return oil
    }

    /// Asks, reads every relationship and checks nothing changed; then answers and saves.
    private func expectAsksFirst<Question: StepQuestion>(
        _ question: Question.Type, on car: Asset, in context: ModelContext,
        _ step: (LowerReadingAnswer?) async throws -> Void,
        sourceLocation: SourceLocation = #_sourceLocation
    ) async throws {
        let before = try counts(context)
        let readings = (car.measurements ?? []).map(\.value).sorted()
        await #expect(throws: question, sourceLocation: sourceLocation) { try await step(nil) }
        readEveryRelationship(of: car)
        #expect(context.hasChanges == false, "Nothing waits to be saved", sourceLocation: sourceLocation)
        #expect(try counts(context) == before, "Nothing was written", sourceLocation: sourceLocation)
        #expect((car.measurements ?? []).map(\.value).sorted() == readings, sourceLocation: sourceLocation)
        #expect(car.value(VehicleFields.odometer) == .number(45_724), sourceLocation: sourceLocation)
    }

    // MARK: A lower counter, on every path that records one

    @Test func editingASectionAsksFirst() async throws {
        let context = try makeContext()
        let golf = try car(context)
        let actions = AssetActions(context: context, calendar: .bucharest, now: { noon(today) })
        func edit(_ answer: LowerReadingAnswer?) throws {
            var values = golf.values
            values[VehicleFields.odometer] = .number(4_572)
            try actions.update(golf, name: "VW Golf 2018 TDI", values: values, notes: "Revizie la 50.000", lowerReading: answer)
        }
        try await expectAsksFirst(LowerReadingQuestion.self, on: golf, in: context) { try edit($0) }
        #expect(golf.name == "VW Golf 2018", "Not even the name")
        try edit(.correctOld)
        #expect(golf.name == "VW Golf 2018 TDI")
        #expect(golf.value(VehicleFields.odometer) == .number(4_572))
    }

    @Test func aReadingOnItsOwnAsksFirst() async throws {
        let context = try makeContext()
        let golf = try car(context)
        let actions = AssetActions(context: context, calendar: .bucharest, now: { noon(today) })
        try await expectAsksFirst(LowerReadingQuestion.self, on: golf, in: context) {
            try actions.recordReading(4_572, on: golf, source: .person, lowerReading: $0)
        }
        try await expectAsksFirst(LowerReadingQuestion.self, on: golf, in: context) {
            try actions.recordMeasurement(on: golf, kind: .odometer, value: 4_572, unit: .kilometres, lowerReading: $0)
        }
        try actions.recordReading(4_572, on: golf, source: .person, lowerReading: .keepAside)
        #expect(golf.measurements?.count == 2)
    }

    @Test func aRecordAsksFirst() async throws {
        let context = try makeContext()
        let golf = try car(context)
        let history = HistoryActions(context: context, now: { noon(today) })
        try await expectAsksFirst(LowerReadingQuestion.self, on: golf, in: context) {
            try history.record(on: golf, kind: .repair, title: "Bec far", metricReading: 4_572,
                               items: [LineItemDraft(name: "Bec H7")], lowerReading: $0)
        }
        try history.record(on: golf, kind: .repair, title: "Bec far", metricReading: 4_572, items: [LineItemDraft(name: "Bec H7")],
                           lowerReading: .keepAside)
        #expect(golf.history?.count == 2)
    }

    @Test func aVisitAsksFirst() async throws {
        let context = try makeContext()
        let golf = try car(context)
        let history = HistoryActions(context: context, now: { noon(today) })
        try await expectAsksFirst(LowerReadingQuestion.self, on: golf, in: context) {
            _ = try history.recordVisit(on: golf, checklist: [], extraItems: [LineItemDraft(name: "Ulei")], odometer: 4_572,
                                        documents: [DocumentDraft(fileName: "factura.pdf", kind: .invoice, originalData: Data([1]))],
                                        calendar: .bucharest, lowerReading: $0)
        }
        let visit = try history.recordVisit(on: golf, checklist: [], odometer: 4_572, calendar: .bucharest, lowerReading: .correctOld)
        #expect(visit.value.metricReading == 4_572)
    }

    @Test func gataAsksFirst() async throws {
        let context = try makeContext()
        let golf = try car(context)
        let oil = try oilChange(on: golf, context)
        let actions = ObligationActions(context: context, calendar: .bucharest, now: { noon(today) })
        try await expectAsksFirst(LowerReadingQuestion.self, on: golf, in: context) {
            _ = try actions.complete(oil, cost: Money(250), metricReading: 4_572, items: [LineItemDraft(name: "Ulei")], lowerReading: $0)
        }
        #expect(oil.dueDay == CalendarDay("2026-06-01"), "The deadline didn't move")
        _ = try actions.complete(oil, metricReading: 4_572, lowerReading: .keepAside)
        #expect(oil.dueDay != CalendarDay("2026-06-01"))
    }

    // MARK: Capture

    private func filer(_ context: ModelContext, store: CaptureDocumentStore, answer: LowerReadingAnswer? = nil) -> CaptureFiler {
        var filer = CaptureFiler(context: context, store: store, calendar: .bucharest, now: { noon(today) })
        filer.lowerReading = answer
        return filer
    }

    private func photo(_ store: CaptureDocumentStore, seed: UInt8) async throws -> CapturedDocumentRef {
        try await store.store(.init(pages: [CaptureDocumentStoreTests.page(width: 900, height: 640, seed: seed)], kind: .serviceInvoice)).ref
    }

    private func visit(on car: Asset, odometer: Double, cost: Decimal = 480, document: CapturedDocumentRef?) -> CaptureFiler.Visit {
        CaptureFiler.Visit(asset: car, kind: .maintenance, occurredAt: noon(today), checklist: [],
                           extraItems: [LineItemDraft(name: "Ulei și filtru")], totalCost: Money(cost), odometer: odometer,
                           odometerSource: .document, provider: .named("Service Exemplu SRL", trade: .mechanic), document: document,
                           documentTitle: "Factură service")
    }

    /// The visit form's filing found the firm (writing it) before the visit asked: now nothing is written first.
    @Test func capturesVisitAsksBeforeItKeepsTheFirm() async throws {
        let context = try makeContext()
        let golf = try car(context)
        let store = CaptureDocumentStore()
        let invoice = try await photo(store, seed: 61)
        try await expectAsksFirst(LowerReadingQuestion.self, on: golf, in: context) {
            _ = try await filer(context, store: store, answer: $0).file(.visit(visit(on: golf, odometer: 4_572, document: invoice)))
        }
        let outcome = try await filer(context, store: store, answer: .keepAside).file(.visit(visit(on: golf, odometer: 4_572, document: invoice)))
        #expect(outcome.visit?.providers?.first?.name == "Service Exemplu SRL")
        #expect(outcome.attachment?.historyEntry?.id == outcome.visit?.id)
    }

    @Test func capturesReviewAsksAboutTheKilometresItPrints() async throws {
        let context = try makeContext()
        let golf = try car(context)
        let fields = [
            CaptureField(key: .provider, value: .text("Service Exemplu SRL"), confidence: 0.9, sourceText: nil, tier: .heuristic),
            CaptureField(key: .issueDate, value: .day(CalendarDay(printedYear: 2026, month: 5, day: 30)!), confidence: 0.9, sourceText: nil, tier: .heuristic),
            CaptureField(key: .odometer, value: .metric(value: 4_572, unit: .kilometres), confidence: 0.9, sourceText: nil, tier: .heuristic),
        ]
        let routing = CaptureRouter.route(kind: .serviceInvoice, kindConfidence: 0.9, fields: fields)
        let result = CaptureResult(kind: .serviceInvoice, kindConfidence: 0.9, fields: fields, suggestions: routing.suggestions,
                                   reminder: routing.reminder, recognizedText: "", barcodes: [], document: nil, notices: [])
        var review = CaptureReview(result: result, assets: try context.fetch(FetchDescriptor<Asset>()), context: context)
        review.destination = .asset(golf.id)
        let store = CaptureDocumentStore()
        try await expectAsksFirst(LowerReadingQuestion.self, on: golf, in: context) {
            _ = try await filer(context, store: store, answer: $0).save(review)
        }
        _ = try await filer(context, store: store, answer: .keepAside).save(review)
        #expect(golf.measurements?.contains { $0.value == 4_572 && $0.recordedAt == noon("2026-05-30") } == true, "Dated by the invoice")
    }

    // MARK: An example

    @Test func aVisitOnAnExampleAsksBeforeItKeepsTheFirm() async throws {
        let context = try makeContext()
        let example = try car(context, isExample: true)
        let store = CaptureDocumentStore()
        let invoice = try await photo(store, seed: 62)
        try await expectAsksFirst(ExampleSectionQuestion.self, on: example, in: context) { _ in
            _ = try await filer(context, store: store).file(.visit(visit(on: example, odometer: 46_000, document: invoice)))
        }
        try ExampleDataService(context: context).adopt(sectionID: example.id)
        let outcome = try await filer(context, store: store).file(.visit(visit(on: example, odometer: 46_000, document: invoice)))
        #expect(outcome.visit?.isExample == false)
    }

    /// A category of one's own was written before the section asked whether it may go into an example.
    @Test func aSectionOfANewCategoryUnderAnExampleAsksFirst() async throws {
        let context = try makeContext()
        let example = try car(context, isExample: true)
        let model = AddSectionModel(request: AddSectionRequest(parentID: example.id))
        model.chooseCustom(CustomSectionDraft(name: "Remorcă", symbol: "shippingbox.fill", switches: CategorySwitches(hasDocuments: true, hasBills: false)))
        let categories = try context.fetchCount(FetchDescriptor<CategoryTemplate>())
        try await expectAsksFirst(ExampleSectionQuestion.self, on: example, in: context) { _ in _ = try model.create(context: context) }
        #expect(try context.fetchCount(FetchDescriptor<CategoryTemplate>()) == categories, "No category of its own left behind")
    }

    /// The edit sheet keeps the photo and the fields in one unit: the counter is asked before the photo is written.
    @Test func thePhotoAndALowerCounterAskBeforeThePhotoIsKept() async throws {
        let context = try makeContext()
        let golf = try car(context)
        let actions = AssetActions(context: context, calendar: .bucharest, now: { noon(today) })
        var values = golf.values
        values[VehicleFields.odometer] = .number(4_572)
        try await expectAsksFirst(LowerReadingQuestion.self, on: golf, in: context) { answer in
            try actions.askFirst(updating: golf, to: values, lowerReading: answer)
            try UnitOfWork.perform(in: context) {
                try actions.setPhoto(golf, Data([1, 2, 3]))
                _ = try actions.update(golf, name: golf.name, values: values, notes: nil, lowerReading: answer)
            }
        }
        #expect(golf.photoData == nil, "Not even the photo")
    }

    // MARK: The same invoice filed again

    @Test func theSameInvoiceFiledAgainUpdatesItsVisit() async throws {
        let context = try makeContext()
        let golf = try car(context)
        let store = CaptureDocumentStore()
        let invoice = try await photo(store, seed: 63)
        let first = try await filer(context, store: store).file(.visit(visit(on: golf, odometer: 48_000, document: invoice)))
        let entry = try #require(first.visit)
        let document = try #require(first.attachment)

        let again = try await filer(context, store: store)
            .file(.visit(visit(on: golf, odometer: 48_100, cost: 520, document: .kept(attachmentID: document.id))))
        #expect(again.visit?.id == entry.id, "The visit it was filed with, not a second one")
        #expect(golf.history?.filter { $0.kind == .maintenance }.count == 1)
        #expect(entry.totalCost == Money(520))
        #expect(entry.metricReading == 48_100)
        #expect(entry.items?.map(\.name) == ["Ulei și filtru"], "Its lines, once")
        #expect(golf.measurements?.map(\.value).sorted() == [45_724, 48_100], "Its reading, replaced")
        #expect(document.historyEntry?.id == entry.id)

        try #require(again.receipt).undo()
        #expect(entry.totalCost == Money(480), "Anulează brings the visit back as it was")
        #expect(golf.measurements?.map(\.value).sorted() == [45_724, 48_000])
    }

    // MARK: Any other failure

    /// A unit that read a section's readings, logged a visit and then failed: SwiftData leaves
    /// the section's relationships unreadable until it is fetched again, which the unit does.
    @Test func aFailedUnitLeavesItsRecordsReadable() throws {
        let context = try makeContext()
        let golf = try car(context)
        #expect(throws: Failure.self) {
            try UnitOfWork.perform(in: context) {
                _ = golf.measurements?.count
                golf.name = "VW Golf 2018 TDI"
                let entry = HistoryEntry(kind: .visit, title: "Vizită", occurredAt: noon(today))
                context.insert(entry)
                entry.asset = golf
                throw Failure()
            }
        }
        readEveryRelationship(of: golf)
        #expect(golf.measurements?.map(\.value) == [45_724])
        #expect(golf.history?.count == 1)
        #expect(golf.name == "VW Golf 2018")
    }

    @Test func aFailedSaveLeavesItsRecordsReadable() async throws {
        let context = try makeContext()
        let golf = try car(context)
        UnitOfWork.failNextCommitForTesting(Failure(), in: context)
        #expect(throws: Failure.self) {
            _ = try HistoryActions(context: context, now: { noon(today) }).recordVisit(on: golf, checklist: [], odometer: 48_000, calendar: .bucharest)
        }
        readEveryRelationship(of: golf)
        #expect(golf.measurements?.map(\.value) == [45_724])
        #expect(golf.history?.count == 1)
    }
}
