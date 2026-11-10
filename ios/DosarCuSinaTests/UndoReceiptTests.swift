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

    @MainActor
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
                                             recurrence: .metric(every: 10_000, unit: .kilometres, fallback: .years(1)))
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
        case fileAReviewOfANewPhoto
        case pauseADeadline
        case resumeADeadline
        case archiveADeadline
        case bringBackASnoozedDeadline
        case deleteADeadline
        case deleteADocumentWithItsPages
        case deleteAPersonalDocument
        case deleteASectionWithItsHistoryAndDocuments
        case deleteACarWithItsDeadlinesVisitsAndReadings
        case deleteAPersonKeepingTheirDocuments
        case deleteAPersonWithTheirDocuments
        case deleteTheLastTenancy
        case deleteAFirm
        case deleteACategoryOfOnesOwn
        case removeTheExamples
        case removeTheExamplesKeepingOneThatHoldsSomethingOfThePersons
        case fileAVisitWithANewPhoto
        case fileAnotherPhotoOfABillAlreadyFiled

        var testDescription: String { rawValue }

        /// What the household has before the step, beyond `Household.make`.
        @MainActor
        func setUp(in house: Household) async throws {
            let context = house.context
            let obligations = ObligationActions(context: context, calendar: .bucharest, now: { noon("2026-11-02") })
            switch self {
            case .resumeADeadline:
                try obligations.pause(house.kit)
            case .deleteADeadline:
                // Its completion stays in the car's history and its policy in the binder, without the link.
                let done = try obligations.complete(house.rca, cost: Money(1_150), providers: [house.mechanic]).value
                _ = try AttachmentActions(context: context, calendar: .bucharest).file(
                    DocumentDraft(title: "Poliță RCA", fileName: "polita.heic", kind: .policy, pageImages: [Data([1, 2]), Data([3, 4])]),
                    asset: house.car, obligation: house.rca, historyEntry: done
                )
            case .deleteACarWithItsDeadlinesVisitsAndReadings:
                _ = try HistoryActions(context: context, now: { noon("2026-11-02") }).recordVisit(
                    on: house.car, checklist: [.init(componentKey: "engine.oil", cost: Money(420))], extraItems: [LineItemDraft(name: "Odorizant")],
                    totalCost: Money(690), odometer: 101_000, provider: house.mechanic,
                    documents: [DocumentDraft(fileName: "factura.heic", kind: .invoice, pageImages: [Data([8, 9])])],
                    rating: 5, calendar: .bucharest
                )
            case .deleteTheLastTenancy:
                let tenancy = try #require(try TemplateStore(context: context).template(forKey: BuiltInTemplates.Key.tenancy))
                var lease = FieldValues()
                lease["tenancy.end"] = .date(CalendarDay("2027-06-30"))
                _ = try AssetActions(context: context, calendar: .bucharest, now: { noon("2026-11-02") })
                    .create(name: "Chiriaș", template: tenancy, values: lease, parent: house.home)
            case .deleteAFirm:
                // The firm worked on the car, did a visit with a part it supplied and issued its invoice.
                let visit = try HistoryActions(context: context, now: { noon("2026-11-02") }).recordVisit(
                    on: house.car, checklist: [.init(componentKey: "engine.oil", cost: Money(420))], totalCost: Money(420), provider: house.mechanic,
                    documents: [DocumentDraft(fileName: "factura.heic", kind: .invoice, pageImages: [Data([4, 2])])], calendar: .bucharest
                ).value
                try ProviderActions(context: context).link(house.mechanic, to: house.car)
                for item in visit.items ?? [] { item.supplier = house.mechanic }
                for paper in visit.attachments ?? [] { paper.provider = house.mechanic }
                try UnitOfWork.save(context)
            case .deleteACategoryOfOnesOwn:
                _ = try TemplateStore(context: context).createCustom(name: "Scule", symbol: "wrench.and.screwdriver.fill", tint: .orange, sections: [
                    FieldSection(key: "tools", title: "Unealtă", fields: [FieldDefinition(key: "tools.serial", label: "Serie", type: .text, role: .identifier)]),
                ])
            case .removeTheExamples:
                try ExampleDataService(context: context).loadExamples()
            case .removeTheExamplesKeepingOneThatHoldsSomethingOfThePersons:
                try ExampleDataService(context: context).loadExamples()
                // Something of the person's in an example, from before the app asked: the example stays, as theirs.
                let example = try #require(try context.fetch(FetchDescriptor<Asset>()).first { $0.isExample && $0.parent == nil })
                let note = HistoryEntry(kind: .note, title: "Notă a mea", occurredAt: noon("2026-11-02"))
                context.insert(note)
                note.asset = example
                try UnitOfWork.save(context)
            case .fileAnotherPhotoOfABillAlreadyFiled:
                let store = CaptureDocumentStore()
                let first = try await store.store(.init(pages: [CaptureDocumentStoreTests.page(width: 900, height: 640, seed: 33)], kind: .utilityInvoice))
                let filer = CaptureFiler(context: context, store: store, calendar: .bucharest, now: { noon("2026-11-02") })
                var review = CaptureReview(result: bill(first.ref), assets: try context.fetch(FetchDescriptor<Asset>()), context: context)
                review.destination = .asset(house.home.id)
                _ = try await filer.save(review)
            default:
                break
            }
        }

        @MainActor
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
            case .fileAReviewOfANewPhoto:
                // The review's "Salvează" with a new photo: its pages, the policy's facts, the deadline it moves.
                let store = CaptureDocumentStore()
                let captured = try await store.store(.init(pages: [CaptureDocumentStoreTests.page(width: 900, height: 640, seed: 31)], kind: .rcaPolicy))
                let filer = CaptureFiler(context: context, store: store, calendar: .bucharest)
                var review = CaptureReview(result: policy(captured.ref), assets: [house.car, house.home], context: context)
                review.destination = .asset(house.car.id)
                return try #require(try await filer.save(review).receipt)
            case .pauseADeadline:
                return try obligations.pause(house.oil)
            case .resumeADeadline:
                return try obligations.resume(house.kit)
            case .archiveADeadline:
                return try obligations.archive(house.kit)
            case .bringBackASnoozedDeadline:
                return try obligations.clearSnooze(house.rca)
            case .deleteADeadline:
                return try obligations.delete(house.rca)
            case .deleteADocumentWithItsPages:
                return try AttachmentActions(context: context).delete(house.keptInvoice)
            case .deleteAPersonalDocument:
                return try assets.delete(house.card)
            case .deleteASectionWithItsHistoryAndDocuments:
                return try assets.delete(house.home)
            case .deleteACarWithItsDeadlinesVisitsAndReadings:
                return try assets.delete(house.car)
            case .deleteAPersonKeepingTheirDocuments:
                return try assets.delete(house.corina, children: .keep)
            case .deleteAPersonWithTheirDocuments:
                return try assets.delete(house.corina, children: .delete)
            case .deleteTheLastTenancy:
                let tenancy = try #require(house.home.children?.first { $0.templateKey == BuiltInTemplates.Key.tenancy })
                return try assets.delete(tenancy)
            case .deleteAFirm:
                return try ProviderActions(context: context).delete(house.mechanic)
            case .deleteACategoryOfOnesOwn:
                let custom = try #require(try TemplateStore(context: context).all().first(where: \.isCustom))
                return try TemplateStore(context: context).delete(custom)
            case .removeTheExamples, .removeTheExamplesKeepingOneThatHoldsSomethingOfThePersons:
                return try ExampleDataService(context: context).removeExamples().receipt
            case .fileAVisitWithANewPhoto:
                // A visit saved through capture: its new invoice, a new firm, the parts and the kilometres.
                let store = CaptureDocumentStore()
                let captured = try await store.store(.init(pages: [CaptureDocumentStoreTests.page(width: 900, height: 640, seed: 32)], kind: .serviceInvoice))
                let filer = CaptureFiler(context: context, store: store, calendar: .bucharest, now: { noon("2026-11-03") })
                return try #require(try await filer.file(.visit(.init(
                    asset: house.car, kind: .maintenance, occurredAt: noon("2026-11-03"), checklist: [.init(componentKey: "engine.oil", cost: Money(420))],
                    totalCost: Money(690), odometer: 102_000, provider: .named("Service Nou Exemplu SRL", trade: .mechanic),
                    document: captured.ref, documentTitle: "Factură service"
                ))).receipt)
            case .fileAnotherPhotoOfABillAlreadyFiled:
                // The same bill, from another photo: its entry is updated and the new photo becomes its copy.
                let store = CaptureDocumentStore()
                let second = try await store.store(.init(pages: [CaptureDocumentStoreTests.page(width: 900, height: 640, seed: 34)], kind: .utilityInvoice))
                let filer = CaptureFiler(context: context, store: store, calendar: .bucharest, now: { noon("2026-11-03") })
                let review = CaptureReview(result: bill(second.ref, total: 254), assets: try context.fetch(FetchDescriptor<Asset>()), context: context)
                return try #require(try await filer.save(review).receipt)
            }
        }

        /// A gas bill for the home. Placeholder provider, codes and number.
        private func bill(_ document: CapturedDocumentRef, total: Decimal = 245) -> CaptureResult {
            let fields = [
                CaptureField(key: .provider, value: .text("ENGIE Romania S.A."), confidence: 0.9, tier: .heuristic),
                CaptureField(key: .serviceKind, value: .text(ServiceKind.gas), confidence: 0.9, tier: .heuristic),
                CaptureField(key: .clcCode, value: .text("DEG0000000000001"), confidence: 0.9, tier: .heuristic),
                CaptureField(key: .invoiceNumber, value: .text("EXM 0000001"), confidence: 0.9, tier: .heuristic),
                CaptureField(key: .issueDate, value: .day(CalendarDay(printedYear: 2026, month: 10, day: 5)!), confidence: 0.9, tier: .heuristic),
                CaptureField(key: .dueDate, value: .day(CalendarDay(printedYear: 2026, month: 11, day: 20)!), confidence: 0.9, tier: .heuristic),
                CaptureField(key: .total, value: .money(Money(total, currency: "RON")), confidence: 0.9, tier: .heuristic),
            ]
            let routing = CaptureRouter.route(kind: .utilityInvoice, kindConfidence: 0.9, fields: fields)
            return CaptureResult(kind: .utilityInvoice, kindConfidence: 0.9, fields: fields, suggestions: routing.suggestions, reminder: routing.reminder,
                                 recognizedText: "", barcodes: [], document: document, notices: [])
        }

        private func policy(_ document: CapturedDocumentRef) -> CaptureResult {
            let expiry = CalendarDay(Calendar.current.date(byAdding: .day, value: 375, to: Date())!)
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
        try await step.setUp(in: house)
        let before = try Self.database(house.context)

        let receipt = try await step.run(in: house)
        let after = try Self.database(house.context)
        #expect(!Self.differences(before, after).isEmpty, "The step changed something")
        #expect(receipt.canUndo)
        #expect(Set(Self.differences(before, after).map(\.ref)).isSubset(of: receipt.touched), "The receipt names every record the step changed")
        // Pictures and files only by their digest, and a copy kept of exactly what the step took away.
        for state in Array(receipt.before.values) + Array(receipt.after.values) {
            for name in UndoableRecords.keptOutside[state.ref.type] ?? [] {
                guard case .file? = state.values[name] else {
                    Issue.record("\(state.ref).\(name) is kept as a value, not by its digest")
                    continue
                }
            }
        }
        let taken = Set(Self.filePlaces(in: before).subtracting(Self.filePlaces(in: after)).map(\.digest))
        #expect((receipt.files?.kept ?? []) == taken, "The receipt keeps a copy of what the step took, and of nothing a record still has")

        try receipt.undo()
        let undone = try Self.database(house.context)
        let left = Self.differences(before, undone)
        #expect(left.isEmpty, "Still different after undo: \(left.map(\.description))")
        #expect(!receipt.canUndo, "A receipt is used once")
        #expect(receipt.files == nil, "Once taken back, its copies go")
    }

    // MARK: Undo takes back only what the step changed

    @Test("Another deadline of the same section completed from the widget while the toast shows doesn't stop Anulează, and stays done")
    func anotherDeadlineCompletedSinceDoesNotStopTheUndo() throws {
        let house = try Household.make()
        let context = house.context
        let before = try Self.database(context)
        let done = try ObligationActions(context: context, calendar: .bucharest, now: { noon("2026-11-03") }).complete(house.rca)
        let afterStep = try Self.database(context)
        let widget = OutsideRequest(obligationId: house.kit.id, cycle: house.kit.dueDay, action: .complete, surface: .widget)
        #expect(try IntentEngine.apply(widget, in: context, calendar: .bucharest, now: { noon("2026-11-03") }) == .completed(next: nil))
        let afterWidget = try Self.database(context)
        let byWidget = Set(Self.differences(afterStep, afterWidget).map(\.ref))
        #expect(byWidget.contains(RecordRef(house.car)), "The widget's completion is in the car's history too")

        try done.receipt.undo()
        let undone = try Self.database(context)
        #expect(Set(Self.differences(before, undone).map(\.ref)) == byWidget, "Only what the widget did is left")
        for ref in byWidget where ref != RecordRef(house.car) {
            #expect(undone[ref] == afterWidget[ref], "\(ref) is as the widget left it")
        }
        #expect(house.kit.status == .done, "The kit stays done")
        #expect((house.car.history ?? []).compactMap(\.obligation?.id) == [house.kit.id], "Its completion stays in the car's history; the RCA's is gone")
    }

    @Test("A newer change to another field of the same record stays after Anulează, with its change time")
    func aNewerChangeToAnotherFieldStays() throws {
        let house = try Household.make()
        let facts = house.home.customFacts
        let receipt = try AssetActions(context: house.context, calendar: .bucharest, now: { noon("2026-11-03") })
            .setCustomFacts(house.home, Array(facts.dropFirst()))
        // Another screen writes the home's notes meanwhile.
        house.home.notes = "Cheia e la vecini"
        try UnitOfWork.save(house.context, now: noon("2026-11-04"))

        try receipt.undo()
        #expect(house.home.customFacts.map(\.label) == facts.map(\.label), "What the step changed is back")
        #expect(house.home.notes == "Cheia e la vecini", "The newer change stays")
        #expect(house.home.updatedAt == noon("2026-11-04"), "And so does its change time")
        let saved = try #require(try Self.database(house.context)[RecordRef(house.home)])
        #expect(saved == RecordState.capture(house.home), "As saved")
    }

    @Test("A newer change to what the step changed stops Anulează, and changes nothing")
    func aNewerChangeToTheSameFieldStopsTheUndo() throws {
        let house = try Household.make()
        let assets = AssetActions(context: house.context, calendar: .bucharest, now: { noon("2026-11-03") })
        let receipt = try assets.setCustomFacts(house.home, [])
        _ = try assets.setCustomFacts(house.home, [CustomFact(label: "Cod poartă", value: "56")])
        let before = try Self.database(house.context)

        #expect(throws: UndoError.changedSince) { try receipt.undo() }
        #expect(Self.differences(before, try Self.database(house.context)).isEmpty, "A refused undo changes nothing")
        #expect(house.home.customFacts.map(\.label) == ["Cod poartă"])
    }

    @Test("Anulează refuses when something was filed since under a record the step made")
    func undoRefusesWhenSomethingPointsAtWhatTheStepMade() throws {
        let house = try Household.make()
        let assets = AssetActions(context: house.context, calendar: .bucharest, now: { noon("2026-11-03") })
        let receipt = try assets.move(house.card, to: .newMember(name: "Manole Ana"), renamingTo: "Carte de identitate – Manole Ana")
        let ana = try #require(house.card.parent)
        let documents = try #require(try TemplateStore(context: house.context).template(forKey: BuiltInTemplates.Key.documents))
        _ = try assets.create(name: "Pașaport – Manole Ana", template: documents,
                              values: FieldValues(["document.type": .text(DocumentType.passport)]), parent: ana)
        let before = try Self.database(house.context)

        #expect(throws: UndoError.changedSince) { try receipt.undo() }
        #expect(Self.differences(before, try Self.database(house.context)).isEmpty, "The passport and its person stay")
    }

    // MARK: Pictures and files

    @Test("Deleting a document keeps its pictures on disk for Anulează, and brings them back")
    func aDeletedDocumentsPicturesComeBackFromDisk() throws {
        let house = try Household.make()
        let picture = Data([5, 6, 7])
        let page = try #require(house.keptInvoice.pages?.first)
        let pageRef = RecordRef(page)
        let receipt = try AttachmentActions(context: house.context).delete(house.keptInvoice)
        let files = try #require(receipt.files, "What the delete took is kept")
        #expect(files.kept.contains(FileDigest(picture)))
        #expect(FileManager.default.fileExists(atPath: files.folder.appending(path: FileDigest(picture).name).path()), "On disk")
        #expect(receipt.before[pageRef]?.values["imageData"] == .file(FileDigest(picture)), "The receipt knows the page by its digest")
        let folder = files.folder

        try receipt.undo()
        let back = try house.context.fetch(FetchDescriptor<AttachmentPage>())
        #expect(back.map(\.imageData) == [picture], "The page's picture is back")
        #expect(back.first?.attachment?.historyEntry?.id == house.repair.id)
        #expect(receipt.files == nil && !FileManager.default.fileExists(atPath: folder.path()), "Once taken back, the copy goes")
    }

    @Test("A receipt knows the pictures a record still has by digest, and keeps no copy of them")
    func aReceiptHoldsNoPictureARecordStillHas() throws {
        let house = try Household.make()
        let photo = Data(repeating: 7, count: 4_096)
        house.home.photoData = photo
        try UnitOfWork.save(house.context)
        let receipt = try AssetActions(context: house.context, calendar: .bucharest, now: { noon("2026-11-03") }).setCustomFacts(house.home, [])

        let state = try #require(receipt.before[RecordRef(house.home)])
        #expect(state.values["photoData"] == .file(FileDigest(photo)))
        #expect(receipt.files == nil, "Nothing is copied: the home still has its photo")
        try receipt.undo()
        #expect(house.home.photoData == photo)
        #expect(house.home.customFacts.count == 2)
    }

    @Test("What an earlier run kept for an undo goes at launch; a receipt's own copies go with it, and one that changed is never written back")
    func undoFilesLeaveWithTheirReceipt() throws {
        let root = URL.temporaryDirectory.appending(path: "undo-files-\(UUID().uuidString)", directoryHint: .isDirectory)
        let earlier = root.appending(path: "an-earlier-run", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: earlier, withIntermediateDirectories: true)
        let picture = Data([1, 2, 3])
        var files: UndoFiles? = UndoFiles(root: root)
        try files?.keep(picture, as: FileDigest(picture))
        let folder = try #require(files?.folder)

        UndoFiles.removeLeftovers(root: root)
        #expect(!FileManager.default.fileExists(atPath: earlier.path()), "An earlier run's copies go")
        #expect(files?.bytes(of: [FileDigest(picture)]) == [FileDigest(picture): picture], "This run's stay")

        try Data([9]).write(to: folder.appending(path: FileDigest(picture).name))
        #expect(files?.bytes(of: [FileDigest(picture)]) == nil, "A copy that no longer matches is never written back")
        files = nil
        #expect(!FileManager.default.fileExists(atPath: folder.path()), "The receipt's copies go with it")
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
        let schema = Schema(versionedSchema: DosarSchemaV10.self)
        #expect(UndoableRecords.types.count == DosarSchemaV10.models.count, "Every model of the schema can be undone")
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

    /// Where a picture or a file is: its record and property.
    struct FilePlace: Hashable {
        let ref: RecordRef
        let name: String
        let digest: FileDigest
    }

    /// Every picture and file in `database`, where it is.
    static func filePlaces(in database: [RecordRef: RecordState]) -> Set<FilePlace> {
        database.values.reduce(into: []) { places, state in
            for (name, value) in state.values {
                if case .file(let digest?) = value { places.insert(FilePlace(ref: state.ref, name: name, digest: digest)) }
            }
        }
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
        #expect(policy.dueDay == CalendarDay("2027-11-10"))

        let effect = HistoryDeletion(of: entry)
        #expect(effect.reopensCycle == CalendarDay("2026-11-10"))
        #expect(!effect.keepsDeadline)
        #expect(effect.removedReading == 101_000)
        #expect(effect.keptDocuments == 1)

        try HistoryActions(context: context).delete(entry)
        #expect(policy.dueDay == CalendarDay("2026-11-10"), "The deadline is open again")
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
        #expect(policy.dueDay == CalendarDay("2028-11-10"))

        let effect = HistoryDeletion(of: older)
        #expect(effect.reopensCycle == nil)
        #expect(effect.keepsDeadline)

        try HistoryActions(context: context).delete(older)
        #expect(policy.dueDay == CalendarDay("2028-11-10"), "The deadline stays where it is")
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
        #expect(policy.dueDay == CalendarDay("2027-11-10"))
    }

    @Test func deletingTheCompletionOfAOneOffOpensItAgain() throws {
        let context = try makeContext()
        let actions = ObligationActions(context: context, calendar: .bucharest, now: { noon("2026-11-02") })
        let task = try actions.create(title: "Cazier", kind: .renewal, dueDay: CalendarDay("2026-11-20"), for: nil)
        let entry = try actions.complete(task).value
        #expect(task.status == .done)
        try HistoryActions(context: context).delete(entry)
        #expect(task.status == .active)
        #expect(task.dueDay == CalendarDay("2026-11-20"))
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
