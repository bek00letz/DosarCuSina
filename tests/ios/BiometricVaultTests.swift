import Foundation
import LocalAuthentication
import SwiftUI

// MARK: - Biometric Vault Manager Test Suite

@MainActor
public final class BiometricVaultTests {
    public static func runAll() async -> (passed: Int, failed: Int) {
        print("\n▶ Running BiometricVaultTests (Model B: Just-in-Time Security)...")
        var passed = 0
        var failed = 0
        
        func assert(_ condition: Bool, _ name: String) {
            if condition {
                print("  ✅ PASS  \(name)")
                passed += 1
            } else {
                print("  ❌ FAIL  \(name)")
                failed += 1
            }
        }
        
        // Test 1: Zero friction for non-sensitive categories
        do {
            let mockAuth = MockBiometricAuthenticator(shouldSucceed: true)
            let vault = BiometricVaultManager(authenticator: mockAuth)
            
            assert(vault.isUnlocked(category: .vehicle), "testNonSensitiveCategoryVehicle_IsUnlockedByDefault")
            assert(vault.isUnlocked(category: .home), "testNonSensitiveCategoryHome_IsUnlockedByDefault")
            assert(vault.isUnlocked(category: .warranties), "testNonSensitiveCategoryWarranties_IsUnlockedByDefault")
            assert(vault.isUnlocked(category: .subscriptions), "testNonSensitiveCategorySubscriptions_IsUnlockedByDefault")
            assert(vault.isUnlocked(category: .custom), "testNonSensitiveCategoryCustom_IsUnlockedByDefault")
        }
        
        // Test 2: Sensitive categories require JiT unlock
        do {
            let mockAuth = MockBiometricAuthenticator(shouldSucceed: true)
            let vault = BiometricVaultManager(authenticator: mockAuth)
            
            assert(!vault.isUnlocked(category: .documents), "testSensitiveCategoryDocuments_IsLockedByDefault")
            assert(!vault.isUnlocked(category: .health), "testSensitiveCategoryHealth_IsLockedByDefault")
        }
        
        // Test 3: Successful JiT authentication unlocks category
        do {
            let mockAuth = MockBiometricAuthenticator(shouldSucceed: true)
            let vault = BiometricVaultManager(authenticator: mockAuth)
            
            let unlocked = await vault.unlockCategory(.documents)
            
            assert(unlocked == true, "testUnlockCategoryDocuments_Succeeds")
            assert(vault.isUnlocked(category: .documents) == true, "testDocumentsCategory_BecomesUnlockedAfterAuth")
            // Health should still remain locked
            assert(vault.isUnlocked(category: .health) == false, "testHealthCategory_RemainsLockedUntilSeparatelyRequested")
        }
        
        // Test 4: Failed authentication preserves lock
        do {
            let mockAuth = MockBiometricAuthenticator(shouldSucceed: false)
            let vault = BiometricVaultManager(authenticator: mockAuth)
            
            let unlocked = await vault.unlockCategory(.documents)
            
            assert(unlocked == false, "testUnlockCategoryDocuments_FailsGracefully")
            assert(vault.isUnlocked(category: .documents) == false, "testDocumentsCategory_RemainsLockedOnAuthFailure")
        }
        
        // Test 5: Sensitive field masking when locked vs unlocked
        do {
            let mockAuth = MockBiometricAuthenticator(shouldSucceed: true)
            let vault = BiometricVaultManager(authenticator: mockAuth)
            let sampleCNP = "1900101123456"
            
            let maskedCNP = vault.displayValue(for: sampleCNP, in: .documents, visiblePrefix: 3, visibleSuffix: 2)
            assert(maskedCNP.hasPrefix("190") && maskedCNP.hasSuffix("56") && maskedCNP.contains("•"), "testCNPMasking_WhenLocked_HidesMiddleDigits")
            assert(!maskedCNP.contains("1234"), "testCNPMasking_MiddleDigitsAreNotVisible")
            
            // Now unlock documents
            _ = await vault.unlockCategory(.documents)
            
            let unmaskedCNP = vault.displayValue(for: sampleCNP, in: .documents)
            assert(unmaskedCNP == sampleCNP, "testCNPDisplay_WhenUnlocked_ShowsFullNumber")
        }
        
        // Test 6: Inactivity timeout re-locks sensitive categories
        do {
            let mockAuth = MockBiometricAuthenticator(shouldSucceed: true)
            let vault = BiometricVaultManager(authenticator: mockAuth)
            vault.sessionTimeoutSeconds = 0.01 // 10ms for test
            
            _ = await vault.unlockCategory(.documents)
            assert(vault.isUnlocked(category: .documents) == true, "testTimeout_InitiallyUnlocked")
            
            try? await Task.sleep(nanoseconds: 50_000_000) // 50ms to exceed timeout
            assert(vault.isUnlocked(category: .documents) == false, "testTimeout_AutomaticallyLocksAfterExpiry")
        }
        
        // Test 7: lockAll immediately closes all active vaults
        do {
            let mockAuth = MockBiometricAuthenticator(shouldSucceed: true)
            let vault = BiometricVaultManager(authenticator: mockAuth)
            
            _ = await vault.unlockCategory(.documents)
            assert(vault.isUnlocked(category: .documents) == true, "testLockAll_BeforeLock")
            
            vault.lockAll()
            assert(vault.isUnlocked(category: .documents) == false, "testLockAll_AfterLockAll_DocumentsRelocked")
        }
        
        print("  ✅ All \(passed) tests passed in BiometricVaultTests")
        return (passed, failed)
    }
}
