import CryptoKit
import Foundation
import Testing
@testable import DosarCuSina

/// The sealing keys go through iCloud Keychain, so a code sealed on one of the person's devices
/// opens on the others, without ever losing this device's own key. Every value is a placeholder.
@Suite("Sealing keys on every device")
struct SecretKeyringTests {
    /// The Keychain, in memory: this device's items and the synced ones apart, with which synced
    /// ones an earlier build kept readable while the phone is locked.
    final class Keychain: SecretKeyStore, @unchecked Sendable {
        var local: [String: Data] = [:]
        var synced: [String: Data] = [:]
        /// Synced accounts readable while locked (an earlier build's class).
        var readableWhileLocked: Set<String> = []
        var syncedWritesFail = false
        var updatesFail = false
        /// An update that loses the item, to show it is put back.
        var updatesLoseTheItem = false
        /// The phone is locked: nothing kept only while unlocked can be read.
        var isLocked = false

        func read(account: String, synchronizable: Bool) throws -> Data? {
            if isLocked { throw SecretFieldError.keyUnavailable }
            return synchronizable ? synced[account] : local[account]
        }
        func readSynchronizable() throws -> [String: Data] {
            if isLocked { throw SecretFieldError.keyUnavailable }
            return synced
        }
        func add(_ data: Data, account: String, synchronizable: Bool) throws -> Bool {
            if isLocked { throw SecretFieldError.keyUnavailable }
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
        func syncedKeysReadableWhileLocked() throws -> [String] {
            Array(readableWhileLocked).filter { synced[$0] != nil }.sorted()
        }
        func keepOnlyWhileUnlocked(syncedAccount account: String) throws {
            if updatesFail || synced[account] == nil { throw SecretFieldError.keyUnavailable }
            if updatesLoseTheItem { synced[account] = nil }
            readableWhileLocked.remove(account)
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
        #expect(SecretFieldError.unreadable.errorDescription?.contains("alt dispozitiv") == true, "It says where it was written")

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

    // MARK: Shared as soon as the binder syncs

    @Test func aKeySealedBeforeSyncIsSharedWithoutSealingOrOpeningAnything() throws {
        let keychain = Keychain()
        let old = Self.keyData()
        keychain.local[SecretKeyring.ownAccount] = old
        let ring = SecretKeyring(store: keychain)

        try ring.shareOwnKey()
        #expect(keychain.synced[SecretKeyring.syncedAccount(for: old)] == old)
        #expect(keychain.local[SecretKeyring.ownAccount] == old, "The device's own key stays where it was")

        try ring.shareOwnKey()
        #expect(keychain.synced.count == 1, "Sharing again adds nothing")
    }

    @Test func aDeviceThatNeverSealedACodeMakesNoKeyToShare() throws {
        let keychain = Keychain()
        try SecretKeyring(store: keychain).shareOwnKey()
        #expect(keychain.local.isEmpty)
        #expect(keychain.synced.isEmpty)
    }

    @Test func aLockedPhoneSharesLater() {
        let keychain = Keychain()
        keychain.local[SecretKeyring.ownAccount] = Self.keyData()
        keychain.isLocked = true
        #expect(throws: SecretFieldError.keyUnavailable) { try SecretKeyring(store: keychain).shareOwnKey() }
        #expect(keychain.synced.isEmpty)
    }

    @MainActor
    @Test func sharingRunsWhenAskedAndAgainOnceThePhoneIsUnlocked() async throws {
        let keychain = Keychain()
        let old = Self.keyData()
        keychain.local[SecretKeyring.ownAccount] = old
        keychain.isLocked = true
        let center = NotificationCenter()
        let unlocked = Notification.Name("test.unlocked")
        let sharing = SecretKeySharing(ring: SecretKeyring(store: keychain), center: center, unlocked: unlocked)

        sharing.start()
        await sharing.running?.value
        #expect(keychain.synced.isEmpty)
        #expect(sharing.isWaitingForUnlock, "Tries again once the phone is unlocked")

        keychain.isLocked = false
        center.post(name: unlocked, object: nil)
        for _ in 0..<100 where sharing.running == nil && sharing.isWaitingForUnlock { await Task.yield() }
        await sharing.running?.value
        #expect(keychain.synced[SecretKeyring.syncedAccount(for: old)] == old)
        #expect(!sharing.isWaitingForUnlock)
    }

    // MARK: Kept only while the phone is unlocked

    @Test func anEarlierBuildsSyncedCopiesMoveToTheStrongerClassWithTheirValues() throws {
        let keychain = Keychain()
        let own = Self.keyData(), other = Self.keyData()
        keychain.local[SecretKeyring.ownAccount] = own
        let ownAccount = SecretKeyring.syncedAccount(for: own), otherAccount = SecretKeyring.syncedAccount(for: other)
        keychain.synced = [ownAccount: own, otherAccount: other]
        keychain.readableWhileLocked = [ownAccount, otherAccount]

        try SecretKeyring(store: keychain).shareOwnKey()
        #expect(keychain.readableWhileLocked.isEmpty, "Every synced copy is kept only while unlocked")
        #expect(keychain.synced == [ownAccount: own, otherAccount: other], "Their values stay as they were")
        #expect(keychain.local == [SecretKeyring.ownAccount: own], "The device's own key is never touched")
    }

    @Test func aCopyThatDidntMoveStaysAsItWas() throws {
        let keychain = Keychain()
        let own = Self.keyData()
        keychain.local[SecretKeyring.ownAccount] = own
        let account = SecretKeyring.syncedAccount(for: own)
        keychain.synced = [account: own]
        keychain.readableWhileLocked = [account]
        keychain.updatesFail = true

        let ring = SecretKeyring(store: keychain)
        #expect(try ring.sealingKey().withUnsafeBytes { Data($0) } == own)
        #expect(keychain.synced == [account: own])
        #expect(keychain.readableWhileLocked == [account], "Tried again next time")

        keychain.updatesFail = false
        try ring.shareOwnKey()
        #expect(keychain.readableWhileLocked.isEmpty)
    }

    @Test func aCopyLostOnTheWayIsPutBack() throws {
        let keychain = Keychain()
        let other = Self.keyData()
        let account = SecretKeyring.syncedAccount(for: other)
        keychain.synced = [account: other]
        keychain.readableWhileLocked = [account]
        keychain.updatesLoseTheItem = true

        try SecretKeyring(store: keychain).shareOwnKey()
        #expect(keychain.synced[account] == other, "Another device's key is never lost here")
    }

    // MARK: What a code from another device says

    @Test func aCodeFromAnotherDeviceSaysWhatToDoForEachCause() throws {
        let there = SymmetricKey(size: .bits256), here = SymmetricKey(size: .bits256), third = SymmetricKey(size: .bits256)
        let sealed = try SecretSealer(key: { there }).seal("0000")

        // Only this device's key: iCloud Keychain may be off on either device.
        let alone = SecretSealer(sealingKey: { here }, openingKeys: { [here] })
        #expect(throws: SecretFieldError.unreadable) { try alone.open(sealed) }

        // Another device's key reached this one: iCloud Keychain works here, the writer hasn't shared yet.
        let receiving = SecretSealer(sealingKey: { here }, openingKeys: { [here, third] })
        #expect(throws: SecretFieldError.notSharedYet) { try receiving.open(sealed) }

        for error in [SecretFieldError.unreadable, .notSharedYet] {
            let text = try #require(error.errorDescription)
            #expect(text.contains("alt dispozitiv"), "Says where it was written")
            #expect(text.contains("Deschide aplicația pe el"), "Says what to do next")
            #expect(text.contains("Parole în iCloud"))
            #expect(!text.contains("!"))
        }
        #expect(SecretFieldError.unreadable.errorDescription != SecretFieldError.notSharedYet.errorDescription)
    }
}
