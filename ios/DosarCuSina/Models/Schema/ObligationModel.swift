import Foundation
import SwiftData

extension DosarSchemaV2 {
    /// Something that has to be done by a date, once or on a schedule: ITP, RCA,
    /// local taxes, a vaccine, a subscription renewal.
    ///
    /// An obligation is never copied to make the next cycle. Completing it writes
    /// a `HistoryEntry` and moves `dueDate` forward (see `ObligationActions`).
    @Model
    public final class Obligation {
        public var id: UUID = UUID()
        public var title: String = ""
        public var notes: String?
        /// The template blueprint this came from, when it came from one.
        public var blueprintKey: String?
        public var kindRaw: String = ObligationKind.routine.rawValue
        /// Noon on the due day (see `CalendarDay.noonDate`). Use `dueDay` to read and write it.
        public var dueDate: Date = Date()
        /// For counter-based obligations, the reading at which it is due (for example 160 000 km).
        public var dueMetric: Double?
        /// Reminder profile, stored flat: lead days (largest first; `0` is the due day),
        /// consequence and grace days. Read and write it through `reminders`.
        public var reminderLeadDays: [Int] = [30, 7, 0]
        public var consequenceRaw: String = Consequence.comfort.rawValue
        public var graceDays: Int = 0
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
        /// Hidden from attention and reminders until this moment.
        public var snoozedUntil: Date?
        public var isExample: Bool = false
        public var createdAt: Date = Date()
        public var updatedAt: Date = Date()

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
            estimatedCost: Money? = nil,
            calendar: Calendar = .current
        ) {
            self.id = id
            self.title = title
            self.kindRaw = kind.rawValue
            self.dueDate = dueDay.noonDate(in: calendar)
            self.recurrenceData = StoredJSON.encode(recurrence)
            let profile = reminders ?? kind.defaultProfile
            self.reminderLeadDays = profile.leadDays
            self.consequenceRaw = profile.consequence.rawValue
            self.graceDays = profile.graceDays
            self.estimatedCostAmount = estimatedCost?.amount
            self.estimatedCostCurrency = estimatedCost?.currency
        }

        public var kind: ObligationKind {
            get { ObligationKind(rawValue: kindRaw) ?? .routine }
            set { kindRaw = newValue.rawValue }
        }

        /// How this obligation reminds. Set from its blueprint, changeable by the person.
        public var reminders: ReminderProfile {
            get {
                ReminderProfile(
                    leadDays: reminderLeadDays,
                    consequence: Consequence(rawValue: consequenceRaw) ?? .comfort,
                    graceDays: graceDays
                )
            }
            set {
                reminderLeadDays = newValue.leadDays
                consequenceRaw = newValue.consequence.rawValue
                graceDays = newValue.graceDays
            }
        }

        public var status: ObligationStatus {
            get { ObligationStatus(rawValue: statusRaw) ?? .active }
            set { statusRaw = newValue.rawValue }
        }

        public var recurrence: RecurrenceRule {
            get { StoredJSON.decode(RecurrenceRule.self, from: recurrenceData) ?? .none }
            set { recurrenceData = StoredJSON.encode(newValue) }
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

        public func dueDay(in calendar: Calendar = .current) -> CalendarDay {
            CalendarDay(dueDate, calendar: calendar)
        }

        public func setDueDay(_ day: CalendarDay, calendar: Calendar = .current) {
            dueDate = day.noonDate(in: calendar)
        }

        /// Whole days from today to the due day; negative when overdue.
        public func daysRemaining(from now: Date = Date(), calendar: Calendar = .current) -> Int {
            CalendarDay(now, calendar: calendar).days(to: dueDay(in: calendar), calendar: calendar)
        }

        public func isSnoozed(at now: Date = Date()) -> Bool {
            guard let snoozedUntil else { return false }
            return snoozedUntil > now
        }

        /// Completions of this obligation, newest first. Two recorded at the same
        /// moment are ordered by the cycle they closed, which only moves forward.
        public var history: [HistoryEntry] {
            (historyEntries ?? []).sorted {
                $0.occurredAt != $1.occurredAt
                    ? $0.occurredAt > $1.occurredAt
                    : ($0.cycleDueDate ?? .distantPast) > ($1.cycleDueDate ?? .distantPast)
            }
        }
    }
}
