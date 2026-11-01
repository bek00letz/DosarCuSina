import SwiftUI

/// The basic content surface: a continuous-corner card on the grouped background.
///
/// The card declares itself as the container shape, so anything inside that uses
/// `ConcentricRectangle()` (icon wells, inner tiles, buttons) gets concentric corners
/// automatically: inner radius = card radius − padding.
struct DSCard<Content: View>: View {
    var padding: CGFloat = DS.Space.m
    var radius: CGFloat = DS.Radius.card
    @ViewBuilder var content: Content

    init(padding: CGFloat = DS.Space.m, radius: CGFloat = DS.Radius.card, @ViewBuilder content: () -> Content) {
        self.padding = padding
        self.radius = radius
        self.content = content()
    }

    var body: some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(DS.Palette.surface, in: .rect(cornerRadius: radius, style: .continuous))
            .containerShape(.rect(cornerRadius: radius, style: .continuous))
            .dsHairlineBorder(RoundedRectangle(cornerRadius: radius, style: .continuous))
    }
}

/// A rounded square holding an SF Symbol, used at the leading edge of rows and tiles.
/// Its corners follow the enclosing container shape so they stay concentric.
struct DSIconWell: View {
    let systemImage: String
    var tint: Color = DS.Palette.accent
    /// Visual size scales with Dynamic Type.
    @ScaledMetric(relativeTo: .body) private var side: CGFloat = 34

    init(systemImage: String, tint: Color = DS.Palette.accent) {
        self.systemImage = systemImage
        self.tint = tint
    }

    var body: some View {
        Image(systemName: systemImage)
            .font(.system(.body, weight: .semibold))
            .imageScale(.medium)
            .symbolRenderingMode(.hierarchical)
            .foregroundStyle(tint)
            .frame(width: side, height: side)
            .background(tint.opacity(0.14), in: ConcentricRectangle(corners: .concentric(minimum: 8), isUniform: true))
            .accessibilityHidden(true)
    }
}
