// The shared folder's App Intents metadata step expects the framework in every
// target that compiles it; importing it keeps that step quiet (it's in the dyld cache).
import AppIntents
import SwiftUI
import UIKit
import UniformTypeIdentifiers

/// The share extension: "Dosar cu Șină" in the share sheet of Mail, WhatsApp,
/// Photos and Files. It only copies what it receives into the App Group inbox
/// and says so; reading the document happens later in the app, where the
/// person reviews it. No database, no recognition here, so it stays light.
final class ShareViewController: UIViewController {
    private let model = ShareModel()

    override func viewDidLoad() {
        super.viewDidLoad()
        let host = UIHostingController(rootView: ShareConfirmationView(model: model) { [weak self] in
            self?.finish()
        })
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
    enum Phase: Equatable {
        case working
        case saved(count: Int)
        /// Nothing we can read: not a photo, a PDF or text.
        case unsupported
        /// The phone couldn't hand the file over, or there's no room.
        case failed
        /// A file, or the whole share, is bigger than the inbox accepts.
        case tooLarge
    }

    private(set) var phase: Phase = .working

    func receive(_ providers: [NSItemProvider]) async {
        guard let inbox = ShareInbox.shared() else {
            phase = .failed
            return
        }
        try? FileManager.default.createDirectory(at: inbox.directory, withIntermediateDirectories: true, attributes: ShareInbox.protection)
        inbox.removeAbandonedStaging()

        var classified: [(Source, ShareInbox.IncomingKind)] = []
        for provider in providers {
            if let item = await Self.classify(provider) { classified.append(item) }
        }
        guard !classified.isEmpty else {
            phase = .unsupported
            return
        }

        var saved = 0
        var failed = false
        var tooLarge = false
        var sharedBytes = 0
        for planned in ShareInbox.plan(classified.map(\.1)) {
            var staging: URL?
            do {
                let folder = try inbox.makeStagingFolder()
                staging = folder
                var files: [String] = []
                var originalName: String?
                for (position, index) in planned.indices.enumerated() {
                    let source = classified[index].0
                    originalName = originalName ?? source.suggestedName
                    if let name = try await Self.stage(source, as: classified[index].1, inbox: inbox, staging: folder, index: position, sharedSoFar: sharedBytes) {
                        files.append(name)
                        sharedBytes += ShareInbox.byteCount(of: name, in: folder)
                    }
                }
                if files.isEmpty {
                    inbox.discard(staging: folder)
                    failed = true
                    continue
                }
                try inbox.commit(staging: folder, payload: planned.payload, files: files, originalName: originalName)
                saved += 1
            } catch {
                if let staging { inbox.discard(staging: staging) }
                if (error as? ShareInbox.InboxError) == .tooLarge { tooLarge = true }
                failed = true
            }
        }
        if saved > 0 { AppGroup.postInboxDidChange() }
        phase = saved > 0 ? .saved(count: saved) : (tooLarge ? .tooLarge : (failed ? .failed : .unsupported))
    }

    /// Where one shared item comes from: typed data, or a link to a file
    /// (how Files, WhatsApp and SwiftUI's ShareLink often send documents).
    enum Source {
        case provider(NSItemProvider)
        case file(URL, NSItemProvider)

        var suggestedName: String? {
            switch self {
            case .provider(let provider): provider.suggestedName
            case .file(let url, let provider): provider.suggestedName ?? url.lastPathComponent
            }
        }
    }

    /// Works out what an attachment is. Typed items say so directly; a file link
    /// is opened to see what the file is, so a PDF sent as a link still counts.
    private static func classify(_ provider: NSItemProvider) async -> (Source, ShareInbox.IncomingKind)? {
        for type in [UTType.pdf, .image, .plainText] where provider.hasItemConformingToTypeIdentifier(type.identifier) {
            if let kind = ShareInbox.kind(of: type) { return (.provider(provider), kind) }
        }
        guard provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier),
              let url = await fileURL(from: provider),
              let kind = ShareInbox.kind(ofFile: url) else { return nil }
        return (.file(url, provider), kind)
    }

    private static func fileURL(from provider: NSItemProvider) async -> URL? {
        await withCheckedContinuation { continuation in
            _ = provider.loadObject(ofClass: URL.self) { url, _ in
                continuation.resume(returning: url?.isFileURL == true ? url : nil)
            }
        }
    }

    /// Copies one attachment into the staging folder; returns its file name.
    private static func stage(_ source: Source, as kind: ShareInbox.IncomingKind, inbox: ShareInbox, staging: URL, index: Int, sharedSoFar: Int) async throws -> String? {
        switch source {
        case .file(let url, _):
            let didAccess = url.startAccessingSecurityScopedResource()
            defer { if didAccess { url.stopAccessingSecurityScopedResource() } }
            return try inbox.stage(copyOf: url, into: staging, index: index, sharedSoFar: sharedSoFar)
        case .provider(let provider):
            return try await stage(provider, as: kind, inbox: inbox, staging: staging, index: index, sharedSoFar: sharedSoFar)
        }
    }

    private static func stage(_ provider: NSItemProvider, as kind: ShareInbox.IncomingKind, inbox: ShareInbox, staging: URL, index: Int, sharedSoFar: Int) async throws -> String? {
        switch kind {
        case .text:
            let data: Data? = try await withCheckedThrowingContinuation { continuation in
                _ = provider.loadDataRepresentation(for: .plainText) { data, error in
                    if let error { continuation.resume(throwing: error) } else { continuation.resume(returning: data) }
                }
            }
            guard let data, !data.isEmpty else { return nil }
            return try inbox.stage(data: data, fileExtension: "txt", into: staging, index: index, sharedSoFar: sharedSoFar)
        case .pdf, .image:
            let type: UTType = kind == .pdf ? .pdf : .image
            return try await withCheckedThrowingContinuation { continuation in
                // The file only exists while this handler runs, so it is copied here.
                _ = provider.loadFileRepresentation(for: type, openInPlace: false) { url, _, error in
                    if let error {
                        continuation.resume(throwing: error)
                        return
                    }
                    guard let url else {
                        continuation.resume(returning: nil)
                        return
                    }
                    do {
                        continuation.resume(returning: try inbox.stage(copyOf: url, into: staging, index: index, sharedSoFar: sharedSoFar))
                    } catch {
                        continuation.resume(throwing: error)
                    }
                }
            }
        }
    }
}

/// The calm confirmation the person sees in the share sheet.
struct ShareConfirmationView: View {
    let model: ShareModel
    let onDone: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOverEnabled
    @State private var showsProgress = false

    var body: some View {
        VStack(spacing: 16) {
            Spacer(minLength: 0)
            symbol
                .font(.system(size: 44, weight: .semibold))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(tint)
                .frame(height: 56)
                .accessibilityHidden(true)
            VStack(spacing: 6) {
                Text(title)
                    .font(.title3.weight(.semibold))
                    .multilineTextAlignment(.center)
                Text(message)
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .accessibilityElement(children: .combine)
            Spacer(minLength: 0)
            Button(action: onDone) {
                Text(model.phase == .working ? "Anulează" : "Gata")
                    .font(.headline)
                    .frame(maxWidth: .infinity, minHeight: 50)
            }
            .buttonStyle(.borderedProminent)
            .buttonBorderShape(.roundedRectangle(radius: 14))
        }
        .padding(24)
        .frame(maxWidth: 480)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(uiColor: .systemGroupedBackground))
        .animation(reduceMotion ? .easeOut(duration: 0.18) : .spring(duration: 0.32, bounce: 0.1), value: model.phase)
        .sensoryFeedback(trigger: model.phase) { _, phase in
            switch phase {
            case .saved: .success
            case .failed, .unsupported, .tooLarge: .warning
            case .working: nil
            }
        }
        .task {
            // Only show a spinner if copying takes a moment.
            try? await Task.sleep(for: .milliseconds(400))
            showsProgress = true
        }
        .task(id: model.phase) {
            guard case .saved = model.phase, !voiceOverEnabled else { return }
            try? await Task.sleep(for: .seconds(2.5))
            onDone()
        }
    }

    @ViewBuilder private var symbol: some View {
        switch model.phase {
        case .working:
            ProgressView().controlSize(.large).opacity(showsProgress ? 1 : 0)
        case .saved:
            Image(systemName: "checkmark.circle.fill")
        case .unsupported, .failed, .tooLarge:
            Image(systemName: "exclamationmark.circle.fill")
        }
    }

    private var tint: Color {
        switch model.phase {
        case .saved: .green
        case .unsupported, .failed, .tooLarge: .orange
        case .working: .secondary
        }
    }

    private var title: LocalizedStringKey {
        switch model.phase {
        case .working: "Se trimite…"
        case .saved: "Trimis în Dosar cu Șină"
        case .unsupported: "Nu pot primi asta"
        case .failed: "Nu s-a trimis"
        case .tooLarge: "Fișierul e prea mare"
        }
    }

    private var message: LocalizedStringKey {
        switch model.phase {
        case .working: " "
        case .saved: "Îl verifici când deschizi aplicația."
        case .unsupported: "Pot primi poze, PDF-uri și text. Trimite factura sau actul ca poză sau PDF."
        case .failed: "Telefonul nu mi-a dat fișierul. Încearcă din nou din aplicația din care l-ai trimis."
        case .tooLarge: "Trimite actele câte unul, sau ca poze în loc de un PDF mare."
        }
    }
}
