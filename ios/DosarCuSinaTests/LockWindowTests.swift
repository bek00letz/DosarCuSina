import Testing
import UIKit
@testable import DosarCuSina

/// The window the lock and the app-switcher cover are drawn in. The tests run inside
/// the app, so they use its scene. They show the app-switcher cover, which draws the
/// same window as the lock without starting Face ID.
@MainActor
@Suite("The lock window", .serialized)
struct LockWindowTests {

    private func makeAppWindow() throws -> UIWindow {
        let scene = try #require(
            UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first,
            "The tests run inside the app"
        )
        return UIWindow(windowScene: scene)
    }

    @Test("Once uncovered, taps reach the app at once and the window goes, whatever updates follow")
    func uncoveringGivesTheAppBack() async throws {
        let appWindow = try makeAppWindow()
        let controller = LockWindowController()
        controller.attach(to: appWindow)
        controller.show(.privacy)
        let cover = try #require(controller.coverWindow)
        #expect(!cover.isHidden)
        #expect(cover.isUserInteractionEnabled)

        controller.show(nil)
        #expect(!cover.isUserInteractionEnabled, "Taps go to the app right away")
        // The app's view updates several times right after Face ID; none of them may
        // keep the empty window on top.
        controller.show(nil)
        controller.show(nil)
        let hide = try #require(controller.pendingHide, "An update after uncovering left the hide in place")
        await hide.value
        #expect(!hide.isCancelled, "No update cancelled the hide")
        #expect(cover.isHidden, "The window is gone once its fade has ended")
        withExtendedLifetime(appWindow) {}
    }

    @Test("Covering again during the fade keeps the cover")
    func coveringAgainDuringTheFade() async throws {
        let appWindow = try makeAppWindow()
        let controller = LockWindowController()
        controller.attach(to: appWindow)
        controller.show(.privacy)
        controller.show(nil)
        let hide = try #require(controller.pendingHide)
        controller.show(.privacy)
        await hide.value
        let cover = try #require(controller.coverWindow)
        #expect(!cover.isHidden)
        #expect(cover.isUserInteractionEnabled)
        withExtendedLifetime(appWindow) {}
    }
}
