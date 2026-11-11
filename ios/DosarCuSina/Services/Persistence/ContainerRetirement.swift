import Foundation
import ObjectiveC
import SwiftData

/// Something outside a screen that keeps the store's container (or a context of its own on it):
/// Caută's index, the side effects (with Spotlight), what follows another device's changes, an
/// undo receipt. When the store opens again under another container (sync turned on or off,
/// examples coming in, the iCloud account changing), `PersistenceController` retires the old
/// one and every holder lets go of it at once, so nothing is written through it again and,
/// once nothing holds it, it is gone: a container that synced stops sending what the next one
/// writes.
@MainActor
protocol ContainerHolder: AnyObject {
    /// `container` was retired: let go of it now, and never write through it again.
    func containerRetired(_ container: ModelContainer)
}

/// Why a write was refused: the context belongs to a container the store no longer runs on.
public struct BinderReopened: LocalizedError, Equatable {
    public var errorDescription: String? {
        String(localized: "Dosarul s-a redeschis între timp, când s-a schimbat sincronizarea cu iCloud, așa că nu am salvat. Fă din nou ce voiai.",
               comment: "A save was refused because the binder reopened under a new container (iCloud sync changed) while the screen still used the old one.")
    }
}

/// The one "container retired" event, and what each container carries for its whole life:
/// whether it syncs, whether it was retired, and a way to know it is gone. Kept on the
/// container itself, so they go with it and a later container at the same address never
/// inherits them.
@MainActor
enum ContainerRetirement {
    private final class WeakHolder {
        weak var holder: (any ContainerHolder)?
        init(_ holder: any ContainerHolder) { self.holder = holder }
    }

    private static var holders: [WeakHolder] = []

    /// Tells `holder` when a container is retired, for as long as it lives.
    static func add(_ holder: any ContainerHolder) {
        holders.removeAll { $0.holder == nil }
        holders.append(WeakHolder(holder))
    }

    /// Retires `container`: from now on nothing saves through it (`isRetired`, checked where
    /// every save happens), and every holder lets go of it.
    static func retire(_ container: ModelContainer) {
        objc_setAssociatedObject(container, &Keys.retired, NSNumber(value: true), .OBJC_ASSOCIATION_RETAIN)
        holders.removeAll { $0.holder == nil }
        for entry in holders {
            entry.holder?.containerRetired(container)
        }
    }

    /// Whether `container` was retired. Safe from any thread.
    nonisolated static func isRetired(_ container: ModelContainer) -> Bool {
        (objc_getAssociatedObject(container, &Keys.retired) as? NSNumber)?.boolValue == true
    }

    /// Marks `container` as one that syncs with the person's iCloud.
    nonisolated static func markSyncing(_ container: ModelContainer) {
        objc_setAssociatedObject(container, &Keys.syncs, NSNumber(value: true), .OBJC_ASSOCIATION_RETAIN)
    }

    /// Whether `container` syncs with the person's iCloud. Safe from any thread.
    nonisolated static func syncs(_ container: ModelContainer) -> Bool {
        (objc_getAssociatedObject(container, &Keys.syncs) as? NSNumber)?.boolValue == true
    }

    /// Calls `gone` once `container` is released (on the main actor). The container itself is
    /// not kept.
    static func whenGone(_ container: ModelContainer, _ gone: @escaping @MainActor () -> Void) {
        objc_setAssociatedObject(container, &Keys.gone, GoneSignal(gone), .OBJC_ASSOCIATION_RETAIN)
    }

    private enum Keys {
        nonisolated(unsafe) static var retired: UInt8 = 0
        nonisolated(unsafe) static var syncs: UInt8 = 0
        nonisolated(unsafe) static var gone: UInt8 = 0
    }

    /// Goes with the container, and says so as it goes.
    private final class GoneSignal: @unchecked Sendable {
        let gone: @MainActor () -> Void
        init(_ gone: @escaping @MainActor () -> Void) { self.gone = gone }
        deinit {
            let gone = gone
            if Thread.isMainThread {
                MainActor.assumeIsolated { gone() }
            } else {
                Task { @MainActor in gone() }
            }
        }
    }
}
