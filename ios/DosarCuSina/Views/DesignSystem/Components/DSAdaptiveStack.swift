import SwiftUI

/// Side by side when everything fits on one line at its natural width, one under
/// the other otherwise. The one layout for a row that has to give way to large
/// text or a narrow screen: a label and its value, a value and its buttons, a row
/// of buttons. It decides by measuring, not by the text size, so short content
/// stays on one line even at the accessibility sizes and long content moves down
/// at any size, and nothing is ever cut off or pushed past the screen's edge.
///
/// The content is laid out once (unlike `ViewThatFits`), so a field or a button
/// keeps its state when the row changes shape.
struct DSAdaptiveStack<Content: View>: View {
    let horizontalAlignment: HorizontalAlignment
    let verticalAlignment: VerticalAlignment
    let spacing: CGFloat
    /// Space between the pieces once they are stacked; the side-by-side spacing when `nil`.
    let stackedSpacing: CGFloat?
    let content: Content

    init(
        horizontalAlignment: HorizontalAlignment = .leading,
        verticalAlignment: VerticalAlignment = .center,
        spacing: CGFloat = DS.Space.s,
        stackedSpacing: CGFloat? = nil,
        @ViewBuilder content: () -> Content
    ) {
        self.horizontalAlignment = horizontalAlignment
        self.verticalAlignment = verticalAlignment
        self.spacing = spacing
        self.stackedSpacing = stackedSpacing
        self.content = content()
    }

    var body: some View {
        DSAdaptiveStackLayout(
            horizontal: HStackLayout(alignment: verticalAlignment, spacing: spacing),
            vertical: VStackLayout(alignment: horizontalAlignment, spacing: stackedSpacing ?? spacing)
        ) {
            content
        }
    }
}

/// The layout behind `DSAdaptiveStack`: an `HStackLayout` when the pieces' natural
/// widths fit the width offered, a `VStackLayout` otherwise.
struct DSAdaptiveStackLayout: Layout {
    let horizontal: HStackLayout
    let vertical: VStackLayout

    /// Whether the pieces fit side by side in `width` at their natural size.
    func fitsSideBySide(in width: CGFloat?, subviews: Subviews) -> Bool {
        guard let width, width.isFinite else { return true }
        var cache = horizontal.makeCache(subviews: subviews)
        let natural = horizontal.sizeThatFits(proposal: .unspecified, subviews: subviews, cache: &cache)
        return natural.width <= width + 0.5
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        if fitsSideBySide(in: proposal.width, subviews: subviews) {
            var stack = horizontal.makeCache(subviews: subviews)
            return horizontal.sizeThatFits(proposal: proposal, subviews: subviews, cache: &stack)
        }
        var stack = vertical.makeCache(subviews: subviews)
        return vertical.sizeThatFits(proposal: proposal, subviews: subviews, cache: &stack)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        if fitsSideBySide(in: bounds.width, subviews: subviews) {
            var stack = horizontal.makeCache(subviews: subviews)
            horizontal.placeSubviews(in: bounds, proposal: proposal, subviews: subviews, cache: &stack)
        } else {
            var stack = vertical.makeCache(subviews: subviews)
            vertical.placeSubviews(in: bounds, proposal: proposal, subviews: subviews, cache: &stack)
        }
    }
}
