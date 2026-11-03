import Foundation
import SwiftData
import Testing
@testable import DosarCuSina

/// The repair list: each step finds its fixture, changes it only when applied, and finds
/// nothing the second time; applying the same finding twice changes nothing more.
@MainActor
@Suite("Data repairs")
struct DataRepairTests {
    private func ledger() -> DataRepairLedger {
        DataRepairLedger(defaults: UserDefaults(suiteName: "repairs-\(UUID().uuidString)")!)
    }

    private func repairs(_ context: ModelContext, ledger: DataRepairLedger? = nil) -> DataRepairs {
        DataRepairs(context: context, calendar: .bucharest, ledger: ledger ?? self.ledger())
    }

    /// Applies `step`'s findings, then checks a second detection finds none and a second
    /// apply of the same findings changes nothing.
    @discardableResult
    private func applyTwice(_ step: DataRepairStepID, in context: ModelContext, check: () throws -> Void) throws -> [DataRepairFinding] {
        let list = repairs(context)
        let found = try list.detect().filter { $0.step == step }
        try #require(!found.isEmpty, "\(step) finds its fixture")
        try list.apply(found)
        try check()
        #expect(try list.detect().filter { $0.step == step }.isEmpty, "\(step) finds nothing once applied")
        try list.apply(found)
        try check()
        #expect(context.hasChanges == false)
        return found
    }

    private func golf(_ context: ModelContext, km: Double) throws -> Asset {
        var values = FieldValues()
        values["vehicle.odometer"] = .number(km)
        let car = Asset(name: "VW Golf 2018", templateKey: BuiltInTemplates.Key.vehicle, values: values)
        context.insert(car)
        return car
    }

    @discardableResult
    private func reading(_ value: Double, on day: String, of asset: Asset, in context: ModelContext) -> MeasurementLog {
        let log = MeasurementLog(kind: .odometer, name: "", value: value, unit: .kilometres, recordedAt: noon(day))
        context.insert(log)
        log.asset = asset
        return log
    }

    // MARK: Counters

    /// The owner's car: 45.724 km became 457 when an earlier version read its own field back.
    @Test func aReadingThatLostItsDigitsIsOfferedBack() throws {
        let context = try makeContext()
        let car = try golf(context, km: 457)
        reading(45_724, on: "2026-01-10", of: car, in: context)
        let wrong = reading(457, on: "2026-02-01", of: car, in: context)
        try context.save()

        let found = try applyTwice(.counterOutliers, in: context) {
            #expect(wrong.value == 45_724)
            #expect(car.value("vehicle.odometer") == .number(45_724))
        }
        #expect(found.map(\.message) == ["Kilometrajul la VW Golf 2018 pare greșit: 457 km. Corectez la 45.724?"])
        #expect(try repairs(context).detect().isEmpty, "The hero value is right too, so nothing else is offered")
    }

    @Test func aReadingTenTimesOffBothNeighboursIsOfferedForRemoval() throws {
        let context = try makeContext()
        let car = try golf(context, km: 47_000)
        reading(45_000, on: "2026-01-10", of: car, in: context)
        reading(4_600_000, on: "2026-02-10", of: car, in: context)
        reading(47_000, on: "2026-03-10", of: car, in: context)
        try context.save()

        try applyTwice(.counterOutliers, in: context) {
            #expect(car.measurements?.map(\.value).sorted() == [45_000, 47_000])
        }
    }

    @Test func aNewCarsFirstSmallReadingIsLeftAlone() throws {
        let context = try makeContext()
        let car = try golf(context, km: 1_000)
        reading(100, on: "2026-01-10", of: car, in: context)
        reading(1_000, on: "2026-06-10", of: car, in: context)
        try context.save()
        #expect(try repairs(context).detect().isEmpty)
    }

    @Test func aVisitsRoundEstimateAboveTheNextReadingIsOffered() throws {
        let context = try makeContext()
        let car = try golf(context, km: 45_950)
        reading(45_000, on: "2026-01-10", of: car, in: context)
        let visit = HistoryEntry(kind: .maintenance, title: "Revizie", occurredAt: noon("2026-03-01"))
        visit.metricReading = 46_000
        context.insert(visit)
        visit.asset = car
        reading(46_000, on: "2026-03-01", of: car, in: context)
        reading(45_950, on: "2026-04-01", of: car, in: context)
        try context.save()

        try applyTwice(.estimatedVisitReadings, in: context) {
            #expect(visit.metricReading == nil, "The visit stays; its guessed reading goes")
            #expect(car.measurements?.map(\.value).sorted() == [45_000, 45_950])
        }
    }

    @Test func aHeroValueThatDiffersFromItsReadingsIsOffered() throws {
        let context = try makeContext()
        let car = try golf(context, km: 457)
        reading(45_724, on: "2026-01-10", of: car, in: context)
        try context.save()

        let found = try applyTwice(.heroFromReadings, in: context) {
            #expect(car.value("vehicle.odometer") == .number(45_724))
        }
        #expect(found.first?.message == "Kilometrajul la VW Golf 2018 pare greșit: 457 km. Corectez la 45.724?")
    }

    // MARK: Deadlines

    @Test func aFirstVersionITPGetsItsBlueprintAndTheLegalRule() throws {
        let context = try makeContext()
        let car = try golf(context, km: 45_724)
        let itp = Obligation(title: "ITP", kind: .legal, dueDay: CalendarDay("2027-05-01"),
                             recurrence: DossierV2Converter.recurrence(cadenceDays: 730), calendar: .bucharest)
        context.insert(itp)
        itp.asset = car
        try context.save()

        let found = try applyTwice(.firstVersionDeadlines, in: context) {
            #expect(itp.blueprintKey == "vehicle.itp")
            #expect(itp.recurrence == .legal(.vehicleITP))
            #expect(itp.dueDay(in: .bucharest) == CalendarDay("2027-05-01"), "The date the person has stays")
        }
        #expect(found.first?.message == "„ITP” la VW Golf 2018 a venit dintr-o copie veche, fără regula lui. Îi pun regula obișnuită?")
    }

    @Test func aFirstVersionBackupsDeadlinesAreOffered() throws {
        let container = try makeInMemoryContainer()
        try DossierArchiveService(container: container, calendar: .bucharest).importArchive(try Fixtures.archive("dosar-v2/ios-export"), mode: .replace)
        let context = container.mainContext
        let rca = try #require(try context.fetch(FetchDescriptor<Obligation>()).first { $0.title == "RCA" })
        #expect(rca.blueprintKey == nil)
        try applyTwice(.firstVersionDeadlines, in: context) {
            #expect(rca.blueprintKey == "vehicle.rca")
        }
    }

    @Test func aDeadlineClosedTwiceIsOfferedForUndo() throws {
        let context = try makeContext()
        let car = try golf(context, km: 45_724)
        let rent = Obligation(title: "Rată leasing", kind: .payment, dueDay: CalendarDay("2026-05-10"),
                              recurrence: .interval(.months(1), anchor: .dueDate), calendar: .bucharest)
        context.insert(rent)
        rent.asset = car
        try context.save()
        _ = try ObligationActions(context: context, calendar: .bucharest, now: { noon("2026-05-08") }).complete(rent)
        _ = try ObligationActions(context: context, calendar: .bucharest, now: { noon("2026-05-10") }).complete(rent)
        #expect(rent.dueDay(in: .bucharest) == CalendarDay("2026-07-10"))

        try applyTwice(.doubleCompletions, in: context) {
            #expect(rent.dueDay(in: .bucharest) == CalendarDay("2026-06-10"))
            #expect(rent.history.count == 1)
        }
    }

    // MARK: Capture repairs

    @Test func firmsKeptTwiceAreOfferedForMerging() throws {
        let context = try makeContext()
        _ = try ProviderActions(context: context).create(name: "Service Exemplu SRL", trades: [.mechanic])
        _ = try ProviderActions(context: context).create(name: "SERVICE EXEMPLU SRL", trades: [.mechanic])
        try applyTwice(.duplicateProviders, in: context) {
            let firms = try context.fetchCount(FetchDescriptor<Provider>())
            #expect(firms == 1)
        }
    }

    // MARK: The list itself

    @Test func choiceKeysRunByThemselvesWithDetection() throws {
        let context = try makeContext()
        var values = FieldValues()
        values["vehicle.fuel"] = .text("Benzină")
        let car = Asset(name: "VW Golf 2018", templateKey: BuiltInTemplates.Key.vehicle, values: values)
        context.insert(car)
        try context.save()
        #expect(try repairs(context).detect().isEmpty, "Nothing to ask")
        #expect(car.value("vehicle.fuel") == .text(FuelType.petrol))
        #expect(context.hasChanges == false)
    }

    @Test func aDismissalIsRemembered() throws {
        let context = try makeContext()
        let car = try golf(context, km: 457)
        reading(45_724, on: "2026-01-10", of: car, in: context)
        try context.save()
        let kept = ledger()
        let list = repairs(context, ledger: kept)
        let found = try list.detect()
        #expect(found.count == 1)
        list.dismiss(found)
        #expect(try list.detect().isEmpty)
        #expect(car.value("vehicle.odometer") == .number(457), "Lasă așa changes nothing")
        #expect(try repairs(context).detect().count == 1, "Another phone's list would still show it")
    }

    @Test func thePromptAnnouncesOnlyWhatIsNew() throws {
        let context = try makeContext()
        let car = try golf(context, km: 457)
        reading(45_724, on: "2026-01-10", of: car, in: context)
        try context.save()
        let center = DataRepairCenter(ledger: ledger())
        try center.refresh(in: context, announce: true)
        #expect(center.announcement.count == 1)
        center.announcement = []
        try center.refresh(in: context, announce: true)
        #expect(center.announcement.isEmpty, "Said once")
        #expect(center.pending.count == 1, "Still in the list")
    }

    @Test func everyStepHasItsOwnStoredID() {
        let ids = DataRepairs.steps.map { type(of: $0).id }
        #expect(Set(ids).count == ids.count)
        #expect(Set(ids) == Set(DataRepairStepID.allCases))
    }

    // MARK: Unknown stored values

    @Test func unknownStoredValuesAreKeptAndReadLoudest() throws {
        let raw = Data(#"{"vehicle.plate":{"type":"text","value":"B-123-ABC"},"vehicle.future":{"type":"hologram","value":42}}"#.utf8)
        var values = try JSONDecoder().decode(FieldValues.self, from: raw)
        #expect(values["vehicle.plate"] == .text("B-123-ABC"))
        values["vehicle.plate"] = .text("B-456-ABC")
        let written = String(decoding: try JSONEncoder().encode(values), as: UTF8.self)
        #expect(written.contains("hologram"), "A value this build can't read is written back unchanged")

        let context = try makeContext()
        let obligation = Obligation(title: "ITP", kind: .legal, dueDay: CalendarDay("2027-05-01"), calendar: .bucharest)
        context.insert(obligation)
        obligation.consequenceRaw = "catastrophic"
        obligation.kindRaw = "spaceLaw"
        #expect(obligation.reminders.consequence == .legal)
        #expect(obligation.kind == .legal)
        var reminders = obligation.reminders
        reminders.leadDays = [14]
        obligation.reminders = reminders
        #expect(obligation.consequenceRaw == "catastrophic", "Never written back downgraded")
        let decoded = try JSONDecoder().decode(ReminderProfile.self, from: Data(#"{"leadDays":[7],"consequence":"catastrophic"}"#.utf8))
        #expect(decoded.consequence == .legal)
    }
}
