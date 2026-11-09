import SwiftData
import SwiftUI

/// The app's side of the App Group handoff: items shared from other apps
/// waiting in "De verificat", and widget taps waiting to be applied.
///
/// Refreshes when the app comes to the foreground and the moment the share
/// extension posts that something arrived. Attach `.intakeHandoff()` once near
/// the root so this runs whatever tab is open.
///
/// Each item that arrives is read once on the phone (`InboxPreviewer`), one at a time,
/// so its row can say what it is and show its first page; what was learned is kept
/// beside the item (`InboxPreview`). Whenever what waits changes, it posts
/// `ShareInbox.didChangeNotification`, so the coordinator can withdraw the share's notice.
@MainActor
@Observable
final class IntakeInbox {
    static let shared = IntakeInbox()

    /// Reads one item's first page: what it is, its pages and its picture.
    typealias PreviewReader = @Sendable (InboxItem, [URL]) async -> (preview: InboxPreview, thumbnail: Data?)

    /// Items waiting for review, newest first.
    private(set) var items: [InboxItem] = []
    /// Items that arrived but couldn't be opened, set aside, newest first.
    private(set) var unreadable: [UnreadableInboxItem] = []
    /// Bumps every time something new arrives, for the share practice.
    private(set) var arrivals = 0
    /// What the phone read of each waiting item, once it has.
    private(set) var previews: [UUID: InboxPreview] = [:]
    /// Each waiting item's first page, small, when one may be shown.
    private(set) var thumbnails: [UUID: UIImage] = [:]

    @ObservationIgnored let inbox: ShareInbox?
    @ObservationIgnored private let reader: PreviewReader?
    @ObservationIgnored private var isObserving = false
    @ObservationIgnored private var previewing: Task<Void, Never>?

    /// - Parameter reader: nil reads nothing (tests that only look at the list).
    init(inbox: ShareInbox? = .shared(), reader: PreviewReader? = { await InboxPreviewer.read($0, files: $1) }) {
        self.inbox = inbox
        self.reader = reader
        let contents = inbox?.contents() ?? ShareInbox.Contents()
        self.items = contents.items
        self.unreadable = contents.unreadable
        loadPreviews()
    }

    /// Items leaving (dismissed, or filed) while their toast can still take that back: hidden
    /// from De verificat, removed for good once the toast is gone (`DSToast.whenGone`).
    private(set) var leaving: Set<UUID> = []

    /// What still waits in De verificat: everything but what is leaving.
    var waiting: [InboxItem] { items.filter { !leaving.contains($0.id) } }

    var count: Int { waiting.count }

    /// Hides an item that is leaving, until `remove` takes it for good or `keep` brings it back.
    func setAside(_ item: InboxItem) {
        leaving.insert(item.id)
    }

    /// Brings back an item that was leaving ("Anulează").
    func keep(_ item: InboxItem) {
        leaving.remove(item.id)
    }

    /// Re-reads the inbox folder.
    func refresh() {
        let contents = inbox?.contents() ?? ShareInbox.Contents()
        let fresh = contents.items
        if Set(fresh.map(\.id)).subtracting(items.map(\.id)).isEmpty == false { arrivals += 1 }
        let changed = fresh != items
        if changed { items = fresh }
        leaving.formIntersection(fresh.map(\.id))
        if contents.unreadable != unreadable { unreadable = contents.unreadable }
        loadPreviews()
        if changed { announceChange() }
    }

    /// Removes something that couldn't be opened.
    func remove(_ item: UnreadableInboxItem) {
        try? inbox?.removeUnreadable(item.id)
        unreadable.removeAll { $0.id == item.id }
    }

    /// Removes an item once it was filed or the person dismissed it.
    func remove(_ item: InboxItem) {
        try? inbox?.remove(item.id)
        items.removeAll { $0.id == item.id }
        leaving.remove(item.id)
        previews[item.id] = nil
        thumbnails[item.id] = nil
        announceChange()
    }

    func fileURLs(of item: InboxItem) -> [URL] {
        inbox?.fileURLs(of: item) ?? []
    }

    /// The row an item shows in De verificat (`InboxWording`).
    func row(for item: InboxItem, lockedCategories: Set<String>, isSessionUnlocked: Bool) -> InboxWording.Row {
        InboxWording.row(for: item, preview: previews[item.id], lockedCategories: lockedCategories, isSessionUnlocked: isSessionUnlocked)
    }

    /// Listens for the share extension's "something arrived" signal.
    func startObserving() {
        guard !isObserving else { return }
        isObserving = true
        let center = CFNotificationCenterGetDarwinNotifyCenter()
        CFNotificationCenterAddObserver(center, nil, { _, _, _, _, _ in
            Task { @MainActor in IntakeInbox.shared.refresh() }
        }, AppGroup.inboxDidChangeNotification as CFString, nil, .deliverImmediately)
    }

    /// Waits until every waiting item has been read (for tests).
    func previewsSettled() async {
        while let task = previewing { await task.value }
    }

    // MARK: Previews

    /// Picks up what was already learned, forgets what left, and reads what is new.
    private func loadPreviews() {
        let ids = Set(items.map(\.id))
        for id in previews.keys where !ids.contains(id) { previews[id] = nil }
        for id in thumbnails.keys where !ids.contains(id) { thumbnails[id] = nil }
        guard let inbox else { return }
        for item in items where previews[item.id] == nil {
            guard let preview = inbox.preview(of: item) else { continue }
            previews[item.id] = preview
            if preview.hasThumbnail, let url = inbox.thumbnailURL(of: item), let image = UIImage(contentsOfFile: url.path()) {
                thumbnails[item.id] = image
            }
        }
        readMissing()
    }

    /// Reads, one after another, the items the phone hasn't read yet.
    private func readMissing() {
        guard previewing == nil, let inbox, let reader else { return }
        guard items.contains(where: { previews[$0.id] == nil }) else { return }
        previewing = Task { [weak self] in
            while let self, let item = self.items.first(where: { self.previews[$0.id] == nil }) {
                let files = inbox.fileURLs(of: item)
                let read = await reader(item, files)
                guard self.items.contains(where: { $0.id == item.id }) else { continue }
                try? inbox.savePreview(read.preview, thumbnail: read.thumbnail, for: item)
                var preview = read.preview
                preview.hasThumbnail = read.thumbnail != nil
                self.previews[item.id] = preview
                if let data = read.thumbnail, let image = UIImage(data: data) { self.thumbnails[item.id] = image }
            }
            self?.previewing = nil
        }
    }

    private func announceChange() {
        NotificationCenter.default.post(name: ShareInbox.didChangeNotification, object: nil)
    }
}

extension View {
    /// Keeps the share inbox and widget taps in step with the app: on launch,
    /// whenever the app comes back to the foreground, and when the share
    /// extension sends something. Attach once, near the root.
    func intakeHandoff() -> some View {
        modifier(IntakeHandoffModifier())
    }
}

private struct IntakeHandoffModifier: ViewModifier {
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.modelContext) private var context

    func body(content: Content) -> some View {
        content
            .task {
                IntakeInbox.shared.startObserving()
                sync()
            }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active { sync() }
            }
    }

    private func sync() {
        IntakeInbox.shared.refresh()
        // Widget taps from iOS 26, where the widget extension can't reach the database.
        IntentEngine.applyQueuedWidgetCompletions(in: context)
    }
}
