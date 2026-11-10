import Foundation
import SwiftData

/// What happened in a history entry. Raw values are part of the `.dosar` contract.
public enum HistoryKind: String, Codable, CaseIterable, Sendable {
    /// A service visit or a check-up.
    case visit
    case repair
    /// Planned upkeep: a revision, a filter change.
    case maintenance
    /// An official inspection: ITP, VTP, gas check.
    case inspection
    /// Something bought for the asset (parts, an accessory) or the asset itself.
    case purchase
    /// A bill, a tax, a premium paid.
    case payment
    case vaccination
    case treatment
    /// Anything else worth remembering.
    case note

    /// The history kind written when an obligation of `kind` is completed.
    public static func forCompleting(_ kind: ObligationKind) -> HistoryKind {
        switch kind {
        case .legal: return .inspection
        case .tax, .insurance, .payment: return .payment
        case .health: return .treatment
        case .renewal: return .note
        case .maintenance, .routine: return .maintenance
        }
    }
}

extension DosarSchemaV10 {
    /// One thing that happened to an asset: a visit, a repair, a purchase, an
    /// inspection. It is the asset's single history: completing an obligation
    /// writes one of these, and so does logging a repair by hand.
    @Model
    public final class HistoryEntry {
        public var id: UUID = UUID()
        public var kindRaw: String = HistoryKind.note.rawValue
        public var title: String = ""
        public var occurredAt: Date = Date()
        /// Counter reading at the time (km, engine hours).
        public var metricReading: Double?
        /// What was paid in total. When empty, the line items add up the cost.
        public var totalCostAmount: Decimal?
        public var totalCostCurrency: String?
        public var note: String?
        /// The number of the paper this entry records, as printed: a bill's or a visit's
        /// invoice number. The paper is known by it when it is filed again (`PaperIdentity`). Version 7.
        public var reference: String?
        /// The person's 1–5 rating of this job; providers' ratings average these.
        public var rating: Int?
        public var isExample: Bool = false
        /// When it last changed, set by the unit of work that saved the change (`ChangeTimes`).
        /// Records from before version 8 have `ChangeTime.unknown`, older than any change. Version 8.
        public var updatedAt: Date = Date.distantPast

        // Set when the entry records the completion of an obligation, for undo.
        /// The due day of the cycle it closed, as an ISO day (`StoredDay`); read and write it
        /// through `cycleDueDay`. Version 9; before, noon of the day in the phone's time zone.
        public var cycleDueDayISO: String?
        /// The due day the obligation moved to, as an ISO day; read and write it through
        /// `nextDueDay`. Version 9, as `cycleDueDayISO`.
        public var nextDueDayISO: String?
        public var previousStatusRaw: String?
        public var previousDueMetric: Double?

        public var asset: Asset?
        public var obligation: Obligation?
        /// Who did the work.
        public var providers: [Provider]? = []

        /// Parts and jobs, each tied to a component.
        @Relationship(deleteRule: .cascade, inverse: \ServiceItem.entry)
        public var items: [ServiceItem]? = []

        @Relationship(deleteRule: .nullify, inverse: \Attachment.historyEntry)
        public var attachments: [Attachment]? = []

        public init(id: UUID = UUID(), kind: HistoryKind, title: String, occurredAt: Date) {
            self.id = id
            self.kindRaw = kind.rawValue
            self.title = title
            self.occurredAt = occurredAt
            self.updatedAt = Date()
        }

        public var kind: HistoryKind {
            get { HistoryKind(rawValue: kindRaw) ?? .note }
            set { kindRaw = newValue.rawValue }
        }

        public var totalCost: Money? {
            get {
                guard let totalCostAmount else { return nil }
                return Money(totalCostAmount, currency: totalCostCurrency ?? Money.defaultCurrency)
            }
            set {
                totalCostAmount = newValue?.amount
                totalCostCurrency = newValue?.currency
            }
        }

        /// The explicit total, or the line items added up per currency.
        public var effectiveCost: MoneyTotals {
            if let totalCost { return MoneyTotals([totalCost]) }
            return MoneyTotals((items ?? []).compactMap(\.totalCost))
        }

        public var providerNames: [String] { (providers ?? []).map(\.name).sorted() }
        public var providerIds: [UUID] { (providers ?? []).map(\.id) }

        /// The due day of the cycle this completion closed; nil when it isn't a completion.
        public var cycleDueDay: CalendarDay? {
            get { StoredDay.day(cycleDueDayISO) }
            set { cycleDueDayISO = newValue.map(StoredDay.text) }
        }

        /// The due day the completion moved its obligation to; nil when it ended the series.
        public var nextDueDay: CalendarDay? {
            get { StoredDay.day(nextDueDayISO) }
            set { nextDueDayISO = newValue.map(StoredDay.text) }
        }

        /// Whether this entry is the completion of an obligation.
        public var isCompletion: Bool { cycleDueDayISO != nil }
    }
}
