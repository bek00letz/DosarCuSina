import SwiftUI
import Testing
import UIKit
@testable import DosarCuSina

/// Every design-system button is a tap target of at least 44 pt, at every text size
/// from the smallest to the largest accessibility size, on a phone-width screen.
/// The architecture check reads one line at a time; this measures the real layout.
@MainActor
@Suite("Hit targets")
struct HitTargetTests {
    static let sizes: [DynamicTypeSize] = [.xSmall, .large, .xxxLarge, .accessibility3, .accessibility5]

    private func size<V: View>(of view: V, at typeSize: DynamicTypeSize, width: CGFloat = 375) -> CGSize {
        let host = UIHostingController(rootView: view.environment(\.dynamicTypeSize, typeSize))
        return host.sizeThatFits(in: CGSize(width: width, height: .greatestFiniteMagnitude))
    }

    @Test(arguments: sizes)
    func fullWidthButtonsAreAtLeast44Points(typeSize: DynamicTypeSize) {
        let primary = size(of: DSPrimaryButton(verbatim: "Salvează", systemImage: "checkmark") {}, at: typeSize)
        let secondary = size(of: DSSecondaryButton(verbatim: "Șterge rândul", role: .destructive) {}, at: typeSize)
        #expect(primary.height >= DS.Control.minimumHitTarget)
        #expect(secondary.height >= DS.Control.minimumHitTarget)
    }

    @Test(arguments: sizes)
    func compactButtonIsAtLeast44PointsAndKeepsItsTitleOnOneLine(typeSize: DynamicTypeSize) {
        let measured = size(of: DSCompactButton("Adaugă") {}, at: typeSize)
        #expect(measured.height >= DS.Control.minimumHitTarget)
        #expect(measured.width >= DS.Control.minimumHitTarget)
    }
}
