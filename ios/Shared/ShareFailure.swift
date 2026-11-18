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
    /// Nothing the inbox can take: not a photo, a PDF or text (a ZIP, a web link). Left without
    /// copying anything (`isLeftUntried`).
    case unsupportedType
    /// Past the files one share takes (`ShareInbox.maxFiles`): left without trying (`isLeftUntried`).
    case overFileLimit

    /// The order in which a reason says more, so a share that failed several ways (the typed
    /// file, then the link to it) is told the most useful one: a known cause before an unnamed one.
    /// The reasons for a file left untried come last: they are never a way's failure.
    public static let mostTellingFirst: [ShareFailure] = [
        .noRoom, .tooLarge, .offline, .stillInCloud, .noAccess, .inboxUnavailable, .notHandedOver, .couldNotCopy,
    ] + leftUntried

    /// The reasons a share leaves a file without trying to copy it, in the order they are told:
    /// each is counted and said on its own (`Missed.left`), never folded into a copy's failure.
    public static let leftUntried: [ShareFailure] = [.unsupportedType, .overFileLimit]

    /// Whether the share left the file without trying to copy it (`leftUntried`).
    public var isLeftUntried: Bool {
        Self.leftUntried.contains(self)
    }

    /// The most telling of several reasons, or nil for none.
    public static func mostTelling(_ failures: some Sequence<ShareFailure>) -> ShareFailure? {
        let found = Set(failures)
        return mostTellingFirst.first(where: found.contains)
    }

    /// The files of one share that didn't arrive. Those it tried to copy are told together, with
    /// the most telling reason among theirs and how many had it (`failed`); those it left untried, each reason with its
    /// own count (`left`: nothing it can take, past the files one share takes). What the
    /// confirmation counts, with `ShareFailureWording`.
    public struct Missed: Equatable, Hashable, Sendable {
        /// How many files, and why: `failure` is true of `ofReason` of the `files`, of all of them
        /// unless the files tried in vain failed for different reasons. A count is only ever said
        /// of what is true of every file it counts (`ShareFailureWording.line`).
        public struct Part: Equatable, Hashable, Sendable {
            public var files: Int
            public var failure: ShareFailure
            /// How many of `files` had `failure`.
            public var ofReason: Int

            public init(files: Int, failure: ShareFailure, ofReason: Int? = nil) {
                self.files = files
                self.failure = failure
                self.ofReason = min(ofReason ?? files, files)
            }

            /// Whether the files had different reasons, so `failure` is true of only some.
            public var isMixed: Bool { ofReason < files }
        }

        /// The files tried in vain, under the most telling reason; nil when none was.
        public var failed: Part?
        /// The files left untried, by reason, in the order of `ShareFailure.leftUntried`.
        public var left: [Part]

        public init(failed: Part?, left: [Part] = []) {
            self.failed = failed
            self.left = left
        }

        /// The files that didn't arrive for one reason: tried in vain, or left untried.
        public init(files: Int, failure: ShareFailure) {
            let part = Part(files: files, failure: failure)
            self.init(failed: failure.isLeftUntried ? nil : part, left: failure.isLeftUntried ? [part] : [])
        }

        /// Every part, in the order the note tells them: the files tried first, then each left one.
        public var parts: [Part] {
            (failed.map { [$0] } ?? []) + left
        }
    }

    /// Counts what didn't arrive as a share goes: each item that failed, with how many files it
    /// held (photos sorted into one document count each), and each file left untried.
    public struct Tally: Sendable {
        private var tried = 0
        /// The files tried in vain, by reason.
        private var reasons: [ShareFailure: Int] = [:]
        private var left: [ShareFailure: Int] = [:]

        public init() {}

        public mutating func add(_ failure: ShareFailure, files: Int = 1) {
            let files = max(files, 1)
            if failure.isLeftUntried {
                left[failure, default: 0] += files
            } else {
                tried += files
                reasons[failure, default: 0] += files
            }
        }

        /// How many didn't arrive and why; nil while nothing failed. The files tried in vain are
        /// one part, under the most telling reason, with how many of them had it.
        public var missed: Missed? {
            let failed = ShareFailure.mostTelling(reasons.keys).map { Missed.Part(files: tried, failure: $0, ofReason: reasons[$0]) }
            let leftParts = ShareFailure.leftUntried.compactMap { reason in left[reason].map { Missed.Part(files: $0, failure: reason) } }
            guard failed != nil || !leftParts.isEmpty else { return nil }
            return Missed(failed: failed, left: leftParts)
        }
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
/// seen. The share extension writes it (it runs while the app doesn't), the app reads it and
/// empties it („Golește lista”, `clear`, with `putBack` for its "Anulează"); every change is one
/// coordinated write (`ShareInbox.changeFailureLog`), so neither writes over the other's.
///
/// It keeps kinds only, as the persistence log does: which way the share tried (the typed
/// file, its data, the link to it), the reason (`ShareFailure`, a file left untried too: one
/// it can't take, those past the limit), how many files, and the error's system domain and
/// code. Never a file's name, a path, a value or anything the file holds. Kept beside the
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

    /// One item of a share that didn't arrive: when, the reason told, every way tried, and how
    /// many files it held (photos sorted into one document, or every file past the limit).
    public struct Entry: Codable, Hashable, Sendable, Identifiable {
        /// Which entry it is, so two that failed alike in the same second stay two
        /// (`merged`): the log keeps moments to the second.
        public var id: UUID
        public var at: Date
        public var failure: ShareFailure
        public var attempts: [Attempt]
        /// How many files: one for most, and one for an entry kept before the count was.
        public var files: Int

        public init(id: UUID = UUID(), at: Date, failure: ShareFailure, attempts: [Attempt], files: Int = 1) {
            self.id = id
            self.at = at
            self.failure = failure
            self.attempts = attempts
            self.files = max(files, 1)
        }

        private enum CodingKeys: String, CodingKey {
            case id, at, failure, attempts, files
        }

        /// An entry kept before entries had an id gets one as it is read, kept from the log's
        /// next change on.
        public init(from decoder: any Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
            at = try container.decode(Date.self, forKey: .at)
            failure = try container.decode(ShareFailure.self, forKey: .failure)
            attempts = try container.decode([Attempt].self, forKey: .attempts)
            files = max(try container.decodeIfPresent(Int.self, forKey: .files) ?? 1, 1)
        }
    }

    /// The error domains whose name the log keeps: the system's own.
    static let domains: Set<String> = [
        NSCocoaErrorDomain, NSPOSIXErrorDomain, NSURLErrorDomain, NSFileProviderErrorDomain,
        NSItemProvider.errorDomain, NSOSStatusErrorDomain, NSMachErrorDomain,
    ]

    /// Posted in the app's own process when the app empties the log or puts it back, so every
    /// screen that shows it reads it again (Despre's row, „Probleme la primire”).
    public static let didChangeNotification = Notification.Name("ShareFailureLog.didChange")

    /// Keeps `entry` in `inbox`'s log, newest last, and tells the system log the kinds only.
    /// A log that can't be written (no room, the phone locked) is left as it was: the share's
    /// own outcome is what matters, and the system log still has it.
    public static func record(_ entry: Entry, in inbox: ShareInbox?) {
        let ways = entry.attempts.map { "\($0.way):\($0.failure.rawValue):\($0.domain):\($0.code)" }.joined(separator: " ")
        logger.error("share failed: \(entry.failure.rawValue, privacy: .public) x\(entry.files, privacy: .public) [\(ways, privacy: .public)]")
        guard let inbox else { return }
        do {
            try inbox.changeFailureLog { $0.append(entry) }
        } catch {
            logger.error("share log not written: \(String(describing: type(of: error)), privacy: .public)")
        }
    }

    /// Empties `inbox`'s log („Golește lista”) and returns what it held, for the toast's
    /// "Anulează" (`putBack`). The share extension may be writing it at the same moment: both
    /// change it under one coordinated write, so a failure it keeps meanwhile is never lost to
    /// a write of the list as it was before, and never brought back by the emptying.
    @discardableResult
    public static func clear(in inbox: ShareInbox) throws -> [Entry] {
        var removed: [Entry] = []
        try inbox.changeFailureLog { entries in
            removed = entries
            entries = []
        }
        NotificationCenter.default.post(name: didChangeNotification, object: nil)
        return removed
    }

    /// Puts back exactly what `clear` took ("Anulează"), every entry of it, beside anything the
    /// share kept since, in time order: the list as it would be had it never been emptied, the
    /// latest `kept` only.
    public static func putBack(_ entries: [Entry], in inbox: ShareInbox) throws {
        try inbox.changeFailureLog { current in
            current = merged(entries, current)
        }
        NotificationCenter.default.post(name: didChangeNotification, object: nil)
    }

    /// Two lists of the log as one: each entry once by its id (two that failed alike in the same
    /// second are two), oldest first (in the order given when two came at the same moment), the
    /// latest `kept` only.
    static func merged(_ earlier: [Entry], _ later: [Entry]) -> [Entry] {
        var seen = Set<UUID>()
        let unique = (earlier + later).filter { seen.insert($0.id).inserted }
        let ordered = unique.enumerated()
            .sorted { ($0.element.at, $0.offset) < ($1.element.at, $1.offset) }
            .map(\.element)
        return Array(ordered.suffix(kept))
    }
}

public extension ShareInbox {
    /// Where the share log is kept, beside the items (a dot name, so it is never read as one).
    static let failureLogName = ".share-failures.json"

    internal var failureLogURL: URL {
        directory.appending(path: Self.failureLogName)
    }

    /// The shares that didn't arrive, oldest first (`ShareFailureLog`). Empty when there is no
    /// log, or it can't be read. A coordinated read, so it never meets a change half made.
    func failureLog() -> [ShareFailureLog.Entry] {
        var entries: [ShareFailureLog.Entry] = []
        var coordination: NSError?
        NSFileCoordinator(filePresenter: nil).coordinate(readingItemAt: failureLogURL, options: [], error: &coordination) { url in
            entries = Self.failureLog(at: url)
        }
        return entries
    }

    /// Changes the log in one coordinated write, read and written under it, so the app and the
    /// share extension never write over each other's change: the latest `kept` only, and no
    /// file once it is empty. Throws when it can't be written.
    internal func changeFailureLog(_ change: (inout [ShareFailureLog.Entry]) -> Void) throws {
        var failed: (any Error)?
        var coordination: NSError?
        NSFileCoordinator(filePresenter: nil).coordinate(writingItemAt: failureLogURL, options: [], error: &coordination) { url in
            do {
                var entries = Self.failureLog(at: url)
                change(&entries)
                entries = Array(entries.suffix(ShareFailureLog.kept))
                if entries.isEmpty {
                    if FileManager.default.fileExists(atPath: url.path(percentEncoded: false)) {
                        try FileManager.default.removeItem(at: url)
                    }
                } else {
                    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: Self.protection)
                    try Self.encoder.encode(entries).write(to: url, options: [.atomic, .completeFileProtection])
                }
            } catch {
                failed = error
            }
        }
        if let error = coordination ?? failed { throw error }
    }

    private static func failureLog(at url: URL) -> [ShareFailureLog.Entry] {
        guard let data = try? Data(contentsOf: url),
              let entries = try? decoder.decode([ShareFailureLog.Entry].self, from: data) else { return [] }
        return entries
    }
}
