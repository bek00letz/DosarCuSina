import Foundation
import SwiftData
import Testing
@testable import DosarCuSina

/// Visits filed before another photo of their invoice was known as the same invoice: the
/// second visit it made is joined into the first only with the owner's OK, idempotently,
/// with its papers, parts and reading once. Placeholder data only.
@MainActor
@Suite("Repair: the same visit twice")
struct VisitRepairTests {

    private func repairs(_ context: ModelContext) -> DataRepairs {
        DataRepairs(context: context, calendar: .bucharest,
                    ledger: DataRepairLedger(defaults: UserDefaults(suiteName: "visit-repairs-\(UUID().uuidString)")!))
    }

    private func car(_ context: ModelContext) throws -> Asset {
        let template = try #require(try TemplateStore(context: context).template(forKey: BuiltInTemplates.Key.vehicle))
        return try AssetActions(context: context, calendar: .bucharest).create(name: "VW Golf 2018", template: template, values: FieldValues())
    }

    /// A visit as an earlier version logged it from a photo of its invoice.
    @discardableResult
    private func oldVisit(on car: Asset, day: String, total: Decimal?, firm: Provider?, number: String? = nil,
                          parts: [String] = [], odometer: Double? = nil, paper: (seed: UInt8, filed: String)?,
                          in context: ModelContext) throws -> HistoryEntry {
        let entry = HistoryEntry(kind: .maintenance, title: "Revizie", occurredAt: noon(day))
        entry.totalCost = total.map { Money($0) }
        entry.reference = number
        context.insert(entry)
        entry.asset = car
        if let firm { entry.providers = [firm] }
        for part in parts {
            let item = ServiceItem(name: part)
            context.insert(item)
            item.entry = entry
        }
        if let odometer {
            entry.metricReading = odometer
            try HouseholdMutations.recordReading(odometer, on: car, at: entry.occurredAt, source: .person, unit: .kilometres, in: context)
        }
        if let paper {
            let document = Attachment(fileName: "Factură.heic", contentType: "public.heic", data: Data([paper.seed]), kind: .invoice)
            document.createdAt = noon(paper.filed)
            context.insert(document)
            document.historyEntry = entry
            document.asset = car
        }
        try UnitOfWork.save(context)
        return entry
    }

    private func firm(_ name: String, in context: ModelContext) throws -> Provider {
        let provider = Provider(name: name, trades: [.mechanic])
        context.insert(provider)
        try UnitOfWork.save(context)
        return provider
    }

    private func visits(on car: Asset) -> [HistoryEntry] {
        PaperIdentity.visits(of: car)
    }

    @Test func theSameVisitLoggedTwiceIsJoinedOnlyWithTheOwnersOK() throws {
        let context = try makeContext()
        let golf = try car(context)
        let service = try firm("Service Exemplu SRL", in: context)
        let first = try oldVisit(on: golf, day: "2026-05-30", total: 480, firm: service, parts: ["Ulei", "Filtru de aer"],
                                 odometer: 48_000, paper: (1, "2026-05-30"), in: context)
        let second = try oldVisit(on: golf, day: "2026-05-30", total: 480, firm: service, number: "SRV 0000001", parts: ["Ulei", "Plăcuțe de frână"],
                                  odometer: 48_000, paper: (2, "2026-06-04"), in: context)
        try oldVisit(on: golf, day: "2026-05-30", total: 150, firm: service, paper: (3, "2026-05-30"), in: context)
        let older = try #require(first.attachments?.first)
        let newer = try #require(second.attachments?.first)
        let list = repairs(context)

        let found = try list.detect().filter { $0.step == .sameVisitTwice }
        #expect(found.count == 1, "Another total is another invoice")
        let finding = try #require(found.first)
        #expect(finding.message == "Factura din 30 mai 2026 e trecută de mai multe ori în istoricul „VW Golf 2018”. O las o singură dată?")
        #expect(finding.subject == .sameVisit(keep: second.id, merge: [first.id]), "The one whose paper came last stays")
        #expect(visits(on: golf).count == 3, "Nothing changes before the OK")

        try list.apply(found)
        #expect(visits(on: golf).count == 2)
        #expect(visits(on: golf).contains { $0.id == second.id })
        #expect(second.reference == "SRV 0000001")
        #expect(Set((second.items ?? []).map(\.name)) == ["Ulei", "Plăcuțe de frână", "Filtru de aer"], "Every part, once")
        #expect((second.items ?? []).count == 3)
        #expect(golf.measurements?.filter { !$0.isDeleted }.map(\.value) == [48_000], "One reading")
        #expect(second.metricReading == 48_000)
        #expect(newer.historyEntry?.id == second.id && !newer.isArchived, "The newest paper is the visit's copy")
        #expect(older.historyEntry?.id == second.id && older.isArchived && older.supersededBy?.id == newer.id,
                "The first paper stays with the visit, archived beside it")
        #expect(try list.detect().filter { $0.step == .sameVisitTwice }.isEmpty, "Found nothing once applied: idempotent")
    }

    @Test func theReadingOfTheVisitThatGoesMovesToTheOneThatStays() throws {
        let context = try makeContext()
        let golf = try car(context)
        let service = try firm("Service Exemplu SRL", in: context)
        let first = try oldVisit(on: golf, day: "2026-05-30", total: 480, firm: service, odometer: 48_000, paper: (1, "2026-05-30"), in: context)
        let second = try oldVisit(on: golf, day: "2026-05-30", total: 480, firm: nil, paper: (2, "2026-06-04"), in: context)
        let list = repairs(context)
        try list.apply(try list.detect().filter { $0.step == .sameVisitTwice })
        #expect(visits(on: golf).map(\.id) == [second.id])
        #expect(first.isDeleted || visits(on: golf).allSatisfy { $0.id != first.id })
        #expect(second.metricReading == 48_000, "It takes the kilometres the other visit read")
        #expect(second.providers?.map(\.name) == ["Service Exemplu SRL"], "And its firm")
        let log = try #require(golf.measurements?.first { !$0.isDeleted })
        #expect(HouseholdMutations.isReading(log, recordedBy: second), "The reading is the visit's own")
        #expect(golf.values[VehicleFields.odometer]?.numberValue == 48_000)
    }

    @Test func visitsThatAreNotTheSameInvoiceAreLeftAlone() throws {
        let context = try makeContext()
        let golf = try car(context)
        let service = try firm("Service Exemplu SRL", in: context)
        let tyres = try firm("Vulcanizare Exemplu SRL", in: context)
        try oldVisit(on: golf, day: "2026-05-30", total: 480, firm: service, paper: (1, "2026-05-30"), in: context)
        try oldVisit(on: golf, day: "2026-05-30", total: 480, firm: tyres, paper: (2, "2026-05-30"), in: context)
        try oldVisit(on: golf, day: "2026-05-30", total: 480, firm: service, paper: nil, in: context)
        try oldVisit(on: golf, day: "2026-05-31", total: 480, firm: service, paper: (3, "2026-05-31"), in: context)
        try oldVisit(on: golf, day: "2025-05-30", total: 300, firm: service, number: "SRV 0000001", paper: (4, "2025-05-30"), in: context)
        try oldVisit(on: golf, day: "2026-04-30", total: 310, firm: service, number: "SRV 0000001", paper: (5, "2026-04-30"), in: context)
        #expect(try repairs(context).detect().filter { $0.step == .sameVisitTwice }.isEmpty,
                "Another firm, a visit typed by hand, another day, a number that started again: never offered")
    }

    @Test func aVisitNoLongerLoggedTwiceChangesNothing() throws {
        let context = try makeContext()
        let golf = try car(context)
        let service = try firm("Service Exemplu SRL", in: context)
        try oldVisit(on: golf, day: "2026-05-30", total: 480, firm: service, paper: (1, "2026-05-30"), in: context)
        let extra = try oldVisit(on: golf, day: "2026-05-30", total: 480, firm: service, paper: (2, "2026-06-04"), in: context)
        let list = repairs(context)
        let found = try list.detect().filter { $0.step == .sameVisitTwice }
        #expect(found.count == 1)
        try HistoryActions(context: context).delete(extra)
        try list.apply(found)
        #expect(visits(on: golf).count == 1, "The finding no longer holds, so it changes nothing")
    }

    @Test func theStepComesAfterTheStepsBeforeItWithItsOwnStoredID() {
        let ids = DataRepairs.steps.map { type(of: $0).id }
        let visits = ids.firstIndex(of: .sameVisitTwice)
        #expect(visits.flatMap { index in ids.firstIndex(of: .sameBillTwice).map { $0 < index } } == true, "A new repair is a new step at the end")
        #expect(DataRepairStepID.sameVisitTwice.rawValue == "same-visit-twice")
    }
}

/// Visits an earlier version saved with their labour („Manoperă”) as a part of one's own: each
/// line is offered, and kept as the visit's labour only once the owner approves, idempotently,
/// what the visit cost unchanged. Placeholder data only.
@MainActor
@Suite("Repair: labour kept as a part")
struct LabourPartsRepairTests {

    private func repairs(_ context: ModelContext) -> DataRepairs {
        DataRepairs(context: context, calendar: .bucharest,
                    ledger: DataRepairLedger(defaults: UserDefaults(suiteName: "labour-repairs-\(UUID().uuidString)")!))
    }

    /// A visit as an earlier version saved it: every line a part, labour's too (`custom.<slug>`).
    private func oldVisit(_ context: ModelContext) throws -> (car: Asset, entry: HistoryEntry) {
        let template = try #require(try TemplateStore(context: context).template(forKey: BuiltInTemplates.Key.vehicle))
        let car = try AssetActions(context: context, calendar: .bucharest).create(name: "VW Golf 2018", template: template, values: FieldValues())
        let entry = HistoryEntry(kind: .maintenance, title: "Revizie", occurredAt: noon("2026-05-30"))
        context.insert(entry)
        entry.asset = car
        let lines: [(String, String, Decimal)] = [
            ("Plăcuțe frână față", "brakes.padsFront", 380), ("Odorizant", "custom.odorizant", 20),
            ("Manoperă", "custom.manopera", 200), ("Mână de lucru", "custom.mana-de-lucru", 150),
        ]
        for (name, key, cost) in lines {
            let item = ServiceItem(name: name, componentKey: key)
            item.costAmount = cost
            context.insert(item)
            item.entry = entry
        }
        try context.save()
        return (car, entry)
    }

    @Test("Labour kept as a part is offered, and kept as the visit's labour once approved")
    func labourBecomesTheVisitsLabour() throws {
        let context = try makeContext()
        let (car, entry) = try oldVisit(context)
        let costBefore = Set((entry.items ?? []).compactMap(\.totalCost))
        let list = repairs(context)
        let found = try list.detect().filter { $0.step == .labourParts }
        #expect(found.count == 2, "„Manoperă” and „Mână de lucru”, never a part")
        #expect(found.allSatisfy { $0.isFixable } && !DataRepairs.step(.labourParts).isSuggestion, "A correction")
        #expect(found.contains { $0.message.contains("„VW Golf 2018”") && $0.message.contains("„Manoperă”") })
        #expect(MaintenanceLog.trackedComponents(in: HistoryItemSnapshot.items(of: car)).contains("custom.manopera"), "Before: listed as a part")

        let check = {
            let labour = (entry.items ?? []).filter { LabourLine.matches($0.name) }
            #expect(labour.count == 2)
            #expect(labour.allSatisfy { $0.componentKey == nil && $0.costAmount == nil && $0.laborCostAmount != nil })
            #expect(Set((entry.items ?? []).compactMap(\.totalCost)) == costBefore, "What the visit cost stays the same")
            #expect(entry.items?.first { $0.name == "Odorizant" }?.componentKey == "custom.odorizant", "A part of one's own stays")
            #expect(entry.items?.first { $0.name == "Plăcuțe frână față" }?.componentKey == "brakes.padsFront")
            let tracked = MaintenanceLog.trackedComponents(in: HistoryItemSnapshot.items(of: car))
            #expect(!tracked.contains("custom.manopera") && !tracked.contains("custom.mana-de-lucru"))
        }
        try list.apply(found)
        check()
        #expect(try list.detect().filter { $0.step == .labourParts }.isEmpty, "Found nothing once applied")
        try list.apply(found)
        check()
        #expect(context.hasChanges == false)
    }

    @Test("Nothing changes until the owner approves")
    func nothingChangesByItself() throws {
        let context = try makeContext()
        let (_, entry) = try oldVisit(context)
        _ = try repairs(context).detect()
        #expect(entry.items?.first { $0.name == "Manoperă" }?.componentKey == "custom.manopera")
        #expect(!DataRepairs.step(.labourParts).runsByItself)
    }

    @Test func theStepComesRightAfterThePreviousOne() {
        let ids = DataRepairs.steps.map { type(of: $0).id }
        #expect(ids.firstIndex(of: .labourParts) == ids.firstIndex(of: .personalLessonLabels).map { $0 + 1 },
                "Added after the steps there were; later steps follow it")
        #expect(DataRepairStepID.labourParts.rawValue == "labour-parts")
    }
}
