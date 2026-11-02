import SwiftUI

/// The type scale. Every style is built on a system text style, so it follows
/// Dynamic Type all the way to the accessibility sizes. Never use fixed point sizes.
enum DSTextStyle: CaseIterable, Sendable {
    /// Hero numbers and the largest headlines inside content (not navigation titles).
    case display
    /// Screen-level headline inside content.
    case title
    /// Card and section titles.
    case sectionTitle
    /// Row titles and emphasized labels.
    case headline
    /// Default reading text.
    case body
    /// Secondary lines under a title.
    case subheadline
    /// Supporting notes, field hints.
    case footnote
    /// Badges, metadata.
    case caption
    /// Small emphasized labels such as field captions.
    case captionEmphasized

    var font: Font {
        switch self {
        case .display: .system(.largeTitle, weight: .bold)
        case .title: .system(.title2, weight: .bold)
        case .sectionTitle: .system(.title3, weight: .semibold)
        case .headline: .headline
        case .body: .body
        case .subheadline: .subheadline
        case .footnote: .footnote
        case .caption: .caption
        case .captionEmphasized: .system(.caption, weight: .semibold)
        }
    }

    /// Large sizes get slightly tighter tracking, like Apple's own large titles in content.
    var tracking: CGFloat {
        switch self {
        case .display: -0.6
        case .title: -0.3
        default: 0
        }
    }

    var defaultColor: Color {
        switch self {
        case .subheadline, .footnote, .caption, .captionEmphasized: DS.Palette.secondaryLabel
        default: DS.Palette.label
        }
    }
}

extension View {
    /// Applies a design-system text style.
    /// - Parameter numeric: Use tabular digits so numbers line up in columns and don't jitter when they change.
    func dsFont(_ style: DSTextStyle, numeric: Bool = false) -> some View {
        modifier(DSFontModifier(style: style, numeric: numeric))
    }
}

private struct DSFontModifier: ViewModifier {
    let style: DSTextStyle
    let numeric: Bool

    func body(content: Content) -> some View {
        content
            .font(numeric ? style.font.monospacedDigit() : style.font)
            .tracking(style.tracking)
            .foregroundStyle(style.defaultColor)
    }
}
