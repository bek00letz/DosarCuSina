import Foundation
import SwiftData
import Synchronization

/// Whether what iCloud is bringing has all arrived on this device: the one signal the app's own
/// steps that act on what is missing read before they act.
///
/// A binder arrives from iCloud a batch at a time, in no order the app chooses: on a new device
/// the household's rental income declaration can come before the tenancy it is for. A step that
/// removes something because what calls for it is missing (`HouseholdRules.reconcile`) would
/// then remove the person's record, and the removal would go back to every device. So it waits
/// while the binder may still be on its way: the first download for the account hasn't finished
/// on this phone (`PersistenceController.binderMayBeArriving`, from the sync events and what the
/// phone remembers, `SyncHealthTracker`), or a download from iCloud is under way (a later batch).
/// A container that syncs starts out not known to be whole (`awaitFirstDownload`): what changed
/// on the person's other devices while this one was closed comes in this launch's first
/// download, so it is whole once that download has finished, not before the mirroring's first
/// report. `PersistenceController` tells it all of this as it opens the store and follows the
/// mirroring's events (`SyncEvent`); a container it doesn't run, a test's, is always whole.
/// Joining two copies of a record waits too (`RecordsMeet`): what is still on its way may point
/// at the copy that would go. When it
/// becomes whole it says so (`didBecomeWhole`), and `SyncedChanges` settles again. Read from any
/// thread (a backup brought in off the main thread asks too).
final class CloudArrival: Sendable {
    /// Posted with `object` the container when what was on its way has all arrived.
    static let didBecomeWhole = Notification.Name("CloudArrival.didBecomeWhole")

    private struct State {
        /// The first download for the account hasn't finished on this phone.
        var firstDownloadPending = false
        /// Setting up the mirroring, or a download, is under way.
        var settingUp = false
        var downloading = false
        /// The store opened to sync and no download has finished since: not known yet.
        var awaitingThisLaunch = false

        var isWhole: Bool { !firstDownloadPending && !settingUp && !downloading && !awaitingThisLaunch }
    }

    /// One container's arrival, kept while the container lives.
    private struct Entry {
        weak var container: ModelContainer?
        let arrival: CloudArrival
    }

    private static let arrivals = Mutex<[ObjectIdentifier: Entry]>([:])

    /// The arrival of `container`'s binder; one per container. A container opened again starts
    /// again, whole until it is told otherwise (a container that syncs is told at once).
    static func of(_ container: ModelContainer) -> CloudArrival {
        arrivals.withLock { arrivals in
            let key = ObjectIdentifier(container)
            if let entry = arrivals[key], entry.container === container { return entry.arrival }
            let arrival = CloudArrival()
            arrivals = arrivals.filter { $0.value.container != nil }
            arrivals[key] = Entry(container: container, arrival: arrival)
            return arrival
        }
    }

    private let state = Mutex(State())

    /// Whether nothing is still on its way.
    var isWhole: Bool {
        state.withLock { $0.isWhole }
    }

    /// Whether the first download for the account is still to finish on this phone.
    static func firstDownload(pending: Bool, in container: ModelContainer) {
        of(container).change(in: container) { $0.firstDownloadPending = pending }
    }

    /// `container` opened to sync: not known to be whole until a download finishes in it.
    static func awaitFirstDownload(in container: ModelContainer) {
        of(container).change(in: container) { $0.awaitingThisLaunch = true }
    }

    /// Follows one of the mirroring's events for `container`. A download that finished well
    /// brought what was waiting in iCloud; one that failed (offline, iCloud busy) says nothing
    /// about it, and the next one is waited for.
    static func follow(_ event: SyncEvent, in container: ModelContainer) {
        of(container).change(in: container) { state in
            let running = event.finishedAt == nil
            switch event.kind {
            case .setup: state.settingUp = running
            case .download:
                state.downloading = running
                if !running, event.succeeded { state.awaitingThisLaunch = false }
            case .upload: break
            }
        }
    }

    /// Applies `change`, and says so when it left the binder whole.
    private func change(in container: ModelContainer, _ change: (inout State) -> Void) {
        let becameWhole = state.withLock { state in
            let before = state.isWhole
            change(&state)
            return !before && state.isWhole
        }
        if becameWhole { NotificationCenter.default.post(name: Self.didBecomeWhole, object: container) }
    }
}
