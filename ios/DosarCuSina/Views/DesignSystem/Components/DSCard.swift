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

/// A small picture of a document's first page at the leading edge of a row, so items
/// that look alike can be told apart ("De verificat"). Until there is a picture, or
/// when there must not be one (a locked item, a bank card), it holds the symbol
/// instead, in the same place and size, so the row never jumps when the picture arrives.
struct DSThumbnailWell: View {
    let image: Image?
    let systemImage: String
    var tint: Color = DS.Palette.accent
    /// A page needs a little more room than a symbol to be recognisable; it scales with Dynamic Type.
    @ScaledMetric(relativeTo: .body) private var side: CGFloat = 44

    var body: some View {
        ZStack {
            if let image {
                image
                    .resizable()
                    .scaledToFill()
                    .frame(width: side, height: side)
                    .transition(.opacity)
            } else {
                Image(systemName: systemImage)
                    .font(.system(.body, weight: .semibold))
                    .imageScale(.medium)
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(tint)
                    .transition(.opacity)
            }
        }
        .frame(width: side, height: side)
        .background(image == nil ? tint.opacity(0.14) : DS.Palette.surface)
        .clipShape(shape)
        .dsHairlineBorder(shape)
        .dsAnimation(DS.Motion.quick, value: image == nil)
        .accessibilityHidden(true)
    }

    /// Concentric with the card around the row, like `DSIconWell`.
    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: DS.Radius.concentric(outer: DS.Radius.card, padding: DS.Space.m, minimum: 8), style: .continuous)
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
