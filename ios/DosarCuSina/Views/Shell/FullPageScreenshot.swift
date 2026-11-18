import CoreGraphics
import SwiftUI
import UIKit

/// The plan of a full-page screenshot (the screenshot editor's „Pagină întreagă”): whether one
/// is offered, which part of the screen's scrolling content it holds, how that is cut into PDF
/// pages and where the part the person was looking at sits on them. Pure geometry, in points,
/// in the scroll view's content coordinates (0 is the top of the content). The capture that
/// follows it is `FullPageScreenshots`.
enum FullPageScreenshot {
    /// The longest a PDF page may be: the PDF reference's limit on a page's side (200 inches),
    /// the largest every reader opens. Longer content goes on to the next page.
    static let largestPageSide: CGFloat = 14_400

    /// How many screens of content a full page holds at most. Each one is scrolled to, laid out
    /// and drawn while the screenshot editor waits, and kept in the PDF as a picture at the
    /// screen's sharpness; a very long list stops here instead of keeping the person waiting
    /// and the file growing. The part they were looking at is always inside.
    static let mostScreens: CGFloat = 30

    /// The least of the screen (or of the sheet) the scroll view must cover to be the page's
    /// own: a short list inside a page that doesn't scroll is not the page.
    static let leastShareOfScreen: CGFloat = 0.5

    /// A stretch of content, from `top` to `bottom`.
    struct Span: Equatable {
        var top: CGFloat
        var bottom: CGFloat

        var height: CGFloat { bottom - top }

        func overlaps(_ other: Span) -> Bool { top < other.bottom && other.top < bottom }
    }

    /// What a scroll view shows right now.
    struct Viewport: Equatable {
        /// How far it is scrolled (`contentOffset.y`).
        var offset: CGFloat
        /// Its height on the screen (`bounds.height`), the part under the bars included.
        var height: CGFloat
        /// The part of it under the bars at the top and the bottom (`adjustedContentInset`).
        var insetTop: CGFloat
        var insetBottom: CGFloat
        /// How tall the content is (`contentSize.height`).
        var contentHeight: CGFloat

        /// The height between the bars: one screen of content.
        var screenHeight: CGFloat { max(0, height - insetTop - insetBottom) }

        /// Whether the content holds more than one screen shows; otherwise the screenshot
        /// itself is the whole page.
        var hasMoreThanShown: Bool { contentHeight > screenHeight + 1 }

        /// The content the person sees between the bars, or nil when none shows.
        var visible: Span? {
            let top = max(0, offset + insetTop)
            let bottom = min(contentHeight, offset + height - insetBottom)
            return bottom > top ? Span(top: top, bottom: bottom) : nil
        }

        /// The offset that brings `y` just under the top bar, as far as the content scrolls.
        func offset(showingFrom y: CGFloat) -> CGFloat {
            let least = -insetTop
            let most = max(least, contentHeight + insetBottom - height)
            return min(max(y - insetTop, least), most)
        }
    }

    /// Whether a full page is offered at all: never while something is locked right now (the
    /// app lock is closed, or the screen shows a locked state), and only for a scroll view with
    /// more than one screen of content.
    static func offers(cover: LockCover?, showsLockedState: Bool, viewport: Viewport?) -> Bool {
        guard !withholds(cover), !showsLockedState, let viewport else { return false }
        return viewport.hasMoreThanShown && viewport.visible != nil
    }

    /// Whether a cover withholds a full page: only the app lock, which hides a session that is
    /// closed. The app-switcher cover (`LockCover.privacy`) is up whenever the app isn't
    /// active after a Face ID in the session, the screenshot editor's moment included; it hides
    /// the app from the app switcher's picture and says nothing about what the screen in front
    /// shows, which the person just saw unlocked. A section that is locked again draws its locked
    /// state, which withholds the page by itself.
    static func withholds(_ cover: LockCover?) -> Bool {
        cover == .lock
    }

    /// The stretch a full page holds: the whole content when it fits in `mostScreens`, else
    /// that many screens from the top when the visible part lies among them, else that many
    /// ending with the visible part.
    static func captured(contentHeight: CGFloat, visible: Span, screenHeight: CGFloat) -> Span {
        let most = max(screenHeight, 1) * mostScreens
        guard contentHeight > most else { return Span(top: 0, bottom: max(0, contentHeight)) }
        guard visible.bottom > most else { return Span(top: 0, bottom: most) }
        let top = min(max(0, visible.bottom - most), contentHeight - most)
        return Span(top: top, bottom: top + most)
    }

    /// `span` cut into PDF pages, each at most `largestPageSide` tall, the last one shorter.
    static func pages(of span: Span) -> [Span] {
        guard span.height > 0 else { return [] }
        var pages: [Span] = []
        var top = span.top
        while top < span.bottom {
            let bottom = min(span.bottom, top + largestPageSide)
            pages.append(Span(top: top, bottom: bottom))
            top = bottom
        }
        return pages
    }

    /// Where the editor opens: the page holding the top of the visible part, and the visible
    /// part on that page in PDF coordinates (the origin at the page's bottom left). Page 0 and
    /// `.zero` (the system's "no visible area") when the visible part isn't on any page.
    static func current(visible: Span, on pages: [Span], width: CGFloat) -> (index: Int, rect: CGRect) {
        guard let index = pages.firstIndex(where: { $0.overlaps(visible) }) else { return (0, .zero) }
        let page = pages[index]
        let top = max(visible.top, page.top)
        let bottom = min(visible.bottom, page.bottom)
        let rect = CGRect(x: 0, y: page.bottom - bottom, width: width, height: bottom - top)
        return (index, rect)
    }

    /// `y` brought down onto the screen's pixel grid, so two pictures meet without a seam.
    static func onPixels(_ y: CGFloat, scale: CGFloat) -> CGFloat {
        guard scale > 0 else { return y }
        return (y * scale).rounded(.down) / scale
    }
}

// MARK: - Screens that withhold a full page

extension View {
    /// Marks a view whose screen offers no full-page screenshot while it shows, such as a
    /// locked state (`DSLockedState`): only the plain screenshot of what is on the screen exists.
    func withholdsFullPageScreenshot() -> some View {
        background(FullPageWithheld())
    }
}

/// The mark `withholdsFullPageScreenshot` leaves in the window, which `FullPageScreenshots`
/// looks for before it offers a full page.
private struct FullPageWithheld: UIViewRepresentable {
    func makeUIView(context: Context) -> FullPageWithheldMark { FullPageWithheldMark() }
    func updateUIView(_ mark: FullPageWithheldMark, context: Context) {}
}

/// An invisible view that says its screen withholds a full page.
final class FullPageWithheldMark: UIView {
    override func didMoveToWindow() {
        super.didMoveToWindow()
        isUserInteractionEnabled = false
        accessibilityElementsHidden = true
    }
}
