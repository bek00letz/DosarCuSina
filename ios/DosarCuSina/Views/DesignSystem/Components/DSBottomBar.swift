import SwiftUI

/// A full-width action pinned above the home indicator on a soft material.
struct DSBottomBar<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        content
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
        safeAreaInset(edge: .bottom) { DSBottomBar { action() } }
    }
}
