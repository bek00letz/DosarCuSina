import CloudKit
import CoreData
import Foundation

/// One step of iCloud's mirroring, as `NSPersistentCloudKitContainer` reports it
/// (`eventChangedNotification`): setting up, bringing changes down, sending them up; started or
/// finished, and what went wrong. Plain values, so the rules below are tested without iCloud.
public struct SyncEvent: Equatable, Sendable {
    public enum Kind: Equatable, Sendable {
        case setup
        case download
        case upload
    }

    public var kind: Kind
    /// Nil while it runs.
    public var finishedAt: Date?
    public var succeeded: Bool
    public var problem: SyncProblem?

    public init(kind: Kind, finishedAt: Date?, succeeded: Bool, problem: SyncProblem? = nil) {
        self.kind = kind
        self.finishedAt = finishedAt
        self.succeeded = succeeded
        self.problem = problem
    }

    /// The event a notification carries; nil for a kind this build doesn't know.
    init?(_ event: NSPersistentCloudKitContainer.Event) {
        switch event.type {
        case .setup: kind = .setup
        case .import: kind = .download
        case .export: kind = .upload
        @unknown default: return nil
        }
        finishedAt = event.endDate
        succeeded = event.succeeded
        problem = event.error.map(SyncProblem.init)
    }
}

/// What went wrong with a sync step, in the few kinds the person can act on.
public enum SyncProblem: Equatable, Sendable {
    /// The person's iCloud storage is full: nothing more goes up.
    case iCloudFull
    /// iCloud says no one is signed in (or iCloud is off for the app).
    case notSignedIn
    /// No network, or iCloud can't be reached.
    case offline
    /// iCloud asked to wait (busy, too many requests): the system tries again by itself.
    case busy
    /// Anything else: the system tries again by itself.
    case other

    /// The kind of `error`, at any depth: a CloudKit error, one of several (a partial failure),
    /// or one wrapped by Core Data.
    public init(_ error: any Error) {
        self = Self.find(in: error as NSError) ?? .other
    }

    private static func find(in error: NSError) -> SyncProblem? {
        if error.domain == CKError.errorDomain {
            let code = CKError.Code(rawValue: error.code)
            switch code {
            case .quotaExceeded: return .iCloudFull
            case .notAuthenticated, .accountTemporarilyUnavailable, .managedAccountRestricted: return .notSignedIn
            case .networkUnavailable, .networkFailure: return .offline
            case .serviceUnavailable, .requestRateLimited, .zoneBusy: return .busy
            case .partialFailure:
                let parts = (error.userInfo[CKPartialErrorsByItemIDKey] as? [AnyHashable: any Error])?.values.map { $0 as NSError } ?? []
                let kinds = parts.compactMap(find(in:))
                // The one the person must act on first.
                for kind in [SyncProblem.iCloudFull, .notSignedIn, .offline, .busy] where kinds.contains(kind) { return kind }
                return kinds.isEmpty ? nil : .other
            default: break
            }
        }
        if let underlying = error.userInfo[NSUnderlyingErrorKey] as? NSError { return find(in: underlying) }
        return nil
    }
}

/// How sync is going, from the mirroring's events: one value, shown in Settings in plain words
/// (`SyncWording`), with what to do.
public enum SyncHealth: Equatable, Sendable {
    /// Nothing has finished yet since the store opened.
    case starting
    /// The first download on this phone is under way: a binder may be on its way.
    case downloading
    /// Everything went up and came down; when the last step finished.
    case upToDate(Date)
    /// No network: changes stay on the phone and go when it comes back.
    case waitingForNetwork
    /// iCloud asked to wait; the system tries again by itself.
    case retrying
    /// The person's iCloud storage is full.
    case iCloudFull
    /// iCloud says no one is signed in.
    case notSignedIn
}

/// Follows the mirroring's events into one `SyncHealth`, and remembers when the first download
/// finished for the account (`SyncMemory`). Pure apart from that memory, so it is tested with
/// made-up events.
@MainActor
final class SyncHealthTracker {
    private(set) var health: SyncHealth = .starting
    /// Whether this account's binder finished coming down on this phone at least once.
    private(set) var firstDownloadFinished: Bool
    private let account: String?
    private let memory: SyncMemory

    init(account: String?, memory: SyncMemory) {
        self.account = account
        self.memory = memory
        firstDownloadFinished = account != nil && memory.firstDownloadFinishedFor == account
        health = firstDownloadFinished ? .starting : .downloading
    }

    /// Takes in one event and returns the problem the person must act on, if it brought one.
    @discardableResult
    func record(_ event: SyncEvent) -> SyncProblem? {
        guard let finishedAt = event.finishedAt else {
            if event.kind == .download, !firstDownloadFinished { health = .downloading }
            return nil
        }
        if event.succeeded {
            if event.kind == .download, !firstDownloadFinished {
                firstDownloadFinished = true
                if let account { memory.firstDownloadFinishedFor = account }
            }
            if event.kind != .setup || firstDownloadFinished { health = firstDownloadFinished ? .upToDate(finishedAt) : .downloading }
            return nil
        }
        let problem = event.problem ?? .other
        switch problem {
        case .iCloudFull: health = .iCloudFull
        case .notSignedIn: health = .notSignedIn
        case .offline: health = .waitingForNetwork
        case .busy, .other: health = .retrying
        }
        return problem
    }
}
