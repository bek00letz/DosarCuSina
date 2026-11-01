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
    public var snoozedUntil: Date?
    public var reminderOffsetsDays: [Int]
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

    public init(
        id: UUID = UUID(),
        title: String,
        kind: ObligationKind,
        status: ObligationStatus = .active,
        dueDay: CalendarDay,
        snoozedUntil: Date? = nil,
        reminderOffsetsDays: [Int] = [30, 7, 1, 0],
        reminderMinuteOfDay: Int? = nil,
        estimatedCost: Money? = nil,
        assetId: UUID? = nil,
        assetName: String? = nil,
        templateKey: String? = nil,
        symbol: String = "checklist",
        tint: TemplateTint = .gray,
        isSensitive: Bool = false,
        isExample: Bool = false
    ) {
        self.id = id
        self.title = title
        self.kind = kind
        self.status = status
        self.dueDay = dueDay
        self.snoozedUntil = snoozedUntil
        self.reminderOffsetsDays = reminderOffsetsDays
        self.reminderMinuteOfDay = reminderMinuteOfDay
        self.estimatedCost = estimatedCost
        self.assetId = assetId
        self.assetName = assetName
        self.templateKey = templateKey
        self.symbol = symbol
        self.tint = tint
        self.isSensitive = isSensitive
        self.isExample = isExample
    }
}

extension ObligationSnapshot {
    /// Snapshots of every obligation that isn't archived, with asset and category details.
    @MainActor
    public static func fetchAll(in context: ModelContext, calendar: Calendar = .current) throws -> [ObligationSnapshot] {
        let archived = ObligationStatus.archived.rawValue
        let obligations = try context.fetch(FetchDescriptor<Obligation>(
            predicate: #Predicate { $0.statusRaw != archived },
            sortBy: [SortDescriptor(\.dueDate)]
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
                dueDay: obligation.dueDay(in: calendar),
                snoozedUntil: obligation.snoozedUntil,
                reminderOffsetsDays: obligation.reminderOffsetsDays,
                reminderMinuteOfDay: obligation.reminderMinuteOfDay,
                estimatedCost: obligation.estimatedCost,
                assetId: asset?.id,
                assetName: asset?.name,
                templateKey: asset?.templateKey,
                symbol: asset?.symbolOverride ?? template?.symbol ?? "checklist",
                tint: asset?.tintOverride ?? template?.tint ?? .gray,
                isSensitive: template?.isSensitive ?? false,
                isExample: obligation.isExample
            )
        }
    }
}
