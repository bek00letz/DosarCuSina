import Foundation

/// One share from the share sheet, from the items handed over to what the confirmation says:
/// every item is received into the share's holding folder (`ShareReceiving.receiveAll`), what
/// arrived is sorted into inbox items (`ShareInbox.plan`: photos together, each PDF alone) and
/// committed, and the quiet notice is posted when the person already allows it (`InboxNotice`).
/// The share extension runs it; it lives here so the app's tests pin it.
///
/// „Renunță” (`ShareCancellation.stop`) stops it wherever it is: nothing more is asked for, the
/// copy under way stops between two pieces, what was staged for this share is removed, no
/// notice is posted, and what it had already committed is taken out of the inbox again.
/// A notice that was already on its way then speaks of nothing that waits, and the app's
/// coordinator withdraws it as it does any such notice (`InboxNotice.follow`).
public enum ShareDelivery {
    public typealias Phase = ShareConfirmation.Phase

    /// Delivers `providers` into `inbox`. Returns what the confirmation says, or nil when the
    /// person stopped the share (`stop`): then nothing of it is left in the inbox. `notificationsOn`
    /// is Settings’ „Notificări”, read as the notice is due (`NotificationSwitch`) unless given.
    @MainActor
    public static func deliver(_ providers: [NSItemProvider], into inbox: ShareInbox?,
                               center: any InboxNoticeCenter = SystemInboxNoticeCenter(),
                               notificationsOn: Bool? = nil,
                               stop: ShareCancellation) async -> Phase? {
        // Before anything is received, a failure is about every file shared.
        let shared = max(providers.count, 1)
        guard let inbox else {
            return failed(.inboxUnavailable, way: "inbox", in: nil, files: shared)
        }
        let holding: URL
        do {
            try FileManager.default.createDirectory(at: inbox.directory, withIntermediateDirectories: true, attributes: ShareInbox.protection)
            inbox.removeAbandonedStaging()
            holding = try inbox.makeStagingFolder()
        } catch {
            return failed(error, way: "inbox", in: inbox, files: shared)
        }
        defer { inbox.discard(staging: holding) }

        let share = await ShareReceiving.receiveAll(providers, into: holding, log: inbox, stop: stop)
        guard !share.stopped, !stop.isStopped else { return nil }
        let received = share.received
        // What didn't arrive (tried in vain, not something it takes, past the limit), told beside
        // what did (`ShareConfirmation`'s note) or on its own.
        var missed = share.missed
        guard !received.isEmpty else {
            return .nothingSaved(missed.missed)
        }

        // From here to the notice nothing waits, so „Renunță” can't come between two commits.
        var saved: [InboxItem] = []
        for planned in ShareInbox.plan(received.map(\.kind)) {
            var staging: URL?
            do {
                let folder = try inbox.makeStagingFolder()
                staging = folder
                var files: [String] = []
                for (position, index) in planned.indices.enumerated() {
                    files.append(try inbox.stage(received: received[index].file, into: folder, index: position))
                }
                let originalName = planned.indices.lazy.compactMap { received[$0].name }.first
                saved.append(try inbox.commit(staging: folder, payload: planned.payload, files: files, originalName: originalName))
            } catch {
                if let staging { inbox.discard(staging: staging) }
                let attempt = ShareFailureLog.Attempt(way: "commit", error: error)
                missed.add(attempt.failure, files: planned.indices.count)
                ShareFailureLog.record(ShareFailureLog.Entry(at: Date(), failure: attempt.failure, attempts: [attempt], files: planned.indices.count), in: inbox)
            }
        }
        guard !saved.isEmpty else {
            return .nothingSaved(missed.missed)
        }
        AppGroup.postInboxDidChange()
        // A quiet notice the person can tap to continue, only if they already allow
        // notifications; the extension never asks (`InboxNotice`), and never once stopped.
        let notified = await InboxNotice.announce(waiting: inbox.waitingItems() ?? [], center: center,
                                                  notificationsOn: notificationsOn ?? NotificationSwitch.isOn(), stop: stop)
        guard !stop.isStopped else {
            takeBack(saved, from: inbox)
            return nil
        }
        return .saved(count: saved.count, next: InboxNotice.nextStep(saved: saved, notified: notified), notArrived: missed.missed)
    }

    /// What a stopped share had already committed, taken out of the inbox again.
    private static func takeBack(_ saved: [InboxItem], from inbox: ShareInbox) {
        for item in saved {
            do {
                try inbox.remove(item.id)
            } catch {
                ShareFailureLog.logger.error("stopped share's item not removed: \(String(describing: type(of: error)), privacy: .public)")
            }
        }
        AppGroup.postInboxDidChange()
    }

    /// A share that failed before any item could be received: logged, and told.
    private static func failed(_ error: any Error, way: String, in inbox: ShareInbox?, files: Int) -> Phase {
        let attempt = ShareFailureLog.Attempt(way: way, error: error)
        ShareFailureLog.record(ShareFailureLog.Entry(at: Date(), failure: attempt.failure, attempts: [attempt]), in: inbox)
        return .failed(attempt.failure, count: files)
    }

    private static func failed(_ failure: ShareFailure, way: String, in inbox: ShareInbox?, files: Int) -> Phase {
        let attempt = ShareFailureLog.Attempt(way: way, failure: failure, domain: "none", code: 0)
        ShareFailureLog.record(ShareFailureLog.Entry(at: Date(), failure: failure, attempts: [attempt]), in: inbox)
        return .failed(failure, count: files)
    }
}
