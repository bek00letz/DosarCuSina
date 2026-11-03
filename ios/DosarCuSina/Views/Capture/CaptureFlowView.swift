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
    /// The reading and its pages. It lives as long as this input: when the screen that
    /// presents the capture lets go of it (the sheet closed or swiped down), any reading
    /// still running stops and the pages are let go.
    let session: CaptureSession

    @MainActor
    init(payload: CaptureRequest.Payload, inboxItem: InboxItem? = nil, preferredAssetID: UUID? = nil, filesAsPersonalDocument: Bool = false) {
        self.payload = payload
        self.inboxItem = inboxItem
        self.preferredAssetID = preferredAssetID
        self.filesAsPersonalDocument = filesAsPersonalDocument
        self.session = CaptureSession(payload: payload, ownerID: preferredAssetID)
    }
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
    @Query(sort: \Asset.name) private var assets: [Asset]

    private var session: CaptureSession { input.session }

    var body: some View {
        NavigationStack {
            Group {
                switch session.phase {
                case .idle, .reading:
                    CaptureReadingView()
                case .read(let result):
                    content(for: result)
                case .failed:
                    DSErrorState("Nu am putut citi actul", message: "Încearcă din nou. Dacă tot nu merge, fă o poză mai clară, cu actul întins și fără umbre.") {
                        session.read()
                    }
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Închide") { finish(.dismissed) }
                        }
                    }
                }
            }
        }
        // Starts once; a sheet SwiftUI rebuilds finds the reading already running.
        .task {
            guard session.phase == .idle else { return }
            session.headsForProtectedPlace = headsForProtectedPlace
            session.read()
        }
    }

    /// The capture started from a person's documents or a locked section.
    private var headsForProtectedPlace: Bool {
        guard !input.filesAsPersonalDocument else { return true }
        guard let id = input.preferredAssetID, let asset = assets.first(where: { $0.id == id }) else { return false }
        let templates = (try? TemplateStore(context: context).templatesByKey()) ?? [:]
        var current: Asset? = asset
        while let node = current {
            if templates[node.templateKey]?.isSensitive == true { return true }
            current = node.parent
        }
        return false
    }

    @ViewBuilder private func content(for result: CaptureResult) -> some View {
        let review = review(for: result)
        if CaptureMapping.opensVisitFlow(result.kind), review.duplicateAttachmentID == nil, case .asset(let id) = review.destination {
            AddVisitFlow(assetID: id, prefill: result) { saved in
                finish(saved ? .visitSaved(message: "Vizita e în istoric.") : .dismissed)
            }
        } else {
            reviewView(review)
        }
    }

    private func review(for result: CaptureResult) -> CaptureReview {
        var review = CaptureReview(result: result, assets: assets, context: context)
        if let preferred = input.preferredAssetID { review.destination = .asset(preferred) }
        review.filesAsPersonalDocument = input.filesAsPersonalDocument
        return review
    }

    private func reviewView(_ review: CaptureReview) -> some View {
        let addPages: ((CaptureRequest.Payload) -> Void)? = canAddPages ? { added in self.addPages(added) } : nil
        // One review for the whole flow: each new reading is merged into it, keeping
        // everything the person changed (`CaptureReview.carryingEdits`).
        return CaptureReviewView(
            review: review,
            assets: assets,
            onReadWithCloud: { session.readAgain(.cloud) },
            onAddPages: addPages,
            rereading: session.rereading,
            rereadResult: session.rereadResult,
            readAgainError: session.readAgainError,
            asksToSendToProvider: session.asksToSendToProvider,
            onAnswerSending: { session.answerSending($0) },
            onClose: { finish($0) }
        )
    }

    /// Photos and scans can take more pages; a PDF or pasted text can't.
    private var canAddPages: Bool {
        if case .images = session.payload ?? input.payload { return true }
        return false
    }

    /// Reads the document again with the added pages as one document.
    private func addPages(_ added: CaptureRequest.Payload) {
        guard case .images(let existing) = session.payload ?? input.payload, case .images(let more) = added, !more.isEmpty else { return }
        session.readAgain(.pages, payload: .images(existing + more))
    }

    private func finish(_ result: CaptureFlowResult) {
        // Saved or not, this capture is over: nothing keeps reading, its pages are let go.
        session.close()
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
