import Foundation

/// What widgets show: the one definition of the widget snapshot, written by the app
/// (`WidgetFeed.make`, `WidgetSnapshotWriter`) to the shared App Group container and read
/// by the widget extension as the same type, so the two can't drift apart.
///
/// File: `widget-snapshot.json` in the App Group, written by `MachineText.jsonEncoder()`.
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
///     "deepLink": "dosarcusina://obligation/…",
///     "urgency": {                  // its urgency rule, so the widget counts down
///       "graceDays": 0, "firstLeadDays": 30, "maxWindowDays": 30   // like the app
///     }
///   }]
/// }
/// ```
/// Items from sensitive categories carry a generic title and no asset name.
public struct WidgetFeed: Codable, Hashable, Sendable {
    public static let fileName = "widget-snapshot.json"
    /// The version the app writes; the widget reads it and every one before it.
    public static let currentVersion = 1
    /// The most items a snapshot carries.
    public static let maxItems = 8

    public struct Item: Codable, Hashable, Sendable, Identifiable {
        public var obligationId: UUID
        public var assetId: UUID?
        public var title: String
        public var assetName: String?
        public var symbol: String
        /// The category's tint, by its stored name (`TemplateTint`).
        public var tint: String
        public var dueDate: CalendarDay
        /// The deadline's kind, by its stored name (`ObligationKind`).
        public var kind: String
        public var isSensitive: Bool
        public var deepLink: URL
        /// The one urgency rule (`ReminderProfile.urgencyRule`), so the widget's tone,
        /// wording and count match the app's on every day the timeline covers. A snapshot
        /// from before it was written has none, and reads as a deadline nothing reminds
        /// about until the app rewrites it.
        public var urgency: UrgencyRule?

        public var id: UUID { obligationId }

        public init(
            obligationId: UUID, assetId: UUID?, title: String, assetName: String?, symbol: String, tint: String,
            dueDate: CalendarDay, kind: String, isSensitive: Bool, deepLink: URL, urgency: UrgencyRule?
        ) {
            self.obligationId = obligationId
            self.assetId = assetId
            self.title = title
            self.assetName = assetName
            self.symbol = symbol
            self.tint = tint
            self.dueDate = dueDate
            self.kind = kind
            self.isSensitive = isSensitive
            self.deepLink = deepLink
            self.urgency = urgency
        }
    }

    public var version: Int
    public var generatedAt: Date
    public var needsActionCount: Int
    public var items: [Item]

    public init(version: Int = WidgetFeed.currentVersion, generatedAt: Date, needsActionCount: Int, items: [Item]) {
        self.version = version
        self.generatedAt = generatedAt
        self.needsActionCount = needsActionCount
        self.items = items
    }

    /// The snapshot as the file holds it.
    public static func encode(_ feed: WidgetFeed) throws -> Data {
        try MachineText.jsonEncoder().encode(feed)
    }

    /// The snapshot in a file's bytes, or nil when it can't be read or a newer version wrote it.
    public static func decode(_ data: Data) -> WidgetFeed? {
        guard let feed = try? MachineText.jsonDecoder().decode(WidgetFeed.self, from: data), feed.version <= currentVersion else { return nil }
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
            let dueDay = item.dueDate
            guard !done.contains("\(item.obligationId.uuidString.lowercased())|\(dueDay.isoString)") else { return nil }
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
                dueKey: dueDay.isoString,
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
