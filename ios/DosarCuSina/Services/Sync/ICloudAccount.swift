import CloudKit
import CryptoKit
import Foundation

/// The iCloud account the phone is signed into, as far as the binder needs to know: whether
/// there is one, and which one (an opaque id, kept only as a digest on this phone).
///
/// It is an input to whether the binder syncs (`PersistenceController.choice`): iCloud's
/// mirroring clears a store's local copy when the account it synced with goes or changes, so
/// the store opens with iCloud only for the account it synced with before (or the first one),
/// and only once that is known.
public enum ICloudAccount: Equatable, Sendable {
    /// Signed in. `id` is a digest of the account's id for this app; nil when iCloud didn't say.
    case signedIn(id: String?)
    /// No account, iCloud is off for the app, or a restriction keeps it out.
    case none
    /// iCloud couldn't say just now (no network the first time, the account being set up).
    case unknown
}

/// Reads the account. The app's own reads CloudKit; tests give one of their own.
public protocol ICloudAccountReader: Sendable {
    func current() async -> ICloudAccount
}

/// The account as CloudKit sees it, for the binder's container.
public struct SystemICloudAccountReader: ICloudAccountReader {
    let containerIdentifier: String

    public init(containerIdentifier: String = PersistenceController.cloudKitContainer) {
        self.containerIdentifier = containerIdentifier
    }

    public func current() async -> ICloudAccount {
        let container = CKContainer(identifier: containerIdentifier)
        let status: CKAccountStatus
        do {
            status = try await container.accountStatus()
        } catch {
            return .unknown
        }
        switch status {
        case .available:
            guard let record = try? await container.userRecordID() else { return .signedIn(id: nil) }
            return .signedIn(id: Self.digest(of: record.recordName))
        case .noAccount, .restricted:
            return .none
        case .temporarilyUnavailable, .couldNotDetermine:
            return .unknown
        @unknown default:
            return .unknown
        }
    }

    /// The account's id is never kept as it is: a digest is enough to tell two apart.
    static func digest(of recordName: String) -> String {
        MachineText.hex(SHA256.hash(data: Data(recordName.utf8)))
    }
}

/// What this phone remembers about sync between launches, beside the store and never in it:
/// which account the binder synced with, and whether that account's binder finished coming
/// down the first time (so a new device knows whether one may still be on its way).
public protocol SyncMemory: AnyObject {
    /// The digest of the account the binder last synced with; nil before it ever synced.
    var syncedAccount: String? { get set }
    /// The digest of the account whose first download finished on this phone.
    var firstDownloadFinishedFor: String? { get set }
}

/// The phone’s own copy, in the app’s preferences on this device (which are safe from any thread).
public final class DeviceSyncMemory: SyncMemory, @unchecked Sendable {
    public static let shared = DeviceSyncMemory()

    private let defaults: UserDefaults
    private enum Key {
        static let syncedAccount = "sync.syncedAccount"
        static let firstDownload = "sync.firstDownloadFinishedFor"
    }

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public var syncedAccount: String? {
        get { defaults.string(forKey: Key.syncedAccount) }
        set { defaults.set(newValue, forKey: Key.syncedAccount) }
    }

    public var firstDownloadFinishedFor: String? {
        get { defaults.string(forKey: Key.firstDownload) }
        set { defaults.set(newValue, forKey: Key.firstDownload) }
    }
}

/// A memory that lives only as long as it is kept, for tests and previews.
public final class InMemorySyncMemory: SyncMemory {
    public var syncedAccount: String?
    public var firstDownloadFinishedFor: String?
    public init(syncedAccount: String? = nil, firstDownloadFinishedFor: String? = nil) {
        self.syncedAccount = syncedAccount
        self.firstDownloadFinishedFor = firstDownloadFinishedFor
    }
}
