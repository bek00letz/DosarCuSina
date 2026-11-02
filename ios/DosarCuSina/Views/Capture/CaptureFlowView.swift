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
    case filed(message: LocalizedStringResource)
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
    @State private var useCloud = false
    /// The pages read, once the person added more (the back of a card).
    @State private var payload: CaptureRequest.Payload?
    @State private var isReadingAgain = false
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
            let key = "\(input.id.uuidString)-\(attempt)-\(useCloud)"
            let result = try await CaptureRunner.result(for: key, payload ?? input.payload, useCloudModel: useCloud, ownerID: input.preferredAssetID)
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
        let addPages: ((CaptureReview, CaptureRequest.Payload) -> Void)? = canAddPages ? { current, added in self.addPages(current, added) } : nil
        return CaptureReviewView(
            review: review,
            assets: assets,
            onReadWithCloud: {
                useCloud = true
                attempt += 1
            },
            onAddPages: addPages,
            isReadingAgain: isReadingAgain,
            readAgainError: readAgainError,
            onClose: { finish($0) }
        )
        // A new read is a new review; the person's edits are carried into it.
        .id(review.id)
    }

    /// Photos and scans can take more pages; a PDF or pasted text can't.
    private var canAddPages: Bool {
        if case .images = payload ?? input.payload { return true }
        return false
    }

    /// Reads the document again with the added pages as one document. The review stays
    /// on screen while it reads, and the new one keeps everything the person changed.
    private func addPages(_ current: CaptureReview, _ added: CaptureRequest.Payload) {
        guard case .images(let existing) = payload ?? input.payload, case .images(let more) = added, !more.isEmpty else { return }
        let combined = CaptureRequest.Payload.images(existing + more)
        readAgainError = nil
        withAnimation(DS.Motion.animation(DS.Motion.standard, reduceMotion: reduceMotion)) { isReadingAgain = true }
        Task {
            do {
                let result = try await CaptureRunner.run(combined, useCloudModel: useCloud, ownerID: input.preferredAssetID)
                payload = combined
                let review = CaptureReview(result: result, assets: assets, context: context).carryingEdits(from: current)
                isReadingAgain = false
                phase = .review(review)
            } catch {
                CaptureLog.engine.error("Reading added pages failed: \((error as NSError).domain, privacy: .public) \((error as NSError).code)")
                isReadingAgain = false
                readAgainError = String(localized: "Încearcă o poză mai clară, cu actul întins și fără umbre.")
            }
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
