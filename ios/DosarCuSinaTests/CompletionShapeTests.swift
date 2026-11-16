import Foundation
import SwiftData
import Testing
@testable import DosarCuSina

/// What completing a deadline asks is its blueprint's (`CompletionKind`, its `CompletionShape`),
/// or for a deadline of one's own its kind's (`CompletionKind.own`): a chore is one tap with a
/// note after it, the others ask only what they need, every one files through the same actions,
/// and outside the app every kind still completes in one step.
@MainActor
@Suite("What completing asks, by kind")
struct CompletionShapeTests {
    let calendar = Calendar.bucharest
    let today = "2026-11-06"

    /// What the toast's "Adaugă o notă" handed the screen.
    @MainActor final class Offered {
        var entry: UUID?
        var toastID: UUID?
    }

    // MARK: Each kind's shape

    @Test func aChoreAsksNothing() {
        let chore = CompletionKind.own(.routine).shape
        #expect(chore == .oneTap)
        #expect(chore.isOneTap)
        #expect(chore.offersNoteAfter)
        #expect(!chore.asksDate && chore.cost == nil && chore.paper == nil)
    }

    @Test func aDeadlineOfOnesOwnAsksWhatItsKindNeeds() {
        let service = CompletionKind.own(.maintenance).shape
        #expect(service.cost == .cost && service.paper?.use == .history && service.counter == .section)
        let bill = CompletionKind.own(.payment).shape
        #expect(bill.cost == .paid && bill.paper?.use == .logged)
        let renewal = CompletionKind.own(.renewal).shape
        #expect(renewal.paper?.use == .expiry && renewal.newEnd == .expires && renewal.cost == nil)
        #expect(CompletionKind.own(.legal).shape.paper?.use == .nextDate)
        #expect(CompletionKind.own(.insurance) == .policy)
        let tax = CompletionKind.own(.tax).shape
        #expect(tax.cost == .paid && tax.paper?.use == .keep)
        let health = CompletionKind.own(.health).shape
        #expect(health.cost == .cost && health.paper != nil && health.asksNote)
        for kind in ObligationKind.allCases where kind != .routine {
            let shape = CompletionKind.own(kind).shape
            #expect(!shape.isOneTap, "\(kind) opens the sheet")
            #expect(shape.asksDate, "\(kind) asks when")
            #expect(!shape.offersNoteAfter)
        }
    }

    @Test("Every built-in deadline states what completing it asks, and a stored one reads it back")
    func everyBuiltInStatesItsCompletion() throws {
        let context = try makeContext()
        let store = TemplateStore(context: context)
        for builtIn in BuiltInTemplates.all {
            for blueprint in builtIn.blueprints {
                #expect(blueprint.completion != nil, "\(builtIn.key) \(blueprint.key)")
            }
            let installed = try #require(try store.template(forKey: builtIn.key))
            #expect(installed.definition.blueprints.map(\.completion) == builtIn.blueprints.map(\.completion), "\(builtIn.key): kept as stated")
        }
        for blueprint in HouseholdRules.blueprints { #expect(blueprint.completion != nil, "\(blueprint.key)") }
    }

    @Test("A deadline completes as its blueprint states, not as its kind")
    func aBlueprintsStatementWins() throws {
        let context = try makeContext()
        let golf = try car(context)
        let template = try #require(try TemplateStore(context: context).template(forKey: golf.templateKey)).definition
        let itp = try ObligationActions(context: context, calendar: calendar, now: { noon(self.today) })
            .create(title: "ITP", kind: .legal, dueDay: CalendarDay("2026-11-10"), for: golf)
        itp.blueprintKey = BuiltInBlueprints.vehicleITP
        #expect(itp.completionKind(template: template) == .itp, "The ITP report, not a legal deadline's proof")
        #expect(itp.completion(template: template).paper?.gender == .masculine)
        itp.blueprintKey = nil
        #expect(itp.completionKind(template: template) == .ownLegal, "With no blueprint, as one of one's own")
        itp.blueprintKey = "vehicle.gone"
        #expect(itp.completionKind(template: template) == .ownLegal, "A blueprint the category no longer has")
    }

    @Test("A value the kind doesn't ask is never filed, whatever the draft holds", arguments: ObligationKind.allCases)
    func theDraftKeepsOnlyWhatTheKindAsks(_ kind: ObligationKind) throws {
        let context = try makeContext()
        let deadline = try ObligationActions(context: context, calendar: calendar, now: { noon(self.today) })
            .create(title: "Termen", kind: kind, dueDay: CalendarDay("2026-11-10"), for: nil)
        let counter = ObligationActions.Counter(title: "Kilometraj", unit: .kilometres)
        var draft = CompletionDraft(date: noon("2026-11-05"), amount: 120, note: "  O notă  ", reading: 101_000,
                                    newExpiry: noon("2036-11-05"))
        draft.document = nil
        let shape = deadline.completion(in: context)
        let completion = draft.completion(of: deadline, shape: shape, counter: counter, calendar: calendar, now: noon(today))

        #expect((completion.cost != nil) == (shape.cost != nil))
        #expect((completion.note != nil) == shape.asksNote)
        #expect((completion.metricReading != nil) == shape.asksReading)
        #expect((completion.nextDue != nil) == shape.asksNewExpiry)
        #expect(completion.date == (shape.asksDate ? noon("2026-11-05") : noon(today)))
        if shape.asksNote { #expect(completion.note == "O notă") }
        if shape.asksNewExpiry { #expect(completion.nextDue == CalendarDay("2036-11-05")) }
    }

    // MARK: A chore: one tap, undo, a note

    @Test func aChoreIsDoneInOneTapAndTakenBack() throws {
        let context = try makeContext()
        let watering = try ObligationActions(context: context, calendar: calendar)
            .create(title: "Udat", kind: .routine, dueDay: CalendarDay(Date()), for: nil, recurrence: .interval(.days(7), anchor: .completion))
        let due = watering.dueDay
        let offered = Offered()

        let toast = try UpcomingActions(context: context, calendar: calendar).complete(watering, title: watering.title) { entry, shown in
            offered.entry = entry
            offered.toastID = shown.id
        }

        let entry = try #require(watering.history.first)
        #expect(watering.history.count == 1, "Done, in one step")
        #expect(entry.totalCost == nil && entry.note == nil, "Nothing asked, nothing kept")
        #expect(watering.dueDay > due, "On to the next cycle")
        #expect(toast.receipt?.canUndo == true, "Anulează")
        let offer = try #require(toast.offer, "Adaugă o notă")
        #expect(toast.duration == DSToast.offerDuration)
        offer.action(toast)
        #expect(offered.entry == entry.id, "The note is for this completion")
        #expect(offered.toastID == toast.id, "Its toast, to show again if no note is saved")

        try #require(toast.receipt).undo()
        #expect(watering.history.isEmpty)
        #expect(watering.dueDay == due)
    }

    @Test func aChoresNoteGoesOnItsCompletionAndIsTakenBackAlone() throws {
        let context = try makeContext()
        let watering = try ObligationActions(context: context, calendar: calendar)
            .create(title: "Udat", kind: .routine, dueDay: CalendarDay(Date()), for: nil, recurrence: .interval(.days(7), anchor: .completion))
        _ = try UpcomingActions(context: context, calendar: calendar).complete(watering, title: watering.title) { _, _ in }
        let entry = try #require(watering.history.first)

        let note = try HistoryActions(context: context).setNote(entry, "  Și ficusul din sufragerie. ")
        #expect(entry.note == "Și ficusul din sufragerie.")
        #expect(watering.history.contains { $0.id == entry.id }, "The same completion")

        try note.undo()
        #expect(entry.note == nil, "Only the note goes")
        #expect(watering.history.contains { $0.id == entry.id }, "The completion stays")

        try HistoryActions(context: context).setNote(entry, "Cu îngrășământ")
        try HistoryActions(context: context).setNote(entry, "   ")
        #expect(entry.note == nil, "Blank clears it")
    }

    @Test("Only a chore's toast offers a note", arguments: ObligationKind.allCases)
    func onlyAChoreOffersANote(_ kind: ObligationKind) throws {
        let context = try makeContext()
        let deadline = try ObligationActions(context: context, calendar: calendar)
            .create(title: "Termen", kind: kind, dueDay: CalendarDay(Date()), for: nil)
        let toast = try UpcomingActions(context: context, calendar: calendar).complete(deadline, title: deadline.title) { _, _ in }
        #expect((toast.offer != nil) == (kind == .routine))
        #expect(toast.receipt?.canUndo == true, "Every kind's quick completion can be taken back")
    }

    // MARK: The sheet, kind by kind

    private func car(_ context: ModelContext) throws -> Asset {
        let template = try #require(try TemplateStore(context: context).template(forKey: BuiltInTemplates.Key.vehicle))
        var values = FieldValues()
        values["vehicle.plate"] = .text("B-123-ABC")
        values["vehicle.year"] = .number(2018)
        values["vehicle.odometer"] = .number(100_000)
        return try AssetActions(context: context, calendar: calendar, now: { noon("2026-10-01") }).create(name: "VW Golf 2018", template: template, values: values)
    }

    private func filer(_ context: ModelContext, store: CaptureDocumentStore = CaptureDocumentStore(),
                       lowerReading: LowerReadingAnswer? = nil) -> CaptureFiler {
        let date = noon(today)
        var filer = CaptureFiler(context: context, store: store, calendar: calendar, now: { date })
        filer.lowerReading = lowerReading
        // Acte is locked by default: Face ID opens it before a renewal writes into it.
        filer.vault = BiometricVaultManager(authenticator: FakeAuthenticator(.succeed), appLockEnabled: { false }, observesAppLifecycle: false)
        return filer
    }

    @Test func maintenanceRecordsTheCounterTheSectionHas() async throws {
        let context = try makeContext()
        let golf = try car(context)
        let oil = try ObligationActions(context: context, calendar: calendar, now: { noon(self.today) })
            .create(title: "Schimb ulei", kind: .maintenance, dueDay: CalendarDay("2026-11-10"), for: golf,
                    recurrence: .interval(.years(1), anchor: .completion))
        let template = try #require(try TemplateStore(context: context).template(forKey: golf.templateKey))
        let counter = try #require(ObligationActions.counter(completing: oil, template: template.definition),
                                   "A time-based service on a car still asks its kilometres")
        #expect(counter.unit == .kilometres)

        let draft = CompletionDraft(date: noon(today), amount: 450, reading: 101_500)
        let outcome = try await filer(context).file(.completion(draft.completion(of: oil, shape: oil.completion(in: context), counter: counter,
                                                                                 calendar: calendar, now: noon(today))))
        let entry = try #require(outcome.completion)
        #expect(entry.metricReading == 101_500)
        #expect(entry.totalCost == Money(450))
        #expect(golf.value("vehicle.odometer") == .number(101_500), "The reading moves the car's kilometres")

        try #require(outcome.receipt).undo()
        #expect(golf.value("vehicle.odometer") == .number(100_000), "Anulează takes the reading back")
    }

    @Test func aLowerCounterAsksBeforeAnythingIsWritten() async throws {
        let context = try makeContext()
        let golf = try car(context)
        let oil = try ObligationActions(context: context, calendar: calendar, now: { noon(self.today) })
            .create(title: "Schimb ulei", kind: .maintenance, dueDay: CalendarDay("2026-11-10"), for: golf,
                    recurrence: .interval(.years(1), anchor: .completion))
        _ = try ObligationActions(context: context, calendar: calendar, now: { noon("2026-10-15") })
            .complete(oil, on: noon("2026-10-15"), metricReading: 100_000)
        let counter = ObligationActions.counter(completing: oil, template: BuiltInTemplates.definition(for: golf.templateKey))
        let draft = CompletionDraft(date: noon(today), reading: 90_000)
        let completion = draft.completion(of: oil, shape: oil.completion(in: context), counter: counter, calendar: calendar, now: noon(today))

        await #expect(throws: LowerReadingQuestion.self) { _ = try await filer(context).file(.completion(completion)) }
        #expect(oil.history.count == 1, "Nothing written while it asks")
    }

    @Test func healthKeepsTheNote() async throws {
        let context = try makeContext()
        let vaccine = try ObligationActions(context: context, calendar: calendar, now: { noon(self.today) })
            .create(title: "Vaccin anual", kind: .health, dueDay: CalendarDay("2026-11-10"), for: nil,
                    recurrence: .interval(.years(1), anchor: .completion))
        let draft = CompletionDraft(date: noon(today), note: "Totul e în regulă. Rapel peste un an.")
        let outcome = try await filer(context).file(.completion(draft.completion(of: vaccine, shape: vaccine.completion(in: context), counter: nil,
                                                                                 calendar: calendar, now: noon(today))))
        #expect(outcome.completion?.note == "Totul e în regulă. Rapel peste un an.")
    }

    // MARK: A renewal: the new document and its expiry

    private func passport(_ context: ModelContext, expiry: String) throws -> (Asset, Obligation) {
        let template = try #require(try TemplateStore(context: context).template(forKey: BuiltInTemplates.Key.documents))
        let actions = AssetActions(context: context, calendar: calendar, now: { noon("2026-10-01") })
        var values = FieldValues()
        values["document.type"] = .text("Pașaport")
        values["document.expiry"] = .date(CalendarDay(expiry))
        let asset = try actions.create(name: "Pașaport", template: template, values: values,
                                       obligations: actions.plannedObligations(for: template, values: values))
        return (asset, try #require(asset.activeObligations.first))
    }

    @Test func aRenewalTakesTheNewExpiryTyped() async throws {
        let context = try makeContext()
        let (asset, renewal) = try passport(context, expiry: "2026-12-01")
        #expect(renewal.completion(in: context).asksNewExpiry)
        let draft = CompletionDraft(date: noon(today), newExpiry: noon("2036-11-20"))
        _ = try await filer(context).file(.completion(draft.completion(of: renewal, shape: renewal.completion(in: context), counter: nil,
                                                                       calendar: calendar, now: noon(today))))
        #expect(asset.value("document.expiry") == .date(CalendarDay("2036-11-20")))
        #expect(renewal.dueDay == CalendarDay("2036-11-20"), "The deadline follows the new expiry")
    }

    @Test func aRenewalStillFilesTheNewDocument() async throws {
        let context = try makeContext()
        let (asset, renewal) = try passport(context, expiry: "2026-12-01")
        let store = CaptureDocumentStore()
        let stored = try await store.store(.init(pages: [CaptureDocumentStoreTests.page(width: 800, height: 1100, seed: 91)], kind: .passport))
        let newPassport = CaptureResult(kind: .passport, kindConfidence: 0.95, fields: [
            CaptureField(key: .expiryDate, value: .day(CalendarDay("2036-11-20")), confidence: 0.9, tier: .heuristic),
        ], suggestions: [], reminder: nil, recognizedText: "PAȘAPORT", barcodes: [], document: stored.ref, notices: [])
        var draft = CompletionDraft(date: noon(today))
        draft.document = newPassport

        let outcome = try await filer(context, store: store).file(.completion(draft.completion(
            of: renewal, shape: renewal.completion(in: context), counter: nil, calendar: calendar, now: noon(today))))
        let filed = try #require(outcome.attachment, "The new document is kept")
        #expect(filed.asset?.id == asset.id)
        #expect(asset.value("document.expiry") == .date(CalendarDay("2036-11-20")), "Its expiry, read off the photo")
        #expect(renewal.dueDay == CalendarDay("2036-11-20"))
        #expect(outcome.receipt?.canUndo == true)
    }

    // MARK: Outside the app

    @Test("Outside the app every kind still completes in one step", arguments: ObligationKind.allCases)
    func outsideTheAppIsOneStep(_ kind: ObligationKind) throws {
        let context = try makeContext()
        let deadline = try ObligationActions(context: context, calendar: calendar, now: { noon(self.today) })
            .create(title: "Termen", kind: kind, dueDay: CalendarDay("2026-11-06"), for: nil, recurrence: .interval(.months(1), anchor: .dueDate))
        let request = OutsideRequest(obligationId: deadline.id, cycle: deadline.dueDay, action: .complete, surface: .widget)

        let outcome = try IntentEngine.apply(request, in: context, calendar: calendar, now: { noon(self.today) })

        #expect(outcome == .completed(next: CalendarDay("2026-12-06")))
        let entry = try #require(deadline.history.first)
        #expect(entry.totalCost == nil && entry.note == nil && entry.metricReading == nil, "Nothing asked outside the app")
    }
}
