import SwiftUI

// A screen's own sheets and full-screen covers, presented so the shell's router knows they are
// up (`ShellRouter.hasSheet`, `ShellSheetQueue`). A route from a notification, a widget, a link
// or a search result then never pushes under one: it closes them, the top one first, each once
// the one above has finished closing, and lands when the last has gone; while one holds work
// the person hasn't saved (a form's changes, through `dsDiscardGuard`, or a sheet that must be
// answered, `keepsRoutesWaiting`), it waits for the person to close them instead.
//
// Every sheet and cover a screen presents goes through `dsSheet` or `dsFullScreenCover` (the
// `sheet-outside-router` check), and a system picker shown by a binding (photos, files) through
// `dsPresents`. The shell's own sheet is `ShellRouter.sheet`.
//
// Each is drawn behind the lock of the screen that presents it (`EnvironmentValues.screenLock`,
// set by the screen's gate), so a sheet of a locked screen lives inside its gate.

extension View {
    /// A sheet the router knows about, shown while `isPresented` is true.
    func dsSheet<Shown: View>(isPresented: Binding<Bool>, onDismiss: (() -> Void)? = nil, keepsRoutesWaiting: Bool = false,
                              @ViewBuilder content: @escaping () -> Shown) -> some View {
        modifier(ScreenSheet(item: ScreenSheetFlag.binding(isPresented), style: .sheet, keepsRoutesWaiting: keepsRoutesWaiting,
                             onDismiss: onDismiss) { _ in content() })
    }

    /// A sheet the router knows about, shown for `item` while it isn't nil.
    func dsSheet<Item: Identifiable, Shown: View>(item: Binding<Item?>, onDismiss: (() -> Void)? = nil, keepsRoutesWaiting: Bool = false,
                                                  @ViewBuilder content: @escaping (Item) -> Shown) -> some View {
        modifier(ScreenSheet(item: item, style: .sheet, keepsRoutesWaiting: keepsRoutesWaiting, onDismiss: onDismiss, shown: content))
    }

    /// A full-screen cover the router knows about, shown while `isPresented` is true.
    func dsFullScreenCover<Shown: View>(isPresented: Binding<Bool>, onDismiss: (() -> Void)? = nil, keepsRoutesWaiting: Bool = false,
                                        @ViewBuilder content: @escaping () -> Shown) -> some View {
        modifier(ScreenSheet(item: ScreenSheetFlag.binding(isPresented), style: .fullScreen, keepsRoutesWaiting: keepsRoutesWaiting,
                             onDismiss: onDismiss) { _ in content() })
    }

    /// A full-screen cover the router knows about, shown for `item` while it isn't nil.
    func dsFullScreenCover<Item: Identifiable, Shown: View>(item: Binding<Item?>, onDismiss: (() -> Void)? = nil, keepsRoutesWaiting: Bool = false,
                                                            @ViewBuilder content: @escaping (Item) -> Shown) -> some View {
        modifier(ScreenSheet(item: item, style: .fullScreen, keepsRoutesWaiting: keepsRoutesWaiting, onDismiss: onDismiss, shown: content))
    }

    /// How big a sheet opens where there is room around it (an iPad, a wide window): a page, as
    /// tall as the screen allows, so a form shows its rows and its pinned action at once, never
    /// a strip sized to what a scroll view would like (a few points). Every sheet takes it, the
    /// shell's (`ShellRouter.sheet`) and a screen's own (`dsSheet`), from here; on an iPhone, or
    /// in a narrow window, a sheet is the system's and its own detents apply.
    func dsSheetSizing() -> some View {
        presentationSizing(.page)
    }

    /// Tells the router a system picker is up while `isPresented` is true (`.photosPicker`,
    /// `.fileImporter`): a route closes it before it lands. Put it beside the picker, with the
    /// same binding.
    func dsPresents(_ isPresented: Binding<Bool>) -> some View {
        modifier(SystemPresentation(isPresented: isPresented))
    }
}

/// What a screen's own sheet gives what it shows (`EnvironmentValues.screenSheet`): a form in it
/// says through it that it holds unsaved work (`dsDiscardGuard`), so a route waits for the person.
struct ScreenSheetHandle {
    let id: UUID
    let router: ShellRouter

    @MainActor func holdsWork(_ holds: Bool) {
        router.screenSheet(id, holdsWork: holds)
    }
}

extension EnvironmentValues {
    /// The sheet this view is shown in, when the router knows it; nil outside one.
    @Entry var screenSheet: ScreenSheetHandle? = nil
}

// MARK: - Implementation

private enum ScreenSheetStyle {
    case sheet, fullScreen
}

/// `isPresented` as an item, so one modifier presents both kinds.
private enum ScreenSheetFlag: Identifiable {
    case shown
    var id: Self { self }

    static func binding(_ isPresented: Binding<Bool>) -> Binding<ScreenSheetFlag?> {
        Binding { isPresented.wrappedValue ? .shown : nil } set: { isPresented.wrappedValue = $0 != nil }
    }
}

private struct ScreenSheet<Item: Identifiable, Shown: View>: ViewModifier {
    @Binding var item: Item?
    let style: ScreenSheetStyle
    let keepsRoutesWaiting: Bool
    let onDismiss: (() -> Void)?
    let shown: (Item) -> Shown

    @Environment(ShellRouter.self) private var router: ShellRouter?
    /// The lock of the screen that presents it: a sheet of a locked screen lives inside its gate.
    @Environment(\.screenLock) private var lock
    @State private var id = UUID()

    @ViewBuilder
    func body(content: Content) -> some View {
        switch style {
        case .sheet:
            content.sheet(item: $item, onDismiss: dismissed) { presented($0).dsSheetSizing() }
        case .fullScreen:
            content.fullScreenCover(item: $item, onDismiss: dismissed) { presented($0) }
        }
    }

    private func presented(_ value: Item) -> some View {
        // Behind the presenting screen's lock (`EnvironmentValues.screenLock`): when that lock
        // comes back while it is up, it shows the locked state with "Închide", and what it held
        // goes unsaved.
        RouteLockGate(lock, inSheet: true) { shown(value) }
            .environment(\.screenSheet, router.map { ScreenSheetHandle(id: id, router: $0) })
            .onAppear {
                router?.screenSheetDidAppear(id, waitsByItself: keepsRoutesWaiting) { item = nil }
            }
    }

    /// Its dismissal completed, however it closed.
    private func dismissed() {
        router?.screenSheetDidDismiss(id)
        onDismiss?()
    }
}

private struct SystemPresentation: ViewModifier {
    @Binding var isPresented: Bool

    @Environment(ShellRouter.self) private var router: ShellRouter?
    @State private var id = UUID()

    func body(content: Content) -> some View {
        content.onChange(of: isPresented, initial: true) { _, isUp in
            if isUp {
                router?.screenSheetDidAppear(id, waitsByItself: false) { isPresented = false }
            } else {
                router?.screenSheetDidDismiss(id)
            }
        }
    }
}
