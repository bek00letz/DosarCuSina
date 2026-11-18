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

    // MARK: The toast, the wells and drawings

    private var toastWords: some View {
        WordsBesideAction(spacing: DS.Space.s) {
            Text(verbatim: "Am salvat „Revizie periodică”. Următoarea e pe 3 mai 2027.").frame(maxWidth: .infinity, alignment: .leading)
            Text(verbatim: "Anulează").padding(.horizontal, DS.Space.xs)
        }
    }

    @Test func theToastsButtonStaysBesideItsWordsAtTheStandardSize() {
        let toast = size(of: toastWords, width: 343, typeSize: .large)
        let words = size(of: Text(verbatim: "Am salvat „Revizie periodică”. Următoarea e pe 3 mai 2027."), width: 343 - 120, typeSize: .large)
        #expect(toast.height <= words.height + 1, "Side by side: as tall as the words beside the button")
    }

    @Test func theToastsButtonMovesUnderItsWordsAtTheLargestSize() {
        let toast = size(of: toastWords, width: 343, typeSize: .accessibility5)
        let button = size(of: Text(verbatim: "Anulează").padding(.horizontal, DS.Space.xs), width: 343, typeSize: .accessibility5)
        let words = size(of: Text(verbatim: "Am salvat „Revizie periodică”. Următoarea e pe 3 mai 2027."), width: 343, typeSize: .accessibility5)
        #expect(toast.width <= 343.5)
        #expect(toast.height >= words.height + button.height - 1, "Stacked: the words across the width, the button under them")
    }

    @Test("A row's symbol and thumbnail stop growing before the accessibility sizes, so its words keep the row")
    func wellsStopGrowing() {
        for well in [AnyView(DSIconWell(systemImage: "car.fill")), AnyView(DSThumbnailWell(image: nil, systemImage: "doc"))] {
            let largest = size(of: well, width: 375, typeSize: .xxxLarge)
            let accessibility = size(of: well, width: 375, typeSize: .accessibility5)
            #expect(accessibility.width <= largest.width + 0.5)
        }
    }

    @Test("The onboarding's drawing of the share sheet fits a phone at every size", arguments: [DynamicTypeSize.large, .accessibility3, .accessibility5])
    func shareDrawingFits(typeSize: DynamicTypeSize) {
        let width: CGFloat = 375 - 2 * DS.Space.m
        #expect(size(of: AppRowIllustration(), width: width, typeSize: typeSize).width <= width + 0.5)
    }

    @Test("Every screen's content keeps one readable width, which grows with the text")
    func oneReadableWidth() {
        let page = Color.clear.frame(height: 10).dsReadableWidth()
        let standard = size(of: page, width: 1366, typeSize: .large)
        #expect(standard.width >= 1366 - 0.5, "Centred in the whole width")
        #expect(DS.ReadableWidth.text.points < 1366 && DS.ReadableWidth.grid.points > DS.ReadableWidth.text.points)
    }

    /// A passport's long travel line under „Valabil până la” pushed „Copiază” under the date.
    /// What is said under a value takes no part in whether its buttons fit beside it: the row
    /// is the value and its button on one line, then the note at the row's width.
    @Test("A line under a value never moves its button away from it")
    func aNoteUnderAValueKeepsTheButtonBesideIt() {
        let note = "Bun de călătorit până pe 14 septembrie 2033, cu șase luni înainte să expire"
        let plain = size(of: DSActionValueRow(title: Text(verbatim: "Valabil până la"), value: "14 martie 2034", action: .copy), width: 375)
        let withNote = size(of: DSActionValueRow(title: Text(verbatim: "Valabil până la"), value: "14 martie 2034", action: .copy,
                                                 note: Text(verbatim: note)), width: 375)
        let noteAlone = size(of: Text(verbatim: note).dsFont(.subheadline, numeric: true), width: 375)
        #expect(withNote.height <= plain.height + noteAlone.height + 4, "The note adds only its own lines; the button stays beside the date")
        #expect(withNote.width <= 375.5)
    }

    /// The binder's plan, by the room it has: never a device's model or size.
    @Test("The binder's boxes: two on a phone, square three or four on a wide screen, one at accessibility sizes")
    func boxGridPlan() {
        #expect(DSBoxGrid.plan(room: CGSize(width: 390, height: 844), isRegularWidth: false, isAccessibilitySize: false)
            == .init(columns: 2, squares: false))
        #expect(DSBoxGrid.plan(room: CGSize(width: 1032, height: 1376), isRegularWidth: true, isAccessibilitySize: false)
            == .init(columns: 3, squares: true), "Taller than wide: three")
        #expect(DSBoxGrid.plan(room: CGSize(width: 1376, height: 1032), isRegularWidth: true, isAccessibilitySize: false)
            == .init(columns: 4, squares: true), "Wider than tall: four")
        #expect(DSBoxGrid.plan(room: CGSize(width: 1376, height: 1032), isRegularWidth: true, isAccessibilitySize: true)
            == .init(columns: 1, squares: false))

        let box = DSBox(title: "VW Golf 2018", systemImage: "car.fill", tint: .blue, statusText: "Totul e în regulă", tone: .allGood)
        let square = size(of: box.dsAtLeastSquare(true), width: 300)
        #expect(abs(square.height - 300) < 1, "As tall as it is wide")
        let narrow = size(of: box.dsAtLeastSquare(true), width: 300, typeSize: .xxxLarge)
        #expect(narrow.height >= 300, "Never shorter than wide, taller when its words need it")
    }
}
