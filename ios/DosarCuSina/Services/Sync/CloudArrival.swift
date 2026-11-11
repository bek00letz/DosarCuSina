import CoreData
import Foundation
import SwiftData
import Synchronization

/// Whether what iCloud is bringing has all arrived on this device: the one signal the app's own
/// steps that act on what is missing read before they act.
///
/// A binder arrives from iCloud a batch at a time, in no order the app chooses: on a new device
/// the household's rental income declaration can come before the tenancy it is for. A step that
/// removes something because what calls for it is missing (`HouseholdRules.reconcile`) would
/// then remove the person's record, and the removal would go back to every device. So it waits:
/// a store that syncs is whole once an import from iCloud has finished since it opened and none
/// is under way (`NSPersistentCloudKitContainer`'s events, followed by `SyncedChanges`). A store
/// that doesn't sync is always whole. Joining two copies of a record waits too (`RecordsMeet`):
/// what is still on its way may point at the copy that would go. Adding what the app itself
/// installs (the built-in categories) never waits. Read from any thread (a backup brought in off
/// the main thread asks too).
final class CloudArrival: Sendable {
    private struct State {
        /// An import from iCloud finished, so what was there when the store opened has come.
        var hasArrivedOnce = false
        /// Imports under way, by the event's id.
        var running: Set<UUID> = []
    }

    /// One container's arrival, kept while the container lives.
    private struct Entry {
        weak var container: ModelContainer?
        let arrival: CloudArrival
    }

    private static let arrivals = Mutex<[ObjectIdentifier: Entry]>([:])

    /// The arrival of `container`'s binder; one per container. A container opened again (sync
    /// turned on or off) starts again: nothing has arrived in it yet.
    static func of(_ container: ModelContainer) -> CloudArrival {
        arrivals.withLock { arrivals in
            let key = ObjectIdentifier(container)
            if let entry = arrivals[key], entry.container === container { return entry.arrival }
            let syncs = container.configurations.contains { $0.cloudKitContainerIdentifier != nil }
            let arrival = CloudArrival(syncs: syncs)
            arrivals = arrivals.filter { $0.value.container != nil }
            arrivals[key] = Entry(container: container, arrival: arrival)
            return arrival
        }
    }

    private let syncs: Bool
    private let state = Mutex(State())

    init(syncs: Bool) {
        self.syncs = syncs
    }

    /// Whether nothing is still on its way: no import under way, and, for a store that syncs, one
    /// has finished since it opened.
    var isWhole: Bool {
        state.withLock { $0.running.isEmpty && ($0.hasArrivedOnce || !syncs) }
    }

    /// What one of the store's iCloud events is to the binder's arrival.
    enum Stage: Sendable {
        /// Getting ready to sync, before the first import: nothing has come yet.
        case settingUp
        /// Bringing what other devices saved.
        case importing
        /// Anything else (sending this device's changes): nothing comes with it.
        case other
    }

    /// Follows one of the store's iCloud events. Returns true when an import has just finished
    /// and left the binder whole, so the steps that waited can run.
    @discardableResult
    func follow(event id: UUID, stage: Stage, hasEnded: Bool, succeeded: Bool) -> Bool {
        guard stage != .other else { return false }
        return state.withLock { state in
            guard hasEnded else {
                state.running.insert(id)
                return false
            }
            state.running.remove(id)
            // A failed import (no network) may have stopped half-way: what is here isn't all yet.
            guard stage == .importing, succeeded else { return false }
            state.hasArrivedOnce = true
            return state.running.isEmpty
        }
    }

    /// Follows the event a store's `NSPersistentCloudKitContainer.eventChangedNotification` carries.
    @discardableResult
    func follow(_ event: NSPersistentCloudKitContainer.Event) -> Bool {
        let stage: Stage = switch event.type {
        case .setup: .settingUp
        case .import: .importing
        default: .other
        }
        return follow(event: event.identifier, stage: stage, hasEnded: event.endDate != nil, succeeded: event.succeeded)
    }
}
