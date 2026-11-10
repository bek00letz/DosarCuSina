import SwiftUI
import UIKit

/// What covers the app right now, if anything.
enum LockCover: Equatable {
    /// The app lock: nothing of the app shows or can be reached until Face ID.
    case lock
    /// The picture in the app switcher: the app is leaving the screen while
    /// locked content could be on it.
    case privacy

    /// The one rule for covering the app.
    /// - The app lock covers everything while the session is closed.
    /// - Leaving the screen covers the app whenever the app lock is on, or a
    ///   section lock is on and the session is open (a locked section could be
    ///   showing). Not while a Face ID prompt is up: that also leaves the screen.
    static func decide(
        appLockEnabled: Bool,
        anySectionLocked: Bool,
        isSessionUnlocked: Bool,
        isActive: Bool,
        isAuthenticating: Bool
    ) -> LockCover? {
        if appLockEnabled, !isSessionUnlocked { return .lock }
        guard !isActive, !isAuthenticating else { return nil }
        if appLockEnabled || (anySectionLocked && isSessionUnlocked) { return .privacy }
        return nil
    }
}

/// Shows the lock and the app-switcher cover in a window of their own, above
/// every window of the app's scene, so sheets, full-screen flows, alerts and
/// menus all stay under it and none of them can be reached or seen.
struct LockWindowHost: UIViewRepresentable {
    let cover: LockCover?
    /// The app's own scene phase, which the lock window's screens follow.
    let scenePhase: ScenePhase
    let vault: BiometricVaultManager

    func makeCoordinator() -> LockWindowController { LockWindowController() }

    func makeUIView(context: Context) -> SceneProbe {
        let probe = SceneProbe()
        probe.onWindow = { [weak coordinator = context.coordinator] window in
            coordinator?.attach(to: window)
        }
        return probe
    }

    func updateUIView(_ probe: SceneProbe, context: Context) {
        context.coordinator.vault = vault
        context.coordinator.scenePhase = scenePhase
        if let window = probe.window { context.coordinator.attach(to: window) }
        context.coordinator.show(cover)
    }

    /// An invisible view that reports the window it lands in.
    final class SceneProbe: UIView {
        var onWindow: ((UIWindow) -> Void)?

        override func didMoveToWindow() {
            super.didMoveToWindow()
            isUserInteractionEnabled = false
            if let window { onWindow?(window) }
        }
    }
}

/// Owns the window the lock and the cover are drawn in.
///
/// Covering is never animated: the cover is whole from its first frame, so nothing of the
/// app shows through it on its way in, and switching between the lock and the app-switcher
/// cover is just as immediate. Uncovering gives taps back to the app at once and fades the
/// cover out; the window goes when that fade has ended, not after a set time. Covering again
/// during the fade stops it where it is: the fade's end then hides nothing.
@MainActor
final class LockWindowController {
    /// Makes `change` with the cover's fade and calls `completion` once the fade has ended
    /// (its last frame drawn, the cover gone from the screen). Tests end it when they choose.
    typealias Fade = @MainActor (_ change: () -> Void, _ completion: @escaping @MainActor () -> Void) -> Void

    /// The design system's fade, a short one with Reduce Motion, which completes either way.
    static let systemFade: Fade = { change, completion in
        let animation = DS.Motion.animation(DS.Motion.standard, reduceMotion: UIAccessibility.isReduceMotionEnabled)
        withAnimation(animation, completionCriteria: .removed, change) { completion() }
    }

    var vault: BiometricVaultManager?
    var scenePhase: ScenePhase {
        get { state.scenePhase }
        set { state.scenePhase = newValue }
    }
    private weak var appWindow: UIWindow?
    private var window: UIWindow?
    private let state = LockLayerState()
    private let fade: Fade
    /// Changes whenever the cover does, so only the fade of the latest uncovering hides the window.
    private var generation = 0

    init(fade: @escaping Fade = LockWindowController.systemFade) {
        self.fade = fade
    }

    func attach(to appWindow: UIWindow) {
        guard appWindow !== window else { return }
        self.appWindow = appWindow
        if let pending = state.cover { show(pending) }
    }

    /// The window the lock and the cover are drawn in, once it exists.
    var coverWindow: UIWindow? { window }

    /// Called on every update of the app's view, so showing the same thing again changes
    /// nothing: in particular, an update that still says "no cover" never starts the fade again.
    func show(_ cover: LockCover?) {
        guard let scene = appWindow?.windowScene else {
            state.cover = cover
            return
        }
        if let cover {
            generation += 1
            let window = self.window ?? makeWindow(in: scene)
            let wasHidden = window.isHidden
            var whole = Transaction()
            whole.disablesAnimations = true
            withTransaction(whole) { state.cover = cover }
            window.isUserInteractionEnabled = true
            window.isHidden = false
            if cover == .lock {
                window.makeKey()
                if wasHidden { UIAccessibility.post(notification: .screenChanged, argument: window.rootViewController?.view) }
            }
        } else if state.cover != nil {
            generation += 1
            let uncovering = generation
            // Taps reach the app at once; the cover fades out, then the window goes.
            window?.isUserInteractionEnabled = false
            appWindow?.makeKey()
            fade({ state.cover = nil }) { [weak self] in self?.fadeDidEnd(uncovering) }
        }
    }

    /// The fade of an uncovering has ended: the window goes, unless the app was covered
    /// again since.
    private func fadeDidEnd(_ uncovering: Int) {
        guard uncovering == generation, state.cover == nil else { return }
        window?.isHidden = true
    }

    private func makeWindow(in scene: UIWindowScene) -> UIWindow {
        let window = UIWindow(windowScene: scene)
        window.windowLevel = .alert + 1
        window.backgroundColor = .clear
        let root = LockLayer(state: state)
            .environment(vault ?? BiometricVaultManager.shared)
            .environment(\.locale, .dosarDefault)
        let host = UIHostingController(rootView: root)
        host.view.backgroundColor = .clear
        host.view.accessibilityViewIsModal = true
        window.rootViewController = host
        window.isHidden = true
        self.window = window
        return window
    }
}

@MainActor
@Observable
final class LockLayerState {
    var cover: LockCover?
    var scenePhase: ScenePhase = .active
}

/// The content of the lock window.
private struct LockLayer: View {
    let state: LockLayerState

    var body: some View {
        ZStack {
            switch state.cover {
            case .lock?: AppLockView().transition(.opacity)
            case .privacy?: PrivacyCover().transition(.opacity)
            case nil: Color.clear
            }
        }
        // No animation of its own: the controller covers at once and fades out (`LockWindowController`).
        .environment(\.scenePhase, state.scenePhase)
    }
}
