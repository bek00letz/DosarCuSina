import Foundation
import SwiftData
import WidgetKit

/// Service responsible for mapping active obligations from SwiftData
/// into high-fidelity `DosarWidgetSnapshot` records and persisting them
/// to the shared App Group container (`group.com.ar.dosarcusina.shared`).
///
/// Features:
/// - Fetches active uncompleted events sorted chronologically by due date.
/// - Calculates an Apple-style overall life-admin health score (0–100):
///   - 100% baseline when no obligations are overdue.
///   - Deducts 25 points per overdue event.
///   - Deducts 5 points per urgent event due within 7 days.
///   - Rewards completed events.
/// - Counts urgent events and total active assets.
/// - Saves snapshot atomically to the shared App Group container via `WidgetDataProvider.saveSnapshot`.
/// - Reloads all widget timelines via `WidgetCenter.shared.reloadAllTimelines()`.
public final class WidgetDataSyncService: Sendable {
    
    public static let shared = WidgetDataSyncService()
    
    public init() {}
    
    /// Pure functional transformer converting arrays of `LifecycleEvent` and `Asset`
    /// into a deterministic `DosarWidgetSnapshot`.
    public func buildSnapshot(
        from events: [LifecycleEvent],
        assets: [Asset] = [],
        referenceDate: Date = Date()
    ) -> DosarWidgetSnapshot {
        let activeAssetsCount = max(assets.count, Set(events.compactMap { $0.asset?.id }).count)
        
        let pendingEvents = events.filter { !$0.isCompleted }
        let completedEvents = events.filter { $0.isCompleted }
        
        let sortedPending = pendingEvents.sorted { $0.dueDate < $1.dueDate }
        
        let overdueCount = sortedPending.filter { $0.isOverdue }.count
        let urgentCount = sortedPending.filter { $0.isUrgent }.count
        let totalUrgentCount = overdueCount + urgentCount
        
        let totalEvents = events.count
        let healthScore: Int
        if totalEvents == 0 {
            healthScore = 100
        } else {
            let baseScore = 100
            let penalties = (overdueCount * 25) + (urgentCount * 5)
            let completionBonus = min(15, completedEvents.count * 3)
            let computed = baseScore - penalties + completionBonus
            healthScore = min(100, max(0, computed))
        }
        
        let widgetItems = sortedPending.prefix(10).map { event in
            DosarWidgetEventItem(
                id: event.id.uuidString,
                title: event.title,
                assetName: event.asset?.name ?? "Dosar cu Șină",
                iconName: event.asset?.iconName ?? "folder.fill",
                assetColorHex: event.asset?.accentColorHex ?? "007AFF",
                dueDate: event.dueDate,
                daysRemaining: event.daysRemaining,
                isUrgent: event.isUrgent,
                isOverdue: event.isOverdue,
                isCompleted: event.isCompleted,
                cost: event.cost,
                currency: event.currency
            )
        }
        
        return DosarWidgetSnapshot(
            lastUpdated: referenceDate,
            healthScore: healthScore,
            activeAssetsCount: max(1, activeAssetsCount),
            urgentEventsCount: totalUrgentCount,
            events: Array(widgetItems)
        )
    }
    
    /// Synchronizes live SwiftData records from a `ModelContext` to the App Group widget snapshot.
    @discardableResult
    public func sync(context: ModelContext) -> DosarWidgetSnapshot {
        let eventDescriptor = FetchDescriptor<LifecycleEvent>(
            sortBy: [SortDescriptor(\.dueDate, order: .forward)]
        )
        let assetDescriptor = FetchDescriptor<Asset>()
        
        let allEvents = (try? context.fetch(eventDescriptor)) ?? []
        let allAssets = (try? context.fetch(assetDescriptor)) ?? []
        
        let snapshot = buildSnapshot(from: allEvents, assets: allAssets)
        WidgetDataProvider.saveSnapshot(snapshot)
        WidgetCenter.shared.reloadAllTimelines()
        return snapshot
    }
    
    /// Synchronizes live records using a `ModelContainer`.
    @discardableResult
    public func sync(container: ModelContainer) -> DosarWidgetSnapshot {
        let context = ModelContext(container)
        return sync(context: context)
    }
}
