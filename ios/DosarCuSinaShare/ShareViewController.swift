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
    /// „Renunță” was tapped: the sheet closes once, whatever else is tapped meanwhile.
    private var isStopping = false

    override func viewDidLoad() {
        super.viewDidLoad()
        let host = UIHostingController(rootView: ShareConfirmationView(model: model, onDone: { [weak self] in
            self?.finish()
        }, onStop: { [weak self] in
            self?.stop()
        }).dosarLocaleAndCalendar())
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
        model.start(providers)
    }

    private func finish() {
        extensionContext?.completeRequest(returningItems: nil)
    }

    /// „Renunță”: the share stops at once, and the sheet closes once what it staged is gone.
    private func stop() {
        guard !isStopping else { return }
        isStopping = true
        Task {
            await model.stop()
            extensionContext?.cancelRequest(withError: CocoaError(.userCancelled))
        }
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

    /// „Renunță”, shared with every copy of this share (`ShareDelivery`).
    private let cancellation = ShareCancellation()
    @ObservationIgnored private var receiving: Task<Void, Never>?

    func start(_ providers: [NSItemProvider]) {
        receiving = Task { await receive(providers) }
    }

    private func receive(_ providers: [NSItemProvider]) async {
        if Self.receivesEveryWay {
            // Nil: the person stopped the share; the sheet is closing.
            guard let delivered = await ShareDelivery.deliver(providers, into: ShareInbox.shared(), stop: cancellation) else { return }
            phase = delivered
        } else {
            phase = await EarlierShareReceiving.receive(providers)
        }
    }

    /// Stops the share („Renunță”) and returns once it has left nothing behind.
    func stop() async {
        cancellation.stop()
        receiving?.cancel()
        await receiving?.value
    }
}

/// The calm confirmation the person sees in the share sheet. It stays until they tap
/// "Închide" (`ShareConfirmation.closesByItself`), so nobody misses what happens next;
/// the button is pinned to the bottom, and the words scroll above it at any text size.
struct ShareConfirmationView: View {
    let model: ShareModel
    let onDone: () -> Void
    /// „Renunță” while copying: stops the share (`ShareModel.stop`).
    let onStop: () -> Void

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
            case .cancel: DSSecondaryButton(verbatim: confirmation.action.title, action: onStop)
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
