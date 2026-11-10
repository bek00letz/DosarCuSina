import Foundation
import SwiftData

/// A plain, thread-safe copy of an obligation and the bits of its asset and
/// category that ranking, reminders and widgets need. Built once per pass so
/// those pure functions never touch the database.
public struct ObligationSnapshot: Hashable, Sendable, Identifiable {
    public var id: UUID
    public var title: String
    public var kind: ObligationKind
    public var status: ObligationStatus
    public var dueDay: CalendarDay
    /// The day it comes back after "Amână"; hidden until that day starts where the phone is.
    public var snoozedUntil: CalendarDay?
    public var reminders: ReminderProfile
    public var reminderMinuteOfDay: Int?
    public var estimatedCost: Money?
    public var assetId: UUID?
    public var assetName: String?
    public var templateKey: String?
    public var symbol: String
    public var tint: TemplateTint
    /// The category asks for Face ID, so lock-screen text stays generic.
    public var isSensitive: Bool
    public var isExample: Bool
    /// Since when the person could know this cycle as it now is: its due day, its reminders'
    /// leads and that it is active (`Obligation.cycleKnownSince`). Reminders that would have
    /// fired before it never had a chance: `ReminderPlanner` makes up for them with one
    /// catch-up reminder. Nil when unknown (no catch-up).
    public var cycleKnownSince: Date?

    public init(
        id: UUID = UUID(),
        title: String,
        kind: ObligationKind,
        status: ObligationStatus = .active,
        dueDay: CalendarDay,
        snoozedUntil: CalendarDay? = nil,
        reminders: ReminderProfile? = nil,
        reminderMinuteOfDay: Int? = nil,
        estimatedCost: Money? = nil,
        assetId: UUID? = nil,
        assetName: String? = nil,
        templateKey: String? = nil,
        symbol: String = "checklist",
        tint: TemplateTint = .gray,
        isSensitive: Bool = false,
        isExample: Bool = false,
        cycleKnownSince: Date? = nil
    ) {
        self.id = id
        self.title = title
        self.kind = kind
        self.status = status
        self.dueDay = dueDay
        self.snoozedUntil = snoozedUntil
        self.reminders = reminders ?? kind.defaultProfile
        self.reminderMinuteOfDay = reminderMinuteOfDay
        self.estimatedCost = estimatedCost
        self.assetId = assetId
        self.assetName = assetName
        self.templateKey = templateKey
        self.symbol = symbol
        self.tint = tint
        self.isSensitive = isSensitive
        self.isExample = isExample
        self.cycleKnownSince = cycleKnownSince
    }
}

extension ObligationSnapshot {
    /// Still hidden at `now`: the day its snooze ends hasn't started yet where the phone is.
    public func isSnoozed(at now: Date = Date(), calendar: Calendar = .dosar) -> Bool {
        guard let snoozedUntil else { return false }
        return CalendarDay(now, calendar: calendar) < snoozedUntil
    }

    /// The moment its snooze ends, the start of that day where the phone is, while still ahead of `now`.
    public func snoozeEnds(after now: Date, calendar: Calendar = .dosar) -> Date? {
        snoozedUntil.map { $0.startDate(in: calendar) }.flatMap { $0 > now ? $0 : nil }
    }

    /// What may leave the app (reminders, the badge, widgets, Siri and Shortcuts,
    /// Spotlight): every snapshot except examples, which are only for exploring.
    /// Every outside surface reads this one list.
    @MainActor
    public static func fetchForOutside(in context: ModelContext, calendar: Calendar = .dosar) throws -> [ObligationSnapshot] {
        try fetchAll(in: context, calendar: calendar).filter { !$0.isExample }
    }

    /// Snapshots of every obligation that isn't archived, with asset and category details.
    @MainActor
    public static func fetchAll(in context: ModelContext, calendar: Calendar = .dosar) throws -> [ObligationSnapshot] {
        let archived = ObligationStatus.archived.rawValue
        let obligations = try context.fetch(FetchDescriptor<Obligation>(
            predicate: #Predicate { $0.statusRaw != archived },
            sortBy: [Obligation.byDueDay]
        ))
        let templates = try TemplateStore(context: context).templatesByKey()
        return obligations.map { obligation in
            let asset = obligation.asset
            let template = asset.flatMap { templates[$0.templateKey] }
            return ObligationSnapshot(
                id: obligation.id,
                title: obligation.title,
                kind: obligation.kind,
                status: obligation.status,
                dueDay: obligation.dueDay,
                snoozedUntil: obligation.snoozedUntil,
                reminders: obligation.reminders,
                reminderMinuteOfDay: obligation.reminderMinuteOfDay,
                estimatedCost: obligation.estimatedCost,
                assetId: asset?.id,
                assetName: asset?.name,
                templateKey: asset?.templateKey,
                symbol: asset?.symbolOverride ?? template?.symbol ?? "checklist",
                tint: asset?.tintOverride ?? template?.tint ?? .gray,
                isSensitive: template?.isSensitive ?? false,
                isExample: obligation.isExample,
                cycleKnownSince: obligation.cycleKnownSince
            )
        }
    }
}
