import Testing
import UIKit
@testable import DosarCuSina

/// The window the lock and the app-switcher cover are drawn in. The tests run inside
/// the app, so they use its scene. They show the app-switcher cover, which draws the
/// same window as the lock without starting Face ID.
@MainActor
@Suite("The lock window", .serialized)
struct LockWindowTests {

    /// A fade the test ends when it chooses: the change is made at once, the end waits.
    @MainActor
    final class HeldFade {
        private(set) var started = 0
        private var ends: [@MainActor () -> Void] = []

        var fade: LockWindowController.Fade {
            { [self] change, completion in
                change()
                started += 1
                ends.append(completion)
            }
        }

        /// Ends the fade that started `index`-th (0 for the first).
        func end(_ index: Int) { ends[index]() }
    }

    private func makeAppWindow() throws -> UIWindow {
        let scene = try #require(
            UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first,
            "The tests run inside the app"
        )
        return UIWindow(windowScene: scene)
    }

    @Test("Covering is immediate: no fade on the way in, or between the two covers")
    func coveringIsImmediate() throws {
        let appWindow = try makeAppWindow()
        let held = HeldFade()
        let controller = LockWindowController(fade: held.fade)
        controller.attach(to: appWindow)
        controller.show(.privacy)
        let cover = try #require(controller.coverWindow)
        #expect(!cover.isHidden)
        #expect(cover.isUserInteractionEnabled)
        controller.show(.privacy)
        #expect(held.started == 0, "Only uncovering fades")
        withExtendedLifetime(appWindow) {}
    }

    @Test("Once uncovered, taps reach the app at once and the window goes when its fade ends")
    func uncoveringGivesTheAppBack() throws {
        let appWindow = try makeAppWindow()
        let held = HeldFade()
        let controller = LockWindowController(fade: held.fade)
        controller.attach(to: appWindow)
        controller.show(.privacy)
        let cover = try #require(controller.coverWindow)

        controller.show(nil)
        #expect(!cover.isUserInteractionEnabled, "Taps go to the app right away")
        #expect(!cover.isHidden, "The cover stays while it fades")
        // The app's view updates several times right after Face ID; none of them starts
        // the fade again or keeps the empty window on top.
        controller.show(nil)
        controller.show(nil)
        #expect(held.started == 1)
        #expect(!cover.isHidden)

        held.end(0)
        #expect(cover.isHidden, "The window is gone once its fade has ended")
        withExtendedLifetime(appWindow) {}
    }

    @Test("Covering again during the fade keeps the cover, whenever the old fade ends")
    func coveringAgainDuringTheFade() throws {
        let appWindow = try makeAppWindow()
        let held = HeldFade()
        let controller = LockWindowController(fade: held.fade)
        controller.attach(to: appWindow)
        controller.show(.privacy)
        controller.show(nil)
        controller.show(.privacy)
        let cover = try #require(controller.coverWindow)

        held.end(0)
        #expect(!cover.isHidden, "The old fade's end hides nothing")
        #expect(cover.isUserInteractionEnabled)

        // Uncovered again: only the new fade's end lets the window go.
        controller.show(nil)
        held.end(0)
        #expect(!cover.isHidden)
        held.end(1)
        #expect(cover.isHidden)
        withExtendedLifetime(appWindow) {}
    }

    @Test("The design system's fade ends by itself, and only then the window goes", .timeLimit(.minutes(1)))
    func theRealFadeEnds() async throws {
        let appWindow = try makeAppWindow()
        var ended: CheckedContinuation<Void, Never>?
        var hiddenBeforeTheEnd: Bool?
        let controller = LockWindowController { change, completion in
            LockWindowController.systemFade(change) {
                completion()
                ended?.resume()
                ended = nil
            }
        }
        controller.attach(to: appWindow)
        controller.show(.privacy)
        let cover = try #require(controller.coverWindow)
        // The cover is drawn, as it is by the time anyone unlocks: there is something to fade.
        cover.rootViewController?.view.layoutIfNeeded()
        await withCheckedContinuation { continuation in
            ended = continuation
            controller.show(nil)
            hiddenBeforeTheEnd = cover.isHidden
        }
        #expect(hiddenBeforeTheEnd == false, "Not before the fade has run")
        #expect(cover.isHidden)
        withExtendedLifetime(appWindow) {}
    }
}
