import Foundation
#if canImport(WidgetKit)
import WidgetKit
#endif

/// The widget snapshot as the app builds it. Its format is `WidgetFeed` (ios/Shared), the
/// one type the app writes and the widget reads.
extension WidgetFeed {
    /// Builds the snapshot in attention order ("now" first, then "soon"). Example
    /// records never appear in widgets, even when they are all there is.
    public static func make(from obligations: [ObligationSnapshot], now: Date = Date(), calendar: Calendar = .dosar) -> WidgetFeed {
        let digest = AttentionModel.digest(obligations.filter { !$0.isExample }, now: now, calendar: calendar)
        let ordered = digest.now + digest.soon.flatMap(\.entries)
        let items = ordered.prefix(maxItems).map { entry -> Item in
            let obligation = entry.obligation
            return Item(
                obligationId: obligation.id,
                assetId: obligation.assetId,
                title: obligation.isSensitive ? String(localized: "Scadență protejată", comment: "Widget title for a protected category") : obligation.title,
                assetName: obligation.isSensitive ? nil : obligation.assetName,
                symbol: obligation.isSensitive ? "lock.fill" : obligation.symbol,
                tint: obligation.tint.rawValue,
                dueDate: obligation.dueDay,
                kind: obligation.kind.rawValue,
                isSensitive: obligation.isSensitive,
                deepLink: DeepLink.url(for: .obligation(obligation.id)),
                urgency: obligation.reminders.urgencyRule
            )
        }
        return WidgetFeed(generatedAt: now, needsActionCount: digest.needsActionCount, items: Array(items))
    }
}

/// Writes the snapshot and asks WidgetKit to reload, only when the content changed.
public struct WidgetSnapshotWriter: Sendable {
    public let directory: URL?

    /// The App Group container, or nil when the entitlement is missing (unsigned builds).
    public init(directory: URL? = AppGroup.containerURL) {
        self.directory = directory
    }

    public var fileURL: URL? { directory?.appending(path: WidgetFeed.fileName) }

    @discardableResult
    public func write(_ snapshot: WidgetFeed) -> Bool {
        guard let fileURL else { return false }
        var comparable = snapshot
        if let existing = try? Data(contentsOf: fileURL), let previous = WidgetFeed.decode(existing) {
            comparable.generatedAt = previous.generatedAt
            if comparable == previous { return false }
        }
        guard let data = try? WidgetFeed.encode(snapshot) else { return false }
        do {
            try data.write(to: fileURL, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        } catch {
            return false
        }
        #if canImport(WidgetKit)
        WidgetCenter.shared.reloadAllTimelines()
        #endif
        return true
    }
}
