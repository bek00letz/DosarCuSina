import Foundation

/// The widget snapshot as the widget extension reads it.
///
/// The app writes the file with `WidgetSnapshot` (Services/SideEffects), the one
/// definition of the format. The extension can't link the app's model layer, so
/// it reads the same JSON through this small mirror; a test in the app target
/// encodes a `WidgetSnapshot` and decodes it here, so the two can't drift apart.
public struct WidgetFeed: Decodable, Hashable, Sendable {
    public static let fileName = "widget-snapshot.json"
    /// Versions this reader understands.
    public static let supportedVersion = 1

    public struct Item: Decodable, Hashable, Sendable, Identifiable {
        public var obligationId: UUID
        public var assetId: UUID?
        public var title: String
        public var assetName: String?
        public var symbol: String
        public var tint: String
        /// `yyyy-MM-dd`.
        public var dueDate: String
        public var kind: String
        public var isSensitive: Bool
        public var deepLink: URL
        /// The app's urgency rule for it. A snapshot from before it was written has
        /// none, and reads as a deadline nothing reminds about until the app rewrites it.
        public var urgency: UrgencyRule?

        public var id: UUID { obligationId }
    }

    public var version: Int
    public var generatedAt: Date
    public var needsActionCount: Int
    public var items: [Item]

    public static func decode(_ data: Data) -> WidgetFeed? {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let feed = try? decoder.decode(WidgetFeed.self, from: data), feed.version <= supportedVersion else { return nil }
        return feed
    }

    /// The snapshot in the App Group, or nil when there is none yet.
    public static func load(from container: URL? = AppGroup.containerURL) -> WidgetFeed? {
        guard let url = container?.appending(path: fileName), let data = try? Data(contentsOf: url) else { return nil }
        return decode(data)
    }
}

/// One line on a widget, worked out from the feed for a given moment.
public struct WidgetRow: Hashable, Sendable, Identifiable {
    public var id: UUID
    public var title: String
    public var subtitle: String?
    public var symbol: String
    /// Whole days until due; negative when late.
    public var daysRemaining: Int
    /// By the app's one rule, so the widget draws what the app draws.
    public var urgency: AttentionUrgency
    /// "Azi", "În 5 zile", "Depășit de 3 zile": the same words as the app.
    public var when: String
    public var dueDate: Date
    /// `yyyy-MM-dd` of the cycle shown, so a tap on "Gata" closes this cycle only.
    public var dueKey: String
    public var deepLink: URL
    /// Protected sections never offer "Gata" outside the app.
    public var canComplete: Bool
}

/// What a widget shows: the feed in attention order, minus anything the person
/// just marked done on a widget, with days left counted from `now`.
public enum WidgetContent {
    public static func rows(
        feed: WidgetFeed?,
        completed: [WidgetCompletion],
        now: Date,
        calendar: Calendar = .dosar,
        protectedTitle: String,
        limit: Int
    ) -> [WidgetRow] {
        guard let feed else { return [] }
        let done = Set(completed.map { "\($0.obligationId.uuidString.lowercased())|\($0.dueDay)" })
        let today = CalendarDay(now, calendar: calendar)
        return feed.items.compactMap { item -> WidgetRow? in
            guard !done.contains("\(item.obligationId.uuidString.lowercased())|\(item.dueDate)"),
                  let dueDay = CalendarDay(isoString: item.dueDate) else { return nil }
            let days = today.days(to: dueDay, calendar: calendar)
            let urgency = (item.urgency ?? .noReminders).urgency(of: dueDay, today: today, calendar: calendar)
            return WidgetRow(
                id: item.obligationId,
                title: item.isSensitive ? protectedTitle : item.title,
                subtitle: item.isSensitive ? nil : item.assetName,
                symbol: item.isSensitive ? "lock.fill" : item.symbol,
                daysRemaining: days,
                urgency: urgency,
                when: WhenWording.standalone(urgency, daysRemaining: days, from: now, calendar: calendar),
                dueDate: dueDay.startDate(in: calendar),
                dueKey: item.dueDate,
                deepLink: item.deepLink,
                canComplete: !item.isSensitive
            )
        }
        .prefix(max(0, limit))
        .map { $0 }
    }

    /// How many need doing now, after widget completions: the app badge's count
    /// (late past grace, or due today), by the same rule.
    public static func needsActionCount(_ rows: [WidgetRow]) -> Int {
        rows.filter { $0.urgency.isAlarming }.count
    }
}
