import CryptoKit
import Foundation
import Security
#if canImport(UIKit)
import UIKit
#endif

/// The rules for secret fields (`FieldType.secret`), such as the PIN codes of
/// an electronic identity card. One place decides them:
///
/// - **Kept sealed.** The value is encrypted before it is saved, with a key that
///   lives in this phone's Keychain and never leaves it. The database holds only
///   the sealed text.
/// - **Opened only after a fresh Face ID** (or the passcode), every time, even
///   when the section is already open: `SecretReveal`.
/// - **Never leaves the binder:** not in search, widgets, notifications, the
///   box status line, logs or `.dosar` archives. A sealed value is known by its
///   own form (`SecretSealer.isSealed`), whatever its template says, so every
///   exit that calls `stripping(_:definition:)` or `strippingFacts(_:)` leaves
///   it out, and `FieldFormatter.display` only ever shows it as a mask.
public enum SecretFields {
    /// What a secret looks like wherever it isn't opened.
    public static let mask = "••••"

    /// The secret fields of a template.
    public static func fields(in definition: TemplateDefinition) -> [FieldDefinition] {
        definition.allFields.filter(\.isSecret)
    }

    /// Whether a value is a sealed secret, by its own form.
    public static func isSealed(_ value: FieldValue) -> Bool {
        switch value {
        case .text(let text): return SecretSealer.isSealed(text)
        case .choices(let items): return items.contains(where: SecretSealer.isSealed)
        default: return false
        }
    }

    /// The values without any secret, for anything that leaves the binder: every
    /// sealed value, and every value of a field the template marks secret.
    public static func stripping(_ values: FieldValues, definition: TemplateDefinition?) -> FieldValues {
        // A value this build can't read is left out too when anything in it is sealed.
        var result = values.mappingUnreadable { $0.containsString(where: SecretSealer.isSealed) ? nil : $0 }
        for (key, value) in values where isSealed(value) { result[key] = nil }
        for field in definition.map(fields(in:)) ?? [] { result[field.key] = nil }
        return result
    }

    /// The same for values as stored: what a newer build wrote inside a value this build reads
    /// is left out too when anything in it is sealed (`KeptObject.mappingKept`).
    public static func stripping(_ values: KeptObject<FieldValues>, definition: TemplateDefinition?) -> KeptObject<FieldValues> {
        values.replacingValue(stripping(values.value, definition: definition)).mappingKept(withoutSecrets)
    }

    /// A part this build doesn't read, or nil when it says it is secret or anything in it is sealed.
    private static func withoutSecrets(_ raw: JSONValue) -> JSONValue? {
        raw["isSecret"]?.bool == true || raw.containsString(where: SecretSealer.isSealed) ? nil : raw
    }

    /// Only the sealed values, by their own form: those this build reads, and those it can't
    /// read with anything sealed in them, kept raw.
    public static func sealedValues(in values: FieldValues) -> FieldValues {
        var result = values.mappingUnreadable(sealedPart)
        for (key, value) in values where !isSealed(value) { result[key] = nil }
        return result
    }

    /// A part this build doesn't read, when it says it is secret or anything in it is sealed.
    private static func sealedPart(_ raw: JSONValue) -> JSONValue? {
        withoutSecrets(raw) == nil ? raw : nil
    }

    /// The person's own rows without the secret ones, for anything that leaves the binder.
    public static func strippingFacts(_ facts: [CustomFact]) -> [CustomFact] {
        facts.filter { !$0.isSecret }
    }

    /// The same for rows as stored: a row this build can't read, and what a newer build wrote
    /// inside a row it reads, is left out too when it says it is secret or anything in it is sealed.
    public static func strippingFacts(_ facts: KeptList<CustomFact>) -> KeptList<CustomFact> {
        facts.replacingItems(strippingFacts(facts.items)).mappingKept(withoutSecrets)
    }

    /// The values with every secret typed in plain sealed. Values already sealed
    /// pass through unchanged. A card number is masked before sealing (`PaymentCardNumbers`):
    /// a sealed value is never rewritten once kept, so this is where it is kept out.
    public static func sealing(_ values: FieldValues, definition: TemplateDefinition, sealer: SecretSealer) throws -> FieldValues {
        var result = values
        for field in fields(in: definition) {
            guard let text = values[field.key]?.textValue, !SecretSealer.isSealed(text) else { continue }
            let plain = PaymentCardNumbers.redact(text.trimmingCharacters(in: .whitespacesAndNewlines))
            result[field.key] = plain.isEmpty ? nil : .text(try sealer.seal(plain))
        }
        return result
    }

    /// The person's rows with every secret row typed in plain sealed. Rows
    /// already sealed pass through unchanged; a secret row left empty keeps no value. A card
    /// number is masked before sealing, as for a secret field.
    public static func sealingFacts(_ facts: [CustomFact], sealer: SecretSealer) throws -> [CustomFact] {
        try facts.map { fact in
            guard fact.isSecret, !SecretSealer.isSealed(fact.value) else { return fact }
            var sealed = fact
            sealed.isSensitive = true
            let plain = PaymentCardNumbers.redact(fact.value.trimmingCharacters(in: .whitespacesAndNewlines))
            sealed.value = plain.isEmpty ? "" : try sealer.seal(plain)
            return sealed
        }
    }

    /// Incoming values (from an archive, which never carries secrets) with the
    /// secrets this phone already keeps for the same record. With a template, a
    /// kept secret stays only while its field still applies (a PIN goes when the
    /// card became a passport).
    public static func keepingLocalSecrets(_ incoming: FieldValues, from existing: FieldValues, definition: TemplateDefinition?) -> FieldValues {
        var result = stripping(incoming, definition: definition)
        for (key, value) in sealedValues(in: existing) {
            if let field = definition?.allFields.first(where: { $0.key == key }), !field.applies(to: result) { continue }
            result[key] = value
        }
        // A sealed value this build can't read stays too, unless the archive gives its field a value.
        return result.addingUnreadable(of: sealedValues(in: existing))
    }

    /// The same for values as an archive carries them, with what this build doesn't read (none secret).
    public static func keepingLocalSecrets(_ incoming: KeptObject<FieldValues>, from existing: FieldValues, definition: TemplateDefinition?) -> KeptObject<FieldValues> {
        let stripped = stripping(incoming, definition: definition)
        return stripped.replacingValue(keepingLocalSecrets(stripped.value, from: existing, definition: definition))
    }

    /// Incoming rows (from an archive, which never carries secret rows) with the
    /// secret rows this phone already keeps for the same record.
    public static func keepingLocalSecretFacts(_ incoming: [CustomFact], from existing: [CustomFact]) -> [CustomFact] {
        keepingLocalSecretFacts(KeptList(incoming), from: KeptList(existing)).items
    }

    /// The phone's secret rows of a record, as stored: those this build reads, with what a newer
    /// build wrote inside them, and those it can't read that say they are secret or hold anything
    /// sealed. What a restore keeps of the phone's own (`DossierImporter.PhoneKeeps`).
    public static func secretFacts(of facts: KeptList<CustomFact>) -> KeptList<CustomFact> {
        facts.filtered(\.isSecret, unreadable: { sealedPart($0) != nil })
    }

    /// Rows as an archive carries them (none secret, read or not) with every secret row this phone
    /// keeps for the same record, read or not, each as it is stored here: they are never exported,
    /// so the phone's copy is the only one. A row from the archive with the same id gives way.
    public static func keepingLocalSecretFacts(_ incoming: KeptList<CustomFact>, from existing: KeptList<CustomFact>) -> KeptList<CustomFact> {
        strippingFacts(incoming).replacingEntries(with: secretFacts(of: existing))
    }
}

extension FieldDefinition {
    /// A secret: kept sealed, shown only after a fresh Face ID, never carried outward.
    public var isSecret: Bool { type == .secret }

    /// Whether the value may appear in search: neither sensitive nor secret.
    public var isIndexable: Bool { !isSensitive && !isSecret }
}

/// Why a secret couldn't be kept or opened, in plain words.
public enum SecretFieldError: LocalizedError, Equatable {
    /// The phone's Keychain refused to keep or give the key.
    case keyUnavailable
    /// The sealed value can't be opened with any key this device has, and no other device's key
    /// has reached this one: it was written on another of the person's devices that hasn't shared
    /// its key yet, or iCloud Keychain is off on one of them (this device can't tell which), or it
    /// was restored from a phone whose key is gone. It is kept as it is, never written over.
    case unreadable
    /// The same, while keys of the person's other devices do reach this one, so iCloud Keychain
    /// works here: the device that wrote the code hasn't shared its key yet (it does once the app
    /// opens there to sync), or iCloud Keychain is off there.
    case notSharedYet

    public var errorDescription: String? {
        switch self {
        case .keyUnavailable:
            return String(localized: "Codul nu s-a putut păstra în siguranță pe acest telefon. Încearcă din nou peste puțin timp.")
        case .unreadable:
            return String(localized: "Codul a fost scris pe alt dispozitiv. Deschide aplicația pe el, apoi încearcă din nou aici peste câteva minute. Dacă tot nu se deschide, pornește Parole în iCloud pe ambele, din Configurări.", comment: "A sealed code from another device; no other device's key has reached this one, so either device may have iCloud Keychain off.")
        case .notSharedYet:
            return String(localized: "Codul a fost scris pe alt dispozitiv. Deschide aplicația pe el, cu Parole în iCloud pornit, apoi încearcă din nou aici peste câteva minute.", comment: "A sealed code from another device that hasn't shared its key yet; iCloud Keychain works on this one.")
        }
    }
}

/// Seals and opens secret values with AES-GCM. A secret is sealed with this device's own key
/// (`sealingKey`) and opened with whichever key of the person's devices opens it (`openingKeys`):
/// AES-GCM tells a wrong key at once. The keys are read only when a secret is sealed or opened.
public struct SecretSealer: Sendable {
    /// Marks sealed text, with the format's version.
    public static let prefix = "sealed:v1:"

    private let sealingKey: @Sendable () throws -> SymmetricKey
    private let openingKeys: @Sendable () throws -> [SymmetricKey]

    /// One key that seals and opens.
    public init(key: @escaping @Sendable () throws -> SymmetricKey) {
        self.init(sealingKey: key, openingKeys: { [try key()] })
    }

    public init(sealingKey: @escaping @Sendable () throws -> SymmetricKey, openingKeys: @escaping @Sendable () throws -> [SymmetricKey]) {
        self.sealingKey = sealingKey
        self.openingKeys = openingKeys
    }

    public static func isSealed(_ text: String) -> Bool {
        text.hasPrefix(prefix)
    }

    public func seal(_ plain: String) throws -> String {
        let box = try AES.GCM.seal(Data(plain.utf8), using: try sealingKey())
        guard let combined = box.combined else { throw SecretFieldError.keyUnavailable }
        return Self.prefix + combined.base64EncodedString()
    }

    public func open(_ sealed: String) throws -> String {
        guard Self.isSealed(sealed), let data = Data(base64Encoded: String(sealed.dropFirst(Self.prefix.count))) else {
            throw SecretFieldError.unreadable
        }
        guard let box = try? AES.GCM.SealedBox(combined: data) else { throw SecretFieldError.unreadable }
        let keys = try openingKeys()
        for key in keys {
            guard let plain = try? AES.GCM.open(box, using: key) else { continue }
            guard let text = String(data: plain, encoding: .utf8) else { throw SecretFieldError.unreadable }
            return text
        }
        // More than one key means another device's key reached this one: iCloud Keychain works here.
        throw keys.count > 1 ? SecretFieldError.notSharedYet : SecretFieldError.unreadable
    }

    /// The person's keys (`SecretKeyring.standard`): this device's own seals, and the key of each of
    /// their devices that iCloud Keychain brought opens what that device sealed.
    public static let device = SecretSealer(
        sealingKey: { try SecretKeyring.standard.sealingKey() },
        openingKeys: { try SecretKeyring.standard.openingKeys() }
    )

    /// A key that lives only as long as the process, for tests and previews.
    public static func ephemeral() -> SecretSealer {
        let key = SymmetricKey(size: .bits256)
        return SecretSealer { key }
    }
}

/// Where the sealing keys are kept: the Keychain, or a stand-in in tests.
protocol SecretKeyStore: Sendable {
    /// The key kept under `account`, synced through iCloud Keychain or kept on this device only.
    func read(account: String, synchronizable: Bool) throws -> Data?
    /// Every key synced through iCloud Keychain, by account.
    func readSynchronizable() throws -> [String: Data]
    /// Adds a key; false when one is already kept under `account`. A synced key is kept only while
    /// the device is unlocked; this device's own, only while it is unlocked and only on it.
    func add(_ data: Data, account: String, synchronizable: Bool) throws -> Bool
    /// The accounts of the synced keys an earlier build kept readable while the device is locked.
    func syncedKeysReadableWhileLocked() throws -> [String]
    /// Keeps the synced key under `account` only while the device is unlocked, its value as it is.
    func keepOnlyWhileUnlocked(syncedAccount account: String) throws
}

/// The sealing keys of the person's devices, so a code sealed on one opens on the others.
///
/// - **This device's own key** seals. It is kept on this device only (`ownAccount`,
///   `WhenUnlockedThisDeviceOnly`), as every build before kept it, and never removed: it is the way
///   back while the synced copy isn't proven.
/// - **A synced copy of it** goes to iCloud Keychain under an account named after the key
///   (`syncedAccount`, `WhenUnlocked`, synchronizable), so each device adds its own and none
///   ever writes over another's. It is added as soon as the binder opens to sync
///   (`SecretKeySharing`), and again whenever a code is sealed or opened, and read back before it
///   counts; until then the device keeps using its own key alone.
/// - **Every synced copy is kept only while the device is unlocked**, like the device's own key:
///   nothing opens a code while the phone is locked (reminders, widgets and search never carry
///   one). A copy an earlier build kept readable after the first unlock is moved to the stronger
///   class in place (`keepOnlyWhileUnlocked`), its value untouched, and read back.
/// - **Opening** tries this device's key, then every key iCloud Keychain brought. Where iCloud
///   Keychain is off, a code sealed on another device stays sealed and shows that it opens there
///   (`SecretFieldError.unreadable`); nothing writes over it.
/// - The keys travel only through iCloud Keychain, end-to-end encrypted; never in the binder, a
///   backup or iCloud's database.
struct SecretKeyring: Sendable {
    let store: any SecretKeyStore

    static let standard = SecretKeyring(store: KeychainSecretKeyStore())

    /// The account this device's own key has always been kept under.
    static let ownAccount = "sealing-key.v1"
    /// The start of every synced key's account; the rest is the key's fingerprint.
    static let syncedPrefix = "sealing-key.synced."

    static func syncedAccount(for key: Data) -> String {
        syncedPrefix + Hashing.sha256(key).prefix(16)
    }

    /// Shares this device's key with the person's other devices, when it has one: its synced copy,
    /// with every synced copy kept only while unlocked. Throws when the Keychain can't be read now
    /// (the phone is locked), so the caller tries again once it is unlocked. Nothing is made: a
    /// device that never sealed a code has no key to share yet.
    func shareOwnKey() throws {
        guard let own = try store.read(account: Self.ownAccount, synchronizable: false), own.count == 32 else {
            strengthenSyncedCopies()
            return
        }
        keepSyncedCopy(of: own)
    }

    /// This device's own key, made once, with its synced copy kept in step.
    func sealingKey() throws -> SymmetricKey {
        let own: Data
        if let existing = try store.read(account: Self.ownAccount, synchronizable: false) {
            own = existing
        } else {
            let made = SymmetricKey(size: .bits256).withUnsafeBytes { Data($0) }
            if try store.add(made, account: Self.ownAccount, synchronizable: false) {
                own = made
            } else if let raced = try store.read(account: Self.ownAccount, synchronizable: false) {
                own = raced
            } else {
                throw SecretFieldError.keyUnavailable
            }
        }
        guard own.count == 32 else { throw SecretFieldError.keyUnavailable }
        keepSyncedCopy(of: own)
        return SymmetricKey(data: own)
    }

    /// Every key that may open a code: this device's own first, then the ones iCloud Keychain brought.
    func openingKeys() throws -> [SymmetricKey] {
        var keys: [Data] = []
        if let own = try? sealingKey().withUnsafeBytes({ Data($0) }) { keys.append(own) }
        for (_, key) in ((try? store.readSynchronizable()) ?? [:]).sorted(by: { $0.key < $1.key }) where key.count == 32 && !keys.contains(key) {
            keys.append(key)
        }
        guard !keys.isEmpty else { throw SecretFieldError.keyUnavailable }
        return keys.map { SymmetricKey(data: $0) }
    }

    /// Whether this device's key is in iCloud Keychain, read back as it is.
    func isSynced(_ own: Data) -> Bool {
        (try? store.read(account: Self.syncedAccount(for: own), synchronizable: true)) == own
    }

    /// Adds the synced copy of `own` when it isn't there yet, after keeping every synced copy only
    /// while unlocked. A failure changes nothing: the device's own key still seals and opens, and
    /// the next use tries again.
    private func keepSyncedCopy(of own: Data) {
        strengthenSyncedCopies()
        guard !isSynced(own) else { return }
        _ = try? store.add(own, account: Self.syncedAccount(for: own), synchronizable: true)
    }

    /// Moves every synced copy an earlier build kept readable while locked to the stronger class,
    /// one at a time, in place, its value untouched: this device's and those of the person's other
    /// devices alike, so a device still on an earlier build is covered too. Each is read back and
    /// put back as it was if it isn't there; one that didn't move stays as it was and is tried
    /// again next time. This device's own key is never touched.
    private func strengthenSyncedCopies() {
        guard let weaker = try? store.syncedKeysReadableWhileLocked() else { return }
        for account in weaker where account.hasPrefix(Self.syncedPrefix) {
            guard let before = try? store.read(account: account, synchronizable: true) else { continue }
            do {
                try store.keepOnlyWhileUnlocked(syncedAccount: account)
            } catch {
                PersistenceLog.failed("Keep a synced key only while unlocked", error)
                continue
            }
            // Read back: a key that isn't there as it was is put back, never lost.
            if (try? store.read(account: account, synchronizable: true)) != before {
                _ = try? store.add(before, account: account, synchronizable: true)
            }
        }
    }
}

/// Shares this device's sealing key as soon as the binder opens to sync with iCloud, so a code
/// sealed before sync (or on an earlier build) opens on the person's other devices without waiting
/// for the next code sealed or opened here. `PersistenceController` starts it each time the store
/// opens to sync, launch included. It runs off the main thread, one at a time; when the Keychain
/// can't be read yet (the phone is locked), it tries again once the phone is unlocked. Sharing is
/// idempotent: a key already shared is only read back.
@MainActor
final class SecretKeySharing {
    static let standard = SecretKeySharing(ring: .standard)

    private let ring: SecretKeyring
    private let center: NotificationCenter
    private let unlocked: Notification.Name
    private var unlockObserver: (any NSObjectProtocol)?
    /// The sharing under way, if any.
    private(set) var running: Task<Void, Never>?
    /// Whether it waits for the phone to be unlocked to try again.
    var isWaitingForUnlock: Bool { unlockObserver != nil }

    init(ring: SecretKeyring, center: NotificationCenter = .default, unlocked: Notification.Name = SecretKeySharing.protectedDataAvailable) {
        self.ring = ring
        self.center = center
        self.unlocked = unlocked
    }

    /// Shares the key, unless a sharing is already under way.
    func start() {
        guard running == nil else { return }
        let ring = ring
        running = Task {
            let shared = await Task.detached(priority: .utility) { (try? ring.shareOwnKey()) != nil }.value
            running = nil
            if shared { stopWaiting() } else { waitForUnlock() }
        }
    }

    private func waitForUnlock() {
        guard unlockObserver == nil else { return }
        unlockObserver = center.addObserver(forName: unlocked, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.stopWaiting()
                self?.start()
            }
        }
    }

    private func stopWaiting() {
        if let unlockObserver { center.removeObserver(unlockObserver) }
        unlockObserver = nil
    }

    /// The system's word that the phone's protected files (and the Keychain) can be read.
    nonisolated static var protectedDataAvailable: Notification.Name {
        #if canImport(UIKit)
        UIApplication.protectedDataDidBecomeAvailableNotification
        #else
        Notification.Name("protectedDataDidBecomeAvailable")
        #endif
    }
}

/// The Keychain, under the app's service for its secrets.
struct KeychainSecretKeyStore: SecretKeyStore {
    private static let service = "com.dosarcusina.app.secretFields"

    func read(account: String, synchronizable: Bool) throws -> Data? {
        var query = base(account: account, synchronizable: synchronizable)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: AnyObject?
        switch SecItemCopyMatching(query as CFDictionary, &result) {
        case errSecSuccess: return result as? Data
        case errSecItemNotFound: return nil
        default: throw SecretFieldError.keyUnavailable
        }
    }

    func readSynchronizable() throws -> [String: Data] {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.service,
            kSecAttrSynchronizable as String: true,
            kSecReturnData as String: true,
            kSecReturnAttributes as String: true,
            kSecMatchLimit as String: kSecMatchLimitAll,
        ]
        var result: AnyObject?
        switch SecItemCopyMatching(query as CFDictionary, &result) {
        case errSecSuccess:
            var keys: [String: Data] = [:]
            for item in result as? [[String: Any]] ?? [] {
                guard let account = item[kSecAttrAccount as String] as? String, account.hasPrefix(SecretKeyring.syncedPrefix),
                      let data = item[kSecValueData as String] as? Data else { continue }
                keys[account] = data
            }
            return keys
        case errSecItemNotFound: return [:]
        default: throw SecretFieldError.keyUnavailable
        }
    }

    func add(_ data: Data, account: String, synchronizable: Bool) throws -> Bool {
        var item = base(account: account, synchronizable: synchronizable)
        item[kSecValueData as String] = data
        // Both only while the phone is unlocked: the synced copy in a class that goes to the
        // person's devices, this device's own on it alone, as before.
        item[kSecAttrAccessible as String] = synchronizable ? kSecAttrAccessibleWhenUnlocked : kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        switch SecItemAdd(item as CFDictionary, nil) {
        case errSecSuccess: return true
        case errSecDuplicateItem: return false
        default: throw SecretFieldError.keyUnavailable
        }
    }

    func syncedKeysReadableWhileLocked() throws -> [String] {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.service,
            kSecAttrSynchronizable as String: true,
            kSecReturnAttributes as String: true,
            kSecMatchLimit as String: kSecMatchLimitAll,
        ]
        var result: AnyObject?
        switch SecItemCopyMatching(query as CFDictionary, &result) {
        case errSecSuccess:
            return (result as? [[String: Any]] ?? []).compactMap { item in
                guard let account = item[kSecAttrAccount as String] as? String, account.hasPrefix(SecretKeyring.syncedPrefix) else { return nil }
                let accessible = item[kSecAttrAccessible as String] as? String
                return accessible == (kSecAttrAccessibleWhenUnlocked as String) ? nil : account
            }
        case errSecItemNotFound: return []
        default: throw SecretFieldError.keyUnavailable
        }
    }

    func keepOnlyWhileUnlocked(syncedAccount account: String) throws {
        let change: [String: Any] = [kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlocked]
        guard SecItemUpdate(base(account: account, synchronizable: true) as CFDictionary, change as CFDictionary) == errSecSuccess else {
            throw SecretFieldError.keyUnavailable
        }
    }

    private func base(account: String, synchronizable: Bool) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.service,
            kSecAttrAccount as String: account,
            kSecAttrSynchronizable as String: synchronizable,
        ]
    }
}

/// Opening a secret to show or copy it: a fresh Face ID or passcode every
/// time, without opening the session for anything else.
@MainActor
public struct SecretReveal {
    public let vault: BiometricVaultManager
    public let sealer: SecretSealer

    public init(vault: BiometricVaultManager, sealer: SecretSealer = .device) {
        self.vault = vault
        self.sealer = sealer
    }

    public enum Outcome: Equatable {
        case revealed(String)
        /// The person cancelled or authentication failed: nothing shown, nothing said.
        case notAuthenticated
        case failed(SecretFieldError)
    }

    public func open(_ sealed: String, reason: String) async -> Outcome {
        guard await vault.authenticateForReveal(reason: reason) == .success else { return .notAuthenticated }
        do {
            return .revealed(try sealer.open(sealed))
        } catch let error as SecretFieldError {
            return .failed(error)
        } catch {
            return .failed(.unreadable)
        }
    }
}
