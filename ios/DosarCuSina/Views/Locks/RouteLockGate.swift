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
        case .unknownSection:
            UnknownSectionLockGate(inSheet: inSheet) { content }
        }
    }
}

// MARK: - A screen's own sheets

extension EnvironmentValues {
    /// The lock a screen's own sheets and full-screen covers are drawn behind (`dsSheet`,
    /// `dsFullScreenCover`): the section the screen shows, set by its gate (`LockGate`) or by a
    /// screen that draws its own locked state (`View.screenLock`). A sheet of a locked screen
    /// lives inside its gate, so when the lock comes back it shows the locked state, with
    /// "Închide", and nothing it held is saved.
    @Entry var screenLock: RouteLock = .open
}

extension View {
    /// Declares the lock this screen's own sheets are drawn behind (`EnvironmentValues.screenLock`).
    /// Every screen that decides a section's lock itself and presents a sheet declares it (the
    /// `sheet-outside-its-lock` check); `.open` for a screen whose sheets show nothing of a locked
    /// section.
    func screenLock(_ lock: RouteLock) -> some View {
        environment(\.screenLock, lock)
    }
}

/// `RouteLock.unknownSection`: drawn only while nothing of the binder is behind Face ID, or the
/// session is open (`BinderLocks`, which counts a section whose category hasn't arrived).
private struct UnknownSectionLockGate<Content: View>: View {
    let inSheet: Bool
    @ViewBuilder var content: Content
    @Environment(BiometricVaultManager.self) private var vault
    @Environment(\.dismiss) private var dismiss
    @Query private var templates: [CategoryTemplate]
    @Query(BinderLocks.sections) private var sections: [Asset]
    @Environment(\.modelContext) private var context

    init(inSheet: Bool, @ViewBuilder content: () -> Content) {
        self.inSheet = inSheet
        self.content = content()
    }

    var body: some View {
        let locks = BinderLocks(templates: templates, naming: sections.map(\.templateKey), in: context.container)
        if vault.isLocked(sectionIsSensitive: locks.anySectionLocked) {
            if inSheet {
                NavigationStack {
                    LockedSectionView.unnamedDocument
                        .toolbar {
                            ToolbarItem(placement: .cancellationAction) {
                                Button("Închide") { dismiss() }
                            }
                        }
                }
            } else {
                LockedSectionView.unnamedDocument
            }
        } else {
            content
                .screenLock(.unknownSection)
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
