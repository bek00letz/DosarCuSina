import SwiftUI

/// A selectable capsule, for filters and quick picks.
/// The visible capsule is compact, but the tap area is at least 44 pt tall.
struct DSChip: View {
    let title: Text
    var systemImage: String?
    var isSelected: Bool
    let action: () -> Void

    init(_ title: LocalizedStringKey, systemImage: String? = nil, isSelected: Bool, action: @escaping () -> Void) {
        self.title = Text(title)
        self.systemImage = systemImage
        self.isSelected = isSelected
        self.action = action
    }

    /// For titles that come from data (user-entered or template strings), which are not localized.
    init(verbatim title: String, systemImage: String? = nil, isSelected: Bool, action: @escaping () -> Void) {
        self.init(title: Text(verbatim: title), systemImage: systemImage, isSelected: isSelected, action: action)
    }

    init(title: Text, systemImage: String? = nil, isSelected: Bool, action: @escaping () -> Void) {
        self.title = title
        self.systemImage = systemImage
        self.isSelected = isSelected
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: DS.Space.xxs) {
                if let systemImage {
                    Image(systemName: systemImage)
                        .imageScale(.small)
                }
                title
                    .lineLimit(1)
            }
            .font(.system(.subheadline, weight: isSelected ? .semibold : .regular))
            .foregroundStyle(isSelected ? Color(uiColor: .systemBackground) : DS.Palette.label)
            .padding(.horizontal, DS.Space.s)
            .padding(.vertical, 7)
            .background(isSelected ? DS.Palette.label : DS.Palette.fill, in: .capsule)
            .frame(minHeight: 44)
        }
        .buttonStyle(.dsPressable)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .sensoryFeedback(.selection, trigger: isSelected)
    }
}

/// A horizontally scrolling row of single-selection chips, e.g. category filters.
/// Pass `nil` as a selectable item to offer an "all" chip.
struct DSChipBar<Item: Hashable>: View {
    let items: [Item]
    @Binding var selection: Item
    let title: (Item) -> Text
    var systemImage: (Item) -> String? = { _ in nil }

    var body: some View {
        ScrollView(.horizontal) {
            HStack(spacing: DS.Space.xs) {
                ForEach(items, id: \.self) { item in
                    chip(for: item)
                }
            }
            .padding(.horizontal, DS.Space.m)
        }
        .scrollIndicators(.hidden)
        .scrollClipDisabled()
        .accessibilityElement(children: .contain)
    }

    private func chip(for item: Item) -> some View {
        DSChip(title: title(item), systemImage: systemImage(item), isSelected: item == selection) {
            selection = item
        }
    }
}

// MARK: - Flow layout

/// Lays children out left to right and wraps onto new lines, like words in a paragraph.
/// Used for multi-choice chips.
struct DSFlowLayout: Layout {
    var spacing: CGFloat = DS.Space.xs
    var lineSpacing: CGFloat = DS.Space.xs

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = arrange(subviews: subviews, maxWidth: proposal.width ?? .infinity)
        let height = rows.map(\.height).reduce(0, +) + lineSpacing * CGFloat(max(rows.count - 1, 0))
        let width = rows.map(\.width).max() ?? 0
        return CGSize(width: proposal.width ?? width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let rows = arrange(subviews: subviews, maxWidth: bounds.width)
        var y = bounds.minY
        for row in rows {
            var x = bounds.minX
            for index in row.indices {
                let size = subviews[index].sizeThatFits(.unspecified)
                subviews[index].place(
                    at: CGPoint(x: x, y: y + (row.height - size.height) / 2),
                    proposal: ProposedViewSize(width: min(size.width, bounds.width), height: size.height)
                )
                x += size.width + spacing
            }
            y += row.height + lineSpacing
        }
    }

    private struct Row {
        var indices: [Int] = []
        var width: CGFloat = 0
        var height: CGFloat = 0
    }

    private func arrange(subviews: Subviews, maxWidth: CGFloat) -> [Row] {
        var rows: [Row] = []
        var current = Row()
        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(.unspecified)
            let needed = current.indices.isEmpty ? size.width : current.width + spacing + size.width
            if needed > maxWidth, !current.indices.isEmpty {
                rows.append(current)
                current = Row()
            }
            current.width = current.indices.isEmpty ? min(size.width, maxWidth) : current.width + spacing + size.width
            current.height = max(current.height, size.height)
            current.indices.append(index)
        }
        if !current.indices.isEmpty { rows.append(current) }
        return rows
    }
}
