import Foundation
import SwiftData
import Testing
@testable import DosarCuSina

/// Since when a deadline's cycle is known as it now is (`Obligation.cycleKnownAt`, kept by
/// `CycleTimes`): the moment the one catch-up reminder counts from. It moves when the due day,
/// the reminders' leads, the travel margin or whether the deadline is active change, whoever
/// changes them, and never for anything else. Its change time is another thing: the app's own
/// steps leave that alone. All names are placeholders.
@MainActor
@Suite("Since when a deadline's cycle is known")
struct CycleKnownSinceTests {
    let calendar = Calendar.bucharest
    let made = noon("2026-12-01")
    let later = noon("2026-12-10")
    let expiry = CalendarDay("2027-08-12")

    /// A passport's renewal made at `made` by the person, as an earlier version saved it: no
    /// travel cut-off, reminders 90 days before it expires and on the day.
    private func passport(in context: ModelContext) throws -> Obligation {
        let renewal = Obligation(title: "Pașaport", kind: .renewal, dueDay: expiry,
                                 reminders: ReminderProfile(leadDays: [90, 0], consequence: .legal))
        context.insert(renewal)
        try UnitOfWork.save(context, now: made)
        return renewal
    }

    private func catchUps(in context: ModelContext, at now: Date) throws -> [PlannedReminder] {
        let snapshots = try ObligationSnapshot.fetchAll(in: context, calendar: calendar)
        return ReminderPlanner.plan(snapshots, now: now, calendar: calendar)
            .filter { $0.identifier.hasSuffix(".\(ReminderPlanner.catchUpSuffix)") }
    }

    @Test("A deadline is known from the moment it is made")
    func knownFromWhenItIsMade() throws {
        let context = try makeContext()
        let renewal = try passport(in: context)
        #expect(renewal.cycleKnownAt == made)
        #expect(renewal.cycleKnownSince == made)
        #expect(try ObligationSnapshot.fetchAll(in: context, calendar: calendar).first?.cycleKnownSince == made)
    }

    @Test("The app's own step that changes when it reminds gives it a fresh anchor, and its catch-up comes")
    func anAppStepThatMovesTheLeadsIsAFreshAnchor() throws {
        let context = try makeContext()
        let renewal = try passport(in: context)
        #expect(try catchUps(in: context, at: later).isEmpty, "Its warnings are months away")

        // What the travel cut-off's repair does, as the app's own step: the leads now count back
        // from six months before the expiry, so the 90-day warning fell before it was made.
        try UnitOfWork.perform(in: context, origin: .app, now: later) {
            renewal.reminders = ReminderProfile(leadDays: [90, 0], consequence: .legal, travelMarginDays: 180)
        }
        #expect(renewal.updatedAt == made, "The app's step gives no change time")
        #expect(renewal.cycleKnownAt == later, "It is known with these reminders from now")

        let catchUp = try #require(try catchUps(in: context, at: later).first, "One reminder makes up for the warning that passed")
        #expect(catchUp.fireDate > later)
        let cutoff = try #require(renewal.reminders.urgencyRule.travelCutoff(before: expiry, calendar: calendar))
        #expect(CalendarDay(catchUp.fireDate, calendar: calendar) < cutoff)

        // Counted from its change time, as before, it would never come: its day had passed.
        var asBefore = try #require(try ObligationSnapshot.fetchAll(in: context, calendar: calendar).first)
        asBefore.cycleKnownSince = renewal.updatedAt
        #expect(!ReminderPlanner.plan([asBefore], now: later, calendar: calendar).contains { $0.identifier.hasSuffix(".catchup") })
    }

    @Test("The passport repair the owner approves gives a fresh anchor and no change time")
    func theTravelCutoffRepairIsAFreshAnchor() throws {
        let context = try makeContext()
        let fixed = noon("2026-11-03")
        let documents = try #require(try TemplateStore(context: context).template(forKey: BuiltInTemplates.Key.documents))
        let assets = AssetActions(context: context, calendar: calendar, now: { fixed })
        var values = FieldValues()
        values[DocumentType.typeFieldKey] = .text(DocumentType.passport)
        values[DocumentFields.expiry] = .date(expiry)
        let passport = try assets.create(name: "Pașaport", template: documents, values: values,
                                         obligations: assets.plannedObligations(for: documents, values: values))
        let renewal = try #require(passport.activeObligations.first)
        // As an earlier version saved it, long ago: no cut-off.
        let long = noon("2025-06-01")
        renewal.reminders = ReminderProfile(leadDays: [180, 60], consequence: .legal)
        renewal.updatedAt = long
        renewal.cycleKnownAt = long
        try context.save()

        let repairs = DataRepairs(context: context, calendar: calendar,
                                  ledger: DataRepairLedger(defaults: try #require(UserDefaults(suiteName: "cycle-\(UUID().uuidString)"))))
        let before = Date()
        try repairs.apply(try repairs.detect().filter { $0.step == .travelCutoff })
        #expect(renewal.travelMarginDays == 180)
        #expect(renewal.updatedAt == long, "A repair isn't the person's change")
        let known = try #require(renewal.cycleKnownAt)
        #expect(known >= before, "Its reminders are new from the moment the repair applied")
    }

    @Test("The person's new due day gives a fresh anchor, and undo puts the old one back")
    func aRescheduleIsAFreshAnchor() throws {
        let context = try makeContext()
        let renewal = try passport(in: context)
        let receipt = try ObligationActions(context: context, calendar: calendar, now: { later })
            .reschedule(renewal, to: CalendarDay("2027-09-01"))
        #expect(renewal.cycleKnownAt == later)
        #expect(renewal.updatedAt == later)
        try receipt.undo()
        #expect(renewal.cycleKnownAt == made)
        #expect(renewal.dueDay == expiry)
    }

    @Test("A newer cycle time doesn't stop an undo, and stays: it is kept like the change time")
    func aNewerCycleTimeStaysThroughUndo() throws {
        let context = try makeContext()
        let renewal = try passport(in: context)
        let receipt = try ObligationActions(context: context, calendar: calendar, now: { later })
            .reschedule(renewal, to: CalendarDay("2027-09-01"))
        let repaired = noon("2026-12-15")
        try UnitOfWork.perform(in: context, origin: .app, now: repaired) {
            renewal.reminders = ReminderProfile(leadDays: [90, 0], consequence: .legal, travelMarginDays: 180)
        }
        #expect(renewal.cycleKnownAt == repaired)
        try receipt.undo()
        #expect(renewal.dueDay == expiry, "The person's step is taken back")
        #expect(renewal.travelMarginDays == 180, "The repair since stays")
        #expect(renewal.cycleKnownAt == repaired, "Known with these reminders since the repair")
    }

    @Test("Reminders the person sets, and a deadline started again, give a fresh anchor")
    func theirRemindersAndResumingAreAFreshAnchor() throws {
        let context = try makeContext()
        let renewal = try passport(in: context)
        try ObligationActions(context: context, calendar: calendar, now: { later })
            .setReminders(renewal, ReminderProfile(leadDays: [30, 0], consequence: .legal))
        #expect(renewal.cycleKnownAt == later)

        let paused = noon("2026-12-20")
        let resumed = noon("2027-01-15")
        try ObligationActions(context: context, calendar: calendar, now: { paused }).pause(renewal)
        #expect(renewal.cycleKnownAt == paused, "Stopped: nothing reminds")
        try ObligationActions(context: context, calendar: calendar, now: { resumed }).resume(renewal)
        #expect(renewal.cycleKnownAt == resumed, "Started again: what passed while it was stopped is made up for")
    }

    @Test("A snooze keeps the anchor: the person knew, and the snooze reminds on its own day")
    func aSnoozeKeepsTheAnchor() throws {
        let context = try makeContext()
        let renewal = try passport(in: context)
        try ObligationActions(context: context, calendar: calendar, now: { later }).snooze(renewal, days: 1)
        #expect(renewal.updatedAt == later, "It is the person's change")
        #expect(renewal.cycleKnownAt == made)
    }

    @Test("A note, a cost or the reminder time keeps the anchor, so a catch-up that came doesn't come again")
    func anUnrelatedEditKeepsTheAnchor() throws {
        let context = try makeContext()
        // Made ten days before it expires: its warnings had passed, so one catch-up comes.
        let late = Obligation(title: "Carte de identitate", kind: .renewal, dueDay: CalendarDay("2026-12-11"),
                              reminders: ReminderProfile(leadDays: [90, 30], consequence: .legal))
        context.insert(late)
        try UnitOfWork.save(context, now: made)
        let first = try #require(try catchUps(in: context, at: made).first)

        let afterIt = first.fireDate.addingTimeInterval(3600)
        late.notes = "Programare la ghișeu."
        late.estimatedCost = Money(40, currency: "RON")
        late.reminderMinuteOfDay = 20 * 60
        try UnitOfWork.save(context, now: afterIt)
        #expect(late.updatedAt == afterIt)
        #expect(late.cycleKnownAt == made)
        #expect(try catchUps(in: context, at: afterIt).isEmpty, "The catch-up that came doesn't come again")
    }

    @Test("A deadline from before version 11, or brought in from a backup, reads as known since its change time")
    func withoutOneItReadsItsChangeTime() throws {
        let context = try makeContext()
        let renewal = try passport(in: context)
        renewal.cycleKnownAt = nil
        renewal.updatedAt = later
        try context.save()
        #expect(renewal.cycleKnownSince == later)
        #expect(try ObligationSnapshot.fetchAll(in: context, calendar: calendar).first?.cycleKnownSince == later)
    }
}
