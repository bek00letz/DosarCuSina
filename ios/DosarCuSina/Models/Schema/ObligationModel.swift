import Foundation
import SwiftData

extension DosarSchemaV13 {
    /// Something that has to be done by a date, once or on a schedule: ITP, RCA,
    /// local taxes, a vaccine, a subscription renewal.
    ///
    /// An obligation is never copied to make the next cycle. Completing it writes
    /// a `HistoryEntry` and moves its due day forward (see `ObligationActions`).
    @Model
    public final class Obligation {
        public var id: UUID = UUID()
        /// Which copy of this record it is (`Asset.copyID`). Version 13.
        public var copyID: UUID?
        public var title: String = ""
        public var notes: String?
        /// The template blueprint this came from, when it came from one.
        public var blueprintKey: String?
        public var kindRaw: String = ObligationKind.routine.rawValue
        /// The due day as an ISO day, `2026-11-15` (`StoredDay`): the same day in every time
        /// zone, and it sorts as the days do. Read and write it through `dueDay`. Version 9;
        /// before, noon of the day in the phone's time zone (`dueDate`).
        public var dueDayISO: String = ""
        /// For counter-based obligations, the reading at which it is due (for example 160 000 km).
        public var dueMetric: Double?
        /// Reminder profile, stored flat: lead days (largest first; `0` is the day they count
        /// from), consequence, grace days and the travel margin. Read and write it through `reminders`.
        public var reminderLeadDays: [Int] = [30, 7, 0]
        public var consequenceRaw: String = Consequence.comfort.rawValue
        public var graceDays: Int = 0
        /// Remind once the day after the due date if it is still open. The reminder
        /// setup screen shows it as a checkbox; defaults come from the blueprint profile.
        public var followUpAfterLapse: Bool = false
        /// How long before the due day its document stops being good for travel (a
        /// passport: 180, six months); 0 for everything else. From the document type,
        /// through the blueprint's profile (`ReminderProfile.travelMarginDays`). Version 4.
        public var travelMarginDays: Int = 0
        /// The person set this deadline's reminders themselves (leads, grace or the follow-up),
        /// so they stay as set when the section changes. False: the reminders follow what the
        /// blueprint gives for the section's values (`DeadlineReminders`). Version 5.
        public var remindersCustomized: Bool = false
        /// Minutes after midnight for this obligation's reminders; nil uses the app setting.
        public var reminderMinuteOfDay: Int?
        /// JSON `RecurrenceRule`.
        public var recurrenceData: Data?
        public var estimatedCostAmount: Decimal?
        public var estimatedCostCurrency: String?
        public var provider: String?
        /// Policy, contract or invoice number.
        public var reference: String?
        public var statusRaw: String = ObligationStatus.active.rawValue
        /// Hidden from attention and reminders until this day starts where the phone is, as an
        /// ISO day (`StoredDay`). Read and write it through `snoozedUntil`. Version 9; before, the
        /// start of that day in the phone's time zone.
        public var snoozedUntilISO: String?
        public var isExample: Bool = false
        public var createdAt: Date = Date()
        public var updatedAt: Date = Date()
        /// Since when its cycle is known as it now is: the last time its due day, its reminders'
        /// leads (or its travel margin) or whether it is active changed, by the person or by
        /// the app, set by the unit of work as it saves (`CycleTimes`). Not its change time,
        /// which only the person's own steps move and which a note's edit moves too. Nil for a
        /// deadline from before version 11 or brought in from a backup: it reads as its change
        /// time (`cycleKnownSince`). Version 11.
        public var cycleKnownAt: Date?
        /// The reminder profile's JSON as a newer build wrote it, kept only while it holds
        /// something this build doesn't read (a key it doesn't know, a value it reads as another);
        /// the columns above stay what this build reads, and this follows them. Read and write it
        /// through `reminders` and `keptReminders`. Version 12.
        public var remindersData: Data?

        public var asset: Asset?

        /// Times it was done. They belong to the asset's history: deleting the
        /// obligation keeps them and only unlinks them.
        @Relationship(deleteRule: .nullify, inverse: \HistoryEntry.obligation)
        public var historyEntries: [HistoryEntry]? = []

        /// Documents filed with this obligation (a policy PDF). They belong to the asset;
        /// deleting the obligation only unlinks them.
        @Relationship(deleteRule: .nullify, inverse: \Attachment.obligation)
        public var attachments: [Attachment]? = []

        public init(
            id: UUID = UUID(),
            title: String,
            kind: ObligationKind,
            dueDay: CalendarDay,
            recurrence: RecurrenceRule = .none,
            reminders: ReminderProfile? = nil,
            estimatedCost: Money? = nil
        ) {
            self.copyID = UUID()
            self.id = id
            self.title = title
            self.kindRaw = kind.rawValue
            self.dueDayISO = StoredDay.text(dueDay)
            self.recurrenceData = StoredJSON.encode(recurrence)
            let profile = reminders ?? kind.defaultProfile
            self.reminderLeadDays = profile.leadDays
            self.consequenceRaw = profile.consequence.rawValue
            self.graceDays = profile.graceDays
            self.followUpAfterLapse = profile.followUpAfterLapse
            self.travelMarginDays = profile.travelMarginDays
            self.estimatedCostAmount = estimatedCost?.amount
            self.estimatedCostCurrency = estimatedCost?.currency
        }

        /// An unknown stored kind (from a newer build or archive) reads as the loudest and
        /// stays stored as it was until the person picks another.
        public var kind: ObligationKind {
            get { ObligationKind(stored: kindRaw) }
            set {
                guard ObligationKind(rawValue: kindRaw) != nil || newValue != ObligationKind(stored: kindRaw) else { return }
                kindRaw = newValue.rawValue
            }
        }

        /// How this obligation reminds. Set from its blueprint, changeable by the person.
        public var reminders: ReminderProfile {
            get {
                ReminderProfile(
                    leadDays: reminderLeadDays,
                    consequence: Consequence(stored: consequenceRaw),
                    graceDays: graceDays,
                    followUpAfterLapse: followUpAfterLapse,
                    travelMarginDays: travelMarginDays
                )
            }
            set {
                let kept = remindersData == nil ? nil : keptReminders
                writeReminderColumns(newValue)
                if let kept { keepReminders(kept) }
            }
        }

        /// The profile as stored, with what a newer build wrote in it that this build doesn't read:
        /// what a backup carries. Writing it keeps that part while the profile is edited here
        /// (`KeptObject`), and lets it go once nothing of it is left.
        public var keptReminders: KeptObject<ReminderProfile> {
            get {
                guard let stored = KeptObject.stored(in: remindersData, fallback: reminders) else { return KeptObject(reminders) }
                return stored.replacingValue(reminders)
            }
            set {
                writeReminderColumns(newValue.value)
                keepReminders(newValue)
            }
        }

        private func writeReminderColumns(_ newValue: ReminderProfile) {
            reminderLeadDays = newValue.leadDays
            // An unknown consequence read as the loudest is kept as stored, never
            // written back as what this build understood.
            if Consequence(rawValue: consequenceRaw) != nil || newValue.consequence != Consequence(stored: consequenceRaw) {
                consequenceRaw = newValue.consequence.rawValue
            }
            graceDays = newValue.graceDays
            followUpAfterLapse = newValue.followUpAfterLapse
            travelMarginDays = newValue.travelMarginDays
        }

        /// What `kept` held beside the columns as they now are, or nothing when that is all it held.
        private func keepReminders(_ kept: KeptObject<ReminderProfile>) {
            let current = kept.replacingValue(reminders)
            let data = current.keepsMore ? StoredJSON.encode(current) : nil
            if data != remindersData { remindersData = data }
        }

        public var status: ObligationStatus {
            get { ObligationStatus(stored: statusRaw) }
            set { statusRaw = newValue.rawValue }
        }

        /// How it repeats. Writing it keeps what a newer build wrote inside the rule that this one
        /// doesn't read, while the rule stays the same kind (`KeptObject`).
        public var recurrence: RecurrenceRule {
            get { KeptObject<RecurrenceRule>.value(in: recurrenceData) ?? .none }
            set { keptRecurrence = keptRecurrence.replacingValue(newValue) }
        }

        /// The rule as stored, with what this build doesn't read: what a backup carries.
        public var keptRecurrence: KeptObject<RecurrenceRule> {
            get { KeptObject.stored(in: recurrenceData, fallback: .none) ?? KeptObject(.none) }
            set { recurrenceData = KeptObject.data(newValue) }
        }

        public var estimatedCost: Money? {
            get {
                guard let amount = estimatedCostAmount else { return nil }
                return Money(amount, currency: estimatedCostCurrency ?? Money.defaultCurrency)
            }
            set {
                estimatedCostAmount = newValue?.amount
                estimatedCostCurrency = newValue?.currency
            }
        }

        /// The day it is due: the same day wherever the phone is. A deadline whose stored day
        /// can't be read (none was ever written) is due on the day it was made.
        public var dueDay: CalendarDay {
            get { StoredDay.day(dueDayISO) ?? CalendarDay(createdAt) }
            set { dueDayISO = StoredDay.text(newValue) }
        }

        /// Since when the person could know this cycle as it now is, which a reminder that makes
        /// up for warnings already passed counts from (`ReminderPlanner`): `cycleKnownAt`, else,
        /// when none is kept, its change time.
        public var cycleKnownSince: Date { cycleKnownAt ?? updatedAt }

        /// The day it comes back after "Amână", or nil when it isn't snoozed.
        public var snoozedUntil: CalendarDay? {
            get { StoredDay.day(snoozedUntilISO) }
            set { snoozedUntilISO = newValue.map(StoredDay.text) }
        }

        /// Whole days from today to the due day; negative when overdue.
        public func daysRemaining(from now: Date = Date(), calendar: Calendar = .dosar) -> Int {
            CalendarDay(now, calendar: calendar).days(to: dueDay, calendar: calendar)
        }

        /// Still hidden at `now`: its day hasn't started yet where the phone is (`calendar`).
        public func isSnoozed(at now: Date = Date(), calendar: Calendar = .dosar) -> Bool {
            guard let snoozedUntil else { return false }
            return CalendarDay(now, calendar: calendar) < snoozedUntil
        }

        /// The moment it stops being hidden: its day's start where the phone is (`calendar`).
        public func snoozeEnds(in calendar: Calendar = .dosar) -> Date? {
            snoozedUntil?.startDate(in: calendar)
        }

        /// Fetches sorted by due day, earliest first: ISO days sort as the days do.
        public static var byDueDay: SortDescriptor<Obligation> { SortDescriptor(\.dueDayISO, comparator: .lexical) }

        /// Completions of this obligation, newest first. Two recorded at the same
        /// moment are ordered by the cycle they closed, which only moves forward.
        public var history: [HistoryEntry] {
            (historyEntries ?? []).sorted {
                $0.occurredAt != $1.occurredAt
                    ? $0.occurredAt > $1.occurredAt
                    : ($0.cycleDueDay ?? .earliest) > ($1.cycleDueDay ?? .earliest)
            }
        }
    }
}
