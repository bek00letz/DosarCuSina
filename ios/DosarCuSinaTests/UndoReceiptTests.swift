import Foundation
import SwiftData
import Testing
@testable import DosarCuSina

/// One undo for every action: each undoable action returns a receipt of exactly what it
/// changed, and undo puts the database back as it was before, record by record.
@MainActor
@Suite("Undo receipts")
struct UndoReceiptTests {

    // MARK: A household

    struct Household {
        let context: ModelContext
        let car: Asset
        let home: Asset
        let corina: Asset
        let ion: Asset
        let card: Asset
        let rca: Obligation
        let oil: Obligation
        let kit: Obligation
        let mechanic: Provider
        let repair: HistoryEntry
        let keptInvoice: DosarCuSina.Attachment

        static func make() throws -> Household {
            let context = try makeContext()
            let store = TemplateStore(context: context)
            let assets = AssetActions(context: context, calendar: .bucharest, now: { noon("2026-11-02") })
            let vehicles = try #require(try store.template(forKey: BuiltInTemplates.Key.vehicle))
            let homes = try #require(try store.template(forKey: BuiltInTemplates.Key.home))
            let members = try #require(try store.template(forKey: BuiltInTemplates.Key.member))
            let documents = try #require(try store.template(forKey: BuiltInTemplates.Key.documents))
            let car = try assets.create(name: "VW Golf 2018", template: vehicles,
                                        values: FieldValues(["vehicle.plate": .text("B-123-ABC"), "vehicle.odometer": .number(100_000)]))
            let home = try assets.create(name: "Apartament", template: homes, values: FieldValues())
            let corina = try assets.create(name: "Manole Corina", template: members, values: FieldValues())
            let ion = try assets.create(name: "Popescu Ion", template: members, values: FieldValues())
            let card = try assets.create(name: "Carte de identitate – Manole Corina", template: documents,
                                         values: FieldValues(["document.type": .text(DocumentType.idCard)]), parent: corina)
            try assets.setCustomFacts(home, [CustomFact(label: "Cod interfon", value: "12"), CustomFact(label: "Administrator", value: "Exemplu")])
            let obligations = ObligationActions(context: context, calendar: .bucharest, now: { noon("2026-11-02") })
            let rca = try obligations.create(title: "RCA", kind: .insurance, dueDay: CalendarDay("2026-11-10"), for: car,
                                             recurrence: .interval(.years(1), anchor: .dueDate))
            try obligations.snooze(rca, days: 1)
            let oil = try obligations.create(title: "Schimb ulei", kind: .maintenance, dueDay: CalendarDay("2027-06-01"), for: car,
                                             recurrence: .metric(every: 10_000, unit: "km", fallback: .years(1)))
            let kit = try obligations.create(title: "Trusă medicală", kind: .legal, dueDay: CalendarDay("2026-12-01"), for: car)
            let mechanic = try ProviderActions(context: context).create(name: "Service Exemplu SRL", trades: [.mechanic])
            let repair = try HistoryActions(context: context, now: { noon("2026-10-01") }).record(on: home, kind: .repair, title: "Robinet nou")
            let invoice = try AttachmentActions(context: context, calendar: .bucharest).file(
                DocumentDraft(title: "Factură robinet", fileName: "factura.heic", kind: .invoice, pageImages: [Data([5, 6, 7])]),
                asset: home, historyEntry: repair
            )
            return Household(context: context, car: car, home: home, corina: corina, ion: ion, card: card, rca: rca, oil: oil, kit: kit,
                             mechanic: mechanic, repair: repair, keptInvoice: invoice)
        }
    }

    // MARK: Every undoable action

    enum Step: String, CaseIterable, CustomTestStringConvertible {
        case completeWithEverything
        case completeAOneOff
        case completeCorrectingAnOlderReading
        case snooze
        case reschedule
        case recordVisit
        case moveToAnotherPerson
        case moveToANewPerson
        case deleteAFact
        case archiveADocument
        case fileAVisitWithAKeptInvoice
        case fileACompletionWithAKeptPolicy
        case fileAReviewOfAKeptPolicy

        var testDescription: String { rawValue }

        func run(in house: Household) async throws -> UndoReceipt {
            let context = house.context
            let obligations = ObligationActions(context: context, calendar: .bucharest, now: { noon("2026-11-03") })
            let assets = AssetActions(context: context, calendar: .bucharest, now: { noon("2026-11-03") })
            switch self {
            case .completeWithEverything:
                return try obligations.complete(house.rca, cost: Money(1_150), metricReading: 101_000, note: "Plătit la ghișeu",
                                                items: [LineItemDraft(name: "Carte verde")], providers: [house.mechanic], rating: 4).receipt
            case .completeAOneOff:
                return try obligations.complete(house.kit).receipt
            case .completeCorrectingAnOlderReading:
                // 90 000 km is lower than the 100 000 recorded: the older reading goes, and undo brings it back.
                return try obligations.complete(house.oil, metricReading: 90_000, lowerReading: .correctOld).receipt
            case .snooze:
                return try obligations.snooze(house.rca, days: 7)
            case .reschedule:
                return try obligations.reschedule(house.rca, to: CalendarDay("2026-12-15"))
            case .recordVisit:
                return try HistoryActions(context: context, now: { noon("2026-11-03") }).recordVisit(
                    on: house.car, checklist: [.init(componentKey: "engine.oil", cost: Money(420))], extraItems: [LineItemDraft(name: "Odorizant")],
                    totalCost: Money(690), odometer: 102_000, provider: house.mechanic,
                    documents: [DocumentDraft(fileName: "factura.pdf", kind: .invoice, contentType: "com.adobe.pdf", originalData: Data([1, 2, 3]))],
                    rating: 5, calendar: .bucharest
                ).receipt
            case .moveToAnotherPerson:
                return try assets.move(house.card, to: .asset(house.ion.id), renamingTo: "Carte de identitate – Popescu Ion")
            case .moveToANewPerson:
                return try assets.move(house.card, to: .newMember(name: "Manole Ana"), renamingTo: "Carte de identitate – Manole Ana")
            case .deleteAFact:
                return try assets.setCustomFacts(house.home, Array(house.home.customFacts.dropFirst()))
            case .archiveADocument:
                return try AttachmentActions(context: context).setArchived(house.keptInvoice, true)
            case .fileAVisitWithAKeptInvoice:
                let filer = CaptureFiler(context: context, store: CaptureDocumentStore(), calendar: .bucharest)
                return try #require(try await filer.file(.visit(.init(
                    asset: house.car, kind: .maintenance, occurredAt: noon("2026-11-03"), checklist: [], totalCost: Money(690),
                    odometer: 102_000, provider: .named("Vulcanizare Exemplu SRL", trade: .tyreShop),
                    document: .kept(attachmentID: house.keptInvoice.id), documentTitle: "Factură service"
                ))).receipt)
            case .fileACompletionWithAKeptPolicy:
                let filer = CaptureFiler(context: context, store: CaptureDocumentStore(), calendar: .bucharest)
                return try #require(try await filer.file(.completion(.init(
                    obligation: house.rca, date: noon("2026-11-03"), cost: Money(1_150), document: policy(.kept(attachmentID: house.keptInvoice.id))
                ))).receipt)
            case .fileAReviewOfAKeptPolicy:
                let filer = CaptureFiler(context: context, store: CaptureDocumentStore(), calendar: .bucharest)
                var review = CaptureReview(result: policy(.kept(attachmentID: house.keptInvoice.id)), assets: [house.car, house.home], context: context)
                review.destination = .asset(house.car.id)
                return try #require(try await filer.save(review).receipt)
            }
        }

        private func policy(_ document: CapturedDocumentRef) -> CaptureResult {
            let expiry = CaptureDay(date: Calendar.current.date(byAdding: .day, value: 375, to: Date())!)
            return CaptureResult(kind: .rcaPolicy, kindConfidence: 0.95, fields: [
                CaptureField(key: .expiryDate, value: .day(expiry), confidence: 0.9, tier: .heuristic),
                CaptureField(key: .policyNumber, value: .text("RO/00/X/000000000"), confidence: 0.9, tier: .heuristic),
                CaptureField(key: .provider, value: .text("Exemplu Asigurări S.A."), confidence: 0.9, tier: .heuristic),
            ], suggestions: [], reminder: nil, recognizedText: "POLIȚĂ RCA", barcodes: [], document: document, notices: [])
        }
    }

    @Test("Undo puts back exactly the state before", arguments: Step.allCases)
    func undoRestoresExactlyTheStateBefore(_ step: Step) async throws {
        let house = try Household.make()
        let before = try Self.database(house.context)

        let receipt = try await step.run(in: house)
        let after = try Self.database(house.context)
        #expect(!Self.differences(before, after).isEmpty, "The step changed something")
        #expect(receipt.canUndo)
        #expect(Set(Self.differences(before, after).map(\.ref)).isSubset(of: receipt.touched), "The receipt names every record the step changed")

        try receipt.undo()
        let undone = try Self.database(house.context)
        let left = Self.differences(before, undone)
        #expect(left.isEmpty, "Still different after undo: \(left.map(\.description))")
        #expect(!receipt.canUndo, "A receipt is used once")
    }

    // MARK: Undo never overwrites something newer

    @Test func undoRefusesWhenTheSameRecordsChangedSince() throws {
        let house = try Household.make()
        let actions = ObligationActions(context: house.context, calendar: .bucharest, now: { noon("2026-11-03") })
        let done = try actions.complete(house.rca)
        try actions.reschedule(house.rca, to: CalendarDay("2028-01-15"))
        let before = try Self.database(house.context)

        #expect(throws: UndoError.changedSince) { try done.receipt.undo() }
        #expect(Self.differences(before, try Self.database(house.context)).isEmpty, "A refused undo changes nothing")
        #expect(done.receipt.canUndo == true, "It can still be tried once the newer change is gone")
    }

    @Test func aStepThatChangedNothingOffersNoUndo() throws {
        let house = try Household.make()
        let receipt = try AttachmentActions(context: house.context).setArchived(house.keptInvoice, false)
        #expect(!receipt.canUndo)
        #expect(!DSToast.undo("Scos din arhivă", receipt: receipt).offersAction)
    }

    @Test func anActionInsideALargerStepIsUndoneWithIt() throws {
        let house = try Household.make()
        let before = try Self.database(house.context)
        let obligations = ObligationActions(context: house.context, calendar: .bucharest, now: { noon("2026-11-03") })
        let step = try UnitOfWork.performUndoable(in: house.context) {
            try obligations.complete(house.rca).receipt
        }
        #expect(step.value === step.receipt, "The inner action's receipt is the whole step's")
        try step.receipt.undo()
        #expect(Self.differences(before, try Self.database(house.context)).isEmpty)
    }

    // MARK: Every stored property is recorded

    @Test func everyStoredPropertyOfEveryModelIsRecorded() throws {
        let schema = Schema(versionedSchema: DosarSchemaV3.self)
        #expect(UndoableRecords.types.count == DosarSchemaV3.models.count, "Every model of the schema can be undone")
        for entity in schema.entities {
            let type = try #require(UndoableRecords.types[entity.name], "\(entity.name) is recorded")
            #expect(Set(Self.propertyNames(type)) == Set(entity.properties.map(\.name)), "\(entity.name) lists every stored property")
        }
    }

    // MARK: Helpers

    private static func propertyNames<M: UndoableRecord>(_ type: M.Type) -> [String] {
        M.storedProperties.map(\.name)
    }

    /// Every record in the store, read in a fresh context: what's really saved.
    static func database(_ context: ModelContext) throws -> [RecordRef: RecordState] {
        let store = ModelContext(context.container)
        var all: [RecordRef: RecordState] = [:]
        for type in UndoableRecords.types.values {
            for state in try states(of: type, in: store) { all[state.ref] = state }
        }
        return all
    }

    private static func states<M: UndoableRecord>(of type: M.Type, in context: ModelContext) throws -> [RecordState] {
        try context.fetch(FetchDescriptor<M>()).map { RecordState.capture($0) }
    }

    struct Difference: CustomStringConvertible {
        let ref: RecordRef
        let properties: [String]
        var description: String { "\(ref): \(properties.isEmpty ? "added or removed" : properties.joined(separator: ", "))" }
    }

    /// The records that differ, with the properties that do.
    static func differences(_ a: [RecordRef: RecordState], _ b: [RecordRef: RecordState]) -> [Difference] {
        Set(a.keys).union(b.keys).compactMap { ref in
            guard let left = a[ref], let right = b[ref] else { return Difference(ref: ref, properties: []) }
            let changed = Set(left.values.keys).union(right.values.keys).filter { left.values[$0] != right.values[$0] }.sorted()
            return changed.isEmpty ? nil : Difference(ref: ref, properties: changed)
        }
    }
}

// MARK: - Deleting an older record from Istoric

@MainActor
@Suite("Deleting from Istoric")
struct HistoryDeletionTests {
    private func car(_ context: ModelContext) throws -> Asset {
        let template = try #require(try TemplateStore(context: context).template(forKey: BuiltInTemplates.Key.vehicle))
        return try AssetActions(context: context, calendar: .bucharest, now: { noon("2026-11-01") }).create(
            name: "VW Golf 2018", template: template, values: FieldValues(["vehicle.odometer": .number(100_000)]))
    }

    private func rca(on car: Asset, _ actions: ObligationActions) throws -> Obligation {
        try actions.create(title: "RCA", kind: .insurance, dueDay: CalendarDay("2026-11-10"), for: car, recurrence: .interval(.years(1), anchor: .dueDate))
    }

    @Test func deletingTheLatestCompletionReopensItsCycleAndTakesItsReadingButKeepsItsDocuments() throws {
        let context = try makeContext()
        let golf = try car(context)
        let actions = ObligationActions(context: context, calendar: .bucharest, now: { noon("2026-11-02") })
        let policy = try rca(on: golf, actions)
        let entry = try actions.complete(policy, cost: Money(1_150), metricReading: 101_000).value
        let paper = try AttachmentActions(context: context).file(DocumentDraft(fileName: "polita.pdf", kind: .policy, originalData: Data([1])),
                                                                  asset: golf, historyEntry: entry)
        #expect(policy.dueDay(in: .bucharest) == CalendarDay("2027-11-10"))

        let effect = HistoryDeletion(of: entry)
        #expect(effect.reopensCycle.map { CalendarDay($0, calendar: .bucharest) } == CalendarDay("2026-11-10"))
        #expect(!effect.keepsDeadline)
        #expect(effect.removedReading == 101_000)
        #expect(effect.keptDocuments == 1)

        try HistoryActions(context: context).delete(entry)
        #expect(policy.dueDay(in: .bucharest) == CalendarDay("2026-11-10"), "The deadline is open again")
        #expect(policy.status == .active)
        #expect(policy.history.isEmpty)
        #expect(golf.measurements?.map(\.value) == [100_000], "Its reading went with it")
        #expect(golf.value("vehicle.odometer") == .number(100_000))
        #expect(paper.asset?.id == golf.id && paper.historyEntry == nil, "The policy stays in the binder")
        #expect(!context.hasChanges)
    }

    @Test func deletingAnOlderCompletionLeavesTheDeadlineAlone() throws {
        let context = try makeContext()
        let golf = try car(context)
        let actions = ObligationActions(context: context, calendar: .bucharest, now: { noon("2026-11-02") })
        let policy = try rca(on: golf, actions)
        let older = try actions.complete(policy).value
        try actions.complete(policy)
        #expect(policy.dueDay(in: .bucharest) == CalendarDay("2028-11-10"))

        let effect = HistoryDeletion(of: older)
        #expect(effect.reopensCycle == nil)
        #expect(effect.keepsDeadline)

        try HistoryActions(context: context).delete(older)
        #expect(policy.dueDay(in: .bucharest) == CalendarDay("2028-11-10"), "The deadline stays where it is")
        #expect(policy.history.count == 1)
    }

    @Test func aBackdatedCompletionIsStillTheLatestByTheCycleItClosed() throws {
        let context = try makeContext()
        let golf = try car(context)
        let actions = ObligationActions(context: context, calendar: .bucharest, now: { noon("2026-11-02") })
        let policy = try rca(on: golf, actions)
        let first = try actions.complete(policy).value
        // Recorded "on date" last month, but it closed the later cycle.
        let second = try actions.complete(policy, on: noon("2026-10-01")).value
        #expect(policy.history.first?.id == first.id, "By date, the first looks newer")
        #expect(policy.latestCompletion?.id == second.id, "By the cycle closed, the second is the latest")

        try HistoryActions(context: context).delete(second)
        #expect(policy.dueDay(in: .bucharest) == CalendarDay("2027-11-10"))
    }

    @Test func deletingTheCompletionOfAOneOffOpensItAgain() throws {
        let context = try makeContext()
        let actions = ObligationActions(context: context, calendar: .bucharest, now: { noon("2026-11-02") })
        let task = try actions.create(title: "Cazier", kind: .renewal, dueDay: CalendarDay("2026-11-20"), for: nil)
        let entry = try actions.complete(task).value
        #expect(task.status == .done)
        try HistoryActions(context: context).delete(entry)
        #expect(task.status == .active)
        #expect(task.dueDay(in: .bucharest) == CalendarDay("2026-11-20"))
    }

    @Test func deletingAVisitTakesItsPartsAndReadingButKeepsItsInvoiceAndTheFirm() throws {
        let context = try makeContext()
        let golf = try car(context)
        let mechanic = try ProviderActions(context: context).create(name: "Service Exemplu SRL", trades: [.mechanic])
        let visit = try HistoryActions(context: context, now: { noon("2026-11-02") }).recordVisit(
            on: golf, checklist: [.init(componentKey: "engine.oil", cost: Money(420))], odometer: 102_000, provider: mechanic,
            documents: [DocumentDraft(fileName: "factura.pdf", kind: .invoice, contentType: "com.adobe.pdf", originalData: Data([1]))],
            calendar: .bucharest
        ).value
        #expect(HistoryDeletion(of: visit).removedReading == 102_000)

        try HistoryActions(context: context).delete(visit)
        #expect(golf.history?.isEmpty == true)
        #expect(try context.fetchCount(FetchDescriptor<ServiceItem>()) == 0)
        #expect(golf.value("vehicle.odometer") == .number(100_000))
        let invoices = try context.fetch(FetchDescriptor<DosarCuSina.Attachment>())
        #expect(invoices.count == 1 && invoices.first?.asset?.id == golf.id, "The invoice stays")
        #expect(try context.fetchCount(FetchDescriptor<Provider>()) == 1, "The firm stays in Agendă")
    }
}
