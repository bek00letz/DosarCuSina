import SwiftUI

// Layout tokens for every target. The app, its widgets and its share extension all
// compile this file, with the full-width buttons and the pinned action bar beside it,
// so the share sheet is spaced and sized like the app.

// MARK: - Spacing (4/8 pt grid)

extension DS {
    /// Spacing on a 4 pt grid. Use the named steps; never a raw number.
    enum Space {
        /// 4 pt — between an icon and its label, inside dense rows.
        static let xxs: CGFloat = 4
        /// 8 pt — between related lines of text, chip gaps.
        static let xs: CGFloat = 8
        /// 12 pt — between rows inside a card.
        static let s: CGFloat = 12
        /// 16 pt — card padding and the screen's side margin.
        static let m: CGFloat = 16
        /// 20 pt — between a section header and the card under it.
        static let l: CGFloat = 20
        /// 24 pt — between sections.
        static let xl: CGFloat = 24
        /// 32 pt — around empty and error states.
        static let xxl: CGFloat = 32
    }
}

// MARK: - Controls

extension DS {
    /// Sizes for things people tap. `HitTargetTests` measures the DS buttons and
    /// field actions at several text sizes and checks each is at least `minimumHitTarget`.
    enum Control {
        /// The smallest tap target: 44 pt. A borderless button's label is its whole
        /// target, so its frame is at least this tall.
        static let minimumHitTarget: CGFloat = 44
        /// The label of a full-width button. The large control size adds padding
        /// above and below it, so the button is about 50 pt.
        static let fullWidthLabel: CGFloat = 34
        /// The label of a compact button beside a row. With the large control
        /// size's padding the button is at least 44 pt.
        static let compactLabel: CGFloat = 30
        /// The smallest height of a bar that floats over the content (the toast): its 44 pt
        /// button with a little room above and below. It grows with its words.
        static let floatingBar: CGFloat = minimumHitTarget + 2 * DS.Space.xxs
        /// The largest text size a symbol beside words grows to (an icon well, a row's
        /// thumbnail, a drawing of a row of apps): it follows the text up to the largest standard
        /// size and stops before the accessibility sizes, so the words beside it keep the row's
        /// width instead of being squeezed into a column.
        static let largestDecorationSize: DynamicTypeSize = .xxxLarge
    }
}

// MARK: - Readable width

extension DS {
    /// How wide a screen's content grows: on an iPad or a wide window, text and forms stay at a
    /// width that reads well and the screen's sides are left empty, as the system's own
    /// readable width does. Grows with the text size, so large text keeps as many words a line.
    enum ReadableWidth {
        /// Text, forms and a section's or a deadline's page.
        case text
        /// A grid of boxes (the binder): wider, for more columns, still never edge to edge.
        case grid

        /// At the standard text size; `dsReadableWidth` scales it with the text.
        var points: CGFloat {
            switch self {
            case .text: 672
            case .grid: 1024
            }
        }
    }
}

extension View {
    /// The one readable-width rule for every screen: the content is centred and grows no wider
    /// than `DS.ReadableWidth`, scaled with the text size. Put it on the content inside a
    /// screen's `ScrollView` (and the pinned bar uses it too), never a `frame(maxWidth:)` of a
    /// screen's own (the `readable-width` check).
    func dsReadableWidth(_ width: DS.ReadableWidth = .text) -> some View {
        modifier(DSReadableWidthModifier(width: width))
    }
}

private struct DSReadableWidthModifier: ViewModifier {
    let width: DS.ReadableWidth
    @ScaledMetric(relativeTo: .body) private var scale: CGFloat = 1

    func body(content: Content) -> some View {
        content
            .frame(maxWidth: width.points * scale)
            .frame(maxWidth: .infinity)
    }
}

// MARK: - Corner radii

extension DS {
    /// Corner radii. All corners are continuous (squircle) curves.
    enum Radius {
        /// Top-level cards and sheets' content blocks.
        static let card: CGFloat = 22
        /// Text fields, tiles inside cards, icon wells on rows.
        static let control: CGFloat = 12
        /// Small badges that are not capsules.
        static let badge: CGFloat = 8
        /// A bar that floats over the content (the toast): half its smallest height, so a bar of
        /// one line is a capsule and a taller one, at a large text size, keeps the same corners.
        static let floatingBar: CGFloat = DS.Control.floatingBar / 2

        /// The radius a child needs to stay concentric with its container:
        /// inner = outer − padding, never below `minimum`.
        ///
        /// Prefer `ConcentricRectangle` inside a `.containerShape(...)` when the
        /// child is laid out by SwiftUI; use this when you need the number.
        static func concentric(outer: CGFloat, padding: CGFloat, minimum: CGFloat = 4) -> CGFloat {
            max(outer - padding, minimum)
        }
    }
}
