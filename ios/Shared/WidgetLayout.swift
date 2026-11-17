import SwiftUI

/// How the Urmează widget lays out each of its families, declared once: how many deadlines
/// each one shows and how much room a row and its „Gata” take, so every „Gata” is a full
/// 44 pt tap target (`DS.Control.minimumHitTarget`) in every size. The widget draws from it,
/// the timeline keeps as many rows as the largest family shows, and `WidgetLayoutTests`
/// checks that the rows fit the smallest widget of their family at the standard text size.
enum WidgetLayout {
    /// The widget's families, as WidgetKit names them.
    enum Family: CaseIterable, Sendable {
        case small
        case medium
        /// The Lock Screen's one line.
        case inline
        /// The Lock Screen's rectangle.
        case rectangular
    }

    /// How many deadlines a family shows.
    static func rows(in family: Family) -> Int {
        switch family {
        // One deadline, with its „Gata” under it; the Lock Screen shows the first one.
        case .small, .inline, .rectangular: 1
        // Two, each with a full 44 pt „Gata” beside it: three would leave each less than that.
        case .medium: 2
        }
    }

    /// Rows a timeline entry keeps: as many as the largest family shows.
    static var rowLimit: Int {
        Family.allCases.map(rows(in:)).max() ?? 1
    }

    /// The height of every „Gata”, and its smallest width: a full tap target.
    static let doneButtonSide: CGFloat = DS.Control.minimumHitTarget
    /// The medium widget's row: as tall as its „Gata”.
    static let rowHeight: CGFloat = doneButtonSide
    /// Between the medium widget's heading and its rows, between its rows, and between the
    /// small widget's lines.
    static let spacing: CGFloat = DS.Space.xxs
    /// Room left beside a „Gata” for its label (the space between its edge and its words).
    static let doneButtonPadding: CGFloat = DS.Space.s

    /// The height the medium widget's content takes, with a heading line of `headingLine`.
    static func mediumHeight(headingLine: CGFloat) -> CGFloat {
        let count = CGFloat(rows(in: .medium))
        return headingLine + count * (spacing + rowHeight)
    }

    /// The height the small widget's content takes at the least, with its lines one line each:
    /// the title (with the section's symbol beside it), the section, when, then „Gata”.
    static func smallHeight(title: CGFloat, subtitle: CGFloat, when: CGFloat) -> CGFloat {
        title + spacing + subtitle + spacing + when + spacing + doneButtonSide
    }
}

/// What „Gata” shows in the widget: its words and a check mark in a tinted capsule, a full
/// `WidgetLayout.doneButtonSide` tall and at least as wide. The capsule is drawn on the label
/// itself, so the whole 44 pt is both what shows and what takes the tap (a bordered button
/// style would add padding of its own around it). The widget wraps it in its button; the title
/// comes from the widget's own String Catalog.
struct WidgetDoneLabel: View {
    let title: Text

    var body: some View {
        Label { title } icon: { Image(systemName: "checkmark") }
            .font(.caption.weight(.semibold))
            .lineLimit(1)
            .padding(.horizontal, WidgetLayout.doneButtonPadding)
            .frame(minWidth: WidgetLayout.doneButtonSide, minHeight: WidgetLayout.doneButtonSide)
            .background(.tint.opacity(0.15), in: .capsule)
            .contentShape(.capsule)
    }
}
