import CryptoKit
import Foundation
import Security

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

    /// Only the sealed values, by their own form.
    public static func sealedValues(in values: FieldValues) -> FieldValues {
        var result = FieldValues()
        for (key, value) in values where isSealed(value) { result[key] = value }
        return result
    }

    /// The person's own rows without the secret ones, for anything that leaves the binder.
    public static func strippingFacts(_ facts: [CustomFact]) -> [CustomFact] {
        facts.filter { !$0.isSecret }
    }

    /// The same for rows as stored: a row this build can't read is left out too when it says
    /// it is secret or anything in it is sealed.
    public static func strippingFacts(_ facts: KeptList<CustomFact>) -> KeptList<CustomFact> {
        facts.replacingItems(strippingFacts(facts.items)).keepingUnreadable { raw in
            raw["isSecret"]?.bool != true && !raw.containsString(where: SecretSealer.isSealed)
        }
    }

    /// The values with every secret typed in plain sealed. Values already sealed
    /// pass through unchanged.
    public static func sealing(_ values: FieldValues, definition: TemplateDefinition, sealer: SecretSealer) throws -> FieldValues {
        var result = values
        for field in fields(in: definition) {
            guard let text = values[field.key]?.textValue, !SecretSealer.isSealed(text) else { continue }
            let plain = text.trimmingCharacters(in: .whitespacesAndNewlines)
            result[field.key] = plain.isEmpty ? nil : .text(try sealer.seal(plain))
        }
        return result
    }

    /// The person's rows with every secret row typed in plain sealed. Rows
    /// already sealed pass through unchanged; a secret row left empty keeps no value.
    public static func sealingFacts(_ facts: [CustomFact], sealer: SecretSealer) throws -> [CustomFact] {
        try facts.map { fact in
            guard fact.isSecret, !SecretSealer.isSealed(fact.value) else { return fact }
            var sealed = fact
            sealed.isSensitive = true
            let plain = fact.value.trimmingCharacters(in: .whitespacesAndNewlines)
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
        return result
    }

    /// Incoming rows (from an archive, which never carries secret rows) with the
    /// secret rows this phone already keeps for the same record.
    public static func keepingLocalSecretFacts(_ incoming: [CustomFact], from existing: [CustomFact]) -> [CustomFact] {
        let kept = existing.filter(\.isSecret)
        let keptIDs = Set(kept.map(\.id))
        return strippingFacts(incoming).filter { !keptIDs.contains($0.id) } + kept
    }

    /// The same for rows as an archive carries them, with the rows it can't read (none secret).
    public static func keepingLocalSecretFacts(_ incoming: KeptList<CustomFact>, from existing: [CustomFact]) -> KeptList<CustomFact> {
        let stripped = strippingFacts(incoming)
        return stripped.replacingItems(keepingLocalSecretFacts(stripped.items, from: existing))
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
    /// The sealed value can't be opened with this phone's key (it was restored
    /// onto another phone, or written by one).
    case unreadable

    public var errorDescription: String? {
        switch self {
        case .keyUnavailable:
            return String(localized: "Codul nu s-a putut păstra în siguranță pe acest telefon. Încearcă din nou peste puțin timp.")
        case .unreadable:
            return String(localized: "Codul nu se mai poate citi pe acest telefon. Scrie-l din nou, din Editează.")
        }
    }
}

/// Seals and opens secret values with AES-GCM. The key comes from `key`, read
/// only when a secret is actually sealed or opened.
public struct SecretSealer: Sendable {
    /// Marks sealed text, with the format's version.
    public static let prefix = "sealed:v1:"

    private let key: @Sendable () throws -> SymmetricKey

    public init(key: @escaping @Sendable () throws -> SymmetricKey) {
        self.key = key
    }

    public static func isSealed(_ text: String) -> Bool {
        text.hasPrefix(prefix)
    }

    public func seal(_ plain: String) throws -> String {
        let box = try AES.GCM.seal(Data(plain.utf8), using: try key())
        guard let combined = box.combined else { throw SecretFieldError.keyUnavailable }
        return Self.prefix + combined.base64EncodedString()
    }

    public func open(_ sealed: String) throws -> String {
        guard Self.isSealed(sealed), let data = Data(base64Encoded: String(sealed.dropFirst(Self.prefix.count))) else {
            throw SecretFieldError.unreadable
        }
        let symmetricKey = try key()
        do {
            let plain = try AES.GCM.open(AES.GCM.SealedBox(combined: data), using: symmetricKey)
            guard let text = String(data: plain, encoding: .utf8) else { throw SecretFieldError.unreadable }
            return text
        } catch {
            throw SecretFieldError.unreadable
        }
    }

    /// The phone's own key: made once, kept in the Keychain for this device only,
    /// readable while the phone is unlocked.
    public static let device = SecretSealer { try DeviceSecretKey.load() }

    /// A key that lives only as long as the process, for tests and previews.
    public static func ephemeral() -> SecretSealer {
        let key = SymmetricKey(size: .bits256)
        return SecretSealer { key }
    }
}

/// The Keychain item that holds the sealing key.
enum DeviceSecretKey {
    private static let service = "com.dosarcusina.app.secretFields"
    private static let account = "sealing-key.v1"

    static func load() throws -> SymmetricKey {
        if let existing = try read() { return existing }
        let key = SymmetricKey(size: .bits256)
        let data = key.withUnsafeBytes { Data($0) }
        let add: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
        ]
        let status = SecItemAdd(add as CFDictionary, nil)
        if status == errSecDuplicateItem, let raced = try read() { return raced }
        guard status == errSecSuccess else { throw SecretFieldError.keyUnavailable }
        return key
    }

    private static func read() throws -> SymmetricKey? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        switch status {
        case errSecSuccess:
            guard let data = result as? Data, data.count == 32 else { throw SecretFieldError.keyUnavailable }
            return SymmetricKey(data: data)
        case errSecItemNotFound:
            return nil
        default:
            throw SecretFieldError.keyUnavailable
        }
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
