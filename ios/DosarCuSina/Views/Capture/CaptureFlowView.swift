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

/// What happened when the flow closed, with the toast that says so for the screen
/// underneath. A filing's toast offers "Anulează", which takes the whole filing back.
enum CaptureFlowResult {
    /// `assetID` is the section the document was filed in, so the screen underneath can open it.
    case filed(toast: DSToast, assetID: UUID?)
    case visitSaved(toast: DSToast)
    case dismissed

    /// The toast for a filing: where it went, and "Anulează" when the receipt can take it back.
    @MainActor
    static func filing(in place: String?, assetID: UUID?, receipt: UndoReceipt?) -> CaptureFlowResult {
        let message: LocalizedStringResource = place.map { "Salvat în \($0)." } ?? "Actul e salvat."
        let toast = receipt.map { DSToast.undo(message, receipt: $0) } ?? DSToast(title: message, actionTitle: nil)
        return .filed(toast: toast, assetID: assetID)
    }

    /// The toast for a visit saved with its invoice, with "Anulează", which takes the visit,
    /// its invoice and its firm back, as the visit's own "Anulează vizita" does.
    @MainActor
    static func visit(receipt: UndoReceipt) -> CaptureFlowResult {
        .visitSaved(toast: .undo("Vizita e în istoric.", receipt: receipt))
    }

    /// The toast the flow closes with; nil when nothing was saved.
    var toast: DSToast? {
        switch self {
        case .filed(let toast, _), .visitSaved(let toast): toast
        case .dismissed: nil
        }
    }

    /// The same result, closing with `toast` instead.
    func showing(_ toast: DSToast) -> CaptureFlowResult {
        switch self {
        case .filed(_, let assetID): .filed(toast: toast, assetID: assetID)
        case .visitSaved: .visitSaved(toast: toast)
        case .dismissed: .dismissed
        }
    }

    /// What the share-inbox item the capture was read from does when the flow closes with this
    /// result. Saved, and "Anulează" can still take it back (a filing or a visit): the item
    /// waits, hidden, until the toast is gone, and comes back to De verificat with the undo.
    /// Saved with nothing to take back: it leaves at once. Not saved: it stays.
    @MainActor
    func leaving(_ item: InboxItem, inbox: IntakeInbox) -> CaptureFlowResult {
        guard var toast = self.toast else { return self }
        guard toast.offersAction else {
            inbox.remove(item)
            return self
        }
        inbox.setAside(item)
        let afterUndo = toast.afterUndo
        toast.afterUndo = { inbox.keep(item); afterUndo?() }
        let whenGone = toast.whenGone
        toast.whenGone = { inbox.remove(item); whenGone?() }
        return showing(toast)
    }
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
            session.destination = CaptureSession.Destination(isProtected: headsForProtectedPlace, staysOnPhone: startsOnPhoneOnlyDocument)
            session.read()
        }
    }

    /// The capture started from a document read only on the phone (a bank card's own page,
    /// "Adaugă poza actului"): the AI provider never reads it (`PhoneOnlyReading`).
    private var startsOnPhoneOnlyDocument: Bool {
        guard let id = input.preferredAssetID, let asset = assets.first(where: { $0.id == id }) else { return false }
        return PhoneOnlyReading.holdsOne(asset.values)
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
        if result.kind.profile.opensVisitFlow, review.duplicateAttachmentID == nil, case .asset(let id) = review.destination {
            AddVisitFlow(assetID: id, prefill: result) { receipt in
                finish(receipt.map(CaptureFlowResult.visit(receipt:)) ?? .dismissed)
            }
        } else {
            reviewView(review)
        }
    }

    private func review(for result: CaptureResult) -> CaptureReview {
        var review = CaptureReview(result: result, assets: assets, context: context)
        if let preferred = input.preferredAssetID { review.destination = .asset(preferred) }
        review.filesAsPersonalDocument = input.filesAsPersonalDocument
        review.staysOnPhone = session.destination.staysOnPhone
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
        // Something shared from another app waits in De verificat while "Anulează" can bring it back.
        onClose(input.inboxItem.map { result.leaving($0, inbox: .shared) } ?? result)
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
