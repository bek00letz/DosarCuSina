import CoreGraphics
import SwiftUI
import Testing
import UIKit
@testable import DosarCuSina

/// The screenshot editor's full page („Pagină întreagă”): when one is offered, which scroll
/// view it is made of, which part of the content it holds and how the PDF's pages are laid
/// out. The editor itself shows only on a device or the simulator.
@MainActor
@Suite("Full-page screenshots", .serialized)
struct FullPageScreenshotTests {
    typealias Span = FullPageScreenshot.Span
    typealias Viewport = FullPageScreenshot.Viewport

    /// A phone's list: 844 pt tall, 100 under the top bars and 80 above the tab bar.
    private func phone(offset: CGFloat = -100, content: CGFloat = 3_000) -> Viewport {
        Viewport(offset: offset, height: 844, insetTop: 100, insetBottom: 80, contentHeight: content)
    }

    // MARK: When a full page is offered

    @Test("A long screen offers a full page")
    func longScreenOffers() {
        #expect(FullPageScreenshot.offers(cover: nil, showsLockedState: false, viewport: phone()))
    }

    @Test("Nothing is offered while the app lock or the app-switcher cover is up", arguments: [LockCover.lock, .privacy])
    func nothingWhileCovered(cover: LockCover) {
        #expect(!FullPageScreenshot.offers(cover: cover, showsLockedState: false, viewport: phone()))
    }

    @Test("Nothing is offered while a locked state shows")
    func nothingOverALockedState() {
        #expect(!FullPageScreenshot.offers(cover: nil, showsLockedState: true, viewport: phone()))
    }

    @Test("Nothing is offered without a scroll view, or for content that fits on the screen")
    func nothingWithoutMoreToShow() {
        #expect(!FullPageScreenshot.offers(cover: nil, showsLockedState: false, viewport: nil))
        #expect(!FullPageScreenshot.offers(cover: nil, showsLockedState: false, viewport: phone(content: 600)))
    }

    // MARK: What the screen shows

    @Test("What shows is the content between the bars")
    func visibleIsBetweenTheBars() {
        #expect(phone().visible == Span(top: 0, bottom: 664))
        #expect(phone(offset: 900).visible == Span(top: 1_000, bottom: 1_664))
        #expect(phone().screenHeight == 664)
    }

    @Test("Scrolling to a point puts it under the top bar, as far as the content goes")
    func offsetShowingAPoint() {
        let viewport = phone()
        #expect(viewport.offset(showingFrom: 0) == -100)
        #expect(viewport.offset(showingFrom: 1_000) == 900)
        // The last screen: the content's end sits on the tab bar.
        // Worked out in points through the bars' insets: equal to the point, not to the bit.
        #expect(abs(viewport.offset(showingFrom: 2_900) - (3_000 + 80 - 844)) < 0.001)
    }

    // MARK: What a full page holds

    @Test("Content within the most screens is held whole")
    func wholeContent() {
        let span = FullPageScreenshot.captured(contentHeight: 3_000, visible: Span(top: 900, bottom: 1_564), screenHeight: 664)
        #expect(span == Span(top: 0, bottom: 3_000))
    }

    @Test("A very long list stops at the most screens, from the top while the visible part is among them")
    func longListFromTheTop() {
        let most = 664 * FullPageScreenshot.mostScreens
        let span = FullPageScreenshot.captured(contentHeight: most * 3, visible: Span(top: 1_000, bottom: 1_664), screenHeight: 664)
        #expect(span == Span(top: 0, bottom: most))
    }

    @Test("Further down a very long list, the full page ends with the visible part")
    func longListEndsWithWhatShows() {
        let most = 664 * FullPageScreenshot.mostScreens
        let visible = Span(top: most * 2, bottom: most * 2 + 664)
        let span = FullPageScreenshot.captured(contentHeight: most * 3, visible: visible, screenHeight: 664)
        #expect(span == Span(top: visible.bottom - most, bottom: visible.bottom))
        // At the very end it ends with the content.
        let atEnd = Span(top: most * 3 - 664, bottom: most * 3)
        #expect(FullPageScreenshot.captured(contentHeight: most * 3, visible: atEnd, screenHeight: 664)
            == Span(top: most * 2, bottom: most * 3))
    }

    // MARK: The PDF's pages

    @Test("Pages are at most the largest page side, the last one shorter")
    func pagesAreCut() {
        let side = FullPageScreenshot.largestPageSide
        #expect(FullPageScreenshot.pages(of: Span(top: 0, bottom: 3_000)) == [Span(top: 0, bottom: 3_000)])
        #expect(FullPageScreenshot.pages(of: Span(top: 100, bottom: 100 + side + 500))
            == [Span(top: 100, bottom: 100 + side), Span(top: 100 + side, bottom: 100 + side + 500)])
        #expect(FullPageScreenshot.pages(of: Span(top: 0, bottom: 0)).isEmpty)
    }

    @Test("The editor opens at the visible part, in PDF coordinates from the page's bottom")
    func currentPageAndRect() {
        let page = [Span(top: 0, bottom: 1_000)]
        let current = FullPageScreenshot.current(visible: Span(top: 100, bottom: 700), on: page, width: 390)
        #expect(current.index == 0)
        #expect(current.rect == CGRect(x: 0, y: 300, width: 390, height: 600))

        let side = FullPageScreenshot.largestPageSide
        let pages = [Span(top: 0, bottom: side), Span(top: side, bottom: side + 2_000)]
        let second = FullPageScreenshot.current(visible: Span(top: side + 100, bottom: side + 700), on: pages, width: 390)
        #expect(second.index == 1)
        #expect(second.rect == CGRect(x: 0, y: 1_300, width: 390, height: 600))

        // Across two pages: the page with its top, the part on it.
        let across = FullPageScreenshot.current(visible: Span(top: side - 200, bottom: side + 400), on: pages, width: 390)
        #expect(across.index == 0)
        #expect(across.rect == CGRect(x: 0, y: 0, width: 390, height: 200))

        let nowhere = FullPageScreenshot.current(visible: Span(top: 0, bottom: 10), on: [], width: 390)
        #expect(nowhere.index == 0)
        #expect(nowhere.rect == .zero)
    }

    @Test("A point is brought down onto the screen's pixels")
    func pixelGrid() {
        #expect(abs(FullPageScreenshot.onPixels(100.5, scale: 3) - 301.0 / 3) < 0.000_1)
        #expect(FullPageScreenshot.onPixels(100.5, scale: 2) == 100.5)
    }

    // MARK: Which scroll view

    private func screen() -> UIView { UIView(frame: CGRect(x: 0, y: 0, width: 390, height: 844)) }

    private func scroll(_ frame: CGRect, content: CGFloat = 3_000) -> UIScrollView {
        let scroll = UIScrollView(frame: frame)
        scroll.contentSize = CGSize(width: frame.width, height: content)
        return scroll
    }

    @Test("The page's scroll view is the largest one on the screen, the outer one on a tie")
    func largestScrollView() {
        let container = screen()
        let page = scroll(container.bounds)
        let row = scroll(CGRect(x: 0, y: 100, width: 390, height: 60))
        let inner = scroll(page.bounds)
        container.addSubview(row)
        container.addSubview(page)
        page.addSubview(inner)
        #expect(FullPageScreenshotTarget.scrollView(in: container) === page)
    }

    @Test("A screen with no scroll view, or only a small one, has no page")
    func noPageWithoutAScreenSizedScrollView() {
        let empty = screen()
        #expect(FullPageScreenshotTarget.scrollView(in: empty) == nil)
        let small = screen()
        small.addSubview(scroll(CGRect(x: 0, y: 0, width: 390, height: 200)))
        #expect(FullPageScreenshotTarget.scrollView(in: small) == nil)
    }

    @Test("Hidden, text, paged and zoomed scroll views are never the page")
    func notThePage() {
        let hidden = screen()
        let hiddenScroll = scroll(hidden.bounds)
        hiddenScroll.isHidden = true
        hidden.addSubview(hiddenScroll)

        let text = screen()
        text.addSubview(UITextView(frame: text.bounds))

        let paged = screen()
        let pagedScroll = scroll(paged.bounds)
        pagedScroll.isPagingEnabled = true
        paged.addSubview(pagedScroll)

        let zoomed = screen()
        let zoomedScroll = scroll(zoomed.bounds)
        zoomedScroll.maximumZoomScale = 4
        let picture = UIView(frame: zoomed.bounds)
        zoomedScroll.addSubview(picture)
        let delegate = ZoomDelegate(picture)
        zoomedScroll.delegate = delegate
        zoomedScroll.setZoomScale(2, animated: false)
        zoomed.addSubview(zoomedScroll)

        for container in [hidden, text, paged, zoomed] {
            #expect(FullPageScreenshotTarget.scrollView(in: container) == nil)
        }
        withExtendedLifetime(delegate) {}
    }

    private final class ZoomDelegate: NSObject, UIScrollViewDelegate {
        let picture: UIView
        init(_ picture: UIView) { self.picture = picture }
        func viewForZooming(in scrollView: UIScrollView) -> UIView? { picture }
    }

    @Test("The screen in front is the window's root without a sheet")
    func frontmostWithoutASheet() {
        let root = UIViewController()
        #expect(FullPageScreenshotTarget.frontmost(from: root) === root)
        #expect(FullPageScreenshotTarget.frontmost(from: nil) == nil)
    }

    // MARK: Locked states

    @Test("A shown mark withholds a full page; a hidden one doesn't")
    func markWithholds() {
        let container = screen()
        let mark = FullPageWithheldMark()
        container.addSubview(mark)
        #expect(FullPageScreenshotTarget.showsLockedState(in: container))
        mark.isHidden = true
        #expect(!FullPageScreenshotTarget.showsLockedState(in: container))
    }

    @Test("A locked state withholds a full page; an open card doesn't")
    func lockedStateCarriesTheMark() throws {
        let window = try makeWindow()
        let locked = UIHostingController(rootView: DSLockedState(
            title: Text(verbatim: "„Mașina” e protejat"), systemImage: "faceid",
            message: Text(verbatim: "Deschide cu Face ID."), unlockTitle: Text(verbatim: "Deblochează"), unlock: {}
        ))
        window.rootViewController = locked
        window.isHidden = false
        locked.view.layoutIfNeeded()
        #expect(FullPageScreenshotTarget.showsLockedState(in: window))

        let open = UIHostingController(rootView: DSCard { Text(verbatim: "VW Golf 2018") })
        window.rootViewController = open
        open.view.layoutIfNeeded()
        #expect(!FullPageScreenshotTarget.showsLockedState(in: window))
        window.isHidden = true
    }

    // MARK: The PDF

    private func picture(height: Int) throws -> CGImage {
        let canvas = try #require(ImageScaling.canvas(width: 39, height: height, onWhite: true))
        return try #require(canvas.makeImage())
    }

    private func pageBoxes(_ data: Data) throws -> [CGRect] {
        let provider = try #require(CGDataProvider(data: data as CFData))
        let document = try #require(CGPDFDocument(provider))
        return (0..<document.numberOfPages).compactMap { document.page(at: $0 + 1)?.getBoxRect(.mediaBox) }
    }

    @Test("The screens' pictures make one page as tall as the content")
    func onePage() throws {
        let document = try #require(FullPageDocument(width: 390, top: 0))
        document.add(try picture(height: 80), covering: Span(top: 0, bottom: 800))
        document.add(try picture(height: 80), covering: Span(top: 800, bottom: 1_600))
        document.add(try picture(height: 40), covering: Span(top: 1_600, bottom: 2_000))
        let page = try #require(document.finish(visible: Span(top: 900, bottom: 1_500)))
        #expect(try pageBoxes(page.data) == [CGRect(x: 0, y: 0, width: 390, height: 2_000)])
        #expect(page.index == 0)
        #expect(page.rect == CGRect(x: 0, y: 500, width: 390, height: 600))
    }

    @Test("Content taller than the largest page goes on to the next page")
    func severalPages() throws {
        let side = FullPageScreenshot.largestPageSide
        let document = try #require(FullPageDocument(width: 390, top: 0))
        var top: CGFloat = 0
        while top < 20_000 {
            let bottom = min(20_000, top + 700)
            document.add(try picture(height: 70), covering: Span(top: top, bottom: bottom))
            top = bottom
        }
        let page = try #require(document.finish(visible: Span(top: 15_000, bottom: 15_600)))
        #expect(try pageBoxes(page.data) == [
            CGRect(x: 0, y: 0, width: 390, height: side),
            CGRect(x: 0, y: 0, width: 390, height: 20_000 - side),
        ])
        #expect(page.index == 1)
        #expect(page.rect == CGRect(x: 0, y: 20_000 - 15_600, width: 390, height: 600))
    }

    @Test("Nothing drawn, no PDF")
    func nothingDrawn() throws {
        let document = try #require(FullPageDocument(width: 390, top: 0))
        #expect(document.finish(visible: Span(top: 0, bottom: 600)) == nil)
    }

    // MARK: A capture in a window

    private func makeWindow() throws -> UIWindow {
        let scene = try #require(
            UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first,
            "The tests run inside the app"
        )
        return UIWindow(windowScene: scene)
    }

    /// A window whose screen is one long scroll view, scrolled a little.
    private func longScreen() throws -> (UIWindow, UIScrollView) {
        let window = try makeWindow()
        let root = UIViewController()
        let scroll = UIScrollView(frame: window.bounds)
        scroll.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        scroll.contentSize = CGSize(width: window.bounds.width, height: 3_000)
        for index in 0..<30 {
            let row = UIView(frame: CGRect(x: 0, y: CGFloat(index) * 100, width: window.bounds.width, height: 100))
            row.backgroundColor = index.isMultiple(of: 2) ? .systemGray5 : .systemBackground
            scroll.addSubview(row)
        }
        root.view.addSubview(scroll)
        window.rootViewController = root
        window.isHidden = false
        root.view.layoutIfNeeded()
        scroll.setContentOffset(CGPoint(x: 0, y: 400), animated: false)
        return (window, scroll)
    }

    @Test("A capture holds the whole content and puts the list back where it was", .timeLimit(.minutes(1)))
    func captureInAWindow() async throws {
        let (window, scroll) = try longScreen()
        defer { window.isHidden = true }
        let before = scroll.contentOffset
        let capture = try #require(FullPageCapture(in: window, cover: nil))
        #expect(capture.planned == Span(top: 0, bottom: 3_000))
        let page = try #require(await capture.run(stillOffered: { true }))
        #expect(try pageBoxes(page.data) == [CGRect(x: 0, y: 0, width: window.bounds.width, height: 3_000)])
        #expect(page.index == 0)
        #expect(page.rect.height == capture.visible.height)
        #expect(scroll.contentOffset == before)
        #expect(window.isUserInteractionEnabled)
    }

    @Test("A capture covered on its way gives nothing and still puts the list back", .timeLimit(.minutes(1)))
    func captureStopsWhenCovered() async throws {
        let (window, scroll) = try longScreen()
        defer { window.isHidden = true }
        let before = scroll.contentOffset
        let capture = try #require(FullPageCapture(in: window, cover: nil))
        var asked = 0
        let page = await capture.run(stillOffered: {
            asked += 1
            return asked < 2
        })
        #expect(page == nil)
        #expect(scroll.contentOffset == before)
    }

    @Test("No capture while covered or over a locked state")
    func noCaptureWhileLocked() throws {
        let (window, _) = try longScreen()
        defer { window.isHidden = true }
        #expect(FullPageCapture(in: window, cover: .lock) == nil)
        window.rootViewController?.view.addSubview(FullPageWithheldMark())
        #expect(FullPageCapture(in: window, cover: nil) == nil)
    }
}
