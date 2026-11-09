import SwiftUI
import UIKit

/// What the person can do to a page in the viewer: turn it a quarter turn, or choose
/// between the document cut out of its photo and the whole photo. Each returns the step's
/// receipt when it can be taken back from a toast (a filed document), nil otherwise.
struct DocumentPageEditing {
    var turn: @MainActor (_ page: DocumentPageSource) async throws -> UndoReceipt?
    var showWholePhoto: @MainActor (_ page: DocumentPageSource, _ whole: Bool) async throws -> UndoReceipt?

    /// In the review nothing is saved yet: the choices are the review's, kept when it saves.
    @MainActor
    static func review(_ choices: Binding<[Int: PageChoice]>) -> DocumentPageEditing {
        DocumentPageEditing(
            turn: { page in
                choices.wrappedValue[page.index] = page.framing.turned().choice
                return nil
            },
            showWholePhoto: { page, whole in
                choices.wrappedValue[page.index] = page.framing.showingWholePhoto(whole).choice
                return nil
            }
        )
    }

    /// A filed document: each change is one undoable step (`AttachmentActions`).
    @MainActor
    static func document(_ attachment: Attachment, actions: AttachmentActions) -> DocumentPageEditing {
        DocumentPageEditing(
            turn: { page in try await actions.turnPage(attachment, page: page.index) },
            showWholePhoto: { page, whole in try await actions.showWholePhoto(whole, of: attachment, pages: [page.index]) }
        )
    }
}

/// A document's pages full screen, as they are shown (cut out, turned): pinch or
/// double-tap to zoom, swipe between pages, swipe down or "Gata" to close. A PDF page is
/// drawn again at the zoom shown, so small print stays sharp. With `editing`, "Rotește"
/// and "Poza întreagă" / "Doar actul"; with `share`, "Trimite". Used by the capture review
/// and the document page.
struct DocumentPagesViewer: View {
    let pages: [DocumentPageSource]
    var editing: DocumentPageEditing?
    var share: DocumentShareRequest?

    @State private var selection: Int
    @State private var isZoomed = false
    @State private var dragOffset: CGFloat = 0
    /// Whether the viewer has faded in (Reduce Motion only).
    @State private var isShown = false
    @State private var isWorking = false
    @State private var toast: DSToast?
    @State private var shareRequest: DocumentShareRequest?
    @State private var turns = 0
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// How far down a swipe has to travel to close the viewer.
    private let closeDistance: CGFloat = 120

    init(pages: [DocumentPageSource], startAt index: Int = 0, editing: DocumentPageEditing? = nil, share: DocumentShareRequest? = nil) {
        self.pages = pages
        self.editing = editing
        self.share = share
        _selection = State(initialValue: min(max(index, 0), max(pages.count - 1, 0)))
    }

    private var current: DocumentPageSource? {
        pages.first { $0.index == selection } ?? pages.first
    }

    var body: some View {
        NavigationStack {
            TabView(selection: $selection) {
                ForEach(pages) { page in
                    ViewerPage(source: page, reduceMotion: reduceMotion) { zoomed in
                        if page.index == selection { isZoomed = zoomed }
                    }
                    .ignoresSafeArea(edges: hasActions ? [] : .bottom)
                    .accessibilityElement()
                    .accessibilityLabel(Text("Pagina \(page.index + 1) din \(pages.count)", comment: "VoiceOver label of a page in the full-screen viewer."))
                    .accessibilityAddTraits(.isImage)
                    .tag(page.index)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: pages.count > 1 ? .always : .never))
            .offset(y: dragOffset)
            .simultaneousGesture(isZoomed ? nil : closeGesture)
            .background(Color.black.opacity(backgroundOpacity).ignoresSafeArea())
            .safeAreaInset(edge: .bottom) {
                if hasActions { actions }
            }
            .navigationTitle(pages.count > 1 ? Text("Pagina \(selection + 1) din \(pages.count)", comment: "Title of the full-screen page viewer.") : Text(verbatim: ""))
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.hidden, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button { close() } label: { Text("Gata", comment: "Closes the full-screen page viewer.") }
                }
            }
            .onChange(of: selection) { isZoomed = false }
        }
        .preferredColorScheme(.dark)
        .dsToast($toast)
        .documentShare($shareRequest)
        .sensoryFeedback(.selection, trigger: turns)
        // With Reduce Motion the cover appears without its slide (see `present`) and
        // cross-fades in and out instead.
        .opacity(reduceMotion && !isShown ? 0 : 1)
        .presentationBackground(.clear)
        .onAppear {
            guard reduceMotion else { return }
            withAnimation(DS.Motion.reducedFade) { isShown = true }
        }
    }

    private var hasActions: Bool { editing != nil || share != nil }

    /// "Rotește", "Poza întreagă" or "Doar actul", and "Trimite", for the page shown.
    private var actions: some View {
        DSAdaptiveStack(horizontalAlignment: .center, spacing: DS.Space.s) {
            if editing != nil, let page = current {
                DSCompactButton("Rotește", systemImage: "rotate.right") { turn(page) }
                    .accessibilityHint(Text("Întoarce pagina un sfert de tură spre dreapta.", comment: "VoiceOver hint of the turn button."))
                if page.framing.hasCrop {
                    if page.framing.showsCrop {
                        DSCompactButton("Poza întreagă", systemImage: "photo") { showWholePhoto(page, true) }
                            .accessibilityLabel(Text("Folosește poza întreagă", comment: "Shows the whole photo instead of the document cut out of it."))
                    } else {
                        DSCompactButton("Doar actul", systemImage: "crop") { showWholePhoto(page, false) }
                            .accessibilityLabel(Text("Arată doar actul, fără ce e în jur", comment: "Shows the document cut out of its photo again."))
                    }
                }
            }
            if let share {
                DSCompactButton("Trimite", systemImage: "square.and.arrow.up") {
                    shareRequest = DocumentShareRequest(pages: pages, name: share.name,
                                                        isFromLockedCategory: share.isFromLockedCategory, needsCare: share.needsCare)
                }
            }
        }
        .disabled(isWorking)
        .frame(maxWidth: .infinity)
        .padding(.horizontal, DS.Space.m)
        .padding(.vertical, DS.Space.xs)
    }

    private func turn(_ page: DocumentPageSource) {
        guard let editing else { return }
        run { _ = try await editing.turn(page); turns += 1 }
    }

    private func showWholePhoto(_ page: DocumentPageSource, _ whole: Bool) {
        guard let editing else { return }
        run {
            guard let receipt = try await editing.showWholePhoto(page, whole) else { return }
            toast = .undo(whole
                ? LocalizedStringResource("Se vede poza întreagă", comment: "Toast after choosing the whole photo of a document.")
                : LocalizedStringResource("Se vede doar actul", comment: "Toast after choosing the document cut out of its photo."), receipt: receipt)
        }
    }

    /// One change at a time; a failure says so calmly.
    private func run(_ work: @escaping @MainActor () async throws -> Void) {
        guard !isWorking else { return }
        isWorking = true
        Task {
            defer { isWorking = false }
            do { try await work() } catch { toast = .failure(error) }
        }
    }

    /// Presents the viewer: with Reduce Motion, without the full-screen cover's slide.
    @MainActor static func present(reduceMotion: Bool, _ show: () -> Void) {
        guard reduceMotion else { return show() }
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction, show)
    }

    /// Closes the viewer: with Reduce Motion, a fade instead of the slide down.
    private func close() {
        guard reduceMotion else { return dismiss() }
        withAnimation(DS.Motion.reducedFade) {
            isShown = false
        } completion: {
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) { dismiss() }
        }
    }

    private var backgroundOpacity: Double {
        1 - min(Double(abs(dragOffset) / (closeDistance * 3)), 0.6)
    }

    /// A downward swipe closes the viewer; a short one springs back.
    private var closeGesture: some Gesture {
        DragGesture(minimumDistance: 20)
            .onChanged { value in
                guard value.translation.height > 0, value.translation.height > abs(value.translation.width) else { return }
                dragOffset = value.translation.height
            }
            .onEnded { value in
                if value.translation.height > closeDistance || value.predictedEndTranslation.height > closeDistance * 2.5 {
                    close()
                } else {
                    withAnimation(DS.Motion.animation(DS.Motion.standard, reduceMotion: reduceMotion)) { dragOffset = 0 }
                }
            }
    }
}

/// One page, drawn as shown away from the main thread and faded in once it is ready. A
/// photo is drawn at its full size; a PDF page to fit the screen, then sharper as it is zoomed.
private struct ViewerPage: View {
    let source: DocumentPageSource
    let reduceMotion: Bool
    let onZoomChange: (Bool) -> Void

    @Environment(\.displayScale) private var displayScale
    @State private var image: UIImage?

    private struct DrawKey: Hashable {
        let page: DocumentPageSource.DrawingKey
        /// The space a PDF page is fitted to; a photo is drawn whole, whatever the space.
        let width: Double
        let height: Double
    }

    var body: some View {
        GeometryReader { geometry in
            ZoomablePage(image: image, source: source, displayScale: displayScale, reduceMotion: reduceMotion, onZoomChange: onZoomChange)
                .opacity(image == nil ? 0 : 1)
                .animation(DS.Motion.animation(DS.Motion.standard, reduceMotion: reduceMotion), value: image == nil)
                .task(id: DrawKey(page: source.drawingKey, width: source.isPDF ? geometry.size.width : 0, height: source.isPDF ? geometry.size.height : 0)) {
                    await draw(fitting: geometry.size)
                }
        }
    }

    private func draw(fitting size: CGSize) async {
        let source = source
        let scale = displayScale
        let drawn = await Task.detached(priority: .userInitiated) { () -> CGImage? in
            guard source.isPDF else { return DocumentPicture.image(of: source, maxLongEdge: 4096) }
            guard let shown = DocumentPicture.shownSize(of: source), shown.width > 0, shown.height > 0,
                  size.width > 0, size.height > 0 else { return nil }
            let fit = min(size.width / shown.width, size.height / shown.height)
            return DocumentPicture.image(of: source, pdfPixelsPerPoint: fit * scale)
        }.value
        guard !Task.isCancelled, let drawn else { return }
        image = UIImage(cgImage: drawn)
    }
}

/// One page in a scroll view that zooms: pinch, or double-tap to zoom in where tapped and
/// back out. A zoomed-in PDF page gets the part on screen drawn again at the zoom shown.
private struct ZoomablePage: UIViewRepresentable {
    let image: UIImage?
    let source: DocumentPageSource
    let displayScale: CGFloat
    let reduceMotion: Bool
    let onZoomChange: (Bool) -> Void

    func makeUIView(context: Context) -> UIScrollView {
        let scrollView = UIScrollView()
        scrollView.delegate = context.coordinator
        scrollView.minimumZoomScale = 1
        scrollView.maximumZoomScale = 5
        scrollView.showsHorizontalScrollIndicator = false
        scrollView.showsVerticalScrollIndicator = false
        scrollView.contentInsetAdjustmentBehavior = .never
        scrollView.backgroundColor = .clear

        let imageView = UIImageView(image: image)
        imageView.contentMode = .scaleAspectFit
        imageView.isUserInteractionEnabled = true
        imageView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.addSubview(imageView)
        NSLayoutConstraint.activate([
            imageView.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor),
            imageView.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor),
            imageView.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor),
            imageView.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor),
            imageView.widthAnchor.constraint(equalTo: scrollView.frameLayoutGuide.widthAnchor),
            imageView.heightAnchor.constraint(equalTo: scrollView.frameLayoutGuide.heightAnchor),
        ])
        context.coordinator.imageView = imageView

        let doubleTap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.doubleTapped(_:)))
        doubleTap.numberOfTapsRequired = 2
        scrollView.addGestureRecognizer(doubleTap)
        return scrollView
    }

    func updateUIView(_ scrollView: UIScrollView, context: Context) {
        context.coordinator.parent = self
        guard let imageView = context.coordinator.imageView, imageView.image !== image else { return }
        // A new drawing (the page turned, or cut out again): what was sharpened for the old one goes.
        imageView.image = image
        context.coordinator.clearSharpened()
        if scrollView.zoomScale > 1.01 { context.coordinator.sharpen(scrollView) }
    }

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    @MainActor
    final class Coordinator: NSObject, UIScrollViewDelegate {
        var parent: ZoomablePage
        weak var imageView: UIImageView?
        /// The part of a PDF page on screen, drawn at the zoom shown, over the page.
        private var sharpened: UIImageView?
        /// Each drawing asked for; an older one that finishes late is dropped.
        private var generation = 0

        init(parent: ZoomablePage) {
            self.parent = parent
        }

        func viewForZooming(in scrollView: UIScrollView) -> UIView? { imageView }

        func scrollViewDidEndZooming(_ scrollView: UIScrollView, with view: UIView?, atScale scale: CGFloat) {
            parent.onZoomChange(scale > 1.01)
            sharpen(scrollView)
        }

        func scrollViewDidEndDragging(_ scrollView: UIScrollView, willDecelerate decelerate: Bool) {
            if !decelerate { sharpen(scrollView) }
        }

        func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) {
            sharpen(scrollView)
        }

        func clearSharpened() {
            generation += 1
            sharpened?.removeFromSuperview()
            sharpened = nil
        }

        /// Draws the part of a PDF page on screen again, one pixel for each of the screen's.
        func sharpen(_ scrollView: UIScrollView) {
            guard parent.source.isPDF, let imageView, let image = imageView.image else { return }
            guard scrollView.zoomScale > 1.01 else { return clearSharpened() }
            let bounds = imageView.bounds
            guard image.size.width > 0, image.size.height > 0, bounds.width > 0, bounds.height > 0,
                  let shown = DocumentPicture.shownSize(of: parent.source), shown.width > 0 else { return }
            // Where the page sits in the view (fitted, centred), and the part of it on screen.
            let fit = min(bounds.width / image.size.width, bounds.height / image.size.height)
            let fitted = CGRect(x: (bounds.width - image.size.width * fit) / 2, y: (bounds.height - image.size.height * fit) / 2,
                                width: image.size.width * fit, height: image.size.height * fit)
            let visible = scrollView.convert(scrollView.bounds, to: imageView).intersection(fitted)
            guard !visible.isNull, visible.width > 0, visible.height > 0 else { return }
            let pagePointsPerViewPoint = shown.width / fitted.width
            let pageRect = CGRect(x: (visible.minX - fitted.minX) * pagePointsPerViewPoint, y: (visible.minY - fitted.minY) * pagePointsPerViewPoint,
                                  width: visible.width * pagePointsPerViewPoint, height: visible.height * pagePointsPerViewPoint)
            let pixelsPerPoint = PDFPageRendering.pixelsPerPoint(pageWidth: shown.width, viewWidth: fitted.width,
                                                                 zoom: scrollView.zoomScale, screenScale: parent.displayScale)
            generation += 1
            let asked = generation
            let source = parent.source
            Task {
                let drawn = await Task.detached(priority: .userInitiated) {
                    DocumentPicture.region(of: source, rect: pageRect, pixelsPerPoint: pixelsPerPoint)
                }.value
                guard asked == self.generation, let drawn, let imageView = self.imageView else { return }
                let view = self.sharpened ?? UIImageView()
                view.image = UIImage(cgImage: drawn)
                view.contentMode = .scaleToFill
                view.frame = visible
                if view.superview == nil { imageView.addSubview(view) }
                self.sharpened = view
            }
        }

        @objc func doubleTapped(_ recognizer: UITapGestureRecognizer) {
            guard let scrollView = recognizer.view as? UIScrollView else { return }
            let animated = !parent.reduceMotion
            if scrollView.zoomScale > 1.01 {
                scrollView.setZoomScale(1, animated: animated)
                parent.onZoomChange(false)
                if !animated { clearSharpened() }
            } else {
                let point = recognizer.location(in: imageView)
                let scale: CGFloat = 2.5
                let size = CGSize(width: scrollView.bounds.width / scale, height: scrollView.bounds.height / scale)
                scrollView.zoom(to: CGRect(x: point.x - size.width / 2, y: point.y - size.height / 2, width: size.width, height: size.height), animated: animated)
                parent.onZoomChange(true)
                if !animated { sharpen(scrollView) }
            }
        }
    }
}
