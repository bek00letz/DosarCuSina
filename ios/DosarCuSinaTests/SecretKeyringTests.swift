import CryptoKit
import Foundation
import Testing
@testable import DosarCuSina

/// The sealing keys go through iCloud Keychain, so a code sealed on one of the person's devices
/// opens on the others, without ever losing this device's own key. Every value is a placeholder.
@Suite("Sealing keys on every device")
struct SecretKeyringTests {
    /// The Keychain, in memory: this device's items and the synced ones apart.
    final class Keychain: SecretKeyStore, @unchecked Sendable {
        var local: [String: Data] = [:]
        var synced: [String: Data] = [:]
        var syncedWritesFail = false

        func read(account: String, synchronizable: Bool) throws -> Data? {
            synchronizable ? synced[account] : local[account]
        }
        func readSynchronizable() throws -> [String: Data] { synced }
        func add(_ data: Data, account: String, synchronizable: Bool) throws -> Bool {
            if synchronizable {
                if syncedWritesFail { throw SecretFieldError.keyUnavailable }
                guard synced[account] == nil else { return false }
                synced[account] = data
            } else {
                guard local[account] == nil else { return false }
                local[account] = data
            }
            return true
        }
    }

    private static func keyData() -> Data { SymmetricKey(size: .bits256).withUnsafeBytes { Data($0) } }

    @Test func thisDevicesKeyIsSyncedWithoutEverBeingLost() throws {
        let keychain = Keychain()
        let old = Self.keyData()
        keychain.local[SecretKeyring.ownAccount] = old
        let ring = SecretKeyring(store: keychain)
        let sealedBefore = try SecretSealer(key: { SymmetricKey(data: old) }).seal("0000")

        let key = try ring.sealingKey()
        #expect(key.withUnsafeBytes { Data($0) } == old, "The key the codes were sealed with keeps sealing")
        #expect(keychain.local[SecretKeyring.ownAccount] == old, "The device's own item stays, the way back")
        #expect(keychain.synced[SecretKeyring.syncedAccount(for: old)] == old, "Its copy is in iCloud Keychain")
        #expect(ring.isSynced(old))
        let sealer = SecretSealer(sealingKey: { try ring.sealingKey() }, openingKeys: { try ring.openingKeys() })
        #expect(try sealer.open(sealedBefore) == "0000", "Codes sealed before open as before")

        // Again: nothing more is written.
        _ = try ring.sealingKey()
        #expect(keychain.synced.count == 1)
    }

    @Test func aFailedSyncedCopyChangesNothing() throws {
        let keychain = Keychain()
        keychain.syncedWritesFail = true
        let old = Self.keyData()
        keychain.local[SecretKeyring.ownAccount] = old
        let ring = SecretKeyring(store: keychain)
        #expect(try ring.sealingKey().withUnsafeBytes { Data($0) } == old)
        #expect(keychain.synced.isEmpty)
        #expect(!ring.isSynced(old))
        #expect(keychain.local[SecretKeyring.ownAccount] == old)
    }

    @Test func aCodeSealedOnAnotherDeviceOpensWhenItsKeyCameAndStaysSealedOtherwise() throws {
        // The other device: its own key, synced.
        let there = Keychain()
        let thereRing = SecretKeyring(store: there)
        let thereSealer = SecretSealer(sealingKey: { try thereRing.sealingKey() }, openingKeys: { try thereRing.openingKeys() })
        let sealed = try thereSealer.seal("0000")

        // This device, with iCloud Keychain off: its own key only.
        let here = Keychain()
        let hereRing = SecretKeyring(store: here)
        let hereSealer = SecretSealer(sealingKey: { try hereRing.sealingKey() }, openingKeys: { try hereRing.openingKeys() })
        #expect(throws: SecretFieldError.unreadable) { try hereSealer.open(sealed) }
        #expect(SecretFieldError.unreadable.errorDescription?.contains("dispozitivul") == true, "It says where it opens")

        // iCloud Keychain on: the other device's key arrives, and its codes open here too.
        for (account, key) in there.synced { here.synced[account] = key }
        #expect(try hereSealer.open(sealed) == "0000")
        // Codes sealed here still use this device's own key, which the other device gets the same way.
        let mine = try hereSealer.seal("0000")
        for (account, key) in here.synced { there.synced[account] = key }
        #expect(try thereSealer.open(mine) == "0000")
        #expect(here.local[SecretKeyring.ownAccount] != there.local[SecretKeyring.ownAccount], "Each device keeps its own key; none writes over another's")
    }

    @Test func aNewDeviceMakesItsKeyAndSyncsIt() throws {
        let keychain = Keychain()
        let ring = SecretKeyring(store: keychain)
        let key = try ring.sealingKey().withUnsafeBytes { Data($0) }
        #expect(keychain.local[SecretKeyring.ownAccount] == key)
        #expect(keychain.synced.values.contains(key))
    }

}
