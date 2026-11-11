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
/// `PersistenceController` tells it both as it follows the mirroring's events (`SyncEvent`); a
/// container it doesn't run, a test's, is always whole. Joining two copies of a record waits too
/// (`RecordsMeet`): what is still on its way may point at the copy that would go. When it
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

        var isWhole: Bool { !firstDownloadPending && !settingUp && !downloading }
    }

    /// One container's arrival, kept while the container lives.
    private struct Entry {
        weak var container: ModelContainer?
        let arrival: CloudArrival
    }

    private static let arrivals = Mutex<[ObjectIdentifier: Entry]>([:])

    /// The arrival of `container`'s binder; one per container. A container opened again starts
    /// again, whole until it is told otherwise.
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

    /// Follows one of the mirroring's events for `container`.
    static func follow(_ event: SyncEvent, in container: ModelContainer) {
        of(container).change(in: container) { state in
            let running = event.finishedAt == nil
            switch event.kind {
            case .setup: state.settingUp = running
            case .download: state.downloading = running
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
