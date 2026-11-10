import Foundation
import LocalAuthentication
import Observation
#if canImport(UIKit)
import UIKit
#endif

/// Face ID, Touch ID, Optic ID or the device passcode, behind a protocol so
/// tests can run without a person.
public protocol BiometricAuthenticating: Sendable {
    func biometryType() -> LABiometryType
    /// Throws `LAError` when the person cancels or authentication fails.
    func evaluate(localizedReason: String) async throws -> Bool
}

public struct SystemBiometricAuthenticator: BiometricAuthenticating {
    public init() {}

    public func biometryType() -> LABiometryType {
        let context = LAContext()
        var error: NSError?
        _ = context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error)
        return context.biometryType
    }

    /// Device-owner authentication: Face ID or Touch ID, with the passcode as fallback.
    public func evaluate(localizedReason: String) async throws -> Bool {
        let context = LAContext()
        context.localizedCancelTitle = String(localized: "Anulează")
        return try await context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: localizedReason)
    }
}

/// The outcome of an unlock attempt. Failing or cancelling never closes the
/// app or leaves the screen: the protected part stays closed and can be retried.
public enum UnlockResult: Sendable, Equatable {
    case success
    case failed
    case cancelled
}

/// The clock every lock timing counts on: how long the app was away, for the relock.
///
/// It counts on `ContinuousClock`, which keeps counting while the phone sleeps and which the
/// phone's date, time and time zone settings don't move. So a minute away is a minute whatever
/// the phone's clock says when the app comes back, and a night with the screen off counts as a
/// night. (`SuspendingClock` stops while the phone sleeps; `Date` follows the phone's clock.)
/// Tests give the vault a clock they move themselves.
public struct LockClock: Sendable {
    private let read: @Sendable () -> Duration

    /// A clock that reads `elapsed` as how long it has counted since a start of its own.
    public init(elapsed read: @escaping @Sendable () -> Duration) {
        self.read = read
    }

    /// How long the clock has counted since its own start. Only differences mean anything.
    public var elapsed: Duration { read() }

    /// The phone's clock for time away (`ContinuousClock`).
    public static let continuous: LockClock = {
        let start = ContinuousClock.now
        return LockClock { start.duration(to: .now) }
    }()
}

/// Two independent locks over one unlock session:
/// - the whole-app lock (`AppPreferences.appLockEnabled`, off by default);
/// - per-section locks (`CategoryTemplate.isSensitive`), on or off whatever the app lock says.
///
/// One successful authentication opens the session for both, so the person is
/// never asked twice in a row. The session closes when the app has been in the
/// background longer than `relockAfterBackground`, counted on `LockClock`, or on `lock()`.
@MainActor
@Observable
public final class BiometricVaultManager {
    public static let shared = BiometricVaultManager()

    /// How long the app may stay in the background before the session closes.
    public static let relockAfterBackground: Duration = .seconds(60)

    public private(set) var isSessionUnlocked = false
    /// An authentication prompt is on screen.
    public private(set) var isAuthenticating = false

    @ObservationIgnored private let authenticator: any BiometricAuthenticating
    @ObservationIgnored private let clock: LockClock
    @ObservationIgnored private let appLockEnabled: @MainActor () -> Bool
    /// When the app went to the background, on `clock`.
    @ObservationIgnored private var backgroundedAt: Duration?
    @ObservationIgnored private var inFlight: Task<UnlockResult, Never>?
    @ObservationIgnored private var observers: [any NSObjectProtocol] = []

    public init(
        authenticator: any BiometricAuthenticating = SystemBiometricAuthenticator(),
        clock: LockClock = .continuous,
        appLockEnabled: @escaping @MainActor () -> Bool = { AppPreferences.shared.appLockEnabled },
        observesAppLifecycle: Bool = true
    ) {
        self.authenticator = authenticator
        self.clock = clock
        self.appLockEnabled = appLockEnabled
        #if canImport(UIKit)
        if observesAppLifecycle {
            let center = NotificationCenter.default
            observers.append(center.addObserver(forName: UIApplication.didEnterBackgroundNotification, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.appDidEnterBackground() }
            })
            observers.append(center.addObserver(forName: UIApplication.willEnterForegroundNotification, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.appWillEnterForeground() }
            })
        }
        #endif
    }

    // MARK: State for screens

    /// The whole app is behind the lock right now.
    public var isAppLocked: Bool {
        appLockEnabled() && !isSessionUnlocked
    }

    /// A section is closed right now: it is marked sensitive and the session isn't open.
    public func isLocked(sectionIsSensitive: Bool) -> Bool {
        sectionIsSensitive && !isSessionUnlocked
    }

    public func isLocked(_ template: CategoryTemplate) -> Bool {
        isLocked(sectionIsSensitive: template.isSensitive)
    }

    // MARK: Unlock

    /// Asks for Face ID, Touch ID or the passcode. Calls made while a prompt is
    /// already showing wait for that prompt instead of opening a second one.
    @discardableResult
    public func unlock(reason: String) async -> UnlockResult {
        if isSessionUnlocked { return .success }
        if let inFlight { return await inFlight.value }
        let authenticator = authenticator
        let task = Task<UnlockResult, Never> {
            do {
                return try await authenticator.evaluate(localizedReason: reason) ? .success : .failed
            } catch let error as LAError {
                switch error.code {
                case .userCancel, .appCancel, .systemCancel: return .cancelled
                default: return .failed
                }
            } catch {
                return .failed
            }
        }
        inFlight = task
        isAuthenticating = true
        let result = await task.value
        inFlight = nil
        isAuthenticating = false
        if result == .success {
            isSessionUnlocked = true
            backgroundedAt = nil
        }
        return result
    }

    /// Asks for Face ID, Touch ID or the passcode for one look at a secret (a PIN
    /// code), always, even while the session is open. It never opens or closes
    /// the session: the answer is for this one reveal only.
    public func authenticateForReveal(reason: String) async -> UnlockResult {
        isAuthenticating = true
        defer { isAuthenticating = false }
        do {
            return try await authenticator.evaluate(localizedReason: reason) ? .success : .failed
        } catch let error as LAError {
            switch error.code {
            case .userCancel, .appCancel, .systemCancel: return .cancelled
            default: return .failed
            }
        } catch {
            return .failed
        }
    }

    /// Asks for Face ID or the passcode before the whole binder leaves the app
    /// or is replaced (a backup, "Înlocuiește tot"), whenever any lock is on.
    /// It asks every time, even with the session open, and never opens or
    /// closes the session. With no lock on, nothing is asked.
    public func confirmWholeBinder(anySectionLocked: Bool, reason: String) async -> UnlockResult {
        guard appLockEnabled() || anySectionLocked else { return .success }
        return await authenticateForReveal(reason: reason)
    }

    /// Asks for Face ID or the passcode before a document from a locked category leaves
    /// the phone ("Trimite"). It asks every time, even with the session open, and never
    /// opens or closes the session. A document from a category that isn't locked goes
    /// without asking.
    public func confirmSharing(fromLockedCategory isLocked: Bool, reason: String) async -> UnlockResult {
        guard isLocked else { return .success }
        return await authenticateForReveal(reason: reason)
    }

    /// Closes the session now.
    public func lock() {
        isSessionUnlocked = false
    }

    // MARK: Lifecycle

    /// Time away starts when the app first goes to the background, and counts until it
    /// comes back.
    func appDidEnterBackground() {
        if backgroundedAt == nil { backgroundedAt = clock.elapsed }
    }

    func appWillEnterForeground() {
        defer { backgroundedAt = nil }
        guard let backgroundedAt else { return }
        if clock.elapsed - backgroundedAt > Self.relockAfterBackground {
            lock()
        }
    }

    // MARK: Presentation

    public var biometryName: String {
        switch authenticator.biometryType() {
        case .faceID: return "Face ID"
        case .touchID: return "Touch ID"
        case .opticID: return "Optic ID"
        case .none: return String(localized: "Codul telefonului")
        @unknown default: return String(localized: "Codul telefonului")
        }
    }

    public var biometrySymbol: String {
        switch authenticator.biometryType() {
        case .faceID: return "faceid"
        case .touchID: return "touchid"
        case .opticID: return "opticid"
        case .none: return "lock.fill"
        @unknown default: return "lock.fill"
        }
    }

    /// Hides the middle of an identifier: `1800101990006` becomes `180•••••••006`.
    public static func mask(_ text: String, visiblePrefix: Int = 3, visibleSuffix: Int = 3) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count > visiblePrefix + visibleSuffix else {
            return String(repeating: "•", count: max(4, trimmed.count))
        }
        let hidden = min(8, trimmed.count - visiblePrefix - visibleSuffix)
        return "\(trimmed.prefix(visiblePrefix))\(String(repeating: "•", count: hidden))\(trimmed.suffix(visibleSuffix))"
    }
}
