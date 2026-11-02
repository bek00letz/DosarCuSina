import SwiftData
import SwiftUI

/// The app's side of the App Group handoff: items shared from other apps
/// waiting in "De verificat", and widget taps waiting to be applied.
///
/// Refreshes when the app comes to the foreground and the moment the share
/// extension posts that something arrived. Attach `.intakeHandoff()` once near
/// the root so this runs whatever tab is open.
@MainActor
@Observable
final class IntakeInbox {
    static let shared = IntakeInbox()

    /// Items waiting for review, newest first.
    private(set) var items: [InboxItem] = []
    /// Bumps every time something new arrives, for the share practice.
    private(set) var arrivals = 0

    @ObservationIgnored let inbox: ShareInbox?
    @ObservationIgnored private var isObserving = false

    init(inbox: ShareInbox? = .shared()) {
        self.inbox = inbox
        self.items = inbox?.items() ?? []
    }

    var count: Int { items.count }

    /// Re-reads the inbox folder.
    func refresh() {
        let fresh = inbox?.items() ?? []
        if Set(fresh.map(\.id)).subtracting(items.map(\.id)).isEmpty == false { arrivals += 1 }
        if fresh != items { items = fresh }
    }

    /// Removes an item once it was filed or the person dismissed it.
    func remove(_ item: InboxItem) {
        try? inbox?.remove(item.id)
        items.removeAll { $0.id == item.id }
    }

    func fileURLs(of item: InboxItem) -> [URL] {
        inbox?.fileURLs(of: item) ?? []
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
