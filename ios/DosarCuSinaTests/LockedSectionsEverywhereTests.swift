import Foundation
import SwiftData
import Testing
import UIKit
@testable import DosarCuSina

/// A locked section behaves the same on every surface: one answer for whether it is locked, even
/// before its category's record arrives; every route and sheet that shows or writes into a
/// section opens behind it; and closing one of its deadlines asks for Face ID from every way in,
/// while „Amână” never does. Every value is a placeholder.
///
/// The surfaces that name a locked section from somewhere else, each pinned below:
/// - Urmează: reads the locks again when they change, and „Gata” asks by the lock as it is now.
/// - A parent's page: a person's documents, a home's subscriptions, a firm's sections
///   (`SectionRowLock`), the person's hero (`HolderHero`) and the hero's status line.
/// - The binder's boxes (`BoxStatus.line`): a deadline of a locked section filed in an open box.
/// - Agendă and a firm's page: the last job of a locked section (`Provider.lastJobLine`).
/// - A deadline's page: its sheets live behind its section's lock (`ObligationScreen.sheetLock`).
/// - A document's page: behind every section it belongs to (`Attachment.lock`).
/// - The lock's cover: the keyboard goes as it goes up (`LockWindowController`).
@MainActor
@Suite("Locked sections, everywhere")
struct LockedSectionsEverywhereTests {
    let calendar = Calendar.bucharest

    /// Counts the Face ID prompts a request asked for, and answers them as told.
    @MainActor final class Prompts {
        var answer: UnlockResult
        var count = 0
        init(_ answer: UnlockResult) { self.answer = answer }
        var confirm: IntentEngine.ClosingConfirmation {
            { [self] _ in
                count += 1
                return answer
            }
        }
    }

    private struct Household {
        let container: ModelContainer
        let car: Asset
        let itp: Obligation
        let coordinator: SideEffectsCoordinator
        let failures: OutsideActionFailures
        let folder: URL
    }

    /// A car whose ITP is due 5 December, its category locked on this device or not.
    private func household(locked: Bool, now: Date) async throws -> Household {
        let container = try makeInMemoryContainer()
        let context = container.mainContext
        try TemplateStore(context: context).installBuiltIns()
        let template = try #require(try TemplateStore(context: context).template(forKey: BuiltInTemplates.Key.vehicle))
        let car = try AssetActions(context: context, calendar: calendar, now: { now }).create(name: "VW Golf 2018", template: template, values: FieldValues())
        let itp = try ObligationActions(context: context, calendar: calendar, now: { now })
            .create(title: "ITP", kind: .legal, dueDay: CalendarDay("2026-12-05"), for: car)
        if locked { try template.setLock(true) }
        let folder = URL.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let defaults = try #require(UserDefaults(suiteName: "tests.\(UUID().uuidString)"))
        let coordinator = SideEffectsCoordinator(
            container: container,
            notificationClient: FakeNotificationCenter(status: .authorized),
            widgetWriter: WidgetSnapshotWriter(directory: folder),
            preferences: AppPreferences(defaults: defaults),
            calendar: { calendar },
            now: { now }
        )
        return Household(container: container, car: car, itp: itp, coordinator: coordinator,
                         failures: OutsideActionFailures(suiteName: "tests.\(UUID().uuidString)"), folder: folder)
    }

    /// Sends one request through the real entry point of `surface`, answering Face ID with `prompts`.
    @discardableResult
    private func send(_ request: OutsideRequest, to home: Household, prompts: Prompts, navigator: AppNavigator = AppNavigator(isAppLocked: { false }),
                      now: Date) async -> IntentEngine.Outcome? {
        switch request.surface {
        case .notification:
            let responder = NotificationResponder(containerProvider: { home.container }, navigator: navigator,
                                                  sideEffects: { _ in home.coordinator }, failures: home.failures, confirmClosing: prompts.confirm)
            let action = request.action == .complete ? ReminderActions.complete : ReminderActions.snooze
            await responder.handle(action: action, payload: ReminderPayload(obligationId: request.obligationId, cycle: request.cycle), calendar: calendar)
            return nil
        case .widget:
            let queue = WidgetCompletionQueue(fileURL: home.folder.appending(path: WidgetCompletionQueue.fileName))
            queue.enqueue(WidgetCompletion(obligationId: request.obligationId, dueDay: request.cycle?.isoString ?? "", requestedAt: now))
            IntentEngine.applyQueuedWidgetCompletions(queue: queue, in: home.container.mainContext, failures: home.failures, calendar: calendar, now: { now })
            #expect(queue.pending().isEmpty, "A tap the app handled leaves the queue")
            return nil
        case .shortcut:
            return try? await IntentEngine.perform(request, container: home.container, sideEffects: { _ in home.coordinator },
                                                   failures: home.failures, confirmClosing: prompts.confirm, calendar: calendar, now: { now })
        }
    }

    // MARK: One answer for a section's lock

    @Test func aSectionWhoseCategoryHasntArrivedStaysLocked() throws {
        let container = try makeInMemoryContainer()
        let context = container.mainContext
        try TemplateStore(context: context).installBuiltIns()
        let template = try #require(try TemplateStore(context: context).template(forKey: BuiltInTemplates.Key.vehicle))
        let section = try AssetActions(context: context, calendar: calendar).create(name: "Caiet", template: template, values: FieldValues())
        try ObligationActions(context: context, calendar: calendar).create(title: "Termen", kind: .routine, dueDay: CalendarDay("2026-12-05"), for: section)
        #expect(!section.isSensitive(template: template), "A car is open by default")

        // Its category of one's own is still on its way from another device.
        section.templateKey = "custom.0b6c6f43-0000-4000-8000-0000000000aa"
        #expect(section.isSensitive(template: nil), "No record yet: locked until it arrives")
        #expect(section.isSensitive(among: try TemplateStore(context: context).templatesByKey()))
        let vault = BiometricVaultManager(authenticator: FakeAuthenticator(.cancel), appLockEnabled: { false }, observesAppLifecycle: false)
        #expect(vault.isLocked(section, template: nil))
        let snapshot = try #require(try ObligationSnapshot.fetchAll(in: context, calendar: calendar).first)
        #expect(snapshot.isSensitive, "Reminders, widgets and Siri give it the generic words")
        #expect(try SpotlightCatalog.entries(obligations: [snapshot], in: context).isEmpty, "Nothing of it in the iPhone's search")

        // This device's own choice for the key still counts, and a built-in follows the catalog.
        try SectionLocks.of(container).set(false, for: section.templateKey)
        #expect(!section.isSensitive(template: nil))
        #expect(!CategoryTemplate.isSensitive(key: BuiltInTemplates.Key.vehicle, template: nil, in: nil))
        #expect(CategoryTemplate.isSensitive(key: BuiltInTemplates.Key.documents, template: nil, in: nil))
        #expect(CategoryTemplate.isSensitive(key: "custom.unknown", template: nil, in: nil))
    }

    @Test func theCoverAndABackupFollowASectionWhoseCategoryHasntArrived() async throws {
        let container = try makeInMemoryContainer()
        let context = container.mainContext
        try TemplateStore(context: context).installBuiltIns()
        // Every lock off, with Face ID: nothing of the binder is behind it.
        let lowering = try await faceIDConfirmed()
        for template in try context.fetch(FetchDescriptor<CategoryTemplate>()) { try template.setLock(false, lowering: lowering) }
        let template = try #require(try TemplateStore(context: context).template(forKey: BuiltInTemplates.Key.vehicle))
        let section = try AssetActions(context: context, calendar: calendar).create(name: "Caiet", template: template, values: FieldValues())
        func cover(_ phase: LockCover.Phase) -> LockCover? {
            LockCover.decide(appLockEnabled: false, anySectionLocked: BinderLocks.read(in: context).anySectionLocked,
                             isSessionUnlocked: true, phase: phase, isAuthenticating: false)
        }
        #expect(!BinderLocks.read(in: context).anySectionLocked)
        #expect(cover(.background) == nil)

        // Its category of one's own is still on its way from another device.
        let key = "custom.0b6c6f43-0000-4000-8000-0000000000bb"
        section.templateKey = key
        let locks = BinderLocks.read(in: context)
        #expect(locks.anySectionLocked, "Locked until its category arrives, as on its own page")
        #expect(locks.lockedKeys == [key])
        #expect(cover(.inactive) == .privacy, "The app switcher's picture is covered")
        #expect(cover(.background) == .privacy)
        #expect(cover(.active) == nil)
        #expect(SettingsStatus.protection(appLock: false, lockedCategories: locks.lockedKeys.count, biometryName: "Face ID", needsChoosingAgain: false)
            == "Face ID pentru o categorie")
        // De verificat: an item read as that category's shows as protected.
        let templates = try context.fetch(FetchDescriptor<CategoryTemplate>())
        #expect(BinderLocks(templates: templates, naming: [key], in: container).lockedKeys == [key])

        // A backup asks for Face ID first, and makes nothing without it.
        let authenticator = FakeAuthenticator(.cancel)
        let vault = BiometricVaultManager(authenticator: authenticator, appLockEnabled: { false }, observesAppLifecycle: false)
        let directory = URL.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let flow = BackupFlow(container: container, vault: vault, workDirectory: directory, inbox: directory.appending(path: "Inbox"),
                              keeper: RecordingBackupKeeper())
        await flow.export(password: nil)
        #expect(authenticator.prompts == 1)
        #expect(flow.exportURL == nil)
        #expect(try FileManager.default.contentsOfDirectory(atPath: directory.path(percentEncoded: false)).isEmpty, "Nothing is written")

        // This device's own choice for the key still counts.
        try SectionLocks.of(container).set(false, for: key)
        #expect(!BinderLocks.read(in: context).anySectionLocked)
        #expect(cover(.background) == nil)
    }

    // MARK: Routes and sheets

    @Test func everyRouteAndSheetIntoASectionOpensBehindItsLock() {
        let id = UUID()
        // The link „dosarcusina://visit/<id>” opens the visit's sheet over its section, both behind its lock.
        let visit = ShellRouting.plan(for: .addVisit(id))
        #expect(visit.sheet?.lock == .section(id))
        #expect(visit.locks == [.section(id), .section(id)])
        #expect(ShellRouting.plan(for: .asset(id)).locks == [.section(id)])

        #expect(ShellSheet.addVisit(id).lock == .section(id))
        #expect(ShellSheet.addSection(AddSectionRequest(parentID: id, templateKey: nil)).lock == .section(id))
        #expect(ShellSheet.addPersonalDocument(holderID: id).lock == .section(id))
        #expect(ShellSheet.addSection(.topLevel).lock == .open, "A new top-level section reveals nothing")
        #expect(ShellSheet.addPersonalDocument(holderID: nil).lock == .open)
        #expect(ShellSheet.settings(nil).lock == .open)

        // A record's screen draws the lock itself; nothing that names one of a section's records is open.
        let records: [AppRoute] = [.obligation(id), .historyEntry(id), .document(id), .provider(id), .category("vehicle"),
                                   .readiness(.sale(assetID: id)), .readiness(.trip(holderID: nil))]
        for route in records { #expect(route.lock == .drawnByItsScreen, "\(route)") }
        let open: [AppRoute] = [.home, .upcoming, .search, .intake, .agenda, .settings(nil)]
        for route in open { #expect(route.lock == .open, "\(route)") }
    }

    // MARK: Closing asks for Face ID, snoozing doesn't

    @Test func theRuleClosesWithFaceIDAndSnoozesFreely() {
        #expect(DeadlineChange.close.asksFaceID(inLockedCategory: true))
        #expect(!DeadlineChange.close.asksFaceID(inLockedCategory: false))
        #expect(!DeadlineChange.snooze.asksFaceID(inLockedCategory: true))
        #expect(OutsideAction.complete.change == .close)
        #expect(OutsideAction.snooze(days: 3).change == .snooze)
        #expect(OutsideSurface.notification.canAskFaceID && OutsideSurface.shortcut.canAskFaceID)
        #expect(!OutsideSurface.widget.canAskFaceID, "A widget runs in the background")

        // A reminder of a locked category opens the app for „Am rezolvat”; „Amână” stays on the Lock Screen.
        #expect(ReminderActions.completeOptions(isProtected: true).contains(.foreground))
        #expect(ReminderActions.completeOptions(isProtected: true).contains(.authenticationRequired))
        #expect(!ReminderActions.completeOptions(isProtected: false).contains(.foreground))
        #expect(ReminderActions.snoozeOptions(isProtected: true).isEmpty)
        #expect(ReminderActions.snoozeOptions(isProtected: false).isEmpty)
        #expect(ReminderActions.category(isProtected: true) != ReminderActions.category(isProtected: false))
    }

    @Test func aRemindersButtonKnowsItsCategorysLock() {
        let locked = snapshot("ITP", kind: .legal, due: "2026-12-05", isSensitive: true)
        let open = snapshot("ITP", kind: .legal, due: "2026-12-05")
        let lockedReminder = ReminderPlanner.reminder(for: locked, on: CalendarDay("2026-12-04"), fireDate: noon("2026-12-04"),
                                                     identifierSuffix: "d1", calendar: calendar, locale: .dosarDefault)
        let openReminder = ReminderPlanner.reminder(for: open, on: CalendarDay("2026-12-04"), fireDate: noon("2026-12-04"),
                                                   identifierSuffix: "d1", calendar: calendar, locale: .dosarDefault)
        #expect(lockedReminder.isProtected)
        #expect(!openReminder.isProtected)
        #expect(lockedReminder.fingerprint != openReminder.fingerprint, "Locking a category plans its reminders again")
    }

    @Test(arguments: OutsideSurface.allCases)
    func closingALockedDeadlineAsksFaceIDFirst(surface: OutsideSurface) async throws {
        let now = noon("2026-12-03")
        let home = try await household(locked: true, now: now)
        let request = OutsideRequest(obligationId: home.itp.id, cycle: CalendarDay("2026-12-05"), action: .complete, surface: surface)

        // Face ID not given (or, on a widget, not possible): nothing closes.
        let refused = Prompts(.cancelled)
        let navigator = AppNavigator(isAppLocked: { false })
        let outcome = await send(request, to: home, prompts: refused, navigator: navigator, now: now)
        #expect(home.itp.status == .active)
        #expect(home.itp.dueDay == CalendarDay("2026-12-05"))
        #expect(refused.count == (surface.canAskFaceID ? 1 : 0))
        switch surface {
        case .notification:
            #expect(home.failures.all().map(\.obligationId) == [home.itp.id], "It waits in Urmează")
            #expect(navigator.pendingRoute == .obligation(home.itp.id), "Its page opens, to finish there")
        case .widget:
            #expect(home.failures.all().map(\.obligationId) == [home.itp.id], "It waits in Urmează")
        case .shortcut:
            #expect(outcome == .leftForTheApp)
            #expect(home.failures.all().isEmpty, "Siri says it at once")
        }

        // Confirmed: it closes, where the surface can ask.
        guard surface.canAskFaceID else { return }
        let given = Prompts(.success)
        await send(request, to: home, prompts: given, now: now)
        #expect(given.count == 1)
        #expect(home.itp.status != .active || home.itp.dueDay != CalendarDay("2026-12-05"), "Closed after Face ID")
    }

    @Test(arguments: OutsideSurface.allCases)
    func anOpenCategorysDeadlineClosesWithoutAsking(surface: OutsideSurface) async throws {
        let now = noon("2026-12-03")
        let home = try await household(locked: false, now: now)
        let prompts = Prompts(.cancelled)
        await send(OutsideRequest(obligationId: home.itp.id, cycle: CalendarDay("2026-12-05"), action: .complete, surface: surface),
                   to: home, prompts: prompts, now: now)
        #expect(prompts.count == 0)
        #expect(home.itp.status != .active || home.itp.dueDay != CalendarDay("2026-12-05"))
        #expect(home.failures.all().isEmpty)
    }

    @Test func snoozingALockedDeadlineFromTheLockScreenAsksNothing() async throws {
        let now = noon("2026-12-03")
        let home = try await household(locked: true, now: now)
        let prompts = Prompts(.cancelled)
        let request = OutsideRequest(obligationId: home.itp.id, cycle: CalendarDay("2026-12-05"), action: .snooze(days: 3), surface: .notification)
        #expect(try !IntentEngine.asksFaceID(request, in: home.container.mainContext))
        await send(request, to: home, prompts: prompts, now: now)
        #expect(prompts.count == 0)
        #expect(home.itp.snoozedUntil != nil)
        #expect(home.failures.all().isEmpty)
    }

    @Test func aStaleTapOnALockedDeadlineAsksNothing() async throws {
        let now = noon("2026-12-03")
        let home = try await household(locked: true, now: now)
        let prompts = Prompts(.success)
        let stale = OutsideRequest(obligationId: home.itp.id, cycle: CalendarDay("2026-11-05"), action: .complete, surface: .notification)
        #expect(try !IntentEngine.asksFaceID(stale, in: home.container.mainContext))
        await send(stale, to: home, prompts: prompts, now: now)
        #expect(prompts.count == 0)
        #expect(home.itp.dueDay == CalendarDay("2026-12-05"))
    }

    @Test func theWidgetOffersGataOnlyWhereClosingAsksNothing() {
        let id = UUID()
        func item(_ isSensitive: Bool) -> WidgetFeed.Item {
            WidgetFeed.Item(obligationId: id, assetId: nil, title: "ITP", assetName: "VW Golf 2018", symbol: "car", tint: "gray", dueDate: CalendarDay("2026-12-05"),
                            kind: "legal", isSensitive: isSensitive, deepLink: DeepLink.url(for: .obligation(id)), urgency: nil)
        }
        for isSensitive in [true, false] {
            let feed = WidgetFeed(generatedAt: noon("2026-12-03"), needsActionCount: 0, items: [item(isSensitive)])
            let row = WidgetContent.rows(feed: feed, completed: [], now: noon("2026-12-03"), calendar: calendar, protectedTitle: "Scadență protejată", limit: 3).first
            #expect(row?.canComplete == !isSensitive)
        }
    }

    // MARK: Every surface that names a locked section

    private func closedVault() -> BiometricVaultManager {
        BiometricVaultManager(authenticator: FakeAuthenticator(.cancel), appLockEnabled: { false }, observesAppLifecycle: false)
    }

    private func openVault() async -> BiometricVaultManager {
        let vault = BiometricVaultManager(authenticator: FakeAuthenticator(.succeed), appLockEnabled: { false }, observesAppLifecycle: false)
        await vault.unlock(reason: "Test")
        return vault
    }

    /// A person (open by default) with an identity card (Acte, locked by default) that expires on
    /// 5 December, and a deadline of the card's.
    private struct Holder {
        let context: ModelContext
        let person: Asset
        let card: Asset
        let templates: [CategoryTemplate]
    }

    private func holder() throws -> Holder {
        let container = try makeInMemoryContainer()
        let context = container.mainContext
        let store = TemplateStore(context: context)
        try store.installBuiltIns()
        let member = try #require(try store.template(forKey: BuiltInTemplates.Key.member))
        let documents = try #require(try store.template(forKey: BuiltInTemplates.Key.documents))
        let actions = AssetActions(context: context, calendar: calendar, now: { noon("2026-12-03") })
        let person = try actions.create(name: "Exemplu Ion", template: member, values: FieldValues())
        var values = FieldValues()
        values[DocumentType.typeFieldKey] = .text(DocumentType.idCard)
        values[DocumentFields.number] = .text("XX000000")
        values[DocumentFields.expiry] = .date(CalendarDay("2026-12-05"))
        let card = try actions.create(name: "Carte de identitate", template: documents, values: values, parent: person)
        try ObligationActions(context: context, calendar: calendar, now: { noon("2026-12-03") })
            .create(title: "Reînnoiește buletinul", kind: .legal, dueDay: CalendarDay("2026-12-05"), for: card)
        return Holder(context: context, person: person, card: card, templates: try context.fetch(FetchDescriptor<CategoryTemplate>()))
    }

    private func template(_ key: String, in templates: [CategoryTemplate]) -> CategoryTemplate? {
        templates.first { $0.key == key }
    }

    @Test func urmeazaReadsALockTurnedOnSinceItsListWasRead() async throws {
        let now = noon("2026-12-03")
        let home = try await household(locked: false, now: now)
        let context = home.container.mainContext
        let read = try #require(try ObligationSnapshot.fetchAll(in: context, calendar: calendar).first)
        #expect(!read.isSensitive)

        // Turning the lock on in Setări tells every list to read again.
        final class Told: @unchecked Sendable { var count = 0 }
        let told = Told()
        let observer = NotificationCenter.default.addObserver(forName: SectionLocks.didChange, object: nil, queue: nil) { _ in told.count += 1 }
        defer { NotificationCenter.default.removeObserver(observer) }
        let template = try #require(try TemplateStore(context: context).template(forKey: BuiltInTemplates.Key.vehicle))
        try template.setLock(true)
        #expect(told.count == 1, "Urmează reloads on it")
        #expect(try #require(try ObligationSnapshot.fetchAll(in: context, calendar: calendar).first).isSensitive, "Read again, its row says nothing")

        // „Gata” asks by the lock as it is now, never by the row read before it.
        #expect(home.itp.isSensitive(in: context))
        #expect(DeadlineChange.close.asksFaceID(inLockedCategory: home.itp.isSensitive(in: context)))
        let request = OutsideRequest(obligationId: home.itp.id, cycle: CalendarDay("2026-12-05"), action: .complete, surface: .shortcut)
        #expect(try IntentEngine.asksFaceID(request, in: context), "The same answer from outside the app")
        let chore = try ObligationActions(context: context, calendar: calendar).create(title: "Gunoi", kind: .routine, dueDay: CalendarDay("2026-12-05"), for: nil)
        #expect(!chore.isSensitive(in: context), "A deadline of the whole household has no lock")
    }

    @Test func aParentsPageShowsItsLockedChildrenOnlyAsLocked() async throws {
        let holder = try holder()
        let documents = template(BuiltInTemplates.Key.documents, in: holder.templates)
        let member = template(BuiltInTemplates.Key.member, in: holder.templates)

        // Session closed: the person's page opens; their identity card says only „Act protejat”.
        let closed = closedVault()
        #expect(SectionRowLock.of(holder.person, template: member, vault: closed) == .open)
        #expect(SectionRowLock.of(holder.card, template: documents, vault: closed) == .locked(title: LockedWording.document))
        guard case .locked = HolderHero.nextDocument(of: holder.person, templates: holder.templates, vault: closed) else {
            Issue.record("The hero names nothing of a locked document, not even when it expires")
            return
        }

        // A home's subscription, its category locked: „Secțiune protejată”.
        let store = TemplateStore(context: holder.context)
        let homeTemplate = try #require(try store.template(forKey: BuiltInTemplates.Key.home))
        let subscriptions = try #require(try store.template(forKey: BuiltInTemplates.Key.subscription))
        let actions = AssetActions(context: holder.context, calendar: calendar)
        let flat = try actions.create(name: "Apartament", template: homeTemplate, values: FieldValues())
        let power = try actions.create(name: "ENGIE Romania S.A.", template: subscriptions, values: FieldValues(), parent: flat)
        #expect(SectionRowLock.of(power, template: subscriptions, vault: closed) == .open)
        try subscriptions.setLock(true)
        #expect(SectionRowLock.of(power, template: subscriptions, vault: closed) == .locked(title: LockedWording.section))

        // A section whose category hasn't arrived reads as locked too.
        power.templateKey = "custom.0b6c6f43-0000-4000-8000-0000000000cc"
        #expect(SectionRowLock.of(power, template: nil, vault: closed).isLocked)

        // Session open: everything shows as itself.
        let open = await openVault()
        #expect(SectionRowLock.of(holder.card, template: documents, vault: open) == .open)
        guard case .shown(let next, let day) = HolderHero.nextDocument(of: holder.person, templates: holder.templates, vault: open) else {
            Issue.record("Open, the hero names the next document")
            return
        }
        #expect(next.id == holder.card.id)
        #expect(day == CalendarDay("2026-12-05"))
    }

    @Test func aBoxLineNamesNothingOfALockedSectionFiledInIt() async throws {
        let holder = try holder()
        let now = noon("2026-12-03")
        let snapshots = try ObligationSnapshot.fetchAll(in: holder.context, calendar: calendar)
        // The person's box (open), holding the card (locked) and its deadline.
        let status = BoxStatus.make(forAsset: holder.person.id, descendants: [holder.card.id], in: snapshots, now: now, calendar: calendar)
        #expect(status.entry != nil)
        let closed = closedVault()
        let shut = status.line(isSensitive: false, isLocked: { closed.isLocked(sectionIsSensitive: $0) }, now: now, calendar: calendar)
        #expect(!shut.contains("buletin"), "„O scadență”, never its title")
        #expect(!status.line(isSensitive: false, now: now, calendar: calendar).contains("buletin"), "Without a vault, every lock reads closed")
        #expect(!status.line(counting: 2, of: nil, isSensitive: false, isLocked: { closed.isLocked(sectionIsSensitive: $0) }, now: now, calendar: calendar).contains("buletin"))
        let open = await openVault()
        #expect(status.line(isSensitive: false, isLocked: { open.isLocked(sectionIsSensitive: $0) }, now: now, calendar: calendar).contains("buletin"))
    }

    @Test func agendaNamesNothingOfAJobInALockedSection() async throws {
        let now = noon("2026-12-03")
        let home = try await household(locked: true, now: now)
        let context = home.container.mainContext
        let provider = Provider(name: "Service Exemplu S.R.L.")
        context.insert(provider)
        let job = HistoryEntry(kind: .repair, title: "Schimb ulei", occurredAt: noon("2026-11-20"))
        job.totalCostAmount = 420
        job.totalCostCurrency = "RON"
        context.insert(job)
        job.asset = home.car
        job.providers = [provider]
        provider.historyEntries = [job]
        let template = try TemplateStore(context: context).template(forKey: BuiltInTemplates.Key.vehicle)

        let closed = closedVault()
        let shut = try #require(provider.lastJobLine { closed.isLocked($0, template: template) })
        #expect(shut.hasPrefix(LockedWording.job))
        #expect(!shut.contains("ulei") && !shut.contains("420"), "No title, no price")
        let open = await openVault()
        let shown = try #require(provider.lastJobLine { open.isLocked($0, template: template) })
        #expect(shown.contains("Schimb ulei") && shown.contains("420"))
    }

    @Test func aDeadlinesSheetsLiveBehindItsSectionsLock() async throws {
        let home = try await household(locked: true, now: noon("2026-12-03"))
        #expect(ObligationScreen.sheetLock(for: home.itp) == .section(home.car.id))
        let chore = try ObligationActions(context: home.container.mainContext, calendar: calendar)
            .create(title: "Gunoi", kind: .routine, dueDay: CalendarDay("2026-12-05"), for: nil)
        #expect(ObligationScreen.sheetLock(for: chore) == .open)
        #expect(EnvironmentValues().screenLock == .open, "A screen that declares nothing: its sheets are open")
    }

    @Test func aDocumentOpensBehindEverySectionItBelongsTo() async throws {
        let home = try await household(locked: true, now: noon("2026-12-03"))
        let context = home.container.mainContext
        let templates = Dictionary(try context.fetch(FetchDescriptor<CategoryTemplate>()).map { ($0.key, $0) }, uniquingKeysWith: { first, _ in first })
        func paper() -> Attachment {
            let attachment = Attachment(fileName: "document.pdf", contentType: "com.adobe.pdf", data: nil)
            context.insert(attachment)
            return attachment
        }

        // Filed on the deadline only: its section's lock.
        let policy = paper()
        policy.obligation = home.itp
        #expect(policy.lock(among: templates) == .section(home.car.id))

        // A record's paper in Istoric, with no section of its own.
        let entry = HistoryEntry(kind: .repair, title: "Reparație", occurredAt: noon("2026-11-20"))
        context.insert(entry)
        entry.asset = home.car
        let invoice = paper()
        invoice.historyEntry = entry
        #expect(invoice.lock(among: templates) == .section(home.car.id))

        // Two sections, one locked: the locked one decides.
        let homeTemplate = try #require(templates[BuiltInTemplates.Key.home])
        let flat = try AssetActions(context: context, calendar: calendar).create(name: "Apartament", template: homeTemplate, values: FieldValues())
        let both = paper()
        both.asset = flat
        both.obligation = home.itp
        #expect(both.sections.map(\.id) == [flat.id, home.car.id])
        #expect(both.lock(among: templates) == .section(home.car.id))

        // The whole household's paper is open; one that names nothing fails closed.
        let chore = try ObligationActions(context: context, calendar: calendar).create(title: "Gunoi", kind: .routine, dueDay: CalendarDay("2026-12-05"), for: nil)
        let householdPaper = paper()
        householdPaper.obligation = chore
        #expect(householdPaper.lock(among: templates) == .open)
        #expect(paper().lock(among: templates) == .unknownSection)
        #expect(BinderLocks.read(in: context).anySectionLocked, "With a lock on, it waits for Face ID")
    }

    @Test func theKeyboardGoesAsTheCoverGoesUp() throws {
        let scene = try #require(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first, "The tests run inside the app")
        let appWindow = UIWindow(windowScene: scene)
        @MainActor final class Ended { var count = 0 }
        let ended = Ended()
        // A fade that never ends, so the window stays while it is uncovered.
        let controller = LockWindowController(fade: { change, _ in change() }, endEditing: { _ in ended.count += 1 })
        controller.attach(to: appWindow)
        controller.show(.privacy)
        #expect(ended.count == 1)
        controller.show(.privacy)
        controller.show(.privacy)
        #expect(ended.count == 1, "Only as it goes up")
        controller.show(nil)
        controller.show(.privacy)
        #expect(ended.count == 2, "Covering again during the fade")
        withExtendedLifetime(appWindow) {}
    }
}
