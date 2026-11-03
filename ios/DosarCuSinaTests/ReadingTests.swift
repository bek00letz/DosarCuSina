import Foundation
import SwiftData
import Testing
@testable import DosarCuSina

/// One way to record a reading: a lower counter asks, an estimate is never stored, a
/// document's reading is dated by the document, undo takes its reading back, and every
/// rate reads one cleaned series.
@MainActor
@Suite("Counter readings")
struct ReadingTests {
    private func car(_ context: ModelContext, km: Double = 45_724, on day: String = "2026-01-10") throws -> Asset {
        let template = try #require(try TemplateStore(context: context).template(forKey: BuiltInTemplates.Key.vehicle))
        var values = FieldValues()
        values["vehicle.odometer"] = .number(km)
        return try AssetActions(context: context, calendar: .bucharest, now: { noon(day) }).create(name: "VW Golf 2018", template: template, values: values)
    }

    private func edit(_ car: Asset, km: Double, in context: ModelContext, on day: String = "2026-03-01", answer: LowerReadingAnswer? = nil) throws {
        var values = car.values
        values["vehicle.odometer"] = .number(km)
        try AssetActions(context: context, calendar: .bucharest, now: { noon(day) })
            .update(car, name: car.name, values: values, notes: car.notes, lowerReading: answer)
    }

    @Test func aLowerCounterAsksAndSavesNothing() throws {
        let context = try makeContext()
        let golf = try car(context)
        #expect(throws: LowerReadingQuestion.self) { try edit(golf, km: 4_572, in: context) }
        #expect(golf.value("vehicle.odometer") == .number(45_724))
        #expect(golf.measurements?.map(\.value) == [45_724])
        #expect(context.hasChanges == false)
    }

    @Test func yesCorrectsTheOldReading() throws {
        let context = try makeContext()
        let golf = try car(context)
        try edit(golf, km: 4_572, in: context, answer: .correctOld)
        #expect(golf.value("vehicle.odometer") == .number(4_572))
        #expect(golf.measurements?.map(\.value) == [4_572])
    }

    @Test func noKeepsTheNewReadingAside() throws {
        let context = try makeContext()
        let golf = try car(context)
        try edit(golf, km: 4_572, in: context, answer: .keepAside)
        #expect(golf.value("vehicle.odometer") == .number(45_724), "The hero value is worked out from the readings")
        let series = HouseholdMutations.readingSeries(of: golf, unit: .kilometres)
        #expect(series.current == 45_724)
        #expect(series.setAside.map(\.metric) == [4_572])
    }

    @Test func theQuestionNamesBothReadings() {
        let question = LowerReadingQuestion(previous: 45_724, previousDate: noon("2026-01-10"), value: 4_572, unit: .kilometres)
        #expect(question.question == "Kilometrajul e mai mic decât ultima dată. Corectez citirea veche?")
        #expect(question.explanation.contains("45.724 km"))
        #expect(question.explanation.contains("4.572 km"))
    }

    @Test func anEstimateIsNeverStored() throws {
        let context = try makeContext()
        let golf = try car(context)
        let log = try AssetActions(context: context).recordReading(46_000, on: golf, source: .estimate)
        #expect(log == nil)
        #expect(golf.measurements?.count == 1)
        #expect(golf.value("vehicle.odometer") == .number(45_724))
    }

    @Test func aDocumentsReadingIsDatedByTheDocument() throws {
        let context = try makeContext()
        let golf = try car(context, km: 40_000, on: "2025-01-10")
        var values = golf.values
        values["vehicle.odometer"] = .number(42_100)
        try AssetActions(context: context, calendar: .bucharest, now: { noon("2026-11-03") })
            .update(golf, name: golf.name, values: values, notes: nil, readingSource: .document, readingDate: noon("2025-06-02"))
        #expect(golf.measurements?.contains { $0.value == 42_100 && $0.recordedAt == noon("2025-06-02") } == true)
    }

    @Test func anOlderDocumentNeverLowersTheCounter() throws {
        let context = try makeContext()
        let golf = try car(context, km: 45_724, on: "2026-01-10")
        var values = golf.values
        values["vehicle.odometer"] = .number(40_000)
        // An invoice from before the latest reading: earlier, not lower, so nothing to ask.
        try AssetActions(context: context, calendar: .bucharest, now: { noon("2026-11-03") })
            .update(golf, name: golf.name, values: values, notes: nil, readingSource: .document, readingDate: noon("2025-06-02"))
        #expect(golf.value("vehicle.odometer") == .number(45_724))
        #expect(golf.measurements?.count == 2)
    }

    @Test func aVisitAsksAboutALowerCounterToo() throws {
        let context = try makeContext()
        let golf = try car(context)
        #expect(throws: LowerReadingQuestion.self) {
            try HistoryActions(context: context, now: { noon("2026-06-01") }).recordVisit(on: golf, checklist: [], odometer: 4_572, calendar: .bucharest)
        }
        #expect(golf.history?.isEmpty ?? true, "Nothing of the visit was saved")
    }

    @Test func undoingGataRemovesItsReading() throws {
        let context = try makeContext()
        let golf = try car(context)
        let oilChange = Obligation(title: "Schimb ulei", kind: .maintenance, dueDay: CalendarDay("2026-06-01"),
                                   recurrence: .metric(every: 10_000, unit: .kilometres, fallback: .years(1)), calendar: .bucharest)
        context.insert(oilChange)
        oilChange.asset = golf
        try context.save()
        let actions = ObligationActions(context: context, calendar: .bucharest, now: { noon("2026-05-20") })
        let done = try actions.complete(oilChange, metricReading: 55_000)
        #expect(golf.value("vehicle.odometer") == .number(55_000))
        try done.receipt.undo()
        #expect(golf.measurements?.map(\.value) == [45_724])
        #expect(golf.value("vehicle.odometer") == .number(45_724))
    }

    // MARK: One cleaned series

    private func readings(_ points: [(Int, Double)]) -> [CadenceCalculator.TelemetryReading] {
        let base = noon("2026-01-01")
        return points.map { .init(date: Calendar.bucharest.date(byAdding: .day, value: $0.0, to: base)!, metric: $0.1) }
    }

    @Test func theSeriesSkipsWhatBreaksTheOrder() {
        #expect(ReadingSeries(readings([(0, 40_000), (30, 45_724), (60, 457)])).readings.map(\.metric) == [40_000, 45_724])
        #expect(ReadingSeries(readings([(0, 450_000), (30, 46_000), (60, 47_000)])).readings.map(\.metric) == [46_000, 47_000])
        #expect(ReadingSeries(readings([(0, 10_000), (30, 9_000)])).current == 10_000, "On a tie the earlier reading wins")
        #expect(ReadingSeries(readings([(0, 80), (30, 75)]), cumulative: false).current == 75, "A weight is the newest")
    }

    /// F1 turned around: one typo no longer switches the projection off.
    @Test func oneTypoDoesNotStopTheProjection() {
        let withTypo = readings([(0, 100_000), (60, 1_020), (120, 104_000)])
        let projection = CadenceCalculator.projectTelemetryDueDate(currentMetric: 104_000, targetMetric: 110_000, readings: withTypo,
                                                                   currentDate: withTypo[2].date, calendar: .bucharest)
        #expect(projection != nil)
        #expect(projection?.isEstimatedFromBaseline == false)
        #expect(projection?.hasRollbackAnomaly == true, "The typo is still flagged")
    }

    /// G2: both rates read the same cleaned series.
    @Test func theMonthlyRateSkipsATypo() throws {
        let rate = try #require(MaintenanceLog.monthlyRate(readings([(0, 100_000), (60, 1_020), (120, 104_000)])))
        // 4.000 km over 120 days; the span crosses the clock change, so an hour off.
        #expect(abs(rate - 1_000) < 1)
    }

    /// U1 turned around: the estimate is a placeholder that never runs ahead of the last reading.
    @Test func theEstimateIsNeverRoundedUpPastThePace() {
        let points = readings([(0, 100_000), (60, 102_010)])
        let estimate = OdometerEstimate.value(readings: points, fallback: nil, now: Calendar.bucharest.date(byAdding: .day, value: 61, to: noon("2026-01-01"))!)
        #expect(estimate == 102_010)
    }
}
