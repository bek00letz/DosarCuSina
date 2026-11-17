import Foundation
import UniformTypeIdentifiers

/// The way the share extension received items before `ShareReceiving`: one way per item (the
/// typed file, or else the link), copied without coordinated reading, with every failure
/// told the same way. Kept switched off (`ShareModel.receivesEveryWay` is on) as the way back
/// until the new one has been seen working on a phone; the owner decides when it goes.
enum EarlierShareReceiving {
    typealias Phase = ShareConfirmation.Phase

    @MainActor
    static func receive(_ providers: [NSItemProvider]) async -> Phase {
        guard let inbox = ShareInbox.shared() else { return .failed(.couldNotCopy) }
        try? FileManager.default.createDirectory(at: inbox.directory, withIntermediateDirectories: true, attributes: ShareInbox.protection)
        inbox.removeAbandonedStaging()

        var classified: [(Source, ShareInbox.IncomingKind)] = []
        for provider in providers {
            if let item = await classify(provider) { classified.append(item) }
        }
        guard !classified.isEmpty else { return .unsupported }

        var saved: [InboxItem] = []
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
                    if let name = try await stage(source, as: classified[index].1, inbox: inbox, staging: folder, index: position, sharedSoFar: sharedBytes) {
                        files.append(name)
                        sharedBytes += ShareInbox.byteCount(of: name, in: folder)
                    }
                }
                if files.isEmpty {
                    inbox.discard(staging: folder)
                    failed = true
                    continue
                }
                saved.append(try inbox.commit(staging: folder, payload: planned.payload, files: files, originalName: originalName))
            } catch {
                if let staging { inbox.discard(staging: staging) }
                if (error as? ShareInbox.InboxError) == .tooLarge { tooLarge = true }
                failed = true
            }
        }
        guard !saved.isEmpty else {
            return tooLarge ? .failed(.tooLarge) : (failed ? .failed(.couldNotCopy) : .unsupported)
        }
        AppGroup.postInboxDidChange()
        let notified = await InboxNotice.announce(waiting: inbox.waitingItems(), center: SystemInboxNoticeCenter())
        return .saved(count: saved.count, next: InboxNotice.nextStep(saved: saved, notified: notified))
    }

    /// Where one shared item comes from: typed data, or a link to a file.
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

    @MainActor
    private static func classify(_ provider: NSItemProvider) async -> (Source, ShareInbox.IncomingKind)? {
        for type in [UTType.pdf, .image, .plainText] where provider.hasItemConformingToTypeIdentifier(type.identifier) {
            if let kind = ShareInbox.kind(of: type) { return (.provider(provider), kind) }
        }
        guard provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier),
              let url = await fileURL(from: provider),
              let kind = ShareInbox.kind(ofFile: url) else { return nil }
        return (.file(url, provider), kind)
    }

    @MainActor
    private static func fileURL(from provider: NSItemProvider) async -> URL? {
        await withCheckedContinuation { continuation in
            _ = provider.loadObject(ofClass: URL.self) { url, _ in
                continuation.resume(returning: url?.isFileURL == true ? url : nil)
            }
        }
    }

    @MainActor
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

    @MainActor
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
