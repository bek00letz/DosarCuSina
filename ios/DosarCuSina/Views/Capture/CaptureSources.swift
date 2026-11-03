import PhotosUI
import SwiftUI
import UniformTypeIdentifiers
import VisionKit

/// Where a document comes from inside the app.
enum CaptureSource: String, Identifiable, CaseIterable {
    /// The document camera (flattens and crops pages). The camera permission is
    /// asked by the system the first time it opens.
    case camera
    /// Photos, through the system picker (no permission needed).
    case photos
    /// PDFs and images from Files.
    case files

    var id: String { rawValue }

    @MainActor static var isCameraAvailable: Bool { VNDocumentCameraViewController.isSupported }
}

extension View {
    /// Presents the picker for `source` and hands back what was picked, ready for capture.
    /// Cancelling hands back nothing and leaves the screen as it was.
    func captureSourcePicker(_ source: Binding<CaptureSource?>, onPicked: @escaping @MainActor (CaptureRequest.Payload) -> Void, onError: @escaping @MainActor (Error) -> Void) -> some View {
        modifier(CaptureSourcePickerModifier(source: source, onPicked: onPicked, onError: onError))
    }
}

private struct CaptureSourcePickerModifier: ViewModifier {
    @Binding var source: CaptureSource?
    let onPicked: @MainActor (CaptureRequest.Payload) -> Void
    let onError: @MainActor (Error) -> Void

    @State private var photoSelection: [PhotosPickerItem] = []

    func body(content: Content) -> some View {
        content
            .fullScreenCover(isPresented: binding(for: .camera)) {
                DocumentCamera { pages in
                    source = nil
                    guard !pages.isEmpty else { return }
                    do { onPicked(try CaptureInput.payload(scannedPages: pages)) } catch { onError(error) }
                }
                .ignoresSafeArea()
            }
            .photosPicker(isPresented: binding(for: .photos), selection: $photoSelection, maxSelectionCount: 10, selectionBehavior: .ordered, matching: .images)
            .onChange(of: photoSelection) { _, items in
                guard !items.isEmpty else { return }
                photoSelection = []
                Task {
                    var data: [Data] = []
                    for item in items {
                        if let bytes = try? await item.loadTransferable(type: Data.self) { data.append(bytes) }
                    }
                    do { onPicked(try CaptureInput.payload(photos: data)) } catch { onError(error) }
                }
            }
            .fileImporter(isPresented: binding(for: .files), allowedContentTypes: [.pdf, .image, .plainText], allowsMultipleSelection: false) { result in
                switch result {
                case .success(let urls):
                    let accessed = urls.map { $0.startAccessingSecurityScopedResource() }
                    defer { for (url, ok) in zip(urls, accessed) where ok { url.stopAccessingSecurityScopedResource() } }
                    do { onPicked(try CaptureInput.payload(files: urls)) } catch { onError(error) }
                case .failure(let error):
                    onError(error)
                }
            }
    }

    private func binding(for kind: CaptureSource) -> Binding<Bool> {
        Binding(get: { source == kind }, set: { if !$0, source == kind { source = nil } })
    }
}

/// VisionKit's document camera: finds the page, flattens it, reads several pages in a row.
struct DocumentCamera: UIViewControllerRepresentable {
    let onFinish: @MainActor ([CGImage]) -> Void

    func makeUIViewController(context: Context) -> VNDocumentCameraViewController {
        let controller = VNDocumentCameraViewController()
        controller.delegate = context.coordinator
        return controller
    }

    func updateUIViewController(_ controller: VNDocumentCameraViewController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(onFinish: onFinish) }

    @MainActor
    final class Coordinator: NSObject, @preconcurrency VNDocumentCameraViewControllerDelegate {
        let onFinish: @MainActor ([CGImage]) -> Void

        init(onFinish: @escaping @MainActor ([CGImage]) -> Void) {
            self.onFinish = onFinish
        }

        func documentCameraViewController(_ controller: VNDocumentCameraViewController, didFinishWith scan: VNDocumentCameraScan) {
            let pages = (0..<scan.pageCount).compactMap { scan.imageOfPage(at: $0).cgImage }
            onFinish(pages)
        }

        func documentCameraViewControllerDidCancel(_ controller: VNDocumentCameraViewController) {
            onFinish([])
        }

        func documentCameraViewController(_ controller: VNDocumentCameraViewController, didFailWithError error: Error) {
            onFinish([])
        }
    }
}

/// Runs capture on what was picked. On-device only, unless the person's AI provider
/// reads this document too (on a tap, or by itself after a weak reading when they chose so).
enum CaptureRunner {
    static func run(_ payload: CaptureRequest.Payload, useCloudModel: Bool = false, ownerID: UUID? = nil) async throws -> CaptureResult {
        let engine = CaptureEngine.standard()
        return try await engine.capture(CaptureRequest(payload, options: CaptureOptions(useCloudModel: useCloudModel, ownerID: ownerID?.uuidString)))
    }

    /// Whether the person set up an AI provider with their own key (Settings).
    static var hasCloudKey: Bool { AIProviderSettings.standard.isReady }
}

/// One capture, from the moment something is picked until its screen is gone: the
/// reading, any reading again (added pages, the AI provider), and this capture's own
/// claim on the pages each reading kept.
///
/// It lives as long as whoever owns it: `CaptureFlowInput` for the capture sheet (so a
/// sheet SwiftUI rebuilds keeps the same reading), a screen's `@State` elsewhere. When
/// it goes (the sheet swiped down, closed or saved) whatever is still reading is
/// cancelled, so a request to the AI provider not yet sent is never sent, and its
/// claims on pages end; pages another capture still holds stay.
@MainActor
@Observable
final class CaptureSession {
    enum Phase: Equatable {
        case idle
        case reading
        case read(CaptureResult)
        case failed
    }

    typealias Reader = @MainActor (CaptureRequest.Payload, _ useCloudModel: Bool, _ ownerID: UUID?) async throws -> CaptureResult

    private(set) var phase: Phase = .idle
    /// What is being read again while the review stays on screen.
    private(set) var rereading: CaptureReread?
    /// The newest reading again, which the review merges with what the person changed.
    private(set) var rereadResult: CaptureResult?
    /// Why the last reading again didn't work.
    private(set) var readAgainError: String?
    /// "Citește automat" wants to send an identity document's photo: the review asks first.
    private(set) var asksToSendToProvider = false
    /// The pages read, with any the person added (the back of a card).
    private(set) var payload: CaptureRequest.Payload?

    /// Where a capture is headed, as far as reading it with the AI provider goes.
    struct Destination: Equatable {
        /// A locked section or a person's documents: "Citește automat" asks first, whatever the page.
        var isProtected = false
        /// The person is adding a document read only on the phone (a bank card's own page):
        /// the provider never reads it (`PhoneOnlyReading`).
        var staysOnPhone = false
    }

    @ObservationIgnored let ownerID: UUID?
    @ObservationIgnored private let reader: Reader
    @ObservationIgnored private let automaticReading: @MainActor (CaptureResult, Destination) -> AIProviderSettings.AutomaticReading
    /// Where the capture is headed, set by what presents it before the first reading.
    @ObservationIgnored var destination = Destination()
    @ObservationIgnored private var usesCloud = false
    /// The provider read, or the person answered, for this document: never asked again.
    @ObservationIgnored private var hasAnsweredSending = false
    /// What must end with the session, even from `deinit`.
    private let holdings: Holdings

    init(
        payload: CaptureRequest.Payload? = nil,
        ownerID: UUID? = nil,
        store: CaptureDocumentStore = .shared(),
        reader: @escaping Reader = { try await CaptureRunner.run($0, useCloudModel: $1, ownerID: $2) },
        automaticReading: @escaping @MainActor (CaptureResult, Destination) -> AIProviderSettings.AutomaticReading = {
            AIProviderSettings.standard.automaticReading(after: $0, headedForProtectedPlace: $1.isProtected, staysOnPhone: $1.staysOnPhone)
        }
    ) {
        self.payload = payload
        self.ownerID = ownerID
        self.reader = reader
        self.automaticReading = automaticReading
        self.holdings = Holdings(store: store)
    }

    deinit {
        holdings.end()
    }

    /// The reading a screen shows, when there is one.
    var result: CaptureResult? {
        if case .read(let result) = phase { return result }
        return nil
    }

    /// Reads `payload`, or what the session was made with: the first reading, or
    /// "Încearcă din nou". A second call while a reading runs does nothing.
    func read(_ newPayload: CaptureRequest.Payload? = nil) {
        guard phase != .reading, let payload = newPayload ?? payload else { return }
        self.payload = payload
        phase = .reading
        rereadResult = nil
        hasAnsweredSending = false
        asksToSendToProvider = false
        let previous = result
        holdings.add(Task { [weak self, reader, ownerID, holdings] in
            do {
                let result = try await reader(payload, false, ownerID)
                guard let self, !Task.isCancelled else { return holdings.release(result) }
                holdings.hold(result.document)
                if let previous, previous.document != result.document { holdings.release(previous) }
                self.phase = .read(result)
                self.afterReading(result)
            } catch {
                guard let self, !(error is CancellationError), !Task.isCancelled else { return }
                CaptureLog.engine.error("Capture failed: \(String(describing: type(of: error)), privacy: .public) \((error as NSError).domain, privacy: .public) \((error as NSError).code)")
                self.phase = .failed
            }
        })
    }

    /// The person chose to have a weak phone reading read by their AI provider too, or
    /// "Citește automat" asks for it. For an identity document it waits for their yes.
    private func afterReading(_ result: CaptureResult) {
        switch automaticReading(result, destination) {
        case .none: break
        case .read:
            CaptureLog.engine.info("Reading with the AI provider automatically: \(ReadingArbiter.weaknesses(of: result).map(\.rawValue).sorted().joined(separator: ","), privacy: .public)")
            readAgain(.cloud)
        case .askFirst:
            asksToSendToProvider = !hasAnsweredSending
        }
    }

    /// The answer to "Trimit poza la <provider>?": yes reads it now; no keeps it on the phone.
    func answerSending(_ send: Bool) {
        asksToSendToProvider = false
        hasAnsweredSending = true
        if send { readAgain(.cloud) }
    }

    /// Whether the person's AI provider may read this document at all: never one read only
    /// on the phone (`PhoneOnlyReading`), whether the person is adding one or the phone read one.
    func providerMayRead(_ reading: CaptureResult?) -> Bool {
        !destination.staysOnPhone && !(reading.map { PhoneOnlyReading.mayBeOne($0) } ?? false)
    }

    /// The one way to read a document again while its review stays on screen: with added
    /// pages, or by the person's AI provider (on a tap, by itself after a weak reading, or
    /// after the person said yes). The review merges the new reading with what they changed.
    /// A document read only on the phone is never sent; added pages are read on the phone,
    /// and the engine checks what it read of them before anything leaves (`PhoneOnlyReading`).
    func readAgain(_ what: CaptureReread, payload newPayload: CaptureRequest.Payload? = nil) {
        guard rereading == nil, let payload = newPayload ?? payload else { return }
        let mayUseProvider = providerMayRead(rereadResult ?? result)
        guard what != .cloud || mayUseProvider else { return }
        let cloud = (usesCloud || what == .cloud) && mayUseProvider
        if what == .cloud { hasAnsweredSending = true; asksToSendToProvider = false }
        readAgainError = nil
        rereading = what
        let replaced = rereadResult ?? result
        holdings.add(Task { [weak self, reader, ownerID, holdings] in
            do {
                let result = try await reader(payload, cloud, ownerID)
                guard let self, !Task.isCancelled else { return holdings.release(result) }
                holdings.hold(result.document)
                if let replaced, replaced.document != result.document { holdings.release(replaced) }
                self.payload = payload
                self.usesCloud = cloud
                self.rereadResult = result
            } catch {
                guard let self, !Task.isCancelled else { return }
                if !(error is CancellationError) {
                    CaptureLog.engine.error("Reading again failed: \((error as NSError).domain, privacy: .public) \((error as NSError).code)")
                    self.readAgainError = String(localized: "Încearcă o poză mai clară, cu actul întins și fără umbre.")
                }
            }
            self?.rereading = nil
        })
    }

    /// Ends the session now: cancels any reading and lets go of every page it holds.
    /// Ending it again, or its `deinit` later, does nothing more.
    func close() {
        holdings.end()
    }

    /// The tasks and page claims of a session, safe to end from `deinit`.
    private final class Holdings: @unchecked Sendable {
        private let lock = NSLock()
        private var tasks: [Task<Void, Never>] = []
        private var refs: Set<CapturedDocumentRef> = []
        private var ended = false
        let store: CaptureDocumentStore

        init(store: CaptureDocumentStore) { self.store = store }

        func add(_ task: Task<Void, Never>) {
            let stillOpen = lock.withLock { () -> Bool in
                guard !ended else { return false }
                tasks.removeAll { $0.isCancelled }
                tasks.append(task)
                return true
            }
            if !stillOpen { task.cancel() }
        }

        func hold(_ ref: CapturedDocumentRef?) {
            guard let ref else { return }
            let stillOpen = lock.withLock { () -> Bool in
                guard !ended else { return false }
                refs.insert(ref)
                return true
            }
            if !stillOpen { Task { [store] in await store.release(ref) } }
        }

        /// Lets go of a reading's pages now: one the session no longer shows, or one that came in after it ended.
        func release(_ result: CaptureResult) {
            guard let ref = result.document else { return }
            lock.withLock { _ = refs.remove(ref) }
            Task { [store] in await store.release(ref) }
        }

        func end() {
            let (tasks, refs) = lock.withLock { () -> ([Task<Void, Never>], Set<CapturedDocumentRef>) in
                guard !ended else { return ([], []) }
                ended = true
                defer { self.tasks = []; self.refs = [] }
                return (self.tasks, self.refs)
            }
            for task in tasks { task.cancel() }
            guard !refs.isEmpty else { return }
            Task { [store] in for ref in refs { await store.release(ref) } }
        }
    }
}
