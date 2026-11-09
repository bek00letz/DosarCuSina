import SwiftUI

/// A page as it is shown (cut out, turned), drawn away from the main thread and faded in.
/// Its space is kept from the start, from the page's shape, so nothing moves when it arrives.
struct DocumentPageImage: View {
    let source: DocumentPageSource
    /// The longest side to draw, in pixels: about the screen's width for a page in a list,
    /// a few hundred for a thumbnail.
    var maxLongEdge: Int
    /// `.fit` shows the whole page at its shape; `.fill` fills a frame the caller sets (a thumbnail).
    var contentMode: ContentMode

    private let aspect: CGFloat?
    @State private var image: UIImage?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(source: DocumentPageSource, maxLongEdge: Int = 1600, contentMode: ContentMode = .fit) {
        self.source = source
        self.maxLongEdge = maxLongEdge
        self.contentMode = contentMode
        let size = DocumentPicture.shownSize(of: source)
        aspect = size.flatMap { $0.height > 0 ? $0.width / $0.height : nil }
    }

    var body: some View {
        Color.clear
            .aspectRatio(contentMode == .fit ? aspect : nil, contentMode: .fit)
            .overlay {
                if let image {
                    Image(uiImage: image)
                        .resizable()
                        .aspectRatio(contentMode: contentMode)
                        .transition(.opacity)
                }
            }
            .clipped()
            .animation(DS.Motion.animation(DS.Motion.standard, reduceMotion: reduceMotion), value: image == nil)
            .task(id: source.drawingKey) { await draw() }
    }

    private func draw() async {
        let source = source
        let maxLongEdge = maxLongEdge
        let drawn = await Task.detached(priority: .userInitiated) {
            DocumentPicture.image(of: source, maxLongEdge: maxLongEdge)
        }.value
        guard !Task.isCancelled else { return }
        image = drawn.map { UIImage(cgImage: $0) }
    }
}
