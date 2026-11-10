import SwiftUI

/// The one bar a screen's or a sheet's main action is pinned to: full width, above the home
/// indicator (and above the keyboard while one is up), on a soft material. What goes with the
/// action sits in it too, in one order: a note above (why it can't be pressed yet, why the last
/// save didn't work), the main action, then the other actions under it. Only `dsPinnedAction`
/// draws it, so every pinned action has the same height, material and keyboard behaviour.
private struct DSBottomBar<Note: View, Action: View, Secondary: View>: View {
    let note: Note
    let action: Action
    let secondary: Secondary

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.s) {
            note
            action
            secondary
        }
        .padding(.horizontal, DS.Space.m)
        .padding(.vertical, DS.Space.s)
        .frame(maxWidth: 640)
        .frame(maxWidth: .infinity)
        .background(.bar)
    }
}

extension View {
    /// Pins a screen's or a sheet's main action to its bottom edge, so it shows whatever
    /// the sheet's height and however long the content above it, which scrolls under it.
    /// A main action is never left at the end of scrolling content.
    func dsPinnedAction<Action: View>(@ViewBuilder _ action: () -> Action) -> some View {
        dsPinnedAction(action, secondary: { EmptyView() }, note: { EmptyView() })
    }

    /// The main action pinned with the other actions of the screen under it
    /// ("Fă copia fără parolă", "Anulează vizita").
    func dsPinnedAction<Action: View, Secondary: View>(
        @ViewBuilder _ action: () -> Action,
        @ViewBuilder secondary: () -> Secondary
    ) -> some View {
        dsPinnedAction(action, secondary: secondary, note: { EmptyView() })
    }

    /// The main action pinned with a note above it: why it can't be pressed yet, or why the
    /// last save didn't work, said where the person is looking when they press it.
    func dsPinnedAction<Action: View, Note: View>(
        @ViewBuilder _ action: () -> Action,
        @ViewBuilder note: () -> Note
    ) -> some View {
        dsPinnedAction(action, secondary: { EmptyView() }, note: note)
    }

    /// The main action pinned with the other actions under it and a note above it.
    func dsPinnedAction<Action: View, Secondary: View, Note: View>(
        @ViewBuilder _ action: () -> Action,
        @ViewBuilder secondary: () -> Secondary,
        @ViewBuilder note: () -> Note
    ) -> some View {
        safeAreaInset(edge: .bottom) {
            DSBottomBar(note: note(), action: action(), secondary: secondary())
        }
    }
}
