import SwiftUI
import Testing
import UIKit
@testable import DosarCuSina

/// Rows give way to large text and narrow screens through one layout,
/// `DSAdaptiveStack`, and nothing is cut off or pushed past the screen's edge.
@MainActor
@Suite("Adaptive layout")
struct AdaptiveLayoutTests {
    private func size<V: View>(of view: V, width: CGFloat, typeSize: DynamicTypeSize = .large) -> CGSize {
        let host = UIHostingController(rootView: view.environment(\.dynamicTypeSize, typeSize))
        return host.sizeThatFits(in: CGSize(width: width, height: .greatestFiniteMagnitude))
    }

    private var pair: some View {
        DSAdaptiveStack(spacing: DS.Space.s) {
            Text(verbatim: "Total de plată")
            Text(verbatim: "1.234,56 lei")
        }
    }

    @Test func sideBySideWhenItFitsStackedWhenItDoesnt() {
        let wide = size(of: pair, width: 600)
        let narrow = size(of: pair, width: 90)
        #expect(narrow.height > wide.height * 1.5, "Too narrow for one line: the pieces stack")
        #expect(narrow.width <= 90.5)
    }

    @Test func shortContentStaysOnOneLineEvenAtTheLargestSize() {
        let row = DSAdaptiveStack { Text(verbatim: "A"); Text(verbatim: "B") }
        let large = size(of: row, width: 375, typeSize: .accessibility5)
        let single = size(of: Text(verbatim: "A"), width: 375, typeSize: .accessibility5)
        #expect(large.height <= single.height + 1)
    }

    @Test(arguments: [DynamicTypeSize.large, .accessibility3, .accessibility5])
    func valueButtonsNeverRunOffTheScreen(typeSize: DynamicTypeSize) {
        let row = DSValueWithActions {
            Text(verbatim: "RO49 AAAA 1B31 0075 9384 0000")
        } actions: {
            Button {} label: { DSValueActionLabel(title: "Copiază", systemImage: "doc.on.doc") }.buttonStyle(.bordered)
            Button {} label: { DSValueActionLabel(title: "Arată", systemImage: "eye") }.buttonStyle(.bordered)
        }
        #expect(size(of: row, width: 320, typeSize: typeSize).width <= 320.5)
    }

    @Test(arguments: [DynamicTypeSize.large, .accessibility5])
    func badgesAndChipsWrapInsteadOfClipping(typeSize: DynamicTypeSize) {
        let badge = DSStatusBadge(.overdue, text: Text(verbatim: "Depășit de 3 zile, cu grație"))
        let chip = DSChip(verbatim: "Asigurare locuință facultativă", isSelected: false) {}
        let width: CGFloat = 160
        let badgeSize = size(of: badge, width: width, typeSize: typeSize)
        let chipSize = size(of: chip, width: width, typeSize: typeSize)
        #expect(badgeSize.width <= width + 0.5)
        #expect(chipSize.width <= width + 0.5)
        if typeSize.isAccessibilitySize {
            // The whole text is there: taller than one line, not cut to one.
            let oneLine = size(of: DSStatusBadge(.overdue, text: Text(verbatim: "Azi")), width: width, typeSize: typeSize)
            #expect(badgeSize.height > oneLine.height)
        }
    }
}
