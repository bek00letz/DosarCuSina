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

    var body: some View {
        NavigationStack {
            Group {
                switch phase {
                case .reading:
                    CaptureReadingView()
                case .review(let review):
                    CaptureReviewView(review: review, assets: assets, onReadWithCloud: {
                        useCloud = true
                        attempt += 1
                    }, onClose: finish)
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
                            Button("Închide") { onClose(.dismissed) }
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
            let result = try await CaptureRunner.run(input.payload, useCloudModel: useCloud, ownerID: input.preferredAssetID)
            var review = CaptureReview(result: result, assets: assets, context: context)
            if let preferred = input.preferredAssetID { review.destination = .asset(preferred) }
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

    private func finish(_ result: CaptureFlowResult) {
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
