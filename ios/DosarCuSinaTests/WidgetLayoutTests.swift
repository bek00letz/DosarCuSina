import SwiftUI
import Testing
import UIKit
@testable import DosarCuSina

/// The Urmează widget's „Gata” is a full 44 pt tap target in every size, and each family shows
/// only as many deadlines as fit beside it (`WidgetLayout`, the one place that says how many):
/// the medium widget two, the small one and the Lock Screen one.
@MainActor
@Suite("The widget's layout")
struct WidgetLayoutTests {
    /// The smallest Home Screen widgets an iPhone that runs iOS 26 draws (a 4.7-inch screen:
    /// small 148 × 148 pt, medium 321 × 148 pt), less WidgetKit's standard 16 pt margins.
    static let smallestContentHeight: CGFloat = 148 - 2 * 16

    private func lineHeight(_ style: UIFont.TextStyle, weight: UIFont.Weight = .regular) -> CGFloat {
        let traits = UITraitCollection(preferredContentSizeCategory: .large)
        let base = UIFont.preferredFont(forTextStyle: style, compatibleWith: traits)
        return ceil(UIFont.systemFont(ofSize: base.pointSize, weight: weight).lineHeight)
    }

    @Test("Each family shows as many rows as fit beside a full „Gata”, and the timeline keeps the most")
    func rowsPerFamily() {
        #expect(WidgetLayout.rows(in: .medium) == 2, "Two rows, so each „Gata” is 44 pt")
        #expect(WidgetLayout.rows(in: .small) == 1)
        #expect(WidgetLayout.rows(in: .inline) == 1 && WidgetLayout.rows(in: .rectangular) == 1, "The Lock Screen shows the first one")
        #expect(WidgetLayout.rowLimit == WidgetLayout.Family.allCases.map(WidgetLayout.rows(in:)).max())
    }

    @Test("„Gata” is 44 pt tall and at least as wide, at every text size", arguments: HitTargetTests.sizes)
    func doneIsAFullTapTarget(typeSize: DynamicTypeSize) {
        let host = UIHostingController(rootView: WidgetDoneLabel(title: Text(verbatim: "Gata")).environment(\.dynamicTypeSize, typeSize))
        let size = host.sizeThatFits(in: CGSize(width: 200, height: CGFloat.greatestFiniteMagnitude))
        #expect(size.height >= DS.Control.minimumHitTarget)
        #expect(size.width >= DS.Control.minimumHitTarget)
        if typeSize <= .large {
            #expect(size.height == WidgetLayout.doneButtonSide, "Exactly 44 pt where its words fit")
        }
        #expect(WidgetLayout.rowHeight >= WidgetLayout.doneButtonSide, "A medium row is as tall as its „Gata”")
    }

    @Test("The medium widget's heading and rows, and the small widget's lines with „Gata”, fit the smallest widget")
    func fitsTheSmallestWidget() {
        let medium = WidgetLayout.mediumHeight(headingLine: lineHeight(.caption1, weight: .semibold))
        #expect(medium <= Self.smallestContentHeight, "\(medium) pt in \(Self.smallestContentHeight) pt")
        // A row's two lines fit beside its „Gata”.
        #expect(lineHeight(.subheadline, weight: .semibold) + lineHeight(.caption1) <= WidgetLayout.rowHeight)

        let small = WidgetLayout.smallHeight(title: lineHeight(.headline), subtitle: lineHeight(.caption1),
                                             when: lineHeight(.subheadline, weight: .semibold))
        #expect(small <= Self.smallestContentHeight, "\(small) pt in \(Self.smallestContentHeight) pt")
    }
}
