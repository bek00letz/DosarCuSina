import Foundation
import SwiftData
import Testing
@testable import DosarCuSina

/// Closing a deadline keeps every deadline right: a one-off closed with a new day goes on from
/// it, a personal document renewed is closed and shown expired (its new one is a document of
/// its own), a new day before today is refused, and only the cycle the person saw is ever
/// closed, from any surface.
@MainActor
@Suite("Closing deadlines: new days, renewals and the cycle seen")
struct CompletionsAndRenewalsTests {
    let calendar = Calendar.bucharest
    let today = "2026-11-17"

    private func filer(_ context: ModelContext) -> CaptureFiler {
        let date = noon(today)
        var filer = CaptureFiler(context: context, store: CaptureDocumentStore(), calendar: calendar, now: { date })
        // Acte is locked by default: Face ID opens it before closing a document's renewal.
        filer.vault = BiometricVaultManager(authenticator: FakeAuthenticator(.succeed), appLockEnabled: { false }, observesAppLifecycle: false)
        return filer
    }

    private func actions(_ context: ModelContext) -> ObligationActions {
        ObligationActions(context: context, calendar: calendar, now: { noon(self.today) })
    }

    private func section(_ context: ModelContext, _ key: String, name: String, values: FieldValues,
                         parent: Asset? = nil, at day: String = "2026-10-01") throws -> Asset {
        let template = try #require(try TemplateStore(context: context).template(forKey: key))
        let assets = AssetActions(context: context, calendar: calendar, now: { noon(day) })
        return try assets.create(name: name, template: template, values: values,
                                 obligations: assets.plannedObligations(for: template, values: values), parent: parent)
    }

    private func file(_ draft: CompletionDraft, closing deadline: Obligation, in context: ModelContext,
                      cycle: CalendarDay? = nil) async throws -> CaptureFiler.Outcome {
        let completion = draft.completion(of: deadline, shape: deadline.completion(in: context), counter: nil,
                                          cycle: cycle, calendar: calendar, now: noon(today))
        return try await filer(context).file(.completion(completion))
    }

    // MARK: 1. A one-off closed with a new day

    @Test("The kit closed with its new expiry: in Istoric, still active, on the new day")
    func theKitGoesOnFromItsNewExpiry() async throws {
        let context = try makeContext()
        var values = FieldValues()
        values["vehicle.plate"] = .text("B-123-ABC")
        let golf = try section(context, BuiltInTemplates.Key.vehicle, name: "VW Golf 2018", values: values)
        let template = try #require(try TemplateStore(context: context).template(forKey: golf.templateKey))
        let blueprint = try #require(template.blueprints.first { $0.key == "vehicle.kit" })
        let kit = try actions(context).create(from: blueprint, for: golf, firstDue: CalendarDay("2026-11-20"))
        #expect(kit.completion(in: context).newEnd == .expires && !kit.recurrence.repeats)

        let draft = CompletionDraft(date: noon(today), amount: 120, newExpiry: noon("2030-11-01"))
        let outcome = try await file(draft, closing: kit, in: context, cycle: kit.dueDay)

        let entry = try #require(outcome.completion, "Recorded in Istoric")
        #expect(entry.cycleDueDay == CalendarDay("2026-11-20"))
        #expect(entry.nextDueDay == CalendarDay("2030-11-01"))
        #expect(entry.totalCost == Money(120))
        #expect(kit.status == .active, "It still reminds about the new kit")
        #expect(kit.dueDay == CalendarDay("2030-11-01"))
        #expect(outcome.nextDue == CalendarDay("2030-11-01"))

        try #require(outcome.receipt).undo()
        #expect(kit.dueDay == CalendarDay("2026-11-20") && kit.status == .active && kit.history.isEmpty, "Anulează takes it all back")
    }

    @Test("A one-off of one's own closed with a new day goes on from it", arguments: [ObligationKind.renewal, .insurance, .legal])
    func aOneOffOfOnesOwnGoesOn(_ kind: ObligationKind) async throws {
        let context = try makeContext()
        let deadline = try actions(context).create(title: "Termen", kind: kind, dueDay: CalendarDay("2026-11-20"), for: nil)
        let shape = deadline.completion(in: context)
        var draft = CompletionDraft(date: noon(today))
        if shape.asksNewExpiry {
            draft.newExpiry = noon("2027-11-20")
        } else {
            // The new day read off its paper (the new policy, the proof).
            draft.document = CaptureResult(kind: .other, kindConfidence: 0.9, fields: [
                CaptureField(key: .expiryDate, value: .day(CalendarDay("2027-11-20")), confidence: 0.9, tier: .heuristic),
            ], suggestions: [], reminder: nil, recognizedText: "", barcodes: [], document: nil, notices: [])
        }
        let outcome = try await file(draft, closing: deadline, in: context, cycle: deadline.dueDay)

        #expect(outcome.completion != nil, "\(kind): in Istoric")
        #expect(deadline.status == .active, "\(kind): still active")
        #expect(deadline.dueDay == CalendarDay("2027-11-20"), "\(kind): on the new day")
    }

    @Test("Closing with a new day is one action for any deadline, repeating or not")
    func completeContinuingOnANewDay() throws {
        let context = try makeContext()
        let oneOff = try actions(context).create(title: "Termen", kind: .legal, dueDay: CalendarDay("2026-11-20"), for: nil)
        let entry = try actions(context).complete(oneOff, continuingOn: CalendarDay("2028-01-10")).value
        #expect(oneOff.status == .active && oneOff.dueDay == CalendarDay("2028-01-10") && entry.nextDueDay == oneOff.dueDay)

        let yearly = try actions(context).create(title: "Anual", kind: .legal, dueDay: CalendarDay("2026-11-20"), for: nil,
                                                 recurrence: .interval(.years(1), anchor: .dueDate))
        _ = try actions(context).complete(yearly, continuingOn: CalendarDay("2028-03-01"))
        #expect(yearly.dueDay == CalendarDay("2028-03-01"), "The day given wins over the rule's")

        let closed = try actions(context).create(title: "O dată", kind: .legal, dueDay: CalendarDay("2026-11-20"), for: nil)
        _ = try actions(context).complete(closed)
        #expect(closed.status == .done, "Without a new day a one-off closes, as before")
    }

    @Test("A contract renewed keeps its new end, in Istoric too")
    func aContractIsExtended() async throws {
        let context = try makeContext()
        var values = FieldValues()
        values["subscription.contractEnd"] = .date(CalendarDay("2026-12-01"))
        let plan = try section(context, BuiltInTemplates.Key.subscription, name: "Telefon", values: values)
        let end = try #require(plan.activeObligations.first { $0.blueprintKey == "subscription.contractEnd" })
        let shape = end.completion(in: context)
        #expect(shape.newEnd == .ends && shape.paper?.use == .end && !shape.replacesSection, "Contractul nou and Se termină pe")

        let outcome = try await file(CompletionDraft(date: noon(today), newExpiry: noon("2028-12-01")), closing: end, in: context, cycle: end.dueDay)
        #expect(outcome.completion != nil, "Recorded in Istoric")
        #expect(end.status == .active && end.dueDay == CalendarDay("2028-12-01"))
        #expect(plan.value("subscription.contractEnd") == .date(CalendarDay("2028-12-01")), "The section's end agrees")
    }

    // MARK: 2. A personal document renewed is a new one

    private func passport(_ context: ModelContext, holder: Asset? = nil, expiry: String = "2026-12-01", at day: String = "2026-10-01") throws -> (Asset, Obligation) {
        var values = FieldValues()
        values[DocumentType.typeFieldKey] = .text(DocumentType.passport)
        values[DocumentFields.expiry] = .date(CalendarDay(expiry))
        let asset = try section(context, BuiltInTemplates.Key.documents, name: "Pașaport", values: values, parent: holder, at: day)
        return (asset, try #require(asset.activeObligations.first { $0.blueprintKey == BuiltInBlueprints.documentRenew }))
    }

    @Test("Every personal document's renewal states its own completion, declared in the catalog")
    func personalDocumentsStateTheirCompletion() throws {
        let renewal = try #require(BuiltInTemplates.documents.blueprints.first { $0.key == BuiltInBlueprints.documentRenew })
        #expect(renewal.completion == .documentReplaced)
        let shape = CompletionKind.documentReplaced.shape
        #expect(shape.newEnd == nil && shape.paper == nil, "No new expiry, no new paper: the new one is a new upload")
        #expect(shape.asksDate && !shape.isOneTap && shape.replacesSection, "„Am rezolvat”, with its offer")
        #expect(CompletionKind.documentReplaced.record == .renewal)
        // Contracts and renewals of one's own still go on from a new end.
        #expect(CompletionKind.newContract.shape.newEnd == .ends && CompletionKind.newLease.shape.newEnd == .ends)
        #expect(CompletionKind.own(.renewal).shape.newEnd == .expires)
        #expect(CompletionKind.allCases.filter { $0.shape.replacesSection } == [.documentReplaced])
    }

    @Test("„Am rezolvat” on a passport closes it, keeps it in Istoric and shows it expired")
    func aPassportIsClosedAndShownExpired() async throws {
        let context = try makeContext()
        let (document, renewal) = try passport(context)
        #expect(!document.wasReplaced)

        let outcome = try await file(CompletionDraft(date: noon(today), amount: 258), closing: renewal, in: context, cycle: renewal.dueDay)

        let entry = try #require(outcome.completion, "Recorded in Istoric")
        #expect(entry.totalCost == Money(258))
        #expect(renewal.status == .done, "Closed: nothing reminds about the old one")
        #expect(document.value(DocumentFields.expiry) == .date(CalendarDay("2026-12-01")), "Its date stays as printed")
        #expect(document.wasReplaced, "Its page shows it expired")
        #expect(DocumentPageFacts.replacement(of: document) == CompletionKind.documentReplaced.shape.replacement)
        #expect(outcome.nextDue == nil)

        try #require(outcome.receipt).undo()
        #expect(renewal.status == .active && !document.wasReplaced, "Anulează opens it again")
    }

    @Test("A new expiry typed on the old one later makes a new deadline, and it is no longer replaced")
    func anExpiryTypedLaterOpensANewDeadline() async throws {
        let context = try makeContext()
        let (document, renewal) = try passport(context)
        _ = try await file(CompletionDraft(date: noon(today)), closing: renewal, in: context, cycle: renewal.dueDay)
        #expect(document.wasReplaced)

        var values = document.values
        values[DocumentFields.expiry] = .date(CalendarDay("2036-11-01"))
        try AssetActions(context: context, calendar: calendar, now: { noon(self.today) })
            .update(document, name: document.name, values: values, notes: document.notes)
        #expect(document.activeObligations.contains { $0.blueprintKey == BuiltInBlueprints.documentRenew && $0.dueDay == CalendarDay("2036-11-01") })
        #expect(!document.wasReplaced)
    }

    @Test("„Adaugă actul nou” is offered until the holder has the new one")
    func theNewOneIsOfferedUntilItIsThere() async throws {
        let context = try makeContext()
        let holder = try section(context, BuiltInTemplates.Key.member, name: "Ion Popescu", values: FieldValues())
        let (old, renewal) = try passport(context, holder: holder)
        _ = try await file(CompletionDraft(date: noon(today)), closing: renewal, in: context, cycle: renewal.dueDay)
        #expect(!DocumentPageFacts.hasSuccessor(old))

        _ = try passport(context, holder: holder, expiry: "2036-11-01", at: today)
        #expect(DocumentPageFacts.hasSuccessor(old), "The new passport is in the binder")
    }

    // MARK: 3. A new day before today

    @Test("A new end before today, or today, is refused under its field; a later one is fine")
    func aPastNewDayIsRefused() throws {
        let context = try makeContext()
        let renewal = try actions(context).create(title: "Abonament", kind: .renewal, dueDay: CalendarDay("2026-11-20"), for: nil)
        let shape = renewal.completion(in: context)
        for day in ["2026-11-01", today] {
            let draft = CompletionDraft(date: noon(today), newExpiry: noon(day))
            #expect(draft.newDayProblem(shape: shape, calendar: calendar, now: noon(today)) == CompletionWording.newDayHasPassed, "\(day)")
        }
        #expect(CompletionDraft(date: noon(today), newExpiry: noon("2026-11-18")).newDayProblem(shape: shape, calendar: calendar, now: noon(today)) == nil)
        #expect(CompletionDraft(date: noon(today)).newDayProblem(shape: shape, calendar: calendar, now: noon(today)) == nil, "Nothing typed")
        let chore = CompletionKind.chore.shape
        #expect(CompletionDraft(date: noon(today), newExpiry: noon("2026-11-01")).newDayProblem(shape: chore, calendar: calendar, now: noon(today)) == nil,
                "A kind that asks no end has nothing to say")
    }

    @Test("A past new day never goes through silently: nothing is filed")
    func aPastNewDayFilesNothing() async throws {
        let context = try makeContext()
        let renewal = try actions(context).create(title: "Abonament", kind: .renewal, dueDay: CalendarDay("2026-11-20"), for: nil)
        await #expect(throws: ObligationActionError.newDayHasPassed) {
            _ = try await file(CompletionDraft(date: noon(today), newExpiry: noon("2026-11-01")), closing: renewal, in: context, cycle: renewal.dueDay)
        }
        #expect(renewal.history.isEmpty && renewal.status == .active && renewal.dueDay == CalendarDay("2026-11-20"))
        #expect(throws: ObligationActionError.newDayHasPassed) {
            try actions(context).complete(renewal, continuingOn: CalendarDay("2026-11-17"))
        }
        #expect(renewal.history.isEmpty)
    }

    // MARK: 4. Only the cycle the person saw

    @Test("A second activation on the same row closes nothing more", arguments: [true, false])
    func aSecondActivationClosesNothing(_ oneTap: Bool) throws {
        let context = try makeContext()
        let deadline = try actions(context).create(title: oneTap ? "Udat" : "Revizie", kind: oneTap ? .routine : .maintenance,
                                                   dueDay: CalendarDay(Date(), calendar: .dosar), for: nil,
                                                   recurrence: .interval(.days(7), anchor: .dueDate))
        let seen = deadline.dueDay
        let entry = CompletionEntry(context: context)
        if oneTap {
            _ = try entry.start(deadline, cycle: seen) { _, _ in }
            #expect(deadline.history.count == 1 && deadline.dueDay > seen)
        } else {
            // Closed meanwhile from a reminder: the sheet asked for never opens for the next one.
            _ = try actions(context).complete(deadline, cycle: seen)
        }
        #expect(throws: ObligationActionError.cycleClosed) { _ = try entry.start(deadline, cycle: seen) { _, _ in } }
        #expect(deadline.history.count == 1, "The next cycle is still open")
        #expect(UpcomingActions.quietFailureToast(ObligationActionError.cycleClosed) == nil, "Nothing to say over the first toast")
    }

    @Test("„Am rezolvat” left open while a reminder closed the cycle files nothing")
    func theSheetFilesNothingOnceTheCycleIsClosed() async throws {
        let context = try makeContext()
        let itp = try actions(context).create(title: "ITP", kind: .legal, dueDay: CalendarDay("2026-11-20"), for: nil,
                                              recurrence: .interval(.years(1), anchor: .dueDate))
        let seen = itp.dueDay
        // The reminder's "Am rezolvat", while the sheet is open.
        let request = OutsideRequest(obligationId: itp.id, cycle: seen, action: .complete, surface: .notification)
        _ = try IntentEngine.apply(request, in: context, calendar: calendar, now: { noon(self.today) })
        #expect(itp.dueDay == CalendarDay("2027-11-20"))

        await #expect(throws: ObligationActionError.cycleClosed) {
            _ = try await file(CompletionDraft(date: noon(today), amount: 180), closing: itp, in: context, cycle: seen)
        }
        #expect(itp.history.count == 1, "Only the reminder's")
        #expect(itp.dueDay == CalendarDay("2027-11-20"), "The next cycle stays open")
        #expect(!CompletionWording.closedMeanwhile.isEmpty)
    }

    @Test("A cycle closed on another device is closed here too, before the context knows")
    func aCycleClosedInTheStore() throws {
        let context = try makeContext()
        let rent = try actions(context).create(title: "Chirie", kind: .payment, dueDay: CalendarDay("2026-11-20"), for: nil,
                                               recurrence: .interval(.months(1), anchor: .dueDate))
        let seen = rent.dueDay
        // Another device's completion, arriving in the store under this context.
        let elsewhere = PersistenceController.context(in: context.container)
        let id = rent.id
        let copy = try #require(try elsewhere.fetch(FetchDescriptor<Obligation>(predicate: #Predicate { $0.id == id })).first)
        _ = try ObligationActions(context: elsewhere, calendar: calendar, now: { noon(self.today) }).complete(copy)

        #expect(try !actions(context).isOpen(rent, cycle: seen))
        #expect(throws: ObligationActionError.cycleClosed) { try actions(context).complete(rent, cycle: seen) }
    }

    @Test("Outside the app and in the app, one rule for the cycle")
    func outsideUsesTheSameRule() throws {
        let context = try makeContext()
        let rent = try actions(context).create(title: "Chirie", kind: .payment, dueDay: CalendarDay("2026-11-20"), for: nil,
                                               recurrence: .interval(.months(1), anchor: .dueDate))
        let old = rent.dueDay
        _ = try actions(context).complete(rent, cycle: old)
        let stale = OutsideRequest(obligationId: rent.id, cycle: old, action: .complete, surface: .widget)
        #expect(try IntentEngine.apply(stale, in: context, calendar: calendar, now: { noon(self.today) }) == .skipped)
        #expect(rent.history.count == 1)
    }
}
