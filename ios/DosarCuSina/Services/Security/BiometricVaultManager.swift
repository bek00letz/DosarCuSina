import Foundation
import LocalAuthentication
import Observation
#if canImport(UIKit)
import UIKit
#endif

/// Face ID, Touch ID, Optic ID or the device passcode, behind a protocol so
/// tests can run without a person.
public protocol BiometricAuthenticating: Sendable {
    func canAuthenticate() -> Bool
    func biometryType() -> LABiometryType
    func evaluate(localizedReason: String) async throws -> Bool
}

public struct SystemBiometricAuthenticator: BiometricAuthenticating {
    public init() {}

    public func canAuthenticate() -> Bool {
        var error: NSError?
        return LAContext().canEvaluatePolicy(.deviceOwnerAuthentication, error: &error)
    }

    public func biometryType() -> LABiometryType {
        let context = LAContext()
        var error: NSError?
        _ = context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error)
        return context.biometryType
    }

    public func evaluate(localizedReason: String) async throws -> Bool {
        let context = LAContext()
        context.localizedCancelTitle = String(localized: "Anulează")
        return try await context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: localizedReason)
    }
}

/// Just-in-time unlock for sensitive categories. The app opens without a prompt;
/// Face ID is asked only when a protected category is opened, stays unlocked
/// while in use, and locks again after `idleTimeout` without activity or as
/// soon as the app goes to the background.
///
/// Which categories are protected is decided by `CategoryTemplate.isSensitive`
/// together with the `AppPreferences.biometricLockEnabled` master switch.
@MainActor
@Observable
public final class BiometricVaultManager {
    public static let shared = BiometricVaultManager()

    /// Unlocked category keys and when they were last used.
    public private(set) var unlockedKeys: [String: Date] = [:]
    public var idleTimeout: TimeInterval = 300

    @ObservationIgnored private let authenticator: any BiometricAuthenticating
    @ObservationIgnored private let now: () -> Date
    @ObservationIgnored private var backgroundObserver: (any NSObjectProtocol)?

    public init(authenticator: any BiometricAuthenticating = SystemBiometricAuthenticator(), now: @escaping () -> Date = { Date() }) {
        self.authenticator = authenticator
        self.now = now
        #if canImport(UIKit)
        backgroundObserver = NotificationCenter.default.addObserver(
            forName: UIApplication.didEnterBackgroundNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.lockAll() }
        }
        #endif
    }

    // MARK: State

    /// Whether `templateKey` is open right now. Reading never changes state, so
    /// views can call it freely.
    public func isUnlocked(_ templateKey: String) -> Bool {
        guard let lastUse = unlockedKeys[templateKey] else { return false }
        return now().timeIntervalSince(lastUse) <= idleTimeout
    }

    /// Whether opening a category needs Face ID first.
    public func needsUnlock(templateKey: String, isSensitive: Bool, lockEnabled: Bool) -> Bool {
        lockEnabled && isSensitive && !isUnlocked(templateKey)
    }

    /// Call while the person is using an unlocked category to keep it open.
    public func noteActivity(_ templateKey: String) {
        guard isUnlocked(templateKey) else { return }
        unlockedKeys[templateKey] = now()
    }

    // MARK: Unlock

    /// Asks for Face ID (or the passcode) to open `templateKey`. Returns whether it is open.
    @discardableResult
    public func unlock(_ templateKey: String, reason: String) async -> Bool {
        if isUnlocked(templateKey) {
            noteActivity(templateKey)
            return true
        }
        do {
            if try await authenticator.evaluate(localizedReason: reason) {
                unlockedKeys[templateKey] = now()
                return true
            }
        } catch {
            return false
        }
        return false
    }

    public func lock(_ templateKey: String) {
        unlockedKeys.removeValue(forKey: templateKey)
    }

    public func lockAll() {
        unlockedKeys.removeAll()
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

    /// Hides the middle of an identifier: `1800101990006` becomes `188••••••456`.
    public static func mask(_ text: String, visiblePrefix: Int = 3, visibleSuffix: Int = 3) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count > visiblePrefix + visibleSuffix else {
            return String(repeating: "•", count: max(4, trimmed.count))
        }
        let hidden = min(8, trimmed.count - visiblePrefix - visibleSuffix)
        return "\(trimmed.prefix(visiblePrefix))\(String(repeating: "•", count: hidden))\(trimmed.suffix(visibleSuffix))"
    }
}
