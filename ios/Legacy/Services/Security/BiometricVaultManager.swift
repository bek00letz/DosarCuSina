import Foundation
import LocalAuthentication
import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

// MARK: - Biometric Authenticator Protocol

/// Protocol defining biometric and device passcode authentication.
/// Allows clean unit testing and mock injection during headless CI test runs.
public protocol BiometricAuthenticating: Sendable {
    func canAuthenticate() -> Bool
    func biometryType() -> LABiometryType
    func evaluate(localizedReason: String) async throws -> Bool
}

// MARK: - System Biometric Authenticator

public final class SystemBiometricAuthenticator: BiometricAuthenticating, @unchecked Sendable {
    public init() {}
    
    public func canAuthenticate() -> Bool {
        let context = LAContext()
        var error: NSError?
        return context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error)
    }
    
    public func biometryType() -> LABiometryType {
        let context = LAContext()
        var error: NSError?
        _ = context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error)
        return context.biometryType
    }
    
    public func evaluate(localizedReason: String) async throws -> Bool {
        let context = LAContext()
        context.localizedCancelTitle = "Anulează"
        
        return try await withCheckedThrowingContinuation { continuation in
            context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: localizedReason) { success, error in
                if let error = error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: success)
                }
            }
        }
    }
}

// MARK: - Mock Biometric Authenticator for Headless Tests

public final class MockBiometricAuthenticator: BiometricAuthenticating, @unchecked Sendable {
    public var shouldSucceed: Bool = true
    public var simulatedBiometryType: LABiometryType = .faceID
    public var canAuthenticateResult: Bool = true
    
    public init(shouldSucceed: Bool = true) {
        self.shouldSucceed = shouldSucceed
    }
    
    public func canAuthenticate() -> Bool {
        return canAuthenticateResult
    }
    
    public func biometryType() -> LABiometryType {
        return simulatedBiometryType
    }
    
    public func evaluate(localizedReason: String) async throws -> Bool {
        if shouldSucceed {
            return true
        } else {
            throw NSError(domain: "LAErrorDomain", code: LAError.authenticationFailed.rawValue, userInfo: nil)
        }
    }
}

// MARK: - Biometric Vault Manager (Model B: Just-in-Time Category Unlock)

/// Manages Just-in-Time (JiT) biometric access to sensitive household categories.
/// The app opens immediately without friction for daily utility (mileage, meter readings).
/// Only accessing sensitive records (Identity/CNP, Health ICE card) prompts for Face ID / Passcode.
@Observable
@MainActor
public final class BiometricVaultManager {
    public static let shared = BiometricVaultManager()
    
    // In-memory set of authorized categories for the current active session
    public private(set) var unlockedCategories: Set<String> = []
    
    // In-memory set of specific authorized asset vault IDs
    public private(set) var unlockedVaults: Set<UUID> = []
    
    // Last user authentication timestamp (for timeout management)
    public private(set) var lastAuthenticationDate: Date?
    
    // Maximum inactivity window in seconds before JiT locks re-engage (default: 5 minutes)
    public var sessionTimeoutSeconds: TimeInterval = 300
    
    // Injected authenticator
    private let authenticator: BiometricAuthenticating
    
    public init(authenticator: BiometricAuthenticating = SystemBiometricAuthenticator()) {
        self.authenticator = authenticator
        setupAppLifecycleObservers()
    }
    
    // MARK: - Biometry Presentation
    
    public var biometryTypeName: String {
        switch authenticator.biometryType() {
        case .faceID:
            return "Face ID"
        case .touchID:
            return "Touch ID"
        case .opticID:
            return "Optic ID"
        case .none:
            return "Cod de acces"
        @unknown default:
            return "Biometrie"
        }
    }
    
    public var biometrySystemImage: String {
        switch authenticator.biometryType() {
        case .faceID:
            return "faceid"
        case .touchID:
            return "touchid"
        case .opticID:
            return "opticid"
        case .none:
            return "lock.shield"
        @unknown default:
            return "lock.fill"
        }
    }
    
    // MARK: - Category & Vault Classification
    
    /// Default sensitive categories requiring Just-in-Time biometric authorization
    public static let defaultSensitiveCategories: Set<String> = [
        AssetCategory.documents.rawValue, // Acte & Documente Oficiale (CNP, Serii buletin, pașaport)
        AssetCategory.health.rawValue     // Sănătate & Familie (Fișă medicală ICE, alergii, rețete)
    ]
    
    public func isSensitive(category: AssetCategory) -> Bool {
        return Self.defaultSensitiveCategories.contains(category.rawValue)
    }
    
    public func isUnlocked(category: AssetCategory) -> Bool {
        // If not a sensitive category, it is always unlocked (zero friction)
        if !isSensitive(category: category) {
            return true
        }
        
        checkTimeout()
        return unlockedCategories.contains(category.rawValue)
    }
    
    public func isUnlocked(vaultId: UUID) -> Bool {
        checkTimeout()
        return unlockedVaults.contains(vaultId)
    }
    
    // MARK: - Just-in-Time Unlock Actions
    
    /// Authenticate access to a sensitive category using Face ID / Passcode.
    @discardableResult
    public func unlockCategory(_ category: AssetCategory, customReason: String? = nil) async -> Bool {
        // If already unlocked and within timeout, return true immediately
        if isUnlocked(category: category) {
            return true
        }
        
        let reason = customReason ?? "Deblochează \(category.title) și datele confidențiale"
        
        do {
            let success = try await authenticator.evaluate(localizedReason: reason)
            if success {
                unlockedCategories.insert(category.rawValue)
                lastAuthenticationDate = Date()
                #if canImport(UIKit)
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                #endif
                return true
            }
        } catch {
            #if canImport(UIKit)
            UINotificationFeedbackGenerator().notificationOccurred(.error)
            #endif
        }
        
        return false
    }
    
    /// Authenticate access to a specific sensitive asset / document
    @discardableResult
    public func unlockVault(id: UUID, title: String) async -> Bool {
        if isUnlocked(vaultId: id) {
            return true
        }
        
        let reason = "Deblochează dosarul confidențial: \(title)"
        
        do {
            let success = try await authenticator.evaluate(localizedReason: reason)
            if success {
                unlockedVaults.insert(id)
                lastAuthenticationDate = Date()
                #if canImport(UIKit)
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                #endif
                return true
            }
        } catch {
            #if canImport(UIKit)
            UINotificationFeedbackGenerator().notificationOccurred(.error)
            #endif
        }
        
        return false
    }
    
    /// Instantly lock all sensitive vaults (e.g. on manual lock or app backgrounding)
    public func lockAll() {
        unlockedCategories.removeAll()
        unlockedVaults.removeAll()
        lastAuthenticationDate = nil
    }
    
    // MARK: - Sensitive Field Masking Helpers
    
    /// Formats a sensitive identifier (e.g., CNP, IBAN, Card).
    /// If the category/vault is unlocked, reveals the full string.
    /// If locked, masks all characters except specified prefix and suffix.
    public func displayValue(for rawValue: String, in category: AssetCategory, visiblePrefix: Int = 3, visibleSuffix: Int = 2) -> String {
        if isUnlocked(category: category) {
            return rawValue
        }
        
        return mask(text: rawValue, visiblePrefix: visiblePrefix, visibleSuffix: visibleSuffix)
    }
    
    public func mask(text: String, visiblePrefix: Int = 3, visibleSuffix: Int = 2) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let count = trimmed.count
        
        guard count > (visiblePrefix + visibleSuffix) else {
            return String(repeating: "•", count: max(4, count))
        }
        
        let prefix = trimmed.prefix(visiblePrefix)
        let suffix = trimmed.suffix(visibleSuffix)
        let maskedCount = count - visiblePrefix - visibleSuffix
        let mask = String(repeating: "•", count: min(8, maskedCount))
        
        return "\(prefix)\(mask)\(suffix)"
    }
    
    // MARK: - Private Lifecycle & Timeout
    
    private func checkTimeout() {
        guard let lastAuth = lastAuthenticationDate else { return }
        if Date().timeIntervalSince(lastAuth) > sessionTimeoutSeconds {
            lockAll()
        }
    }
    
    private func setupAppLifecycleObservers() {
        #if canImport(UIKit)
        NotificationCenter.default.addObserver(
            forName: UIApplication.willResignActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.lockAll()
            }
        }
        #endif
    }
}

// MARK: - SwiftUI View Modifier for JiT Unlocking

public struct JustInTimeBiometricVaultModifier: ViewModifier {
    let category: AssetCategory
    @State private var vaultManager = BiometricVaultManager.shared
    
    public func body(content: Content) -> some View {
        Group {
            if vaultManager.isUnlocked(category: category) {
                content
            } else {
                LockedVaultPlaceholderView(category: category) {
                    Task {
                        await vaultManager.unlockCategory(category)
                    }
                }
            }
        }
    }
}

public struct LockedVaultPlaceholderView: View {
    let category: AssetCategory
    let onUnlockTapped: () -> Void
    @State private var vaultManager = BiometricVaultManager.shared
    
    public var body: some View {
        VStack(spacing: 20) {
            Spacer()
            
            ZStack {
                Circle()
                    .fill(Color.secondary.opacity(0.15))
                    .frame(width: 88, height: 88)
                
                Image(systemName: vaultManager.biometrySystemImage)
                    .font(.system(size: 40, weight: .regular))
                    .foregroundStyle(.tint)
            }
            
            VStack(spacing: 8) {
                Text("Dosar Confidențial")
                    .font(.title3.weight(.semibold))
                
                Text("\(category.title) conține date cu caracter personal protejate.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }
            
            Button(action: onUnlockTapped) {
                HStack(spacing: 8) {
                    Image(systemName: vaultManager.biometrySystemImage)
                    Text("Deblochează cu \(vaultManager.biometryTypeName)")
                }
                .font(.body.weight(.medium))
                .padding(.horizontal, 24)
                .padding(.vertical, 12)
                .background(Color.accentColor)
                .foregroundStyle(.white)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            .padding(.top, 8)
            
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.secondary.opacity(0.06))
    }
}

public extension View {
    /// Protects a view with Model B Just-in-Time Biometric Unlock
    func requiresBiometricUnlock(for category: AssetCategory) -> some View {
        self.modifier(JustInTimeBiometricVaultModifier(category: category))
    }
}
