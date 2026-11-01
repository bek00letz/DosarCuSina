import Foundation
#if canImport(WidgetKit)
import WidgetKit
#endif

/// What widgets show, written by the app to the shared App Group container.
///
/// File: `<App Group group.com.ar.dosarcusina.shared>/widget-snapshot.json`.
/// Format (version 1, JSON, keys stable):
/// ```
/// {
///   "version": 1,
///   "generatedAt": "2026-11-02T08:00:00Z",
///   "needsActionCount": 2,          // overdue + due today
///   "items": [{                     // attention order, at most 8
///     "obligationId": "…", "assetId": "…",
///     "title": "ITP", "assetName": "VW Golf",
///     "symbol": "car.fill", "tint": "blue",
///     "dueDate": "2026-11-15",      // calendar day; the widget works out days left itself
///     "kind": "legal", "isSensitive": false,
///     "deepLink": "dosarcusina://obligation/…"
///   }]
/// }
/// ```
/// Items from sensitive categories carry a generic title and no asset name.
public struct WidgetSnapshot: Codable, Hashable, Sendable {
    public static let currentVersion = 1
    public static let appGroupIdentifier = "group.com.ar.dosarcusina.shared"
    public static let fileName = "widget-snapshot.json"
    public static let maxItems = 8

    public struct Item: Codable, Hashable, Sendable {
        public var obligationId: UUID
        public var assetId: UUID?
        public var title: String
        public var assetName: String?
        public var symbol: String
        public var tint: TemplateTint
        public var dueDate: CalendarDay
        public var kind: ObligationKind
        public var isSensitive: Bool
        public var deepLink: URL
    }

    public var version: Int
    public var generatedAt: Date
    public var needsActionCount: Int
    public var items: [Item]

    /// Builds the snapshot from an attention digest: "now" first, then "soon" in order.
    public static func make(from digest: AttentionDigest, generatedAt: Date = Date()) -> WidgetSnapshot {
        let ordered = digest.now + digest.soon.flatMap(\.entries)
        let items = ordered.prefix(maxItems).map { entry -> Item in
            let obligation = entry.obligation
            return Item(
                obligationId: obligation.id,
                assetId: obligation.assetId,
                title: obligation.isSensitive ? String(localized: "Scadență protejată", comment: "Widget title for a protected category") : obligation.title,
                assetName: obligation.isSensitive ? nil : obligation.assetName,
                symbol: obligation.isSensitive ? "lock.fill" : obligation.symbol,
                tint: obligation.tint,
                dueDate: obligation.dueDay,
                kind: obligation.kind,
                isSensitive: obligation.isSensitive,
                deepLink: DeepLink.url(for: .obligation(obligation.id))
            )
        }
        return WidgetSnapshot(version: currentVersion, generatedAt: generatedAt, needsActionCount: digest.needsActionCount, items: Array(items))
    }

    public static func encoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }

    public static func decoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}

/// Writes the snapshot and asks WidgetKit to reload, only when the content changed.
public struct WidgetSnapshotWriter: Sendable {
    public let directory: URL?

    /// The App Group container, or nil when the entitlement is missing (unsigned builds).
    public init(directory: URL? = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: WidgetSnapshot.appGroupIdentifier)) {
        self.directory = directory
    }

    public var fileURL: URL? { directory?.appending(path: WidgetSnapshot.fileName) }

    @discardableResult
    public func write(_ snapshot: WidgetSnapshot) -> Bool {
        guard let fileURL else { return false }
        var comparable = snapshot
        if let existing = try? Data(contentsOf: fileURL),
           let previous = try? WidgetSnapshot.decoder().decode(WidgetSnapshot.self, from: existing) {
            comparable.generatedAt = previous.generatedAt
            if comparable == previous { return false }
        }
        guard let data = try? WidgetSnapshot.encoder().encode(snapshot) else { return false }
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
