import Foundation
import Testing
@testable import DosarCuSina

/// A route from a notification, a widget, a link or a search result never lands under a screen's
/// own sheet: it closes them from the top, each once the one above has closed, then lands; while
/// one holds unsaved work or must be answered first, it waits for the person.
@Suite("Routes over sheets")
struct RoutesOverSheetsTests {
    @Test("A route over a screen's own sheet closes it, then lands once it has closed")
    func aRouteClosesAScreensSheetFirst() {
        let edit = UUID(), deadline = UUID()
        var sheets = ShellSheetQueue()
        sheets.screenDidAppear(edit, waitsByItself: false)
        #expect(sheets.isBusy, "The router knows a screen's own sheet is up")
        #expect(sheets.arrive(.obligation(deadline)) == .close(edit))
        #expect(sheets.isBusy, "Nothing else pops up while the route waits")
        #expect(sheets.screenDidDismiss(edit) == .land(.obligation(deadline)))
        #expect(!sheets.isBusy)
    }

    @Test("Sheets over sheets close from the top, each once the one above has closed; the newest route wins")
    func sheetsOverSheetsCloseFromTheTop() {
        let below = UUID(), above = UUID(), first = UUID(), second = UUID()
        var sheets = ShellSheetQueue()
        sheets.screenDidAppear(below, waitsByItself: false)
        sheets.screenDidAppear(above, waitsByItself: false)
        sheets.screenDidAppear(below, waitsByItself: false)
        #expect(sheets.screens.map(\.id) == [below, above], "Coming back on screen keeps its place")
        #expect(sheets.arrive(.obligation(first)) == .close(above))
        #expect(sheets.arrive(.obligation(second)) == .close(above))
        #expect(sheets.screenDidDismiss(above) == .close(below))
        #expect(sheets.screenDidDismiss(below) == .land(.obligation(second)))
    }

    @Test("A route waits while a sheet holds unsaved work or must be answered, until the person closes it")
    func aRouteWaitsForUnsavedWork() {
        let form = UUID(), question = UUID(), deadline = UUID()
        var sheets = ShellSheetQueue()
        sheets.screenDidAppear(form, waitsByItself: false)
        sheets.screen(form, holdsWork: true)
        #expect(sheets.arrive(.obligation(deadline)) == .wait, "Typed changes are never closed away")
        sheets.screen(form, holdsWork: false)
        #expect(sheets.waitingRoute == .obligation(deadline), "It goes on waiting for the person")
        #expect(sheets.screenDidDismiss(form) == .land(.obligation(deadline)))

        sheets.screenDidAppear(question, waitsByItself: true)
        #expect(sheets.arrive(.upcoming) == .wait, "The notification question before a save is answered first")
        #expect(sheets.screenDidDismiss(question) == .land(.upcoming))
    }

    @Test("The shell's sheet holding unsaved work keeps a route waiting until it closes")
    func theShellsSheetWithUnsavedWork() {
        let section = UUID()
        var sheets = ShellSheetQueue()
        sheets.present(.addSection(.topLevel))
        sheets.didAppear()
        sheets.shellSheet(holdsWork: true)
        #expect(sheets.arrive(.asset(section)) == .wait)
        #expect(sheets.shown == .addSection(.topLevel), "Still up")
        #expect(sheets.didDismiss() == .land(.asset(section)))

        // Without unsaved work the route lands at once, and its landing closes the shell's sheet.
        sheets.present(.settings(nil))
        sheets.didAppear()
        #expect(sheets.arrive(.asset(section)) == .land(.asset(section)))
    }

    @MainActor
    @Test("The router never pushes under a screen's own sheet")
    func theRouterClosesAScreensSheetBeforeItPushes() {
        let edit = UUID(), deadline = UUID()
        let router = ShellRouter()
        let closed = Counter()
        router.screenSheetDidAppear(edit, waitsByItself: false) { closed.count += 1 }
        #expect(router.hasSheet)
        router.open(.obligation(deadline))
        #expect(closed.count == 1, "Asked to close")
        #expect(router.tab == .dosar && router.upcomingPath.isEmpty, "Nothing pushed under the sheet")
        router.screenSheetDidDismiss(edit)
        #expect(router.tab == .upcoming && router.upcomingPath.count == 1, "Landed once it had closed")
        #expect(!router.hasSheet)

        // A form with changes: the route waits for the person, and closes nothing.
        router.screenSheetDidAppear(edit, waitsByItself: false) { closed.count += 1 }
        router.screenSheet(edit, holdsWork: true)
        router.open(.home)
        #expect(closed.count == 1 && router.tab == .upcoming)
        router.screenSheetDidDismiss(edit)
        #expect(router.tab == .dosar)
    }
}
