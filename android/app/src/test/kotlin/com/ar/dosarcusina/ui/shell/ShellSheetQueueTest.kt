package com.ar.dosarcusina.ui.shell

import com.ar.dosarcusina.ui.shell.ShellSheetQueue.RouteStep
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertFalse
import org.junit.jupiter.api.Assertions.assertNull
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test

/**
 * The sheet queue, as the iPhone app's `ShellSheetQueueTests`: sheets never stack, the next opens
 * once the last's dismissal completes, and a route never lands under a sheet.
 */
class ShellSheetQueueTest {
    private val settings = ShellSheet.Settings()
    private val visit = ShellSheet.AddVisit(Routes.asset)
    private val asset = AppRoute.Asset(Routes.asset)

    @Test
    fun `with nothing up a sheet opens and closes at once`() {
        val queue = ShellSheetQueue()
        queue.present(settings)
        assertEquals(settings, queue.shown)
        queue.present(null)
        assertNull(queue.shown)
        assertFalse(queue.isBusy)
    }

    @Test
    fun `a sheet asked for over another waits for that one's dismissal to complete`() {
        val queue = ShellSheetQueue()
        queue.present(settings)
        queue.didAppear()
        queue.present(visit)
        assertNull(queue.shown, "the one on screen closes first")
        assertEquals(visit, queue.waiting)
        assertTrue(queue.isBusy)
        queue.didDismiss()
        assertEquals(visit, queue.shown)
        assertNull(queue.waiting)
    }

    @Test
    fun `asking again for the sheet on screen forgets what waited`() {
        val queue = ShellSheetQueue()
        queue.present(settings)
        queue.didAppear()
        queue.present(settings)
        assertEquals(settings, queue.shown)
        assertNull(queue.waiting)
    }

    @Test
    fun `with nothing up a route lands at once`() {
        val queue = ShellSheetQueue()
        assertEquals(RouteStep.Land(asset), queue.arrive(asset))
        assertNull(queue.waitingRoute)
    }

    @Test
    fun `a route closes a screen's own sheets from the top, each once the one above has closed, then lands`() {
        val queue = ShellSheetQueue()
        queue.screenDidAppear("below", waitsByItself = false)
        queue.screenDidAppear("above", waitsByItself = false)
        assertEquals(RouteStep.Close("above"), queue.arrive(asset))
        assertEquals(RouteStep.Close("below"), queue.screenDidDismiss("above"))
        assertEquals(RouteStep.Land(asset), queue.screenDidDismiss("below"))
        assertFalse(queue.isBusy)
    }

    @Test
    fun `a route under a sheet that holds unsaved work waits for the person`() {
        val queue = ShellSheetQueue()
        queue.screenDidAppear("form", waitsByItself = false)
        queue.screen("form", holdsWork = true)
        assertEquals(RouteStep.Wait, queue.arrive(asset))
        // Saving clears the work; the route waits until the sheet closes, then lands.
        queue.screen("form", holdsWork = false)
        assertEquals(RouteStep.Land(asset), queue.screenDidDismiss("form"))
    }

    @Test
    fun `a sheet that must be answered keeps routes waiting`() {
        val queue = ShellSheetQueue()
        queue.screenDidAppear("question", waitsByItself = true)
        assertEquals(RouteStep.Wait, queue.arrive(asset))
        assertEquals(RouteStep.Land(asset), queue.screenDidDismiss("question"))
    }

    @Test
    fun `the shell's sheet doesn't hold a route back unless it holds unsaved work`() {
        val queue = ShellSheetQueue()
        queue.present(settings)
        queue.didAppear()
        assertEquals(RouteStep.Land(asset), queue.arrive(asset))

        queue.shellSheet(holdsWork = true)
        assertEquals(RouteStep.Wait, queue.arrive(asset))
        // The person closes it: the route lands once its dismissal completes.
        queue.present(null)
        assertEquals(RouteStep.Land(asset), queue.didDismiss())
        assertFalse(queue.shellHoldsWork)
    }

    @Test
    fun `the newest route wins while one waits`() {
        val queue = ShellSheetQueue()
        queue.screenDidAppear("question", waitsByItself = true)
        queue.arrive(asset)
        queue.arrive(AppRoute.Search)
        assertEquals(RouteStep.Land(AppRoute.Search), queue.screenDidDismiss("question"))
    }

    @Test
    fun `a screen's sheet that comes back on screen keeps its place`() {
        val queue = ShellSheetQueue()
        queue.screenDidAppear("first", waitsByItself = false)
        queue.screenDidAppear("second", waitsByItself = false)
        queue.screenDidAppear("first", waitsByItself = false)
        assertEquals(listOf("first", "second"), queue.screens.map { it.id })
    }

    @Test
    fun `a closing sheet with nothing waiting leaves no route step`() {
        val queue = ShellSheetQueue()
        queue.present(settings)
        queue.didAppear()
        queue.present(null)
        assertNull(queue.didDismiss())
        assertFalse(queue.isBusy)
    }
}
