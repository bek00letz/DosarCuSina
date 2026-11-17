import FileProvider
import Foundation
import OSLog

/// Why something shared with the share sheet didn't arrive, as a kind only: what the
/// confirmation says (`ShareConfirmation`) and what the share log keeps (`ShareFailureLog`).
/// Worked out from the error the system gave (`init(_:)`), never from a file's name or path.
public enum ShareFailure: String, Codable, Sendable, CaseIterable {
    /// The file is in iCloud (or another cloud service) and couldn't be downloaded now.
    case stillInCloud
    /// Downloading it needs the internet, and the phone isn't connected.
    case offline
    /// The phone has no room left for the copy.
    case noRoom
    /// The app it came from didn't let the share read it.
    case noAccess
    /// A file, or the whole share, is bigger than the inbox accepts (`ShareInbox.maxFileBytes`).
    case tooLarge
    /// The app it came from handed over nothing: no file, no data.
    case notHandedOver
    /// The App Group's folder isn't there, so there is nowhere to put it.
    case inboxUnavailable
    /// Copying failed for a reason the system didn't name.
    case couldNotCopy

    /// The order in which a reason says more, so a share that failed several ways (the typed
    /// file, then the link to it) is told the most useful one: a known cause before an unnamed one.
    public static let mostTellingFirst: [ShareFailure] = [
        .noRoom, .tooLarge, .offline, .stillInCloud, .noAccess, .inboxUnavailable, .notHandedOver, .couldNotCopy,
    ]

    /// The most telling of several reasons, or nil for none.
    public static func mostTelling(_ failures: some Sequence<ShareFailure>) -> ShareFailure? {
        let found = Set(failures)
        return mostTellingFirst.first(where: found.contains)
    }

    /// What an error means for a share, from its domain and code, and those of the errors
    /// under it (`NSUnderlyingErrorKey`): the system often wraps the telling one.
    public init(_ error: any Error) {
        if let inbox = error as? ShareInbox.InboxError {
            self = switch inbox {
            case .tooLarge: .tooLarge
            case .nothingToSave: .notHandedOver
            }
            return
        }
        for layer in Self.layers(of: error) {
            if let known = Self.known(domain: layer.domain, code: layer.code) {
                self = known
                return
            }
        }
        self = .couldNotCopy
    }

    /// The error and the ones it wraps, outermost first, a few deep.
    static func layers(of error: any Error) -> [NSError] {
        var layers: [NSError] = []
        var next: NSError? = error as NSError
        while let current = next, layers.count < 4 {
            layers.append(current)
            next = current.userInfo[NSUnderlyingErrorKey] as? NSError
        }
        return layers
    }

    private static func known(domain: String, code: Int) -> ShareFailure? {
        switch domain {
        case NSCocoaErrorDomain:
            switch code {
            case NSFileWriteOutOfSpaceError: return .noRoom
            case NSUbiquitousFileUnavailableError: return .stillInCloud
            case NSFileReadNoPermissionError, NSFileWriteNoPermissionError: return .noAccess
            case NSFileReadNoSuchFileError, NSFileNoSuchFileError: return .notHandedOver
            default: return nil
            }
        case NSPOSIXErrorDomain:
            switch POSIXErrorCode(rawValue: Int32(clamping: code)) {
            case .ENOSPC, .EDQUOT: return .noRoom
            // A file whose contents are still in the cloud and weren't brought down for the read.
            case .EDEADLK: return .stillInCloud
            case .EPERM, .EACCES: return .noAccess
            case .ENOENT: return .notHandedOver
            default: return nil
            }
        case NSURLErrorDomain:
            switch URLError.Code(rawValue: code) {
            case .notConnectedToInternet, .networkConnectionLost, .cannotFindHost, .cannotConnectToHost,
                 .timedOut, .dataNotAllowed, .internationalRoamingOff:
                return .offline
            default: return nil
            }
        case NSFileProviderErrorDomain:
            switch NSFileProviderError.Code(rawValue: code) {
            case .serverUnreachable: return .offline
            case .notAuthenticated, .cannotSynchronize: return .stillInCloud
            case .noSuchItem: return .notHandedOver
            default: return nil
            }
        case NSItemProvider.errorDomain:
            switch NSItemProvider.ErrorCode(rawValue: code) {
            case .itemUnavailableError, .unexpectedValueClassError, .unavailableCoercionError: return .notHandedOver
            default: return nil
            }
        default:
            return nil
        }
    }
}

/// The share log: why the last shares that didn't arrive failed, so the next failure can be
/// seen. The share extension writes it (it runs while the app doesn't), the app reads it.
///
/// It keeps kinds only, as the persistence log does: which way the share tried (the typed
/// file, its data, the link to it), the reason (`ShareFailure`) and the error's system domain
/// and code. Never a file's name, a path, a value or anything the file holds. Kept beside the
/// inbox's items (`ShareInbox.failureLogName`), the latest `ShareFailureLog.kept` only.
public enum ShareFailureLog {
    static let logger = Logger(subsystem: "com.ar.dosarcusina.app", category: "share")

    /// How many failures the log keeps; older ones go.
    public static let kept = 20

    /// One way a share tried to receive an item, and how it failed.
    public struct Attempt: Codable, Hashable, Sendable {
        /// Which way: `ShareReceiving.Way.logName`, or the inbox's own step (`inbox`, `commit`).
        public var way: String
        public var failure: ShareFailure
        /// The system's error domain when it is one of the system's own (`ShareFailureLog.domains`),
        /// else "other". Never anything a sending app wrote.
        public var domain: String
        public var code: Int

        public init(way: String, failure: ShareFailure, domain: String, code: Int) {
            self.way = way
            self.failure = failure
            self.domain = domain
            self.code = code
        }

        /// The attempt for `error`, keeping the innermost error's domain and code that the
        /// system names (the one that says most), else the outermost.
        public init(way: String, error: any Error) {
            let layers = ShareFailure.layers(of: error)
            let named = layers.last(where: { ShareFailureLog.domains.contains($0.domain) }) ?? layers[0]
            self.init(
                way: way,
                failure: ShareFailure(error),
                domain: ShareFailureLog.domains.contains(named.domain) ? named.domain : "other",
                code: ShareFailureLog.domains.contains(named.domain) ? named.code : 0
            )
        }
    }

    /// One item of a share that didn't arrive: when, the reason told, and every way tried.
    public struct Entry: Codable, Hashable, Sendable {
        public var at: Date
        public var failure: ShareFailure
        public var attempts: [Attempt]

        public init(at: Date, failure: ShareFailure, attempts: [Attempt]) {
            self.at = at
            self.failure = failure
            self.attempts = attempts
        }
    }

    /// The error domains whose name the log keeps: the system's own.
    static let domains: Set<String> = [
        NSCocoaErrorDomain, NSPOSIXErrorDomain, NSURLErrorDomain, NSFileProviderErrorDomain,
        NSItemProvider.errorDomain, NSOSStatusErrorDomain, NSMachErrorDomain,
    ]

    /// Keeps `entry` in `inbox`'s log, newest last, and tells the system log the kinds only.
    /// A log that can't be written (no room, the phone locked) is left as it was: the share's
    /// own outcome is what matters, and the system log still has it.
    public static func record(_ entry: Entry, in inbox: ShareInbox?) {
        let ways = entry.attempts.map { "\($0.way):\($0.failure.rawValue):\($0.domain):\($0.code)" }.joined(separator: " ")
        logger.error("share failed: \(entry.failure.rawValue, privacy: .public) [\(ways, privacy: .public)]")
        guard let inbox else { return }
        var entries = inbox.failureLog()
        entries.append(entry)
        do {
            try FileManager.default.createDirectory(at: inbox.directory, withIntermediateDirectories: true, attributes: ShareInbox.protection)
            try ShareInbox.encoder.encode(Array(entries.suffix(kept))).write(to: inbox.failureLogURL, options: [.atomic, .completeFileProtection])
        } catch {
            logger.error("share log not written: \(String(describing: type(of: error)), privacy: .public)")
        }
    }
}

public extension ShareInbox {
    /// Where the share log is kept, beside the items (a dot name, so it is never read as one).
    static let failureLogName = ".share-failures.json"

    internal var failureLogURL: URL {
        directory.appending(path: Self.failureLogName)
    }

    /// The shares that didn't arrive, oldest first (`ShareFailureLog`). Empty when there is no
    /// log, or it can't be read.
    func failureLog() -> [ShareFailureLog.Entry] {
        guard let data = try? Data(contentsOf: failureLogURL),
              let entries = try? Self.decoder.decode([ShareFailureLog.Entry].self, from: data) else { return [] }
        return entries
    }
}
