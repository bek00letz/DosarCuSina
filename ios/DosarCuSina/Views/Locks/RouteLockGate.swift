import SwiftData
import SwiftUI

/// Draws a route's screen or a sheet behind the lock it declares (`RouteLock`): a section's
/// screen or a flow that writes into it shows only while its category is open, wherever it was
/// opened from. Over a sheet, the locked state keeps a way to close it.
struct RouteLockGate<Content: View>: View {
    let lock: RouteLock
    var inSheet = false
    @ViewBuilder var content: Content

    init(_ lock: RouteLock, inSheet: Bool = false, @ViewBuilder content: () -> Content) {
        self.lock = lock
        self.inSheet = inSheet
        self.content = content()
    }

    var body: some View {
        switch lock {
        case .open, .drawnByItsScreen:
            content
        case .section(let id):
            SectionIDLockGate(assetID: id, inSheet: inSheet) { content }
        }
    }
}

/// `LockGate` for a section known by its id. A section that is gone opens its screen, which
/// says so.
struct SectionIDLockGate<Content: View>: View {
    let inSheet: Bool
    @ViewBuilder var content: Content
    @Query private var matches: [Asset]
    @Environment(\.dismiss) private var dismiss

    init(assetID: UUID, inSheet: Bool = false, @ViewBuilder content: () -> Content) {
        self.inSheet = inSheet
        self.content = content()
        let id = assetID
        _matches = Query(filter: #Predicate<Asset> { $0.id == id })
    }

    var body: some View {
        if let asset = matches.first {
            if inSheet {
                LockGate(asset: asset) { content }
                    .lockedSheetChrome(asset: asset, dismiss: dismiss)
            } else {
                LockGate(asset: asset) { content }
            }
        } else {
            content
        }
    }
}

private extension View {
    /// A sheet's locked state sits in a stack of its own, with "Închide", until it opens; the
    /// flow it opens to brings its own.
    @ViewBuilder
    func lockedSheetChrome(asset: Asset, dismiss: DismissAction) -> some View {
        LockedSheetChrome(asset: asset, dismiss: dismiss) { self }
    }
}

private struct LockedSheetChrome<Content: View>: View {
    let asset: Asset
    let dismiss: DismissAction
    @ViewBuilder var content: Content
    @Environment(BiometricVaultManager.self) private var vault
    @Query private var templates: [CategoryTemplate]

    init(asset: Asset, dismiss: DismissAction, @ViewBuilder content: () -> Content) {
        self.asset = asset
        self.dismiss = dismiss
        self.content = content()
        let key = asset.templateKey
        _templates = Query(filter: #Predicate<CategoryTemplate> { $0.key == key })
    }

    var body: some View {
        if vault.isLocked(asset, template: templates.first) {
            NavigationStack {
                content
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Închide") { dismiss() }
                        }
                    }
            }
        } else {
            content
        }
    }
}
