import SwiftUI

// The `DS` namespace, its motion and the delayed spinner are in ios/Shared/DSMotion.swift;
// spacing, controls and corners in ios/Shared/DSLayout.swift, beside the full-width buttons
// (DSButtons.swift) and the pinned action (DSBottomBar.swift), so the widgets and the
// share extension use them too.

// MARK: - Hairlines

extension DS {
    /// One physical pixel, for separators and card outlines.
    struct Hairline: View {
        @Environment(\.displayScale) private var displayScale

        var body: some View {
            Rectangle()
                .fill(Color(uiColor: .separator))
                .frame(height: 1 / displayScale)
                .accessibilityHidden(true)
        }
    }
}

extension View {
    /// A one-pixel outline along `shape`, used to separate a surface from its background.
    /// It strengthens automatically when Increase Contrast is on.
    func dsHairlineBorder<S: InsettableShape>(_ shape: S) -> some View {
        modifier(DSHairlineBorder(shape: shape))
    }
}

private struct DSHairlineBorder<S: InsettableShape>: ViewModifier {
    let shape: S
    @Environment(\.displayScale) private var displayScale
    @Environment(\.colorSchemeContrast) private var contrast

    func body(content: Content) -> some View {
        content.overlay {
            shape
                .strokeBorder(
                    Color(uiColor: contrast == .increased ? .label : .separator)
                        .opacity(contrast == .increased ? 0.45 : 1),
                    lineWidth: 1 / displayScale
                )
                .accessibilityHidden(true)
        }
    }
}
