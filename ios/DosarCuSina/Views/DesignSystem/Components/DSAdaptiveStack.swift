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
            horizontalAlignment: horizontalAlignment,
            verticalAlignment: verticalAlignment,
            spacing: spacing,
            stackedSpacing: stackedSpacing ?? spacing
        ) {
            content
        }
    }
}

/// The layout behind `DSAdaptiveStack`: a row when the pieces' natural widths fit
/// the width offered, a column otherwise. In a row, pieces that can grow (a
/// `frame(maxWidth: .infinity)`) share what is left; in a column every piece is
/// offered the whole width, so text wraps instead of running past the edge.
struct DSAdaptiveStackLayout: Layout {
    let horizontalAlignment: HorizontalAlignment
    let verticalAlignment: VerticalAlignment
    let spacing: CGFloat
    let stackedSpacing: CGFloat

    /// The width the pieces take side by side, at their natural size.
    private func naturalRowWidth(_ subviews: Subviews) -> CGFloat {
        let widths = subviews.map { $0.sizeThatFits(.unspecified).width }
        return widths.reduce(0, +) + spacing * CGFloat(max(subviews.count - 1, 0))
    }

    /// Whether the pieces fit side by side in `width`.
    func fitsSideBySide(in width: CGFloat?, subviews: Subviews) -> Bool {
        guard let width, width.isFinite else { return true }
        return naturalRowWidth(subviews) <= width + 0.5
    }

    /// Each piece's width in a row of `width`: its natural width, plus an equal
    /// share of what is left for the pieces that can grow.
    private func rowWidths(_ subviews: Subviews, width: CGFloat?) -> [CGFloat] {
        let natural = subviews.map { $0.sizeThatFits(.unspecified).width }
        guard let width, width.isFinite else { return natural }
        let growing = subviews.indices.filter { index in
            subviews[index].sizeThatFits(ProposedViewSize(width: .infinity, height: nil)).width > natural[index] + 0.5
        }
        let left = max(width - naturalRowWidth(subviews), 0)
        guard !growing.isEmpty, left > 0 else { return natural }
        let share = left / CGFloat(growing.count)
        return subviews.indices.map { growing.contains($0) ? natural[$0] + share : natural[$0] }
    }

    /// Where each piece of a row sits vertically, and the row's height.
    private func rowOffsets(_ subviews: Subviews, widths: [CGFloat]) -> (offsets: [CGFloat], height: CGFloat) {
        let dimensions = subviews.indices.map { subviews[$0].dimensions(in: ProposedViewSize(width: widths[$0], height: nil)) }
        let guides = dimensions.map { $0[verticalAlignment] }
        let line = guides.max() ?? 0
        let offsets = guides.map { line - $0 }
        let height = zip(offsets, dimensions).map { $0 + $1.height }.max() ?? 0
        return (offsets, height)
    }

    private func columnSizes(_ subviews: Subviews, width: CGFloat?) -> [CGSize] {
        subviews.map { $0.sizeThatFits(ProposedViewSize(width: width, height: nil)) }
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        guard !subviews.isEmpty else { return .zero }
        if fitsSideBySide(in: proposal.width, subviews: subviews) {
            let widths = rowWidths(subviews, width: proposal.width)
            let total = widths.reduce(0, +) + spacing * CGFloat(subviews.count - 1)
            return CGSize(width: total, height: rowOffsets(subviews, widths: widths).height)
        }
        let sizes = columnSizes(subviews, width: proposal.width)
        let height = sizes.map(\.height).reduce(0, +) + stackedSpacing * CGFloat(subviews.count - 1)
        return CGSize(width: proposal.width ?? (sizes.map(\.width).max() ?? 0), height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        guard !subviews.isEmpty else { return }
        if fitsSideBySide(in: bounds.width, subviews: subviews) {
            let widths = rowWidths(subviews, width: bounds.width)
            let (offsets, _) = rowOffsets(subviews, widths: widths)
            var x = bounds.minX
            for index in subviews.indices {
                subviews[index].place(at: CGPoint(x: x, y: bounds.minY + offsets[index]), proposal: ProposedViewSize(width: widths[index], height: nil))
                x += widths[index] + spacing
            }
            return
        }
        var y = bounds.minY
        for (index, size) in columnSizes(subviews, width: bounds.width).enumerated() {
            let width = min(size.width, bounds.width)
            let x: CGFloat
            switch horizontalAlignment {
            case .trailing: x = bounds.maxX - width
            case .center: x = bounds.midX - width / 2
            default: x = bounds.minX
            }
            subviews[index].place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(width: width, height: nil))
            y += size.height + stackedSpacing
        }
    }
}

