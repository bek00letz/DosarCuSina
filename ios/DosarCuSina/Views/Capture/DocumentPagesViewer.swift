import SwiftUI
import UIKit

/// A document's pages full screen: pinch or double-tap to zoom, swipe between pages,
/// swipe down or "Gata" to close. Used by the capture review and the document page.
struct DocumentPagesViewer: View {
    let pages: [UIImage]

    @State private var selection: Int
    @State private var isZoomed = false
    @State private var dragOffset: CGFloat = 0
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// How far down a swipe has to travel to close the viewer.
    private let closeDistance: CGFloat = 120

    init(pages: [UIImage], startAt index: Int = 0) {
        self.pages = pages
        _selection = State(initialValue: min(max(index, 0), max(pages.count - 1, 0)))
    }

    var body: some View {
        NavigationStack {
            TabView(selection: $selection) {
                ForEach(pages.indices, id: \.self) { index in
                    ZoomablePage(image: pages[index], reduceMotion: reduceMotion) { zoomed in
                        if index == selection { isZoomed = zoomed }
                    }
                    .ignoresSafeArea(edges: .bottom)
                    .accessibilityElement()
                    .accessibilityLabel(Text("Pagina \(index + 1) din \(pages.count)", comment: "VoiceOver label of a page in the full-screen viewer."))
                    .accessibilityAddTraits(.isImage)
                    .tag(index)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: pages.count > 1 ? .always : .never))
            .offset(y: dragOffset)
            .simultaneousGesture(isZoomed ? nil : closeGesture)
            .background(Color.black.opacity(backgroundOpacity).ignoresSafeArea())
            .navigationTitle(pages.count > 1 ? Text("Pagina \(selection + 1) din \(pages.count)", comment: "Title of the full-screen page viewer.") : Text(verbatim: ""))
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.hidden, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button { dismiss() } label: { Text("Gata", comment: "Closes the full-screen page viewer.") }
                }
            }
            .onChange(of: selection) { isZoomed = false }
        }
        .preferredColorScheme(.dark)
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
                    dismiss()
                } else {
                    withAnimation(DS.Motion.animation(DS.Motion.standard, reduceMotion: reduceMotion)) { dragOffset = 0 }
                }
            }
    }
}

/// One page in a scroll view that zooms: pinch, or double-tap to zoom in where tapped and back out.
private struct ZoomablePage: UIViewRepresentable {
    let image: UIImage
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
    }

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    @MainActor
    final class Coordinator: NSObject, UIScrollViewDelegate {
        var parent: ZoomablePage
        weak var imageView: UIImageView?

        init(parent: ZoomablePage) {
            self.parent = parent
        }

        func viewForZooming(in scrollView: UIScrollView) -> UIView? { imageView }

        func scrollViewDidEndZooming(_ scrollView: UIScrollView, with view: UIView?, atScale scale: CGFloat) {
            parent.onZoomChange(scale > 1.01)
        }

        @objc func doubleTapped(_ recognizer: UITapGestureRecognizer) {
            guard let scrollView = recognizer.view as? UIScrollView else { return }
            let animated = !parent.reduceMotion
            if scrollView.zoomScale > 1.01 {
                scrollView.setZoomScale(1, animated: animated)
                parent.onZoomChange(false)
            } else {
                let point = recognizer.location(in: imageView)
                let scale: CGFloat = 2.5
                let size = CGSize(width: scrollView.bounds.width / scale, height: scrollView.bounds.height / scale)
                scrollView.zoom(to: CGRect(x: point.x - size.width / 2, y: point.y - size.height / 2, width: size.width, height: size.height), animated: animated)
                parent.onZoomChange(true)
            }
        }
    }
}

/// Loads a capture's pages from the store, for the viewer.
enum CapturePages {
    static func images(for documentID: UUID?) async -> [UIImage] {
        guard let documentID, let processed = await CaptureDocumentStore.shared().processed(id: documentID) else { return [] }
        return processed.pageData.compactMap(UIImage.init(data:))
    }
}
