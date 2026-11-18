// The shared folder's App Intents metadata step expects the framework in every
// target that compiles it; importing it keeps that step quiet (it's in the dyld cache).
import AppIntents
import SwiftUI
import UIKit
import UniformTypeIdentifiers

/// The share extension: "Dosar cu Șină" in the share sheet of Mail, WhatsApp,
/// Photos and Files. It only copies what it receives into the App Group inbox
/// and says what happens next; reading the document happens later in the app, where the
/// person reviews it. No database, no recognition here, so it stays light.
///
/// iOS doesn't let a share extension open its app, so when the person already allows
/// notifications it leaves a quiet one (`InboxNotice`) whose tap opens De verificat.
final class ShareViewController: UIViewController {
    private let model = ShareModel()

    override func viewDidLoad() {
        super.viewDidLoad()
        let host = UIHostingController(rootView: ShareConfirmationView(model: model) { [weak self] in
            self?.finish()
        }.dosarLocaleAndCalendar())
        addChild(host)
        host.view.translatesAutoresizingMaskIntoConstraints = false
        host.view.backgroundColor = .clear
        view.addSubview(host.view)
        NSLayoutConstraint.activate([
            host.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            host.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            host.view.topAnchor.constraint(equalTo: view.topAnchor),
            host.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
        host.didMove(toParent: self)

        let items = (extensionContext?.inputItems as? [NSExtensionItem]) ?? []
        let providers = items.flatMap { $0.attachments ?? [] }
        Task { await model.receive(providers) }
    }

    private func finish() {
        extensionContext?.completeRequest(returningItems: nil)
    }
}

/// Copies the shared attachments into the inbox.
@MainActor
@Observable
final class ShareModel {
    /// What the confirmation shows and says (`ShareConfirmation`).
    typealias Phase = ShareConfirmation.Phase

    /// Every item is received every way its sender offers (`ShareReceiving`), and a share that
    /// fails says why. Off, the earlier way (`EarlierShareReceiving`) runs instead: kept as the
    /// way back until this one has been seen working on a phone.
    static let receivesEveryWay = true

    private(set) var phase: Phase = .working

    func receive(_ providers: [NSItemProvider]) async {
        if Self.receivesEveryWay {
            phase = await Self.receiveEveryWay(providers)
        } else {
            phase = await EarlierShareReceiving.receive(providers)
        }
    }

    /// Receives every item into the share's holding folder in the inbox, then sorts what
    /// arrived into inbox items (`ShareInbox.plan`): photos together, each PDF alone.
    private static func receiveEveryWay(_ providers: [NSItemProvider]) async -> Phase {
        // Before anything is received, a failure is about every file shared.
        let shared = max(providers.count, 1)
        guard let inbox = ShareInbox.shared() else {
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

        let share = await ShareReceiving.receiveAll(providers, into: holding, log: inbox)
        let received = share.received
        // What didn't arrive (tried in vain, not something it takes, past the limit), told beside
        // what did (`ShareConfirmation`'s note) or on its own.
        var missed = share.missed
        guard !received.isEmpty else {
            return .nothingSaved(missed.missed)
        }

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
        // notifications; the extension never asks (`InboxNotice`).
        let notified = await InboxNotice.announce(waiting: inbox.waitingItems() ?? [], center: SystemInboxNoticeCenter())
        return .saved(count: saved.count, next: InboxNotice.nextStep(saved: saved, notified: notified), notArrived: missed.missed)
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

/// The calm confirmation the person sees in the share sheet. It stays until they tap
/// "Închide" (`ShareConfirmation.closesByItself`), so nobody misses what happens next;
/// the button is pinned to the bottom, and the words scroll above it at any text size.
struct ShareConfirmationView: View {
    let model: ShareModel
    let onDone: () -> Void

    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOverEnabled

    private var confirmation: ShareConfirmation { ShareConfirmation(model.phase) }

    var body: some View {
        GeometryReader { proxy in
            ScrollView {
                content
                    .padding(DS.Space.xl)
                    .frame(maxWidth: 480)
                    .frame(maxWidth: .infinity, minHeight: proxy.size.height)
            }
            .scrollBounceBehavior(.basedOnSize)
        }
        .dsPinnedAction {
            switch confirmation.action {
            case .cancel: DSSecondaryButton(verbatim: confirmation.action.title, action: onDone)
            case .close: DSPrimaryButton(verbatim: confirmation.action.title, action: onDone)
            }
        }
        .background(Color(uiColor: .systemGroupedBackground))
        .dsAnimation(value: model.phase)
        .sensoryFeedback(trigger: model.phase) { _, phase in
            switch phase {
            case .saved: .success
            case .failed, .unsupported: .warning
            case .working: nil
            }
        }
        .task(id: model.phase) {
            // The way back, switched off: it used to close by itself after a short dwell.
            guard ShareConfirmation.closesByItself, case .saved = model.phase, !voiceOverEnabled else { return }
            try? await Task.sleep(for: DS.Motion.confirmationDwell)
            guard !Task.isCancelled else { return }
            onDone()
        }
    }

    private var content: some View {
        VStack(spacing: DS.Space.m) {
            symbol
                .font(.system(size: 44, weight: .semibold))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(tint)
                .frame(height: 56)
                .accessibilityHidden(true)
            VStack(spacing: DS.Space.xs) {
                Text(verbatim: confirmation.title)
                    .font(.title3.weight(.semibold))
                    .multilineTextAlignment(.center)
                    .accessibilityAddTraits(.isHeader)
                // While copying there is nothing to say yet; the line keeps its place.
                Text(verbatim: confirmation.message ?? " ")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                // What didn't arrive of the same share, and what to do: one confirmation, read
                // with the rest.
                if let note = confirmation.note {
                    Text(verbatim: note)
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.top, DS.Space.s)
                }
            }
            .accessibilityElement(children: .combine)
        }
    }

    @ViewBuilder private var symbol: some View {
        switch model.phase {
        case .working:
            // Only shows if copying takes a moment; the title already says what's happening.
            DSDelayedProgress(label: nil).controlSize(.large)
        case .saved:
            Image(systemName: "checkmark.circle.fill")
        case .unsupported, .failed:
            Image(systemName: "exclamationmark.circle.fill")
        }
    }

    private var tint: Color {
        switch model.phase {
        case .saved: .green
        case .unsupported, .failed: .orange
        case .working: .secondary
        }
    }
}
