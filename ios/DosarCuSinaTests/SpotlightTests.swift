import Foundation
import SwiftData
import Testing
@testable import DosarCuSina

/// The iPhone's search (Spotlight): what it shows, what it never shows, and that it
/// follows every save with only what changed.
@MainActor
@Suite("Spotlight")
struct SpotlightTests {
    let calendar = Calendar.bucharest
    let today = noon("2026-11-03")

    /// A household with a car (its RCA and policy), a home, and a passport in Acte.
    struct Household {
        let container: ModelContainer
        let context: ModelContext
        let index: FakeSpotlightIndex
        let indexer: SpotlightIndexer
        let car: Asset
        let rca: Obligation
        let policy: Attachment
        let home: Asset
        let passport: Asset
        let passportRenewal: Obligation
        let passportPhoto: Attachment
        let enabled: Switch
    }

    @MainActor
    final class Switch {
        var isOn: Bool
        init(_ isOn: Bool = true) { self.isOn = isOn }
    }

    private func template(_ key: String, in context: ModelContext) throws -> CategoryTemplate {
        try #require(try TemplateStore(context: context).template(forKey: key))
    }

    private func household() throws -> Household {
        let container = try makeInMemoryContainer()
        let context = ModelContext(container)
        try TemplateStore(context: context).installBuiltIns()
        let assets = AssetActions(context: context, calendar: calendar, now: { today })
        let obligations = ObligationActions(context: context, calendar: calendar, now: { today })
        let attachments = AttachmentActions(context: context, calendar: calendar)

        let car = try assets.create(name: "VW Golf", template: try template(BuiltInTemplates.Key.vehicle, in: context), values: FieldValues())
        let rca = try obligations.create(title: "RCA", kind: .insurance, dueDay: CalendarDay("2027-01-10"), for: car,
                                         recurrence: .interval(.years(1), anchor: .dueDate))
        let policy = try attachments.file(DocumentDraft(title: "Poliță RCA 2026", fileName: "polita.pdf", kind: .policy,
                                                        extractedText: "Asigurat 1800101990006 Seria RO/12/ABC citit de pe act"), asset: car)
        let home = try assets.create(name: "Apartament", template: try template(BuiltInTemplates.Key.home, in: context), values: FieldValues())

        let documents = try template(BuiltInTemplates.Key.documents, in: context)
        let passport = try assets.create(
            name: "Pașaport – Manole Corina", template: documents,
            values: FieldValues([
                DocumentType.typeFieldKey: .text(DocumentType.passport),
                DocumentFields.number: .text("054321987"),
                DocumentFields.expiry: .date(CalendarDay("2031-08-12")),
            ]),
            obligations: assets.plannedObligations(for: documents, values: FieldValues([DocumentFields.expiry: .date(CalendarDay("2031-08-12"))]))
        )
        let renewal = try #require(passport.activeObligations.first)
        let photo = try attachments.file(DocumentDraft(title: "Pașaport – Manole Corina", fileName: "pasaport.jpg", kind: .identity), asset: passport)

        let index = FakeSpotlightIndex()
        let enabled = Switch()
        let ledger = SpotlightLedgerStore(url: URL.temporaryDirectory.appending(path: "spotlight-\(UUID().uuidString)/ledger.json"))
        let indexer = SpotlightIndexer(index: index, ledger: ledger, isEnabled: { enabled.isOn })
        return Household(container: container, context: context, index: index, indexer: indexer, car: car, rca: rca, policy: policy,
                         home: home, passport: passport, passportRenewal: renewal, passportPhoto: photo, enabled: enabled)
    }

    private func entries(_ context: ModelContext) throws -> [SpotlightEntry] {
        try SpotlightCatalog.entries(obligations: ObligationSnapshot.fetchForOutside(in: context, calendar: calendar), in: context)
    }

    private func pass(_ h: Household) async throws {
        await h.indexer.reconcile(obligations: try ObligationSnapshot.fetchForOutside(in: h.context, calendar: calendar), context: h.context)
    }

    private func routes(_ entries: [SpotlightEntry]) -> Set<AppRoute> {
        Set(entries.map(\.route))
    }

    private func id(_ route: AppRoute) -> String {
        DeepLink.url(for: route).absoluteString
    }

    // MARK: What is shown

    @Test func showsSectionNamesDeadlinesAndDocumentTitles() throws {
        let h = try household()
        let all = try entries(h.context)

        let car = try #require(all.first { $0.route == .asset(h.car.id) })
        #expect(car.title == "VW Golf")
        #expect(car.kind == .section)
        #expect(car.detail == "Mașini")

        let rca = try #require(all.first { $0.route == .obligation(h.rca.id) })
        #expect(rca.title == "RCA – VW Golf")
        #expect(rca.detail == "10 ianuarie 2027")
        #expect(rca.keywords == ["VW Golf"])

        let policy = try #require(all.first { $0.route == .document(h.policy.id) })
        #expect(policy.title == "Poliță RCA 2026")
        #expect(policy.detail == "VW Golf")

        #expect(all.contains { $0.route == .asset(h.home.id) && $0.title == "Apartament" })
    }

    @Test func aDeadlineThatNamesItsSectionIsNotNamedTwice() {
        #expect(SpotlightCatalog.deadlineTitle("ITP VW Golf", section: "VW Golf") == "ITP VW Golf")
        #expect(SpotlightCatalog.deadlineTitle("ITP", section: "VW Golf") == "ITP – VW Golf")
    }

    @Test func aClosedDeadlineAndAnArchivedDocumentAreNotShown() throws {
        let h = try household()
        let oneOff = try ObligationActions(context: h.context, calendar: calendar, now: { today })
            .create(title: "Schimb de ulei", kind: .maintenance, dueDay: CalendarDay("2026-12-01"), for: h.car)
        _ = try ObligationActions(context: h.context, calendar: calendar, now: { today }).complete(oneOff)
        _ = try AttachmentActions(context: h.context, calendar: calendar).setArchived(h.policy, true)

        let shown = routes(try entries(h.context))
        #expect(!shown.contains(.obligation(oneOff.id)))
        #expect(!shown.contains(.document(h.policy.id)))
        #expect(shown.contains(.obligation(h.rca.id)))
    }

    // MARK: What is never shown

    /// Every built-in category, locked and unlocked: a locked one shows nothing at all,
    /// titles included, whether or not the session is open.
    @Test(arguments: BuiltInTemplates.all.map(\.key), [false, true])
    func aLockedCategoryShowsNothing(key: String, isLocked: Bool) throws {
        let container = try makeInMemoryContainer()
        let context = ModelContext(container)
        try TemplateStore(context: context).installBuiltIns()
        let category = try template(key, in: context)
        try TemplateStore(context: context).setSensitive(category, isLocked)
        let section = try AssetActions(context: context, calendar: calendar, now: { today })
            .create(name: "Secțiune de probă", template: category, values: FieldValues())
        let deadline = try ObligationActions(context: context, calendar: calendar, now: { today })
            .create(title: "Termen de probă", kind: .routine, dueDay: CalendarDay("2027-03-01"), for: section)
        let paper = try AttachmentActions(context: context, calendar: calendar)
            .file(DocumentDraft(title: "Act de probă", fileName: "act.pdf", kind: .other), obligation: deadline)

        let shown = routes(try entries(context))
        let ours: Set<AppRoute> = [.asset(section.id), .obligation(deadline.id), .document(paper.id)]
        if isLocked {
            #expect(shown.isDisjoint(with: ours), "Nothing from a locked category, titles included")
        } else {
            #expect(ours.isSubset(of: shown))
        }
    }

    @Test func actsLockedByDefaultShowNothingAndUnlockedShowOnlyTheirTitles() throws {
        let h = try household()
        let locked = routes(try entries(h.context))
        #expect(!locked.contains(.asset(h.passport.id)))
        #expect(!locked.contains(.obligation(h.passportRenewal.id)))
        #expect(!locked.contains(.document(h.passportPhoto.id)))

        try TemplateStore(context: h.context).setSensitive(try template(BuiltInTemplates.Key.documents, in: h.context), false)
        let unlocked = try entries(h.context)
        let passport = try #require(unlocked.first { $0.route == .asset(h.passport.id) })
        #expect(passport.title == "Pașaport – Manole Corina")
        #expect(passport.detail == "Acte")
        #expect(unlocked.contains { $0.route == .document(h.passportPhoto.id) })
    }

    @Test func neverACNPADocumentNumberASecretOrTheTextReadOffADocument() throws {
        let h = try household()
        let documents = try template(BuiltInTemplates.Key.documents, in: h.context)
        try TemplateStore(context: h.context).setSensitive(documents, false)
        let sealer = SecretSealer.ephemeral()
        let assets = AssetActions(context: h.context, calendar: calendar, now: { today }, sealer: sealer)
        // Names a person typed with the numbers in them.
        try assets.update(h.passport, name: "Pașaport 054 321 987 – Manole Corina", values: h.passport.values, notes: nil)
        let sealed = try sealer.seal("0000")
        let card = try assets.create(name: "Card 1800101990006", template: try template(BuiltInTemplates.Key.other, in: h.context), values: FieldValues())
        let attachments = AttachmentActions(context: h.context, calendar: calendar)
        let paper = try attachments.file(DocumentDraft(title: "Cod \(sealed) alarmă", fileName: "cod.pdf", kind: .other), asset: h.home)
        let numbered = try attachments.file(DocumentDraft(title: "Copie 054-321-987", fileName: "copie.pdf", kind: .other), asset: h.passport)

        let all = try entries(h.context)
        let shown = all.flatMap { [$0.title, $0.detail ?? ""] + $0.keywords }.joined(separator: "\n")
        #expect(!shown.contains("054"), "The passport's number, with or without spaces")
        #expect(!shown.contains("1800101990006"), "Nothing shaped like a CNP")
        #expect(!shown.contains(SecretSealer.prefix), "No sealed value")
        #expect(!shown.contains("citit"), "Never the text read off a document")
        #expect(all.first { $0.route == .asset(h.passport.id) }?.title == "Pașaport – Manole Corina")
        #expect(all.first { $0.route == .asset(card.id) }?.title == "Card")
        #expect(all.first { $0.route == .document(paper.id) }?.title == "Cod alarmă")
        #expect(all.first { $0.route == .document(numbered.id) }?.title == "Copie")
    }

    @Test func aTitleThatIsOnlyANumberIsNotShown() {
        #expect(SearchPrivacy.outsideText("1800101990006") == nil)
        #expect(SearchPrivacy.outsideText("RX 123456", withholding: ["RX123456"]) == nil)
        #expect(SearchPrivacy.outsideText("Buletin – RX-123456", withholding: ["rx123456"]) == "Buletin")
        #expect(SearchPrivacy.outsideText("Cod 12", withholding: ["12"]) == "Cod 12", "Too short to stand for anything")
    }

    @Test func examplesAreNeverShownAndOneMadeYoursIs() async throws {
        let h = try household()
        let examples = ExampleDataService(context: h.context, calendar: calendar, now: { today })
        try examples.loadExamples()
        let exampleRoutes = try h.context.fetch(FetchDescriptor<Asset>(predicate: #Predicate { $0.isExample })).map { AppRoute.asset($0.id) }
            + h.context.fetch(FetchDescriptor<Obligation>(predicate: #Predicate { $0.isExample })).map { AppRoute.obligation($0.id) }
            + h.context.fetch(FetchDescriptor<Attachment>(predicate: #Predicate { $0.isExample })).map { AppRoute.document($0.id) }
        #expect(!exampleRoutes.isEmpty)
        try await pass(h)
        #expect(Set(h.index.items.values.map(\.route)).isDisjoint(with: exampleRoutes))

        // Removing the examples changes nothing in the index: nothing of theirs is there.
        let before = h.index.items
        _ = try examples.removeExamples()
        try await pass(h)
        #expect(h.index.items == before)
    }

    @Test func anExampleMadeYoursIsShown() async throws {
        let h = try household()
        let examples = ExampleDataService(context: h.context, calendar: calendar, now: { today })
        try examples.loadExamples()
        let lockedKeys = Set(try TemplateStore(context: h.context).all().filter(\.isSensitive).map(\.key))
        let example = try #require(try h.context.fetch(FetchDescriptor<Asset>(predicate: #Predicate { $0.isExample }))
            .first { $0.parent == nil && !lockedKeys.contains($0.templateKey) })
        try await pass(h)
        #expect(h.index.items[id(.asset(example.id))] == nil)

        try examples.adopt(sectionID: example.id)
        try await pass(h)
        #expect(h.index.items[id(.asset(example.id))] != nil)
    }

    // MARK: Following saves

    @Test func aSaveReindexesOnlyWhatChanged() async throws {
        let h = try household()
        try await pass(h)
        let first = h.index.applied.count
        #expect(first == 1)

        try await pass(h)
        #expect(h.index.applied.count == first, "Nothing changed, nothing written")
        #expect(h.indexer.lastChange == SpotlightIndexer.Change())

        try AssetActions(context: h.context, calendar: calendar, now: { today })
            .update(h.car, name: "VW Passat", values: h.car.values, notes: nil)
        try await pass(h)
        let change = try #require(h.indexer.lastChange)
        // The car, and what shows its name: its deadline and its document.
        #expect(Set(change.indexed) == [id(.asset(h.car.id)), id(.obligation(h.rca.id)), id(.document(h.policy.id))])
        #expect(change.removed.isEmpty)
        #expect(!change.removedEverything)
        #expect(h.index.items[id(.obligation(h.rca.id))]?.title == "RCA – VW Passat")

        _ = try ObligationActions(context: h.context, calendar: calendar, now: { today }).complete(h.rca)
        try await pass(h)
        #expect(h.indexer.lastChange?.indexed == [id(.obligation(h.rca.id))], "A new due day, only that deadline")
        #expect(h.index.items[id(.obligation(h.rca.id))]?.detail == "10 ianuarie 2028")

        try AttachmentActions(context: h.context, calendar: calendar).delete(h.policy)
        try await pass(h)
        #expect(h.indexer.lastChange?.removed == [id(.document(h.policy.id))], "A deleted document is deleted")
        #expect(h.indexer.lastChange?.indexed.isEmpty == true)
    }

    @Test func turningALockOnRemovesWhatWasShown() async throws {
        let h = try household()
        try await pass(h)
        let carRoutes: [AppRoute] = [.asset(h.car.id), .obligation(h.rca.id), .document(h.policy.id)]
        for route in carRoutes { #expect(h.index.items[id(route)] != nil) }

        try TemplateStore(context: h.context).setSensitive(try template(BuiltInTemplates.Key.vehicle, in: h.context), true)
        try await pass(h)
        for route in carRoutes { #expect(h.index.items[id(route)] == nil) }
        #expect(Set(h.indexer.lastChange?.removed ?? []) == Set(carRoutes.map(id)))
        #expect(h.index.items[id(.asset(h.home.id))] != nil, "The rest stays")
    }

    @Test func turningItOffDeletesEverythingOnceAndOnBringsItBack() async throws {
        let h = try household()
        try await pass(h)
        #expect(!h.index.items.isEmpty)

        h.enabled.isOn = false
        try await pass(h)
        #expect(h.index.items.isEmpty)
        #expect(h.index.deleteAllCount == 1)
        #expect(h.indexer.lastChange?.removedEverything == true)
        try await pass(h)
        #expect(h.index.deleteAllCount == 1, "Deleted once, not on every pass")
        #expect(h.index.items.isEmpty)

        h.enabled.isOn = true
        try await pass(h)
        #expect(h.index.items[id(.asset(h.car.id))] != nil)
    }

    @Test func anIndexThatNoLongerMatchesIsWrittenAgainFromNothing() async throws {
        let h = try household()
        try await pass(h)
        let written = h.index.items
        // The system cleared the index, or the phone was restored from a backup.
        h.index.items = [:]
        h.index.state = nil
        try await pass(h)
        #expect(h.index.deleteAllCount == 1)
        #expect(h.index.items == written)
        #expect(h.indexer.lastChange?.removedEverything == true)
    }

    @Test func aBatchThatFailedIsSentAgain() async throws {
        let h = try household()
        h.index.failsNext = true
        try await pass(h)
        #expect(h.index.items.isEmpty)
        try await pass(h)
        #expect(h.index.items[id(.asset(h.car.id))] != nil)
    }

    @Test func theCoordinatorRunsTheIndexerAfterAPass() async throws {
        let h = try household()
        let folder = URL.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let coordinator = SideEffectsCoordinator(container: h.container, notificationClient: FakeNotificationCenter(status: .authorized),
                                                 widgetWriter: WidgetSnapshotWriter(directory: folder))
        coordinator.register(h.indexer)
        await coordinator.reconcileNow()
        #expect(h.index.items[id(.obligation(h.rca.id))]?.title == "RCA – VW Golf")
    }

    // MARK: Opening a result

    @Test func aResultOpensItsRouteAfterUnlocking() throws {
        let h = try household()
        let all = try entries(h.context)
        for entry in all {
            #expect(SpotlightEntry.route(forIdentifier: entry.identifier) == entry.route)
        }
        #expect(ShellRouting.plan(for: .obligation(h.rca.id)) == ShellRoutePlan(tab: .upcoming, path: [.obligation(h.rca.id)]))

        let locked = Switch(true)
        let navigator = AppNavigator(isAppLocked: { locked.isOn })
        #expect(navigator.open(spotlightIdentifier: id(.document(h.policy.id))))
        #expect(navigator.consume() == nil, "It waits while the app is locked")
        locked.isOn = false
        #expect(navigator.consume() == .document(h.policy.id))
        #expect(!navigator.open(spotlightIdentifier: "something-else"))
    }
}

/// Stands in for Core Spotlight: keeps what was written, the batch token and the calls.
@MainActor
final class FakeSpotlightIndex: SpotlightIndexClient {
    struct Failure: Error {}

    var items: [String: SpotlightEntry] = [:]
    var state: Data?
    var failsNext = false
    private(set) var applied: [(upserts: [String], removals: [String])] = []
    private(set) var deleteAllCount = 0

    func lastState() async throws -> Data? { state }

    func apply(upserts: [SpotlightEntry], removals: [String], state: Data) async throws {
        if failsNext {
            failsNext = false
            throw Failure()
        }
        for entry in upserts { items[entry.identifier] = entry }
        for identifier in removals { items[identifier] = nil }
        self.state = state
        applied.append((upserts.map(\.identifier), removals))
    }

    func deleteAll() async throws {
        items = [:]
        state = nil
        deleteAllCount += 1
    }
}
