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
@MainActor
final class LockWindowController {
    var vault: BiometricVaultManager?
    var scenePhase: ScenePhase {
        get { state.scenePhase }
        set { state.scenePhase = newValue }
    }
    private weak var appWindow: UIWindow?
    private var window: UIWindow?
    private let state = LockLayerState()
    private var hideTask: Task<Void, Never>?

    func attach(to appWindow: UIWindow) {
        guard appWindow !== window else { return }
        self.appWindow = appWindow
        if let pending = state.cover { show(pending) }
    }

    /// The window the lock and the cover are drawn in, once it exists.
    var coverWindow: UIWindow? { window }

    /// Called on every update of the app's view, so showing the same thing again
    /// changes nothing: in particular, a pending hide is never cancelled by an
    /// update that still says "no cover".
    func show(_ cover: LockCover?) {
        guard let scene = appWindow?.windowScene else {
            state.cover = cover
            return
        }
        if let cover {
            hideTask?.cancel()
            hideTask = nil
            let window = self.window ?? makeWindow(in: scene)
            let wasHidden = window.isHidden
            state.cover = cover
            window.isUserInteractionEnabled = true
            window.isHidden = false
            if cover == .lock {
                window.makeKey()
                if wasHidden { UIAccessibility.post(notification: .screenChanged, argument: window.rootViewController?.view) }
            }
        } else if state.cover != nil {
            state.cover = nil
            // Taps reach the app at once; the layer fades out, then the window goes.
            window?.isUserInteractionEnabled = false
            appWindow?.makeKey()
            hideTask = Task { [weak self] in
                try? await Task.sleep(for: .milliseconds(400))
                guard !Task.isCancelled, let self, self.state.cover == nil else { return }
                self.window?.isHidden = true
            }
        }
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
            case .privacy?: PrivacyCover()
            case nil: Color.clear
            }
        }
        .dsAnimation(value: state.cover == .lock)
        .environment(\.scenePhase, state.scenePhase)
    }
}
