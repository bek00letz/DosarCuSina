import Foundation

/// What "Editează" on a deadline's page edits, as one value: its name and how important it is
/// (only a deadline of the person's own, `Obligation.isPersonsOwn`), its due day, how it
/// repeats, its reminders and its reminder time. The sheet keeps the one it opened with and the
/// one the person leaves; `ObligationActions.edit(_:to:startedFrom:)` saves the difference as one
/// undoable step.
struct DeadlineEdit: Equatable {
    var title: String
    /// How important it is, offered only for a deadline of the person's own whose kind is one of
    /// the answers (`DeadlineChoice.Importance(kind:)`); nil when it isn't offered.
    var importance: DeadlineChoice.Importance?
    var dueDay: CalendarDay
    var recurrence: RecurrenceRule
    /// Its leads and follow-up, as the person sets them; the rest of the profile as stored.
    var reminders: ReminderProfile
    /// Its own reminder time, nil for the general one from Settings.
    var reminderMinuteOfDay: Int?
    /// Whether its name and importance are the person's to change.
    let isPersonsOwn: Bool

    init(title: String, importance: DeadlineChoice.Importance?, dueDay: CalendarDay, recurrence: RecurrenceRule,
         reminders: ReminderProfile, reminderMinuteOfDay: Int?, isPersonsOwn: Bool) {
        self.title = title
        self.importance = isPersonsOwn ? importance : nil
        self.dueDay = dueDay
        self.recurrence = recurrence
        self.reminders = reminders
        self.reminderMinuteOfDay = reminderMinuteOfDay
        self.isPersonsOwn = isPersonsOwn
    }

    /// The deadline as it is now.
    @MainActor
    init(_ obligation: Obligation) {
        self.init(title: obligation.title, importance: DeadlineChoice.Importance(kind: obligation.kind), dueDay: obligation.dueDay,
                  recurrence: obligation.recurrence, reminders: obligation.reminders,
                  reminderMinuteOfDay: obligation.reminderMinuteOfDay, isPersonsOwn: obligation.isPersonsOwn)
    }

    /// Whether the sheet offers "Cât de important e".
    var offersImportance: Bool { importance != nil }

    /// Whether "Se repetă" is offered: a rule of every so many days, weeks, months or years, or
    /// none (`RepeatChoice`). A rule on fixed dates, by a counter or by law is its category's.
    var offersRepeat: Bool { RepeatChoice(rule: recurrence) != nil }

    /// A new importance, with the reminders moved by the one rule (`DeadlineChoice.reminders`), so
    /// the sheet shows what saving will keep.
    mutating func choose(_ answer: DeadlineChoice.Importance) {
        guard let current = importance, current != answer else { return }
        reminders = DeadlineChoice.reminders(reminders, from: current.kind, to: answer.kind)
        importance = answer
    }

    /// It has a name.
    var canSave: Bool { !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    /// Whether, against `start` (the deadline as the sheet opened with it), this edit adds or
    /// changes what reminds: its leads, its follow-up, its reminder time (a new importance moves
    /// the leads too). Only then does saving explain the notification question first; a new name,
    /// due day or repeat keeps the reminders the person already has.
    func changesReminders(from start: DeadlineEdit) -> Bool {
        reminders != start.reminders || reminderMinuteOfDay != start.reminderMinuteOfDay
    }
}
