import SwiftUI

/// A standard row: optional icon well, title, optional subtitle, and a trailing accessory.
/// At least 44 pt tall at every text size. At accessibility text sizes the trailing
/// value moves under the title instead of squeezing it.
///
/// Wrap it in a `Button` or `NavigationLink` to make it tappable; the row reads as one
/// VoiceOver element either way.
struct DSListRow<Trailing: View>: View {
    let title: Text
    var subtitle: Text?
    var systemImage: String?
    var tint: Color = DS.Palette.accent
    /// A document row: its first page's picture (or its symbol) in place of the icon well.
    var thumbnail: DSThumbnailWell?
    var showsChevron: Bool = false
    @ViewBuilder var trailing: Trailing


    var body: some View {
        HStack(spacing: DS.Space.s) {
            if let thumbnail {
                thumbnail
            } else if let systemImage {
                DSIconWell(systemImage: systemImage, tint: tint)
            }

            DSAdaptiveStack(spacing: DS.Space.s, stackedSpacing: DS.Space.xxs) {
                titleBlock
                    .frame(maxWidth: .infinity, alignment: .leading)
                trailing
                    .dsFont(.subheadline)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if showsChevron {
                Image(systemName: "chevron.forward")
                    .font(.system(.footnote, weight: .semibold))
                    .foregroundStyle(DS.Palette.tertiaryLabel)
                    .accessibilityHidden(true)
            }
        }
        .padding(.vertical, DS.Space.xs)
        .frame(minHeight: 44)
        .contentShape(.rect)
        .accessibilityElement(children: .combine)
    }

    private var titleBlock: some View {
        VStack(alignment: .leading, spacing: 2) {
            title
                .dsFont(.headline)
            if let subtitle {
                subtitle
                    .dsFont(.subheadline)
            }
        }
    }
}

extension DSListRow where Trailing == EmptyView {
    init(
        _ title: LocalizedStringKey,
        subtitle: LocalizedStringKey? = nil,
        systemImage: String? = nil,
        tint: Color = DS.Palette.accent,
        showsChevron: Bool = false
    ) {
        self.init(
            title: Text(title),
            subtitle: subtitle.map { Text($0) },
            systemImage: systemImage,
            tint: tint,
            showsChevron: showsChevron,
            trailing: { EmptyView() }
        )
    }
}

extension DSListRow where Trailing == Text {
    /// A row with a trailing value, e.g. "Kilometraj · 84.200 km".
    init(
        _ title: LocalizedStringKey,
        value: Text,
        subtitle: LocalizedStringKey? = nil,
        systemImage: String? = nil,
        tint: Color = DS.Palette.accent,
        showsChevron: Bool = false
    ) {
        self.init(
            title: Text(title),
            subtitle: subtitle.map { Text($0) },
            systemImage: systemImage,
            tint: tint,
            showsChevron: showsChevron,
            trailing: { value }
        )
    }
}
