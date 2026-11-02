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

/// Runs capture on what was picked. On-device only, unless the person asks
/// for their own Gemini key on this document.
enum CaptureRunner {
    static func run(_ payload: CaptureRequest.Payload, useCloudModel: Bool = false, ownerID: UUID? = nil) async throws -> CaptureResult {
        let engine = CaptureEngine.standard()
        return try await engine.capture(CaptureRequest(payload, options: CaptureOptions(useCloudModel: useCloudModel, ownerID: ownerID?.uuidString)))
    }

    /// Reads that outlive the screen showing them. SwiftUI may rebuild a sheet while
    /// it appears (a picker still closing, for instance); the rebuilt screen picks up
    /// the same read instead of cancelling it and starting over.
    @MainActor private static var jobs: [String: Task<CaptureResult, any Error>] = [:]

    @MainActor
    static func result(for key: String, _ payload: CaptureRequest.Payload, useCloudModel: Bool, ownerID: UUID?) async throws -> CaptureResult {
        let job = jobs[key] ?? {
            let task = Task { try await run(payload, useCloudModel: useCloudModel, ownerID: ownerID) }
            jobs[key] = task
            return task
        }()
        do {
            return try await job.value
        } catch {
            // A failed read is forgotten, so "Încearcă din nou" really reads again.
            jobs[key] = nil
            throw error
        }
    }

    /// Forgets every read for a capture once its screen is closed for good.
    @MainActor
    static func forget(_ inputID: UUID) {
        jobs = jobs.filter { !$0.key.hasPrefix(inputID.uuidString) }
    }

    /// Whether the person added their own Gemini key (Settings).
    static var hasCloudKey: Bool { KeychainManager.hasConfiguredAPIKey }
}
