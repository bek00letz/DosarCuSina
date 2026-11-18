import Foundation
import UniformTypeIdentifiers

/// How the share extension receives one shared item as a file in the inbox, whichever way
/// the app it comes from hands it over: Mail, WhatsApp and Photos give the file for a type;
/// Files and iCloud Drive give that and a link to the file where it lives, which may still be
/// only in iCloud; some apps give only the bytes. Each way is tried in order (`Plan.ways`)
/// until one gives the file, and why each failed is kept (`ShareFailureLog`).
///
/// Every copy goes into the share's own holding folder in the inbox a piece at a time
/// (`ShareInbox.copyStreaming`), within the room the share has left (`ShareInbox.room`); the
/// share then sorts what arrived into items (`ShareInbox.plan`, `ShareDelivery`). A whole share
/// is received by `receiveAll`, which also counts every file that didn't arrive, untried ones
/// included. Here so the app's tests pin the plan; `ShareDelivery` is the only caller of
/// `receiveAll`.
///
/// A file never comes whole into memory because of its size: one that says it is too large
/// (its stated size, or the bytes counted as it streams) is refused at once, never asked for
/// another way; once the share has no room left, an item isn't asked for at all; and an item's
/// bytes are asked for only when no way had a file to give (`Way.data`).
public enum ShareReceiving {
    /// One way of asking the sending app for an item.
    public enum Way: Hashable, Sendable {
        /// The file the sender keeps for a type (`loadFileRepresentation`): a copy the system
        /// makes, after downloading it when the sender is a cloud service.
        case file(String)
        /// The bytes for a type (`loadDataRepresentation`), for a sender that has no file. They
        /// come whole into memory, the way the sender gives them, so a file is asked for this
        /// way last, and only when the ways before it found no file to give (each said
        /// `notHandedOver`): never for a file that is there but couldn't be copied or is too
        /// large. The size is checked before they are kept.
        case data(String)
        /// A link to the file where it lives (Files, iCloud Drive), read with the permission the
        /// link carries and with coordinated reading, which downloads a file still in iCloud
        /// (`ShareInbox.coordinatedCopy`).
        case link

        /// Its name in the share log.
        public var logName: String {
            switch self {
            case .file: "file"
            case .data: "data"
            case .link: "link"
            }
        }
    }

    /// What to ask a sender for, in order, and what the item is when its type says so.
    public struct Plan: Hashable, Sendable {
        /// What the item is by the type it declares; nil when only the file can tell
        /// (`ShareInbox.settle`).
        public var kind: ShareInbox.IncomingKind?
        /// The declared type, for the copy's extension when the sender's file has none.
        public var type: UTType?
        public var ways: [Way]
    }

    /// The plan for an item its sender registered with `identifiers`, best first; nil when it
    /// offers nothing the inbox could take.
    ///
    /// A declared PDF or picture is asked for as a file first, then through its link (the way
    /// that still works when the typed file can't be had, as for a file in iCloud Drive that
    /// isn't on the phone), and only then as bytes, which come whole into memory. Text with no
    /// file of its own (copied from a message) is asked for as bytes first (it is short), then
    /// as a file; text that is a file (a .txt from Files, with its link) is a file like any
    /// other. An item that declares nothing the inbox takes is looked at through its link, or
    /// through plain data when that is all it offers (a PDF saved without an extension).
    public static func plan(identifiers: [String]) -> Plan? {
        let link: [Way] = identifiers.contains(UTType.fileURL.identifier) ? [.link] : []
        if let declared = ShareInbox.declaredType(among: identifiers), let kind = ShareInbox.kind(of: declared) {
            let ways: [Way] = kind == .text && link.isEmpty
                ? [.data(declared.identifier), .file(declared.identifier)]
                : [.file(declared.identifier)] + link + [.data(declared.identifier)]
            return Plan(kind: kind, type: declared, ways: ways)
        }
        let plain = identifiers.compactMap { UTType($0) }.first { ShareInbox.saysNothing($0) && !$0.conforms(to: .directory) }
        let ways = link + (plain.map { [.file($0.identifier), .data($0.identifier)] } ?? [])
        return ways.isEmpty ? nil : Plan(kind: nil, type: nil, ways: ways)
    }

    /// One item that arrived, in the share's holding folder.
    public struct Received: Hashable, Sendable {
        public var file: URL
        public var kind: ShareInbox.IncomingKind
        public var bytes: Int
        /// The name it had in the app it came from, for the item's row (masked when kept,
        /// `InboxItem.originalName`).
        public var name: String?
    }

    /// How receiving one item ended.
    public enum Outcome: Sendable {
        case received(Received)
        /// Nothing the inbox takes (a ZIP, a web link, a Live Photo's bundle).
        case unsupported
        /// Every way failed: the most telling reason, and each way's.
        case failed(ShareFailure, [ShareFailureLog.Attempt])
        /// The person stopped the share („Renunță”): nothing kept, nothing logged.
        case stopped
    }

    /// What one way gave.
    private enum Copy: Sendable {
        case copied(file: URL, bytes: Int, hint: UTType?, name: String?)
        /// The link's file is of a type the inbox doesn't take: nothing was copied.
        case leave
    }

    /// Receives one item into `holding`, as `received-<index + 1>`, within `room` bytes. On the
    /// main actor, where the share hands its items over; the copying itself runs on the
    /// system's queues and, for a link, on a queue of its own.
    ///
    /// With no room left, the item is refused as too large without asking its sender for
    /// anything. A way that finds it too large ends it: no other way is asked, so its bytes
    /// never come whole into memory. Its bytes are asked for only after every way before said
    /// there was no file to give (`Way.data`). „Renunță” (`stop`) ends it between two ways and
    /// between two pieces of a copy.
    @MainActor
    public static func receive(_ provider: NSItemProvider, into holding: URL, index: Int, room: Int,
                               stop: ShareCancellation? = nil) async -> Outcome {
        guard let plan = plan(identifiers: provider.registeredTypeIdentifiers) else { return .unsupported }
        guard room > 0 else {
            return .failed(.tooLarge, [ShareFailureLog.Attempt(way: "room", failure: .tooLarge, domain: "none", code: 0)])
        }
        let base = holding.appending(path: "received-\(index + 1)")
        var attempts: [ShareFailureLog.Attempt] = []
        for way in plan.ways {
            if stop?.isStopped == true { return .stopped }
            if case .data = way, !attempts.allSatisfy({ $0.failure == .notHandedOver }) { break }
            do {
                guard let copy = try await copy(provider, by: way, declared: plan.type, to: base, room: room, stop: stop) else {
                    attempts.append(ShareFailureLog.Attempt(way: way.logName, failure: .notHandedOver, domain: "none", code: 0))
                    continue
                }
                switch copy {
                case .leave:
                    return .unsupported
                case .copied(let file, let bytes, let hint, let name):
                    guard let settled = ShareInbox(directory: holding).settle(received: file, declared: plan.kind, hint: hint) else {
                        return .unsupported
                    }
                    return .received(Received(file: settled.file, kind: settled.kind, bytes: bytes, name: provider.suggestedName ?? name))
                }
            } catch {
                if stop?.isStopped == true || error is CancellationError { return .stopped }
                let attempt = ShareFailureLog.Attempt(way: way.logName, error: error)
                attempts.append(attempt)
                if attempt.failure == .tooLarge { break }
            }
        }
        if stop?.isStopped == true { return .stopped }
        return .failed(ShareFailure.mostTelling(attempts.map(\.failure)) ?? .notHandedOver, attempts)
    }

    /// What one share received, and what of it didn't arrive.
    public struct Share: Sendable {
        /// The items that arrived, in the order shared: at most `ShareInbox.maxFiles`.
        public var received: [Received] = []
        /// Every file that didn't: tried in vain, not one the inbox takes, or past the limit.
        public var missed = ShareFailure.Tally()
        /// The person stopped the share („Renunță”) before every item was asked for.
        public var stopped = false
    }

    /// Receives a share's items in order into `holding`, within the room the share has left
    /// (`ShareInbox.room`), until `ShareInbox.maxFiles` have arrived. Every file that doesn't
    /// arrive is counted (`Share.missed`) and kept in `inbox`'s share log as kinds only: one that
    /// failed every way, with its ways; one the inbox can't take (`unsupportedType`); and those
    /// past the limit, one entry for all of them (`overFileLimit`), which are never asked for.
    /// „Renunță” (`stop`) ends it at once: no item after is asked for, and nothing more is logged.
    @MainActor
    public static func receiveAll(_ providers: [NSItemProvider], into holding: URL, log inbox: ShareInbox?,
                                  stop: ShareCancellation? = nil) async -> Share {
        var share = Share()
        var sharedBytes = 0
        for (index, provider) in providers.enumerated() {
            guard stop?.isStopped != true else {
                share.stopped = true
                break
            }
            guard share.received.count < ShareInbox.maxFiles else {
                left(.overFileLimit, way: "limit", files: providers.count - index, in: &share, log: inbox)
                break
            }
            switch await receive(provider, into: holding, index: index, room: ShareInbox.room(sharedSoFar: sharedBytes), stop: stop) {
            case .received(let item):
                share.received.append(item)
                sharedBytes += item.bytes
            case .unsupported:
                left(.unsupportedType, way: "kind", files: 1, in: &share, log: inbox)
            case .failed(let failure, let attempts):
                share.missed.add(failure)
                ShareFailureLog.record(ShareFailureLog.Entry(at: Date(), failure: failure, attempts: attempts), in: inbox)
            case .stopped:
                share.stopped = true
            }
            if share.stopped { break }
        }
        return share
    }

    /// Files the share left untried: counted, and kept in the log under the step that left them.
    private static func left(_ failure: ShareFailure, way: String, files: Int, in share: inout Share, log inbox: ShareInbox?) {
        share.missed.add(failure, files: files)
        let attempt = ShareFailureLog.Attempt(way: way, failure: failure, domain: "none", code: 0)
        ShareFailureLog.record(ShareFailureLog.Entry(at: Date(), failure: failure, attempts: [attempt], files: files), in: inbox)
    }

    /// The copy's file: `base` with the extension the sender's file or type gives.
    private static func target(_ base: URL, extension ext: String?) -> URL {
        guard let ext, !ext.isEmpty else { return base }
        return base.appendingPathExtension(ext)
    }

    /// Asks for the item one way. Nil when the sender answered with nothing. „Renunță” (`stop`)
    /// cancels what the system is fetching for it.
    @MainActor
    private static func copy(_ provider: NSItemProvider, by way: Way, declared: UTType?, to base: URL, room: Int,
                             stop: ShareCancellation?) async throws -> Copy? {
        switch way {
        case .file(let identifier):
            return try await withCheckedThrowingContinuation { continuation in
                let loading = provider.loadFileRepresentation(forTypeIdentifier: identifier) { url, error in
                    // The system's copy only exists while this runs, so it is copied here.
                    if let error {
                        continuation.resume(throwing: error)
                        return
                    }
                    guard let url else {
                        continuation.resume(returning: nil)
                        return
                    }
                    let type = UTType(identifier)
                    let file = target(base, extension: url.pathExtension.isEmpty ? type?.preferredFilenameExtension : url.pathExtension)
                    continuation.resume(with: Result {
                        let bytes = try ShareInbox.copyStreaming(from: url, to: file, limit: room, stop: stop)
                        // The system names its copy itself ("PDF document.pdf"): only the sender's name counts.
                        return .copied(file: file, bytes: bytes, hint: ShareInbox.type(ofFile: url) ?? type, name: nil)
                    })
                }
                stop?.onStop { loading.cancel() }
            }
        case .data(let identifier):
            return try await withCheckedThrowingContinuation { continuation in
                let loading = provider.loadDataRepresentation(forTypeIdentifier: identifier) { data, error in
                    if let error {
                        continuation.resume(throwing: error)
                        return
                    }
                    guard let data, !data.isEmpty else {
                        continuation.resume(returning: nil)
                        return
                    }
                    let type = UTType(identifier)
                    let file = target(base, extension: type?.preferredFilenameExtension)
                    continuation.resume(with: Result {
                        try stop?.check()
                        guard data.count <= room else { throw ShareInbox.InboxError.tooLarge }
                        try data.write(to: file, options: [.atomic, .completeFileProtection])
                        return .copied(file: file, bytes: data.count, hint: type, name: nil)
                    })
                }
                stop?.onStop { loading.cancel() }
            }
        case .link:
            guard let url = try await link(from: provider) else { return nil }
            return try await copy(linkedFile: url, declared: declared, to: base, room: room, stop: stop)
        }
    }

    /// The file a link points to, copied where it lives. A file still in iCloud is downloaded
    /// first; one that can't be is told as such (`stillInCloud`), whatever error the copy gave.
    private static func copy(linkedFile url: URL, declared: UTType?, to base: URL, room: Int, stop: ShareCancellation?) async throws -> Copy {
        try await withCheckedThrowingContinuation { continuation in
            // Coordinated reading waits while the file downloads: off the main thread, and off
            // Swift's own threads, which must never wait.
            DispatchQueue.global(qos: .userInitiated).async {
                let scoped = url.startAccessingSecurityScopedResource()
                defer { if scoped { url.stopAccessingSecurityScopedResource() } }
                let hint = ShareInbox.type(ofFile: url)
                if declared == nil, ShareInbox.verdict(for: hint) == .leave {
                    continuation.resume(returning: .leave)
                    return
                }
                let file = target(base, extension: url.pathExtension.isEmpty ? (declared ?? hint)?.preferredFilenameExtension : url.pathExtension)
                do {
                    let bytes = try ShareInbox.coordinatedCopy(of: url, to: file, limit: room, stop: stop)
                    continuation.resume(returning: .copied(file: file, bytes: bytes, hint: hint, name: url.lastPathComponent))
                } catch {
                    let failure = ShareFailure(error)
                    let unnamed: Set<ShareFailure> = [.couldNotCopy, .notHandedOver, .noAccess]
                    if unnamed.contains(failure), ShareInbox.isWaitingInCloud(url) {
                        continuation.resume(throwing: ShareReceivingError.stillInCloud(underlying: error))
                    } else {
                        continuation.resume(throwing: error)
                    }
                }
            }
        }
    }

    /// The link an item carries to its file, as the sender hands it (a URL, or its bytes).
    /// Only a link to a file counts: a web address is no file to copy.
    @MainActor
    private static func link(from provider: NSItemProvider) async throws -> URL? {
        try await withCheckedThrowingContinuation { continuation in
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                continuation.resume(returning: fileURL(from: item))
            }
        }
    }

    /// A file's URL from what a sender handed over for a file link.
    static func fileURL(from item: Any?) -> URL? {
        let url: URL? = switch item {
        case let url as URL: url
        case let data as Data: URL(dataRepresentation: data, relativeTo: nil)
        case let text as String: URL(string: text)
        default: nil
        }
        return url?.isFileURL == true ? url : nil
    }
}

/// A copy of a linked file that failed while the file's contents were still only in iCloud:
/// the reason told is `ShareFailure.stillInCloud`; the log keeps the error under it.
public enum ShareReceivingError: Error, CustomNSError {
    case stillInCloud(underlying: any Error)

    public static var errorDomain: String { NSCocoaErrorDomain }
    public var errorCode: Int { NSUbiquitousFileUnavailableError }
    public var errorUserInfo: [String: Any] {
        switch self {
        case .stillInCloud(let underlying): [NSUnderlyingErrorKey: underlying as NSError]
        }
    }
}

/// „Renunță” in the share sheet: once stopped, the share asks for nothing more, every copy stops
/// between two pieces (`check`, which throws `CancellationError`), what the system is fetching
/// or waiting for is cancelled (`onStop`), and the share keeps nothing and posts no notice
/// (`ShareDelivery`). Shared by the main actor, which stops it, and the queues that copy.
public final class ShareCancellation: @unchecked Sendable {
    private let lock = NSLock()
    private var stopped = false
    private var actions: [() -> Void] = []

    public init() {}

    /// Whether the person stopped the share.
    public var isStopped: Bool {
        lock.withLock { stopped }
    }

    /// Throws `CancellationError` once the share is stopped.
    public func check() throws {
        if isStopped { throw CancellationError() }
    }

    /// Stops the share, once: runs what was waiting to be cancelled.
    public func stop() {
        let waiting: [() -> Void] = lock.withLock {
            guard !stopped else { return [] }
            stopped = true
            defer { actions = [] }
            return actions
        }
        waiting.forEach { $0() }
    }

    /// Runs `action` when the share is stopped, or at once if it already was.
    public func onStop(_ action: @escaping () -> Void) {
        let runNow: Bool = lock.withLock {
            guard !stopped else { return true }
            actions.append(action)
            return false
        }
        if runNow { action() }
    }
}
