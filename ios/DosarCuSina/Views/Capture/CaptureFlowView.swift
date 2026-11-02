import SwiftData
import SwiftUI

/// Something to read and file: what was picked, and the share-inbox item it
/// came from (removed once filed or dismissed).
struct CaptureFlowInput: Identifiable {
    let id = UUID()
    var payload: CaptureRequest.Payload
    var inboxItem: InboxItem?
    /// The section the person started from ("Scriu eu" › a section › "Un act").
    var preferredAssetID: UUID?
    /// The person started from a household member's documents: whatever is read
    /// becomes one of that member's documents, even when it isn't an identity card.
    var filesAsPersonalDocument = false
}

/// What happened when the flow closed, for the toast on the screen underneath.
enum CaptureFlowResult {
    /// `assetID` is the section the document was filed in, so the screen underneath can open it.
    case filed(message: LocalizedStringResource, assetID: UUID?)
    case visitSaved(message: LocalizedStringResource)
    case dismissed
}

/// Reads a document and walks the person through confirming it: a skeleton
/// while capture runs, then the review (or the visit flow for an invoice with
/// parts), then the one save. Present it in a sheet.
struct CaptureFlowView: View {
    let input: CaptureFlowInput
    let onClose: (CaptureFlowResult) -> Void

    @Environment(\.modelContext) private var context
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Query(sort: \Asset.name) private var assets: [Asset]

    private enum Phase {
        case reading
        case review(CaptureReview)
        case visit(assetID: UUID, result: CaptureResult)
        case failed(String)
    }

    @State private var phase: Phase = .reading
    @State private var attempt = 0
    /// The person's AI provider read this document, so later readings (the back of a card) use it too.
    @State private var useCloud = false
    /// The pages read, once the person added more (the back of a card).
    @State private var payload: CaptureRequest.Payload?
    /// What is being read again while the review stays on screen.
    @State private var rereading: CaptureReread?
    /// The newest reading, which the review merges with what the person changed.
    @State private var rereadResult: CaptureResult?
    @State private var readAgainError: String?

    var body: some View {
        NavigationStack {
            Group {
                switch phase {
                case .reading:
                    CaptureReadingView()
                case .review(let review):
                    reviewView(review)
                case .visit(let assetID, let result):
                    AddVisitFlow(assetID: assetID, prefill: result) { saved in
                        finish(saved ? .visitSaved(message: "Vizita e în istoric.") : .dismissed)
                    }
                case .failed(let message):
                    DSErrorState("Nu am putut citi actul", message: LocalizedStringKey(message)) {
                        attempt += 1
                    }
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Închide") { finish(.dismissed) }
                        }
                    }
                }
            }
        }
        .task(id: attempt) { await read() }
    }

    private func read() async {
        phase = .reading
        do {
            let key = "\(input.id.uuidString)-\(attempt)"
            let result = try await CaptureRunner.result(for: key, payload ?? input.payload, useCloudModel: false, ownerID: input.preferredAssetID)
            var review = CaptureReview(result: result, assets: assets, context: context)
            if let preferred = input.preferredAssetID { review.destination = .asset(preferred) }
            review.filesAsPersonalDocument = input.filesAsPersonalDocument
            if CaptureMapping.opensVisitFlow(result.kind), review.duplicateAttachmentID == nil, case .asset(let id) = review.destination {
                phase = .visit(assetID: id, result: result)
            } else {
                phase = .review(review)
            }
        } catch is CancellationError {
            // The sheet went away or a new attempt started; that one shows its own result.
            return
        } catch {
            guard !Task.isCancelled else { return }
            CaptureLog.engine.error("Capture failed: \(String(describing: type(of: error)), privacy: .public) \((error as NSError).domain, privacy: .public) \((error as NSError).code)")
            phase = .failed(String(localized: "Încearcă din nou. Dacă tot nu merge, fă o poză mai clară, cu actul întins și fără umbre."))
        }
    }

    private func reviewView(_ review: CaptureReview) -> some View {
        let addPages: ((CaptureRequest.Payload) -> Void)? = canAddPages ? { added in self.addPages(added) } : nil
        // One review for the whole flow: each new reading is merged into it, keeping
        // everything the person changed (`CaptureReview.carryingEdits`).
        return CaptureReviewView(
            review: review,
            assets: assets,
            onReadWithCloud: { readAgain(.cloud, payload ?? input.payload) },
            onAddPages: addPages,
            rereading: rereading,
            rereadResult: rereadResult,
            readAgainError: readAgainError,
            onClose: { finish($0) }
        )
    }

    /// Photos and scans can take more pages; a PDF or pasted text can't.
    private var canAddPages: Bool {
        if case .images = payload ?? input.payload { return true }
        return false
    }

    /// Reads the document again with the added pages as one document.
    private func addPages(_ added: CaptureRequest.Payload) {
        guard case .images(let existing) = payload ?? input.payload, case .images(let more) = added, !more.isEmpty else { return }
        readAgain(.pages, .images(existing + more))
    }

    /// The one way to read a document again while its review stays on screen: with added
    /// pages, or by the person's AI provider (on a tap, or by itself after a weak reading).
    /// The review merges the new reading with what the person changed meanwhile.
    private func readAgain(_ what: CaptureReread, _ newPayload: CaptureRequest.Payload) {
        guard rereading == nil else { return }
        let cloud = useCloud || what == .cloud
        readAgainError = nil
        withAnimation(DS.Motion.animation(DS.Motion.standard, reduceMotion: reduceMotion)) { rereading = what }
        Task {
            do {
                let result = try await CaptureRunner.run(newPayload, useCloudModel: cloud, ownerID: input.preferredAssetID)
                payload = newPayload
                useCloud = cloud
                rereadResult = result
            } catch {
                CaptureLog.engine.error("Reading again failed: \((error as NSError).domain, privacy: .public) \((error as NSError).code)")
                readAgainError = String(localized: "Încearcă o poză mai clară, cu actul întins și fără umbre.")
            }
            withAnimation(DS.Motion.animation(DS.Motion.standard, reduceMotion: reduceMotion)) { rereading = nil }
        }
    }

    private func finish(_ result: CaptureFlowResult) {
        CaptureRunner.forget(input.id)
        if let item = input.inboxItem {
            switch result {
            case .filed, .visitSaved: IntakeInbox.shared.remove(item)
            case .dismissed: break
            }
        }
        onClose(result)
    }
}

/// The skeleton shown while capture reads the document. The layout matches the
/// review, so nothing jumps when the values arrive.
private struct CaptureReadingView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DS.Space.l) {
                DSCard {
                    HStack(spacing: DS.Space.s) {
                        RoundedRectangle(cornerRadius: DS.Radius.control, style: .continuous)
                            .fill(DS.Palette.fill)
                            .frame(width: 64, height: 84)
                        VStack(alignment: .leading, spacing: DS.Space.xs) {
                            Text(verbatim: "Poliță RCA").dsFont(.title)
                            Text(verbatim: "Citit pe telefon").dsFont(.footnote)
                        }
                    }
                }
                DSCard {
                    VStack(alignment: .leading, spacing: DS.Space.s) {
                        ForEach(0..<4, id: \.self) { _ in
                            VStack(alignment: .leading, spacing: 4) {
                                Text(verbatim: "Număr poliță").dsFont(.footnote)
                                Text(verbatim: "RO/00/000000000").dsFont(.headline)
                            }
                        }
                    }
                }
            }
            .padding(DS.Space.m)
            .dsSkeleton(true)
            DSDelayedProgress(label: "Citesc actul…")
                .padding(.top, DS.Space.m)
        }
        .background(DS.Palette.background)
        .navigationTitle("Citesc actul")
        .navigationBarTitleDisplayMode(.inline)
    }
}
