import Foundation

/// "Gata" tapped on a widget for one cycle of an obligation.
public struct WidgetCompletion: Codable, Hashable, Sendable {
    public var obligationId: UUID
    /// `yyyy-MM-dd` of the cycle the person saw. The app completes it only if the
    /// obligation is still on that cycle, so a late hand-over never closes the next one.
    public var dueDay: String
    public var requestedAt: Date

    public init(obligationId: UUID, dueDay: String, requestedAt: Date = Date()) {
        self.obligationId = obligationId
        self.dueDay = dueDay
        self.requestedAt = requestedAt
    }
}

/// Widget completions waiting for the app, in the App Group.
///
/// When the system runs the widget's intent inside the widget extension (iOS 26),
/// the extension can't open the household database, so it leaves the request
/// here and the widget hides the item at once. The app completes it through
/// `ObligationActions` the next time it runs. From iOS 27 the intent runs in the
/// app itself and the queue stays empty.
public struct WidgetCompletionQueue: Sendable {
    public static let fileName = "widget-completions.json"
    /// Requests older than this are dropped unapplied; the person has long moved on.
    public static let maxAge: TimeInterval = 30 * 86_400

    public let fileURL: URL

    public init(fileURL: URL) {
        self.fileURL = fileURL
    }

    public static func shared() -> WidgetCompletionQueue? {
        AppGroup.containerURL.map { WidgetCompletionQueue(fileURL: $0.appending(path: fileName)) }
    }

    public func pending() -> [WidgetCompletion] {
        var result: [WidgetCompletion] = []
        coordinate(writing: false) { url in
            result = Self.read(url)
        }
        return result
    }

    /// Adds a request; the same cycle twice is kept once.
    public func enqueue(_ completion: WidgetCompletion) {
        coordinate(writing: true) { url in
            var all = Self.read(url)
            guard !all.contains(where: { $0.obligationId == completion.obligationId && $0.dueDay == completion.dueDay }) else { return }
            all.append(completion)
            Self.write(all, to: url)
        }
    }

    /// Removes handled requests and any that are too old.
    public func remove(_ handled: [WidgetCompletion], now: Date = Date()) {
        coordinate(writing: true) { url in
            let all = Self.read(url).filter { item in
                !handled.contains(item) && now.timeIntervalSince(item.requestedAt) < Self.maxAge
            }
            Self.write(all, to: url)
        }
    }

    // MARK: Private

    private func coordinate(writing: Bool, _ body: (URL) -> Void) {
        let coordinator = NSFileCoordinator()
        var error: NSError?
        if writing {
            coordinator.coordinate(writingItemAt: fileURL, options: [], error: &error, byAccessor: body)
        } else {
            coordinator.coordinate(readingItemAt: fileURL, options: [], error: &error, byAccessor: body)
        }
    }

    private static func read(_ url: URL) -> [WidgetCompletion] {
        guard let data = try? Data(contentsOf: url) else { return [] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return (try? decoder.decode([WidgetCompletion].self, from: data)) ?? []
    }

    private static func write(_ items: [WidgetCompletion], to url: URL) {
        if items.isEmpty {
            try? FileManager.default.removeItem(at: url)
            return
        }
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        guard let data = try? encoder.encode(items) else { return }
        // Readable after first unlock, like the widget snapshot, so a locked phone still shows widgets.
        try? data.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }
}
