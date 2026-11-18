import SwiftUI
import UIKit

/// Offers the screenshot editor a full page („Pagină întreagă”) of the screen's whole
/// scrolling content, for every screen of the app: the one path for full-page screenshots.
///
/// It is the scene's `UIScreenshotService` delegate, set where the app's window lands
/// (`FullPageScreenshotHost`, in `AppShell`). The lock window is in the same scene, so this
/// one delegate answers for it too. When a screenshot is taken it finds the frontmost screen
/// (the topmost sheet, else the selected tab's top screen) and that screen's scroll view, then
/// scrolls through it a screen at a time and draws each from the app's own window, so what the
/// PDF shows is what the screen showed: the same text size, appearance and masked values. A
/// still copy of the screen stays over the app while it scrolls, so nothing moves under the
/// person, and the content goes back to where it was.
///
/// Nothing is offered while a lock covers the app (`LockCover`) or while a locked state shows
/// (`withholdsFullPageScreenshot`): then only the plain screenshot exists. The PDF is made in
/// memory and handed to the system; no file is written.
@MainActor
final class FullPageScreenshots: NSObject, UIScreenshotServiceDelegate {
    /// What covers the app right now (`LockCover.decide`), set by the shell on every update.
    var cover: LockCover?
    private weak var window: UIWindow?
    private var isCapturing = false

    /// Answers for the scene `window` is in.
    func attach(to window: UIWindow) {
        guard window !== self.window || window.windowScene?.screenshotService?.delegate !== self else { return }
        self.window = window
        window.windowScene?.screenshotService?.delegate = self
    }

    func screenshotService(
        _ screenshotService: UIScreenshotService,
        generatePDFRepresentationWithCompletion completionHandler: @escaping (Data?, Int, CGRect) -> Void
    ) {
        guard !isCapturing, let window, let capture = FullPageCapture(in: window, cover: cover) else {
            completionHandler(nil, 0, .zero)
            return
        }
        isCapturing = true
        Task {
            let page = await capture.run(stillOffered: { [weak self] in self.map { $0.cover == nil } ?? false })
            isCapturing = false
            completionHandler(page?.data, page?.index ?? 0, page?.rect ?? .zero)
        }
    }
}

/// Sets `FullPageScreenshots` as the delegate of the scene the shell's window is in.
struct FullPageScreenshotHost: UIViewRepresentable {
    let cover: LockCover?

    func makeCoordinator() -> FullPageScreenshots { FullPageScreenshots() }

    func makeUIView(context: Context) -> LockWindowHost.SceneProbe {
        let probe = LockWindowHost.SceneProbe()
        probe.onWindow = { [weak screenshots = context.coordinator] window in
            screenshots?.attach(to: window)
        }
        return probe
    }

    func updateUIView(_ probe: LockWindowHost.SceneProbe, context: Context) {
        context.coordinator.cover = cover
        if let window = probe.window { context.coordinator.attach(to: window) }
    }
}

// MARK: - What is on the screen

/// Finds what a full page is made of, in the app's window.
@MainActor
enum FullPageScreenshotTarget {
    /// The screen in front: the topmost sheet or cover still up, else the window's root. Nil
    /// while an alert is in front, which is not a page.
    static func frontmost(from root: UIViewController?) -> UIViewController? {
        var top = root
        while let next = top?.presentedViewController, !next.isBeingDismissed { top = next }
        return top is UIAlertController ? nil : top
    }

    /// The scroll view of the screen `container` holds: the largest one on it that scrolls up
    /// and down, covering at least `FullPageScreenshot.leastShareOfScreen` of it. Never a text
    /// view (it lays out only the lines on the screen), a paged or zoomed one (a document's
    /// pictures), or one that is hidden or turned off.
    static func scrollView(in container: UIView) -> UIScrollView? {
        let screenArea = container.bounds.width * container.bounds.height
        guard screenArea > 0 else { return nil }
        var best: (view: UIScrollView, area: CGFloat)?
        visitShown(container) { view in
            guard let scroll = view as? UIScrollView, isPage(scroll) else { return }
            let shown = scroll.convert(scroll.bounds, to: container).intersection(container.bounds)
            guard !shown.isNull else { return }
            let area = shown.width * shown.height
            // Strictly larger: on a tie the outer one, met first, stays.
            if area > (best?.area ?? 0) { best = (scroll, area) }
        }
        guard let best, best.area >= screenArea * FullPageScreenshot.leastShareOfScreen else { return nil }
        return best.view
    }

    /// Whether anything shown under `root` withholds a full page (`withholdsFullPageScreenshot`).
    static func showsLockedState(in root: UIView) -> Bool {
        var found = false
        visitShown(root) { view in
            if view is FullPageWithheldMark { found = true }
        }
        return found
    }

    /// What a scroll view shows right now.
    static func viewport(of scroll: UIScrollView) -> FullPageScreenshot.Viewport {
        FullPageScreenshot.Viewport(
            offset: scroll.contentOffset.y,
            height: scroll.bounds.height,
            insetTop: scroll.adjustedContentInset.top,
            insetBottom: scroll.adjustedContentInset.bottom,
            contentHeight: scroll.contentSize.height
        )
    }

    private static func isPage(_ scroll: UIScrollView) -> Bool {
        !(scroll is UITextView) && scroll.isScrollEnabled && !scroll.isPagingEnabled
            && abs(scroll.zoomScale - 1) < 0.01
    }

    /// Visits `view` and every view under it that shows (not hidden, not see-through), front to back.
    private static func visitShown(_ view: UIView, _ visit: (UIView) -> Void) {
        guard !view.isHidden, view.alpha > 0.01 else { return }
        visit(view)
        for subview in view.subviews { visitShown(subview, visit) }
    }
}

// MARK: - The capture

/// One full-page capture of one scroll view, planned when the screenshot is taken.
@MainActor
struct FullPageCapture {
    /// A full page, as the screenshot service takes it.
    struct Page {
        let data: Data
        let index: Int
        let rect: CGRect
    }

    let window: UIWindow
    let scroll: UIScrollView
    /// What the person saw when the screenshot was taken.
    let visible: FullPageScreenshot.Span
    /// The stretch planned: the whole content, or `mostScreens` of it around what was seen.
    let planned: FullPageScreenshot.Span

    /// The capture of the frontmost screen in `window`, or nil when no full page is offered.
    init?(in window: UIWindow, cover: LockCover?) {
        let showsLockedState = FullPageScreenshotTarget.showsLockedState(in: window)
        let scroll = FullPageScreenshotTarget.frontmost(from: window.rootViewController)
            .flatMap { $0.viewIfLoaded }
            .flatMap(FullPageScreenshotTarget.scrollView(in:))
        let viewport = scroll.map(FullPageScreenshotTarget.viewport(of:))
        guard FullPageScreenshot.offers(cover: cover, showsLockedState: showsLockedState, viewport: viewport),
              let scroll, let viewport, let visible = viewport.visible else { return nil }
        self.window = window
        self.scroll = scroll
        self.visible = visible
        planned = FullPageScreenshot.captured(contentHeight: viewport.contentHeight, visible: visible,
                                              screenHeight: viewport.screenHeight)
    }

    /// Scrolls through the content a screen at a time, draws each, and puts the scroll view
    /// back where it was. Nil when it can't be finished, or when `stillOffered` stops saying yes
    /// (the app was covered meanwhile).
    func run(stillOffered: () -> Bool) async -> Page? {
        let scale = max(1, window.traitCollection.displayScale)
        let width = scroll.bounds.width
        guard let document = FullPageDocument(width: width, top: planned.top) else { return nil }
        let original = scroll.contentOffset
        let still = StillScreen(over: window)
        let tapsWereOn = window.isUserInteractionEnabled
        window.isUserInteractionEnabled = false

        var covered = planned.top
        var finished = true
        while true {
            // Lists measure their rows as they come, so the end is read again at every screen.
            let end = min(planned.bottom, scroll.contentSize.height)
            guard covered < end - 0.5 else { break }
            guard stillOffered(), let slice = await show(from: covered, until: end, scale: scale),
                  let picture = picture(of: slice, scale: scale) else {
                finished = false
                break
            }
            document.add(picture, covering: slice)
            covered = slice.bottom
        }

        scroll.setContentOffset(original, animated: false)
        scroll.layoutIfNeeded()
        // The content back where it was is drawn before the still copy goes, so nothing flashes.
        _ = await NextFrame.drawn()
        still.remove()
        window.isUserInteractionEnabled = tapsWereOn
        guard finished, stillOffered() else { return nil }
        return document.finish(visible: visible)
    }

    /// Scrolls so the content from `y` is under the top bar, and returns the stretch from `y`
    /// that shows between the bars, at most to `end`. Nil when `y` can't be brought on the
    /// screen (the content got shorter, the app left the screen).
    private func show(from y: CGFloat, until end: CGFloat, scale: CGFloat) async -> FullPageScreenshot.Span? {
        // A second try for a bar that changed height as the content moved (a large title folding).
        for _ in 0..<2 {
            let target = FullPageScreenshotTarget.viewport(of: scroll).offset(showingFrom: y)
            if abs(scroll.contentOffset.y - target) > 0.25 {
                scroll.setContentOffset(CGPoint(x: scroll.contentOffset.x, y: target), animated: false)
            }
            scroll.layoutIfNeeded()
            window.layoutIfNeeded()
            // The rows that came on the screen are laid out and drawn on the next frame.
            guard await NextFrame.drawn() else { return nil }
            guard let shown = FullPageScreenshotTarget.viewport(of: scroll).visible else { return nil }
            guard shown.top <= y + 0.5 else { continue }
            let bottom = shown.bottom >= end ? end : FullPageScreenshot.onPixels(shown.bottom, scale: scale)
            return bottom > y + 0.5 ? FullPageScreenshot.Span(top: y, bottom: bottom) : nil
        }
        return nil
    }

    /// The app's window drawn where `slice` of the content is on the screen, at the screen's
    /// sharpness, on the one bitmap canvas (`ImageScaling.canvas`).
    private func picture(of slice: FullPageScreenshot.Span, scale: CGFloat) -> CGImage? {
        let region = scroll.convert(CGRect(x: scroll.bounds.minX, y: slice.top, width: scroll.bounds.width, height: slice.height),
                                    to: window)
        let width = Int((region.width * scale).rounded())
        let height = Int((region.height * scale).rounded())
        guard let canvas = ImageScaling.canvas(width: width, height: height, onWhite: false) else { return nil }
        // What nothing draws on is the screen's own background, in this appearance.
        canvas.setFillColor(UIColor.systemBackground.resolvedColor(with: scroll.traitCollection).cgColor)
        canvas.fill(CGRect(x: 0, y: 0, width: width, height: height))
        // UIKit draws from the top left, in points.
        canvas.translateBy(x: 0, y: CGFloat(height))
        canvas.scaleBy(x: scale, y: -scale)
        canvas.translateBy(x: -region.minX, y: -region.minY)
        UIGraphicsPushContext(canvas)
        defer { UIGraphicsPopContext() }
        guard window.drawHierarchy(in: window.bounds, afterScreenUpdates: true) else { return nil }
        return canvas.makeImage()
    }
}

/// The full page's PDF, made in memory: each screen's picture goes on a page of its own as it
/// is drawn, and `finish` lays them out on the final pages once the content's height is known.
final class FullPageDocument {
    let width: CGFloat
    /// Where in the content the first picture starts.
    let top: CGFloat
    private let slicesData = NSMutableData()
    private let slices: CGContext
    private(set) var spans: [FullPageScreenshot.Span] = []

    init?(width: CGFloat, top: CGFloat) {
        guard width > 0, let consumer = CGDataConsumer(data: slicesData as CFMutableData),
              let slices = CGContext(consumer: consumer, mediaBox: nil, nil) else { return nil }
        self.width = width
        self.top = top
        self.slices = slices
    }

    /// Adds the picture of `span`, which starts where the one before it ended.
    func add(_ picture: CGImage, covering span: FullPageScreenshot.Span) {
        let box = CGRect(x: 0, y: 0, width: width, height: span.height)
        slices.beginPDFPage(Self.pageInfo(box))
        slices.draw(picture, in: box)
        slices.endPDFPage()
        spans.append(span)
    }

    /// The PDF, with the page and the place the editor opens at for `visible`. Nil with nothing added.
    func finish(visible: FullPageScreenshot.Span) -> FullPageCapture.Page? {
        slices.closePDF()
        guard let last = spans.last, let provider = CGDataProvider(data: slicesData as CFData),
              let drawn = CGPDFDocument(provider) else { return nil }
        let pages = FullPageScreenshot.pages(of: FullPageScreenshot.Span(top: top, bottom: last.bottom))
        let data = NSMutableData()
        guard let consumer = CGDataConsumer(data: data as CFMutableData),
              let pdf = CGContext(consumer: consumer, mediaBox: nil, nil) else { return nil }
        for page in pages {
            pdf.beginPDFPage(Self.pageInfo(CGRect(x: 0, y: 0, width: width, height: page.height)))
            for (index, span) in spans.enumerated() where span.overlaps(page) {
                guard let slice = drawn.page(at: index + 1) else { continue }
                pdf.saveGState()
                // PDF pages count from the bottom up; the page's box cuts off what falls outside it.
                pdf.translateBy(x: 0, y: page.bottom - span.bottom)
                pdf.drawPDFPage(slice)
                pdf.restoreGState()
            }
            pdf.endPDFPage()
        }
        pdf.closePDF()
        let current = FullPageScreenshot.current(visible: visible, on: pages, width: width)
        return FullPageCapture.Page(data: data as Data, index: current.index, rect: current.rect)
    }

    private static func pageInfo(_ box: CGRect) -> CFDictionary {
        var box = box
        let boxData = Data(bytes: &box, count: MemoryLayout<CGRect>.size)
        return [kCGPDFContextMediaBox as String: boxData] as CFDictionary
    }
}

// MARK: - Waiting for the screen

/// A still copy of the window's screen, in a window of its own just above it, kept while the
/// content scrolls underneath so the person sees nothing move. Under the lock window.
@MainActor
private struct StillScreen {
    private let cover: UIWindow?

    init(over window: UIWindow) {
        guard let scene = window.windowScene, let still = window.snapshotView(afterScreenUpdates: false) else {
            cover = nil
            return
        }
        let cover = UIWindow(windowScene: scene)
        cover.frame = window.frame
        cover.windowLevel = window.windowLevel + 1
        let holder = UIViewController()
        holder.view = still
        cover.rootViewController = holder
        cover.accessibilityElementsHidden = true
        cover.isHidden = false
        self.cover = cover
    }

    func remove() {
        cover?.isHidden = true
        cover?.rootViewController = nil
    }
}

/// Waits for the screen's next frame, the moment what was laid out has been drawn.
@MainActor
private final class NextFrame: NSObject {
    private var continuation: CheckedContinuation<Bool, Never>?
    private var link: CADisplayLink?
    private var leaving: NSObjectProtocol?

    /// True once the next frame is drawn; false when the app leaves the screen first, where
    /// no frame comes.
    static func drawn() async -> Bool {
        let waiter = NextFrame()
        return await withCheckedContinuation { continuation in
            waiter.start(continuation)
        }
    }

    private func start(_ continuation: CheckedContinuation<Bool, Never>) {
        self.continuation = continuation
        guard UIApplication.shared.applicationState != .background else {
            finish(drawn: false)
            return
        }
        leaving = NotificationCenter.default.addObserver(
            forName: UIScene.didEnterBackgroundNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.finish(drawn: false) }
        }
        let link = CADisplayLink(target: self, selector: #selector(frame))
        link.add(to: .main, forMode: .common)
        self.link = link
    }

    @objc private func frame() { finish(drawn: true) }

    private func finish(drawn: Bool) {
        link?.invalidate()
        link = nil
        if let leaving { NotificationCenter.default.removeObserver(leaving) }
        leaving = nil
        continuation?.resume(returning: drawn)
        continuation = nil
    }
}
