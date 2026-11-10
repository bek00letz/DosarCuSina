import Foundation
import SwiftData
import Testing
@testable import DosarCuSina

private func field(_ key: CaptureFieldKey, _ value: CaptureValue) -> CaptureField {
    CaptureField(key: key, value: value, confidence: 0.9, sourceText: nil, tier: .heuristic)
}

private func day(_ iso: String) -> CaptureValue {
    let parts = iso.split(separator: "-").compactMap { Int($0) }
    return .day(CalendarDay(printedYear: parts[0], month: parts[1], day: parts[2])!)
}

/// A gas bill with its meter index, routed the way the engine routes it. Placeholder provider and codes.
private func gasBill(meter: Decimal, issued: String, due: String) -> CaptureResult {
    let fields = [
        field(.provider, .text("ENGIE Romania S.A.")),
        field(.serviceKind, .text(ServiceKind.gas)),
        field(.clientCode, .text("1000000000")),
        field(.clcCode, .text("DEG0000000000001")),
        field(.issueDate, day(issued)),
        field(.dueDate, day(due)),
        field(.total, .money(Money(245, currency: "RON"))),
        field(.meterIndex, .number(meter)),
    ]
    let routing = CaptureRouter.route(kind: .utilityInvoice, kindConfidence: 0.9, fields: fields)
    return CaptureResult(kind: .utilityInvoice, kindConfidence: 0.9, fields: fields, suggestions: routing.suggestions, reminder: routing.reminder,
                         recognizedText: "", barcodes: [], document: nil, notices: [])
}

/// "Contor nou": a reading lower than the last one can start a new counter (a replaced meter or
/// dashboard, one that went round). The old readings stay as history, they are no longer
/// compared with the new ones, the value shown is the new counter's, and every rate counts each
/// counter on its own. For a car's kilometres and a subscription's meter alike, through the one
/// reading path.
@MainActor
@Suite("A new counter")
struct NewCounterTests {
    // MARK: A car's kilometres

    private func car(_ context: ModelContext, km: Double = 145_000, on day: String = "2026-01-10") throws -> Asset {
        let template = try #require(try TemplateStore(context: context).template(forKey: BuiltInTemplates.Key.vehicle))
        var values = FieldValues()
        values["vehicle.odometer"] = .number(km)
        return try AssetActions(context: context, calendar: .bucharest, now: { noon(day) }).create(name: "VW Golf 2018", template: template, values: values)
    }

    private func edit(_ car: Asset, km: Double, in context: ModelContext, on day: String, answer: LowerReadingAnswer? = nil) throws {
        var values = car.values
        values["vehicle.odometer"] = .number(km)
        try AssetActions(context: context, calendar: .bucharest, now: { noon(day) })
            .update(car, name: car.name, values: values, notes: car.notes, lowerReading: answer)
    }

    private func readings(of asset: Asset) -> [MeasurementLog] {
        (asset.measurements ?? []).filter { !$0.isDeleted }.sorted { $0.recordedAt < $1.recordedAt }
    }

    @Test func theQuestionOffersThreeAnswers() {
        #expect(LowerReadingAnswer.allCases == [.correctOld, .keepAside, .newCounter])
        #expect(LowerReadingAnswer.allCases.map(\.title) == ["Corectează citirea veche", "Lasă citirea veche", "Contor nou"])
        let question = LowerReadingQuestion(previous: 145_000, previousDate: noon("2026-01-10"), value: 1_200, unit: .kilometres)
        #expect(question.explanation.hasSuffix("Dacă e un contor nou, cele vechi rămân în istoric."))
    }

    @Test func aNewCounterKeepsTheOldReadingsAndShowsTheNewOne() throws {
        let context = try makeContext()
        let golf = try car(context)
        #expect(throws: LowerReadingQuestion.self) { try edit(golf, km: 1_200, in: context, on: "2026-03-01") }

        try edit(golf, km: 1_200, in: context, on: "2026-03-01", answer: .newCounter)
        #expect(readings(of: golf).map(\.value) == [145_000, 1_200], "The old dashboard's reading stays")
        #expect(readings(of: golf).map(\.startsCounter) == [false, true])
        #expect(golf.value("vehicle.odometer") == .number(1_200), "Kilometraj shows the new dashboard")
        #expect(HouseholdMutations.counterStart(of: golf, unit: .kilometres)?.value == 1_200)
        let series = HouseholdMutations.readingSeries(of: golf, unit: .kilometres)
        #expect(series.counters.map { $0.map(\.metric) } == [[145_000], [1_200]])
        #expect(series.setAside.isEmpty, "Nothing is set aside: each counter counts on its own")
    }

    @Test func laterReadingsOnTheNewCounterNeverAsk() throws {
        let context = try makeContext()
        let golf = try car(context)
        try edit(golf, km: 1_200, in: context, on: "2026-03-01", answer: .newCounter)
        try edit(golf, km: 2_500, in: context, on: "2026-04-01")
        #expect(golf.value("vehicle.odometer") == .number(2_500))

        // A lower one on the new counter asks about the new counter only.
        do {
            try edit(golf, km: 2_000, in: context, on: "2026-05-01")
            Issue.record("A lower reading on the new counter asks")
        } catch let question as LowerReadingQuestion {
            #expect(question.previous == 2_500, "Compared with the new counter, never the old one")
        }
    }

    @Test func anOlderReadingFiledLateBelongsToTheOldCounter() throws {
        let context = try makeContext()
        let golf = try car(context, km: 140_000, on: "2026-01-10")
        try edit(golf, km: 1_200, in: context, on: "2026-03-01", answer: .newCounter)
        // An invoice from before the change, with the old dashboard's kilometres: earlier, on the old counter.
        var values = golf.values
        values["vehicle.odometer"] = .number(142_000)
        try AssetActions(context: context, calendar: .bucharest, now: { noon("2026-04-01") })
            .update(golf, name: golf.name, values: values, notes: nil, readingSource: .document, readingDate: noon("2026-02-01"))
        let series = HouseholdMutations.readingSeries(of: golf, unit: .kilometres)
        #expect(series.counters.map { $0.map(\.metric) } == [[140_000, 142_000], [1_200]])
        #expect(golf.value("vehicle.odometer") == .number(1_200))
    }

    @Test func correctingAReadingOnTheNewCounterKeepsTheCounter() throws {
        let context = try makeContext()
        let golf = try car(context)
        try edit(golf, km: 12_000, in: context, on: "2026-03-01", answer: .newCounter)
        // 12.000 was a typo for 1.200: correcting it takes it away, and the new counter passes on.
        try edit(golf, km: 1_200, in: context, on: "2026-03-02", answer: .correctOld)
        #expect(readings(of: golf).map(\.value) == [145_000, 1_200], "The old dashboard's reading stays")
        #expect(readings(of: golf).map(\.startsCounter) == [false, true])
        #expect(golf.value("vehicle.odometer") == .number(1_200))
    }

    @Test func deletingTheFirstReadingOfANewCounterHandsItOn() throws {
        let context = try makeContext()
        let golf = try car(context)
        let history = HistoryActions(context: context, now: { noon("2026-03-01") })
        let visit = try history.recordVisit(on: golf, occurredAt: noon("2026-03-01"), checklist: [], odometer: 1_200,
                                            calendar: .bucharest, lowerReading: .newCounter).value
        try edit(golf, km: 2_500, in: context, on: "2026-04-01")
        try history.delete(visit)
        #expect(readings(of: golf).map(\.value) == [145_000, 2_500])
        #expect(readings(of: golf).map(\.startsCounter) == [false, true], "The next reading of the new counter starts it")
        #expect(golf.value("vehicle.odometer") == .number(2_500))
    }

    @Test func filingTheSameVisitAgainKeepsItsNewCounter() throws {
        let context = try makeContext()
        let golf = try car(context)
        let history = HistoryActions(context: context, now: { noon("2026-03-01") })
        let visit = try history.recordVisit(on: golf, occurredAt: noon("2026-03-01"), checklist: [], odometer: 1_200,
                                            calendar: .bucharest, lowerReading: .newCounter).value
        // The same invoice again, its kilometres corrected: nothing to ask, it is still the new counter's first.
        _ = try history.recordVisit(on: golf, occurredAt: noon("2026-03-01"), checklist: [], odometer: 1_250,
                                    calendar: .bucharest, replacing: visit)
        #expect(readings(of: golf).map(\.value) == [145_000, 1_250])
        #expect(readings(of: golf).map(\.startsCounter) == [false, true])
        #expect(golf.value("vehicle.odometer") == .number(1_250))
    }

    // MARK: Undo

    @Test func anulareazaTakesTheNewCounterBack() throws {
        let context = try makeContext()
        let golf = try car(context)
        let done = try HistoryActions(context: context, now: { noon("2026-03-01") })
            .recordVisit(on: golf, occurredAt: noon("2026-03-01"), checklist: [], odometer: 1_200, calendar: .bucharest, lowerReading: .newCounter)
        #expect(golf.value("vehicle.odometer") == .number(1_200))
        try done.receipt.undo()
        #expect(readings(of: golf).map(\.value) == [145_000])
        #expect(HouseholdMutations.counterStart(of: golf, unit: .kilometres) == nil)
        #expect(golf.value("vehicle.odometer") == .number(145_000))
    }

    @Test func notANewCounterTakesItBackLaterAndCanBeUndone() throws {
        let context = try makeContext()
        let golf = try car(context)
        try edit(golf, km: 1_200, in: context, on: "2026-03-01", answer: .newCounter)
        let start = try #require(HouseholdMutations.counterStart(of: golf, unit: .kilometres))

        let receipt = try AssetActions(context: context, calendar: .bucharest, now: { noon("2026-03-05") }).notANewCounter(start)
        #expect(HouseholdMutations.counterStart(of: golf, unit: .kilometres) == nil)
        #expect(readings(of: golf).map(\.value) == [145_000, 1_200], "Nothing is deleted")
        #expect(golf.value("vehicle.odometer") == .number(145_000), "One counter again: the lower one is set aside")
        #expect(HouseholdMutations.readingSeries(of: golf, unit: .kilometres).setAside.map(\.metric) == [1_200])

        try receipt.undo()
        #expect(HouseholdMutations.counterStart(of: golf, unit: .kilometres)?.value == 1_200)
        #expect(golf.value("vehicle.odometer") == .number(1_200))
    }

    // MARK: Rates stay sane across the change

    private func reading(_ iso: String, _ km: Double, starts: Bool = false) -> CadenceCalculator.TelemetryReading {
        .init(date: noon(iso), metric: km, startsCounter: starts)
    }

    @Test func aCarsPaceCountsEachCounterOnItsOwn() throws {
        // 3.000 km in 90 days on the old dashboard, 1.000 km in 31 days on the new one.
        let readings = [
            reading("2026-01-01", 100_000), reading("2026-04-01", 103_000),
            reading("2026-05-01", 500, starts: true), reading("2026-06-01", 1_500),
        ]
        let series = ReadingSeries(readings)
        #expect(series.current == 1_500)
        let progress = try #require(series.progress())
        #expect(progress.distance == 4_000, "Each counter's own distance, nothing across the change")
        #expect(abs(progress.days - 121) < 0.1, "The month between the counters counts for neither")
        let rate = try #require(MaintenanceLog.monthlyRate(readings))
        #expect(abs(rate - 4_000.0 / 121 * 30) < 1)

        // Projected from the new counter's value at the joined pace, never a negative rate.
        let projection = try #require(CadenceCalculator.projectTelemetryDueDate(
            currentMetric: 1_500, targetMetric: 11_500, readings: readings, currentDate: noon("2026-06-01"), calendar: .bucharest))
        #expect(projection.isEstimatedFromBaseline == false)
        #expect(projection.hasRollbackAnomaly == false, "A new counter is no rollback")
        #expect(projection.dailyBurnRate > 0)
        #expect(abs(Double(projection.daysRemaining) - 10_000 / (4_000.0 / 121)) < 2)

        // The visit form's estimate starts from the new dashboard.
        let estimate = try #require(OdometerEstimate.value(readings: readings, fallback: nil, now: noon("2026-06-01")))
        #expect(estimate >= 1_500 && estimate < 2_000)
    }

    @Test func distanceSinceAJobCrossesTheChange() throws {
        let readings = [
            reading("2026-01-01", 100_000), reading("2026-04-01", 103_000),
            reading("2026-05-01", 500, starts: true), reading("2026-06-01", 1_500),
        ]
        let series = ReadingSeries(readings)
        #expect(series.distance(from: (noon("2026-02-01"), 101_000), to: (noon("2026-06-01"), 1_500)) == 3_000, "2.000 on the old, 1.000 on the new")
        #expect(series.distance(from: (noon("2026-05-15"), 900), to: (noon("2026-06-01"), 1_500)) == 600, "On one counter, the difference")

        // "Acum … km" since the pads, and when they are due again, on the counter in use.
        let pads = [
            HistoryItemSnapshot(componentKey: "brakes.padsFront", name: "Plăcuțe", occurredAt: noon("2025-01-01"), metricReading: 70_000),
            HistoryItemSnapshot(componentKey: "brakes.padsFront", name: "Plăcuțe", occurredAt: noon("2026-02-01"), metricReading: 101_000),
        ]
        let last = try #require(MaintenanceLog.lastOccurrence(of: "brakes.padsFront", in: pads, currentMetric: 1_500, readings: readings,
                                                              now: noon("2026-06-01"), calendar: .bucharest))
        #expect(last.metricSince == 3_000)
        let next = try #require(MaintenanceLog.nextEstimate(of: "brakes.padsFront", in: pads, readings: readings, currentMetric: 1_500,
                                                            now: noon("2026-06-01"), calendar: .bucharest))
        #expect(next.basis == .distance)
        #expect(next.metric.map { abs($0 - 29_500) < 0.5 } == true, "What is left of the usual 31.000 km (1.500 + 31.000 − 3.000), on the new dashboard")
    }

    @Test func aSeriesMadeAgainFromItsReadingsSplitsTheSameWay() {
        let readings = [reading("2026-01-01", 100_000), reading("2026-05-01", 500, starts: true), reading("2026-06-01", 1_500)]
        let series = ReadingSeries(readings)
        #expect(ReadingSeries(series.readings) == series)
    }

    @Test func aRepairNeverTakesTheNewCountersFirstReadingForALostDigit() throws {
        let context = try makeContext()
        let golf = try car(context, km: 45_724, on: "2026-01-10")
        try edit(golf, km: 4_572, in: context, on: "2026-03-01", answer: .newCounter)
        try edit(golf, km: 5_000, in: context, on: "2026-04-01")
        var scan = DataRepairScan(context: context, calendar: .bucharest)
        #expect(try CounterOutliersStep().findings(&scan).isEmpty)
    }

    // MARK: A subscription's meter, through capture

    private func home(_ context: ModelContext) throws -> Asset {
        let template = try #require(try TemplateStore(context: context).template(forKey: BuiltInTemplates.Key.home))
        var values = FieldValues()
        values["home.address"] = .text("Strada Exemplu nr. 1")
        return try AssetActions(context: context).create(name: "Casa Exemplu", template: template, values: values)
    }

    private func file(_ result: CaptureResult, _ context: ModelContext, on iso: String, answer: LowerReadingAnswer? = nil) async throws -> CaptureFiler.Outcome {
        var filer = CaptureFiler(context: context, store: CaptureDocumentStore(), calendar: .bucharest, now: { noon(iso) })
        filer.lowerReading = answer
        let review = CaptureReview(result: result, assets: try context.fetch(FetchDescriptor<Asset>()), context: context)
        return try await filer.save(review)
    }

    @Test func aReplacedGasMeterAsksFirstThenCountsOnItsOwn() async throws {
        let context = try makeContext()
        _ = try home(context)
        let gas = try #require(try await file(gasBill(meter: 12_345, issued: "2026-09-05", due: "2026-09-25"), context, on: "2026-09-06").asset)
        _ = try await file(gasBill(meter: 12_500, issued: "2026-10-05", due: "2026-10-25"), context, on: "2026-10-06")

        // The new meter's first bill: asked before anything is saved.
        let first = gasBill(meter: 20, issued: "2026-11-05", due: "2026-11-25")
        await #expect(throws: LowerReadingQuestion.self) { _ = try await file(first, context, on: "2026-11-06") }
        #expect(context.hasChanges == false)
        #expect(readings(of: gas).map(\.value) == [12_345, 12_500])

        _ = try await file(first, context, on: "2026-11-06", answer: .newCounter)
        #expect(readings(of: gas).map(\.value) == [12_345, 12_500, 20], "The old meter's indexes stay")
        #expect(SubscriptionMeter.last(on: gas, calendar: .bucharest)?.value == 20, "Ultimul index is the new meter's")

        // The next bill asks nothing.
        _ = try await file(gasBill(meter: 80, issued: "2026-12-05", due: "2026-12-25"), context, on: "2026-12-06")
        #expect(SubscriptionMeter.last(on: gas, calendar: .bucharest)?.value == 80)
        let progress = try #require(HouseholdMutations.readingSeries(of: gas, unit: .cubicMetres).progress())
        #expect(progress.distance == 155 + 60, "Consumption counted on each meter on its own")
    }

    // MARK: Backups

    @Test func aBackupCarriesTheNewCounterBothWays() throws {
        let source = try makeInMemoryContainer()
        let context = ModelContext(source)
        try TemplateStore(context: context).installBuiltIns()
        let golf = try car(context)
        try edit(golf, km: 1_200, in: context, on: "2026-03-01", answer: .newCounter)
        let data = try DossierArchiveService(container: source, calendar: .bucharest).exportData(exportedAt: noon("2026-11-02"))

        let target = try makeInMemoryContainer()
        try DossierArchiveService(container: target, calendar: .bucharest).importArchive(data, mode: .replace)
        let copy = try #require(try ModelContext(target).fetch(FetchDescriptor<Asset>()).first { $0.name == "VW Golf 2018" })
        #expect(readings(of: copy).map(\.value) == [145_000, 1_200])
        #expect(readings(of: copy).map(\.startsCounter) == [false, true])
        #expect(HouseholdMutations.readingSeries(of: copy, unit: .kilometres).current == 1_200)
    }

    @Test func aReadingWritesStartsCounterOnlyWhenItStartsOne() throws {
        let plain = DossierV3.Measurement(id: UUID().uuidString, kind: "odometer", name: "", value: 1, unit: "km", recordedAt: noon("2026-01-01"),
                                          isSelfRead: true, isExample: false)
        let json = try #require(String(data: try JSONEncoder().encode(plain), encoding: .utf8))
        #expect(!json.contains("startsCounter"), "An archive stays as it was for a reading that starts nothing")
    }

    @Test func anOlderBackupImportsAsOneCounter() throws {
        let container = try makeInMemoryContainer()
        try DossierArchiveService(container: container, calendar: .bucharest).importArchive(try Fixtures.archive("dosar-v3/household"), mode: .replace)
        let logs = try ModelContext(container).fetch(FetchDescriptor<MeasurementLog>())
        #expect(!logs.isEmpty)
        #expect(logs.allSatisfy { !$0.startsCounter })
    }
}
