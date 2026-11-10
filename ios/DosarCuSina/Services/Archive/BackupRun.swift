import Foundation

/// One long backup step the person started ("Fă o copie", checking a backup, bringing one in),
/// shared by the screen that started it, the system's background task that keeps it going
/// (`BackupKeeper`) and the thread that does the work.
///
/// - **Progress:** what the work has done of what it expects (`progress`), which the system shows
///   while the person is away from the app.
/// - **Cancelling:** the person stops it from the system's progress, or the system ends it; the
///   work stops at its next file (`checkpoint`), leaving nothing half-done: an export removes its
///   unfinished file, an import writes nothing (its save is one unit of work, all or nothing).
/// - **The phone locked:** the binder's documents can't be read or written while the phone is
///   locked (their files are protected, `DocumentFileProtection`), so the steps that need them wait
///   at their next file until it is unlocked and go on from there. What only reads the backup's
///   own file keeps going: a file a backup is working on is open to a locked phone only while it
///   is open (`BackupFileProtection.working`).
final class BackupRun: @unchecked Sendable {
    /// What the work has done of what it expects, in files (and one more for a save).
    let progress: Progress

    private let condition = NSCondition()
    private var cancelled = false
    private var protectedDataAvailable: Bool
    private var locks = 0

    init(protectedDataAvailable: Bool = true) {
        self.protectedDataAvailable = protectedDataAvailable
        progress = Progress(totalUnitCount: 0)
        progress.isCancellable = true
        progress.cancellationHandler = { [weak self] in self?.cancel() }
    }

    /// Stops the work at its next file. Wakes a step waiting for the phone to be unlocked.
    func cancel() {
        condition.lock()
        cancelled = true
        condition.broadcast()
        condition.unlock()
    }

    /// Stopped here, or from the system's progress (whose handler may come a moment later).
    var isCancelled: Bool {
        condition.lock()
        defer { condition.unlock() }
        return cancelled || progress.isCancelled
    }

    /// The phone locked (false) or was unlocked (true): what the system says about the protected
    /// files (`UIApplication.isProtectedDataAvailable`).
    func protectedData(isAvailable: Bool) {
        condition.lock()
        if protectedDataAvailable && !isAvailable { locks += 1 }
        protectedDataAvailable = isAvailable
        condition.broadcast()
        condition.unlock()
    }

    /// How many times the phone has locked while this ran.
    var timesLocked: Int {
        condition.lock()
        defer { condition.unlock() }
        return locks
    }

    /// Between two files: stops here when cancelled, and, for a step that reads or writes the
    /// binder's documents (`needsProtectedData`), waits here while the phone is locked. Never
    /// called inside a unit of work, which never waits.
    func checkpoint(needsProtectedData: Bool) throws {
        condition.lock()
        defer { condition.unlock() }
        while needsProtectedData && !protectedDataAvailable && !cancelled && !progress.isCancelled { condition.wait() }
        if cancelled || progress.isCancelled { throw CancellationError() }
    }

    /// The work expects `units` more files.
    func expect(_ units: Int) {
        progress.totalUnitCount += Int64(units)
    }

    /// The work did `units` more.
    func did(_ units: Int = 1) {
        progress.completedUnitCount += Int64(units)
    }

    /// Runs `write` once the binder's documents can be written, and again, up to twice more, when
    /// it failed because the phone locked while it ran: it is one unit of work, which took
    /// everything back, so running it again is safe. Any other failure is the failure.
    func writing<T>(_ write: () throws -> T) throws -> T {
        var attempts = 0
        while true {
            try checkpoint(needsProtectedData: true)
            let before = timesLocked
            do {
                return try write()
            } catch {
                attempts += 1
                guard timesLocked != before, attempts < 3 else { throw error }
            }
        }
    }

    /// Runs `body` away from the main thread, on a thread of the backup's own, where waiting for the
    /// phone to be unlocked keeps no other work waiting.
    func perform<T: Sendable>(_ body: @escaping @Sendable () throws -> T) async throws -> T {
        try await withCheckedThrowingContinuation { continuation in
            Self.queue.async { continuation.resume(with: Result { try body() }) }
        }
    }

    private static let queue = DispatchQueue(label: "com.ar.dosarcusina.backup", qos: .userInitiated)
}

/// How a backup's own files are protected, by one rule: closed to a locked phone, but while a
/// running backup works on one (writing a copy, reading one in, its documents' files on their way
/// in), when it stays open to the work that holds it open. A file nothing works on any more, and
/// every finished backup, is closed to a locked phone again: never weaker than the binder's own.
enum BackupFileProtection {
    /// A file a running backup is working on: readable and writable while the phone is locked only
    /// while it is open.
    static let working = FileProtectionType.completeUnlessOpen
    /// A finished backup, and a file waiting for the person.
    static let finished = FileProtectionType.complete

    /// Sets `protection` on the file at `url`. On a phone a failure is the step's failure: a finished
    /// backup is never handed out less protected. The Simulator has no data protection to set.
    static func set(_ protection: FileProtectionType, on url: URL) throws {
        #if targetEnvironment(simulator)
        try? FileManager.default.setAttributes([.protectionKey: protection], ofItemAtPath: url.path(percentEncoded: false))
        #elseif os(iOS)
        try FileManager.default.setAttributes([.protectionKey: protection], ofItemAtPath: url.path(percentEncoded: false))
        #endif
    }
}
