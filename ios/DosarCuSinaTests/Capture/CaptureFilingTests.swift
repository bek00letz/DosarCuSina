import Foundation
import LocalAuthentication
import SwiftData
import Testing
@testable import DosarCuSina

/// One filer for every captured document, and one document in one place.
@Suite("Capture filing")
@MainActor
struct CapturedDocumentFilingTests {

    /// The three ways a captured document comes into the binder.
    enum EntryPoint: String, CaseIterable, CustomTestStringConvertible {
        case review, completion, visit
        var testDescription: String { rawValue }
    }

    struct Household {
        let context: ModelContext
        let car: Asset
        let home: Asset
        let rca: Obligation
        let boilerCheck: Obligation
        let repair: HistoryEntry
    }

    private func household() throws -> Household {
        let context = try makeContext()
        let store = TemplateStore(context: context)
        let vehicles = try #require(try store.template(forKey: BuiltInTemplates.Key.vehicle))
        let homes = try #require(try store.template(forKey: BuiltInTemplates.Key.home))
        let assets = AssetActions(context: context)
        var values = FieldValues()
        values["vehicle.plate"] = .text("B-123-ABC")
        let car = try assets.create(name: "VW Golf 2018", template: vehicles, values: values)
        let home = try assets.create(name: "Apartament", template: homes, values: FieldValues())
        let obligations = ObligationActions(context: context)
        let rca = try obligations.create(title: "RCA", kind: .insurance, dueDay: CalendarDay(Date()).adding(days: 10, calendar: .current), for: car,
                                         recurrence: .interval(.years(1), anchor: .dueDate))
        let boiler = try obligations.create(title: "Verificare centrală", kind: .maintenance, dueDay: CalendarDay(Date()).adding(days: 200, calendar: .current), for: home)
        let repair = try HistoryActions(context: context).record(on: home, kind: .repair, title: "Robinet nou")
        return Household(context: context, car: car, home: home, rca: rca, boilerCheck: boiler, repair: repair)
    }

    /// A firm's invoice, for who issued it (policies' insurers aren't kept in Oameni).
    private func invoice(document: CapturedDocumentRef?) -> CaptureResult {
        CaptureResult(kind: .serviceInvoice, kindConfidence: 0.95, fields: [
            CaptureField(key: .provider, value: .text("Service Exemplu SRL"), confidence: 0.9, tier: .heuristic),
        ], suggestions: [], reminder: nil, recognizedText: "FACTURĂ", barcodes: [], document: document, notices: [])
    }

    private func policy(document: CapturedDocumentRef?) -> CaptureResult {
        let expiry = CaptureDay(date: Calendar.current.date(byAdding: .day, value: 375, to: Date())!)
        return CaptureResult(kind: .rcaPolicy, kindConfidence: 0.95, fields: [
            CaptureField(key: .expiryDate, value: .day(expiry), confidence: 0.9, tier: .heuristic),
            CaptureField(key: .policyNumber, value: .text("RO/00/X/000000000"), confidence: 0.9, tier: .heuristic),
            CaptureField(key: .provider, value: .text("Exemplu Asigurări S.A."), confidence: 0.9, tier: .heuristic),
        ], suggestions: [], reminder: nil, recognizedText: "POLIȚĂ RCA", barcodes: [], document: document, notices: [])
    }

    @discardableResult
    private func file(_ entry: EntryPoint, _ document: CapturedDocumentRef, in house: Household, store: CaptureDocumentStore,
                      vault: BiometricVaultManager? = nil) async throws -> CaptureFiler.Outcome {
        var filer = CaptureFiler(context: house.context, store: store)
        if let vault { filer.vault = vault }
        switch entry {
        case .review:
            var review = CaptureReview(result: policy(document: document), assets: [house.car, house.home], context: house.context)
            review.destination = .asset(house.car.id)
            return try await filer.save(review)
        case .completion:
            return try await filer.file(.completion(.init(obligation: house.rca, date: Date(), cost: Money(1_150), document: policy(document: document))))
        case .visit:
            return try await filer.file(.visit(.init(asset: house.car, kind: .maintenance, occurredAt: Date(), checklist: [],
                                                     totalCost: Money(690), provider: .named("Service Exemplu SRL", trade: .mechanic),
                                                     document: document, documentTitle: "Factură service")))
        }
    }

    private func attachments(_ context: ModelContext) throws -> [DosarCuSina.Attachment] {
        try context.fetch(FetchDescriptor<DosarCuSina.Attachment>())
    }

    // MARK: One filer

    @Test("A photo already kept elsewhere moves here through every entry point, with none of its old links", arguments: EntryPoint.allCases)
    func aDuplicatePhotoMovesHere(_ entry: EntryPoint) async throws {
        let house = try household()
        let store = CaptureDocumentStore()
        let documents = AttachmentActions(context: house.context)
        let kept = try documents.file(DocumentDraft(fileName: "poza.heic", kind: .other, pageImages: [Data([1, 2, 3])]),
                                      asset: house.home, obligation: house.boilerCheck, historyEntry: house.repair)
        try documents.setArchived(kept, true)

        let outcome = try await file(entry, .kept(attachmentID: kept.id), in: house, store: store)

        #expect(outcome.attachment?.id == kept.id, "The kept copy, not a new one")
        #expect(try attachments(house.context).count == 1, "One document, one place")
        #expect(kept.asset?.id == house.car.id)
        #expect(kept.obligation?.id != house.boilerCheck.id, "No link to the old place's deadline")
        #expect(kept.historyEntry?.id != house.repair.id, "No link to the old place's history")
        #expect(kept.historyEntry.map { $0.asset?.id == house.car.id } ?? true)
        #expect(kept.isArchived, "Its archived state stays as it was")
        #expect(outcome.receipt?.canUndo == true, "The move can be taken back")
    }

    @Test("New pages are filed the same way through every entry point, and leave capture once kept", arguments: EntryPoint.allCases)
    func newPagesAreFiled(_ entry: EntryPoint) async throws {
        let house = try household()
        let store = CaptureDocumentStore()
        let stored = try await store.store(.init(pages: [CaptureDocumentStoreTests.page(width: 800, height: 1100, seed: 31)], kind: .rcaPolicy))
        let outcome = try await file(entry, stored.ref, in: house, store: store)
        let attachment = try #require(outcome.attachment)
        #expect(attachment.asset?.id == house.car.id)
        #expect(attachment.orderedPages.count == 1)
        #expect(await store.pendingCount == 0)
    }

    @Test("Who issued a document is the same firm, whichever way the document came in")
    func theProviderIsFoundOnce() async throws {
        let house = try household()
        let store = CaptureDocumentStore()
        var review = CaptureReview(result: invoice(document: nil), assets: [house.car], context: house.context)
        review.destination = .asset(house.car.id)
        _ = try await CaptureFiler(context: house.context, store: store).save(review)
        _ = try await CaptureFiler(context: house.context, store: store).file(.completion(.init(
            obligation: house.rca, date: Date(), cost: nil, document: invoice(document: nil))))
        let stored = try await store.store(.init(pages: [CaptureDocumentStoreTests.page(width: 800, height: 1100, seed: 71)], kind: .serviceInvoice))
        try await file(.visit, stored.ref, in: house, store: store)
        let firms = try house.context.fetch(FetchDescriptor<Provider>())
        #expect(firms.map(\.name) == ["Service Exemplu SRL"], "One firm, found by name each time")
        #expect(firms.first?.assets?.contains { $0.id == house.car.id } == true)
    }

    @Test("A new RCA policy through Am rezolvat updates the car's policy details")
    func completingWithAPolicyUpdatesTheCar() async throws {
        let house = try household()
        let outcome = try await CaptureFiler(context: house.context).file(.completion(.init(
            obligation: house.rca, date: Date(), cost: Money(1_150), document: policy(document: nil)
        )))
        #expect(house.car.value("vehicle.policyNumber") == .text("RO/00/X/000000000"))
        #expect(house.car.value("vehicle.insurer") == .text("Exemplu Asigurări S.A."))
        #expect(outcome.completion != nil)
        #expect(outcome.nextDue == CaptureFiler.nextDay(in: policy(document: nil)), "The policy's expiry is the next deadline")
    }

    // MARK: One document, one place

    enum Order: String, CaseIterable, CustomTestStringConvertible {
        case saveFirstThenSecond, closeFirstThenSaveSecond, saveSecondThenCloseFirst
        var testDescription: String { rawValue }
    }

    @Test("The same photo shared twice: each one saved has its document, and closing one never takes the other's pages", arguments: Order.allCases)
    func sharedTwice(_ order: Order) async throws {
        let house = try household()
        let store = CaptureDocumentStore()
        let bytes = Data("the same bill photo".utf8)
        let first = try await store.store(.init(pages: [CaptureDocumentStoreTests.page(width: 800, height: 1100, seed: 41)], sourceData: bytes, kind: .rcaPolicy))
        let second = try await store.store(.init(pages: [CaptureDocumentStoreTests.page(width: 800, height: 1100, seed: 41)], sourceData: bytes, kind: .rcaPolicy))
        switch order {
        case .saveFirstThenSecond:
            let a = try await file(.review, first.ref, in: house, store: store)
            let b = try await file(.review, second.ref, in: house, store: store)
            #expect(a.attachment != nil && b.attachment?.id == a.attachment?.id, "The second save has its document: the same one")
        case .closeFirstThenSaveSecond:
            await store.release(first.ref)
            let b = try await file(.review, second.ref, in: house, store: store)
            #expect(b.attachment?.orderedPages.count == 1)
        case .saveSecondThenCloseFirst:
            let b = try await file(.review, second.ref, in: house, store: store)
            await store.release(first.ref)
            #expect(b.attachment?.orderedPages.count == 1)
        }
        #expect(try attachments(house.context).count == 1)
        #expect(await store.pendingCount == 0, "Nothing is left in capture once every capture ended")
    }

    @Test("A capture whose pages are gone stops and says so, instead of saving without its document")
    func pagesGoneStops() async throws {
        let house = try household()
        let store = CaptureDocumentStore()
        let stored = try await store.store(.init(pages: [CaptureDocumentStoreTests.page(width: 800, height: 1100, seed: 51)], kind: .rcaPolicy))
        await store.release(stored.ref)
        let entriesBefore = try house.context.fetchCount(FetchDescriptor<HistoryEntry>())
        await #expect(throws: CapturedDocumentError.pagesGone) { _ = try await file(.visit, stored.ref, in: house, store: store) }
        #expect(try house.context.fetchCount(FetchDescriptor<HistoryEntry>()) == entriesBefore, "No visit without its invoice")
    }

    @Test("Moving a document out of a locked section asks to open it first")
    func movingOutOfALockedSectionAsks() async throws {
        let house = try household()
        let store = CaptureDocumentStore()
        let documentsTemplate = try #require(try TemplateStore(context: house.context).template(forKey: BuiltInTemplates.Key.documents))
        #expect(documentsTemplate.isSensitive, "Acte is locked by default")
        let passport = try AssetActions(context: house.context).create(name: "Pașaport", template: documentsTemplate, values: FieldValues())
        let kept = try AttachmentActions(context: house.context).file(DocumentDraft(fileName: "poza.heic", kind: .identity, pageImages: [Data([4])]), asset: passport)

        let refusing = FakeAuthenticator(.cancel)
        await #expect(throws: CaptureFiler.FilingError.locked) {
            _ = try await file(.review, .kept(attachmentID: kept.id), in: house, store: store,
                           vault: BiometricVaultManager(authenticator: refusing, appLockEnabled: { false }, observesAppLifecycle: false))
        }
        #expect(refusing.prompts == 1)
        #expect(kept.asset?.id == passport.id, "Nothing moved without Face ID")

        let opening = FakeAuthenticator(.succeed)
        try await file(.review, .kept(attachmentID: kept.id), in: house, store: store,
                       vault: BiometricVaultManager(authenticator: opening, appLockEnabled: { false }, observesAppLifecycle: false))
        #expect(kept.asset?.id == house.car.id)
    }

    @Test("Undoing a visit puts a moved invoice back where it was, and deletes only what the visit made")
    func undoingAVisitRestoresAMovedInvoice() async throws {
        let house = try household()
        let kept = try AttachmentActions(context: house.context).file(DocumentDraft(fileName: "factura.heic", kind: .invoice, pageImages: [Data([5])]),
                                                                       asset: house.home, historyEntry: house.repair)
        let outcome = try await file(.visit, .kept(attachmentID: kept.id), in: house, store: CaptureDocumentStore())
        try #require(outcome.receipt).undo()
        #expect(try attachments(house.context).count == 1, "The older invoice wasn't deleted")
        #expect(kept.asset?.id == house.home.id)
        #expect(kept.historyEntry?.id == house.repair.id)
    }
}

// MARK: - Examples become yours

@Suite("Examples become yours")
@MainActor
struct ExampleOwnershipTests {

    private func examples() throws -> (ModelContext, Asset) {
        let context = try makeContext()
        try ExampleDataService(context: context).loadExamples()
        let car = try #require(try context.fetch(FetchDescriptor<Asset>()).first { $0.isExample && $0.templateKey == BuiltInTemplates.Key.vehicle })
        return (context, car)
    }

    enum Addition: String, CaseIterable, CustomTestStringConvertible {
        case deadline, blueprintDeadline, historyEntry, visit, document, reading, childSection
        var testDescription: String { rawValue }
    }

    private func add(_ addition: Addition, to car: Asset, in context: ModelContext) throws {
        switch addition {
        case .deadline:
            _ = try ObligationActions(context: context).create(title: "Rovinietă", kind: .payment, dueDay: CalendarDay(Date()).adding(days: 30, calendar: .current), for: car)
        case .blueprintDeadline:
            let template = try #require(try TemplateStore(context: context).template(forKey: car.templateKey))
            let blueprint = try #require(template.blueprints.first)
            _ = try ObligationActions(context: context).create(from: blueprint, for: car, firstDue: CalendarDay(Date()).adding(days: 30, calendar: .current))
        case .historyEntry:
            _ = try HistoryActions(context: context).record(on: car, kind: .repair, title: "Bec schimbat")
        case .visit:
            _ = try HistoryActions(context: context).recordVisit(on: car, checklist: [])
        case .document:
            _ = try AttachmentActions(context: context).file(DocumentDraft(fileName: "poza.heic", kind: .other, pageImages: [Data([6])]), asset: car)
        case .reading:
            _ = try AssetActions(context: context).recordMeasurement(on: car, kind: .odometer, value: 150_000, unit: .kilometres)
        case .childSection:
            let template = try #require(try TemplateStore(context: context).template(forKey: BuiltInTemplates.Key.other))
            _ = try AssetActions(context: context).create(name: "Scaun copil", template: template, values: FieldValues(), parent: car)
        }
    }

    @Test("Something real added to an example asks first and saves nothing, until the person keeps the example", arguments: Addition.allCases)
    func addingAsksFirst(_ addition: Addition) throws {
        let (context, car) = try examples()
        do {
            try add(addition, to: car, in: context)
            Issue.record("It saved without asking")
        } catch let question as ExampleSectionQuestion {
            #expect(question.sectionID == car.id)
            #expect(question.question == "Păstrezi „\(car.name)” ca a ta?", "A car is „mașina”: feminine")
        }
        #expect(!context.hasChanges, "Nothing was left half made")
        #expect(car.isExample, "No keeps the example as it was")

        try ExampleDataService(context: context).adopt(sectionID: car.id)
        try add(addition, to: car, in: context)
        #expect(!car.isExample)
        try ExampleDataService(context: context).removeExamples()
        #expect(try context.fetch(FetchDescriptor<Asset>()).contains { $0.id == car.id }, "Removing examples never touches it again")
        #expect(try context.fetch(FetchDescriptor<Obligation>()).filter { $0.asset?.id == car.id }.allSatisfy { !$0.isExample })
    }

    @Test("A neuter section reads „al tău”")
    func neuterWording() {
        let question = ExampleSectionQuestion(sectionID: UUID(), name: "Internet fibră", gender: BuiltInTemplates.gender(ofSectionIn: BuiltInTemplates.Key.subscription))
        #expect(question.question == "Păstrezi „Internet fibră” ca al tău?")
    }

    @Test("Removing examples keeps an example that already holds something of the person's, and makes it theirs")
    func removingKeepsWhatIsReal() throws {
        let (context, car) = try examples()
        // From before the app asked: a real deadline on the example car.
        let real = Obligation(title: "Rovinietă", kind: .payment, dueDay: CalendarDay(Date()).adding(days: 30, calendar: .current), recurrence: .none, reminders: nil, estimatedCost: nil, calendar: .current)
        context.insert(real)
        real.asset = car
        try context.save()
        let kept = try ExampleDataService(context: context).removeExamples()
        #expect(kept == [car.name])
        #expect(!car.isExample)
        #expect(real.asset?.id == car.id)
        #expect(try !ExampleDataService(context: context).hasExamples())
    }

    @Test("Examples load in one step and are marked only by the loader")
    func loadingIsOneStep() throws {
        let context = try makeContext()
        UnitOfWork.failNextCommitForTesting(ForcedLoadFailure(), in: context)
        #expect(throws: ForcedLoadFailure.self) { try ExampleDataService(context: context).loadExamples() }
        #expect(try context.fetchCount(FetchDescriptor<Asset>()) == 0, "No half household")
        try ExampleDataService(context: context).loadExamples()
        #expect(try context.fetch(FetchDescriptor<HistoryEntry>()).allSatisfy(\.isExample))
    }
}

private struct ForcedLoadFailure: Error {}

// MARK: - A capture closed while reading stops

@Suite("Capture session")
@MainActor
struct CaptureSessionTests {

    /// Waits for work the session hands to other tasks (releasing pages).
    private func eventually(_ condition: () async -> Bool) async -> Bool {
        for _ in 0..<200 {
            if await condition() { return true }
            try? await Task.sleep(for: .milliseconds(5))
        }
        return await condition()
    }

    private final class Calls: @unchecked Sendable {
        private let lock = NSLock()
        private var _cancelled = 0
        private var _cloud: [Bool] = []
        var cancelled: Int { lock.withLock { _cancelled } }
        var cloud: [Bool] { lock.withLock { _cloud } }
        func cancel() { lock.withLock { _cancelled += 1 } }
        func read(cloud: Bool) { lock.withLock { _cloud.append(cloud) } }
    }

    private func result(_ kind: CaptureDocumentKind, document: CapturedDocumentRef?) -> CaptureResult {
        CaptureResult(kind: kind, kindConfidence: 0.5, fields: [], suggestions: [], reminder: nil, recognizedText: "",
                      barcodes: [], document: document, notices: [])
    }

    @Test("Swiping the sheet down cancels the reading: nothing runs on, nothing is sent")
    func closingCancelsTheReading() async throws {
        let calls = Calls()
        var session: CaptureSession? = CaptureSession(payload: .text("RCA"), reader: { _, cloud, _ in
            calls.read(cloud: cloud)
            try await withTaskCancellationHandler {
                try await Task.sleep(for: .seconds(60))
            } onCancel: { calls.cancel() }
            throw CancellationError()
        })
        session?.read()
        #expect(await eventually { calls.cloud.count == 1 })
        session = nil // the sheet let go of its input
        #expect(await eventually { calls.cancelled == 1 })
    }

    @Test("Closing a capture lets go of its pages, and only its own")
    func closingReleasesItsPages() async throws {
        let store = CaptureDocumentStore()
        let bytes = Data("one photo".utf8)
        let mine = try await store.store(.init(pages: [CaptureDocumentStoreTests.page(width: 400, height: 600, seed: 61)], sourceData: bytes))
        let other = try await store.store(.init(pages: [CaptureDocumentStoreTests.page(width: 400, height: 600, seed: 61)], sourceData: bytes))
        let id = try #require(mine.ref.pendingID)
        let session = CaptureSession(payload: .text("RCA"), store: store, reader: { _, _, _ in self.result(.rcaPolicy, document: mine.ref) },
                                     automaticReading: { _, _ in .none })
        session.read()
        #expect(await eventually { session.result != nil })
        session.close()
        #expect(await eventually { await store.processed(id: id) != nil }, "The other capture still has the pages")
        await store.release(other.ref)
        #expect(await eventually { await store.processed(id: id) == nil })
    }

    @Test("Citește automat asks before an identity document's photo leaves the phone, once, and sends nothing before yes")
    func identityAsksOnce() async throws {
        let calls = Calls()
        func session() -> CaptureSession {
            CaptureSession(payload: .text("CARTE DE IDENTITATE"), reader: { _, cloud, _ in
                calls.read(cloud: cloud)
                return self.result(.identityCard, document: nil)
            }, automaticReading: { _, _ in .askFirst })
        }
        let saysNo = session()
        saysNo.read()
        #expect(await eventually { saysNo.asksToSendToProvider })
        #expect(calls.cloud == [false], "Nothing was sent while asking")
        saysNo.answerSending(false)
        #expect(!saysNo.asksToSendToProvider)
        try await Task.sleep(for: .milliseconds(20))
        #expect(calls.cloud == [false])

        let saysYes = session()
        saysYes.read()
        #expect(await eventually { saysYes.asksToSendToProvider })
        saysYes.answerSending(true)
        #expect(await eventually { calls.cloud == [false, false, true] })
        #expect(!saysYes.asksToSendToProvider, "Asked once for this document")
    }
}

// MARK: - Repairs that wait for the owner's OK

@Suite("Capture repairs")
@MainActor
struct CaptureRepairTests {

    @Test("Documents moved with stale links are found, repaired only when approved, and a second run changes nothing")
    func staleLinks() throws {
        let context = try makeContext()
        let store = TemplateStore(context: context)
        let assets = AssetActions(context: context)
        let car = try assets.create(name: "VW Golf 2018", template: try #require(try store.template(forKey: BuiltInTemplates.Key.vehicle)), values: FieldValues())
        let home = try assets.create(name: "Apartament", template: try #require(try store.template(forKey: BuiltInTemplates.Key.home)), values: FieldValues())
        let boiler = try ObligationActions(context: context).create(title: "Verificare centrală", kind: .maintenance, dueDay: CalendarDay(Date()).adding(days: 30, calendar: .current), for: home)
        let moved = try AttachmentActions(context: context).file(DocumentDraft(fileName: "a.heic", kind: .other, pageImages: [Data([7])]), asset: home, obligation: boiler)
        moved.asset = car // as the old move left it
        try context.save()
        let repairs = CaptureRepairs(context: context)

        let found = try repairs.staleDocumentLinkCandidates()
        #expect(found.map(\.attachmentID) == [moved.id])
        #expect(moved.obligation?.id == boiler.id, "Finding changes nothing")
        try repairs.dropStaleDocumentLinks(found)
        #expect(moved.obligation == nil)
        #expect(moved.asset?.id == car.id)
        try repairs.dropStaleDocumentLinks(found)
        #expect(try repairs.staleDocumentLinkCandidates().isEmpty)
    }

    @Test("A visit saved without its invoice is matched with the one invoice that fits, and linked only when approved")
    func visitsWithoutInvoice() throws {
        let context = try makeContext()
        let car = try AssetActions(context: context).create(name: "VW Golf 2018", template: try #require(try TemplateStore(context: context).template(forKey: BuiltInTemplates.Key.vehicle)), values: FieldValues())
        var draft = DocumentDraft(fileName: "factura.heic", kind: .invoice, pageImages: [Data([8])])
        draft.documentDate = CalendarDay(Date()).adding(days: -2, calendar: .current)
        let invoice = try AttachmentActions(context: context).file(draft, asset: car)
        let visit = try HistoryActions(context: context).recordVisit(on: car, checklist: []).value
        let repairs = CaptureRepairs(context: context)

        let found = try repairs.visitsWithoutInvoiceCandidates()
        #expect(found == [.init(visitID: visit.id, invoiceID: invoice.id)])
        #expect(invoice.historyEntry == nil, "Finding changes nothing")
        try repairs.linkInvoices(found)
        #expect(invoice.historyEntry?.id == visit.id)
        try repairs.linkInvoices(found)
        #expect(try repairs.visitsWithoutInvoiceCandidates().isEmpty)
    }
}

@Suite("Providers found once")
@MainActor
struct ProviderLookupTests {

    @Test("The filer and the visit form find a firm by its name before making a new one")
    func findOrCreateFindsByName() throws {
        let context = try makeContext()
        let actions = ProviderActions(context: context)
        let first = try #require(try actions.findOrCreate(name: "Service Exemplu SRL", trade: .mechanic))
        let again = try actions.findOrCreate(name: "  service exemplu srl ", trade: .mechanic)
        #expect(again?.id == first.id)
        #expect(try context.fetchCount(FetchDescriptor<Provider>()) == 1)
        #expect(try actions.findOrCreate(name: "   ", trade: .mechanic) == nil)
    }

    @Test("Duplicate firms are merged only when approved, into the one kept first, and a second run changes nothing")
    func mergeDuplicates() throws {
        let context = try makeContext()
        let car = try AssetActions(context: context).create(name: "VW Golf 2018", template: try #require(try TemplateStore(context: context).template(forKey: BuiltInTemplates.Key.vehicle)), values: FieldValues())
        let actions = ProviderActions(context: context)
        let kept = try actions.create(name: "Service Exemplu SRL", trades: [.mechanic])
        kept.createdAt = Date(timeIntervalSince1970: 1_700_000_000)
        let copy = try actions.create(name: "SERVICE EXEMPLU SRL", trades: [.tyreShop], phone: "0700 000 001", linkedTo: [car])
        let visit = try HistoryActions(context: context).recordVisit(on: car, checklist: [], provider: copy).value
        try context.save()
        let repairs = CaptureRepairs(context: context)

        let found = try repairs.duplicateProviderCandidates()
        #expect(found == [.init(keptID: kept.id, duplicateIDs: [copy.id])])
        #expect(try context.fetchCount(FetchDescriptor<Provider>()) == 2, "Finding changes nothing")
        try repairs.mergeDuplicateProviders(found)
        #expect(try context.fetchCount(FetchDescriptor<Provider>()) == 1)
        #expect(visit.providers?.map(\.id) == [kept.id])
        #expect(kept.assets?.contains { $0.id == car.id } == true)
        #expect(kept.phone != nil)
        #expect(Set(kept.knownTrades) == [.mechanic, .tyreShop])
        try repairs.mergeDuplicateProviders(found)
        #expect(try repairs.duplicateProviderCandidates().isEmpty)
    }
}
