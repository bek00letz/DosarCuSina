package com.ar.dosarcusina.ui.ds

import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertFalse
import org.junit.jupiter.api.Assertions.assertNull
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test

/** The toast: only the newest shows, „Anulează” takes the step back, and what leaves unused is told. */
class DSToastCenterTest {
    private class Receipt(var canTakeBack: Boolean = true, val fails: Boolean = false) : DSUndo {
        var undone = 0

        override val canUndo: Boolean get() = canTakeBack

        override fun undo() {
            check(!fails) { "changed since" }
            undone += 1
            canTakeBack = false
        }
    }

    @Test
    fun `Anulează shows only while the receipt can take the step back`() {
        val receipt = Receipt()
        val toast = DSToast.undo("ITP: gata", receipt)
        assertTrue(toast.offersUndo)
        receipt.canTakeBack = false
        assertFalse(toast.offersUndo)
        assertFalse(DSToast.failure("Nu am putut salva.").offersUndo)
    }

    @Test
    fun `Anulează takes the step back and the toast goes, used`() {
        val center = DSToastCenter()
        val receipt = Receipt()
        var gone = 0
        var after = 0
        val toast = DSToast("ITP: gata", undo = receipt, afterUndo = { after += 1 }, whenGone = { gone += 1 })
        center.show(toast)
        center.takeBack(toast)
        assertEquals(1, receipt.undone)
        assertEquals(1, after)
        assertEquals(0, gone, "a toast whose button was used isn't told it left unused")
        assertNull(center.toast)
    }

    @Test
    fun `an undo that can't be done says so in its place`() {
        val center = DSToastCenter()
        val toast = DSToast.undo("ITP: gata", Receipt(fails = true))
        center.show(toast)
        center.takeBack(toast)
        assertEquals(DSToastTone.FAILURE, center.toast?.tone)
    }

    @Test
    fun `only the newest toast shows, and the one it replaces is told it left`() {
        val center = DSToastCenter()
        var gone = 0
        center.show(DSToast("Prima", whenGone = { gone += 1 }))
        center.show(DSToast("A doua"))
        assertEquals("A doua", center.toast?.title)
        assertEquals(1, gone)
    }

    @Test
    fun `a toast that times out is told, once, and an old id changes nothing`() {
        val center = DSToastCenter()
        var gone = 0
        val toast = DSToast("Prima", whenGone = { gone += 1 })
        center.show(toast)
        center.dismiss("someone else")
        assertEquals(toast, center.toast)
        center.dismiss(toast.id)
        center.dismiss(toast.id)
        assertEquals(1, gone)
    }

    @Test
    fun `an offered next step closes the toast and runs`() {
        val center = DSToastCenter()
        var taken = 0
        val toast = DSToast("Gata", offer = DSToast.Offer("Adaugă o notă") { taken += 1 })
        center.show(toast)
        center.take(toast)
        assertEquals(1, taken)
        assertNull(center.toast)
    }

    @Test
    fun `a deletion's toast stays longer`() {
        assertEquals(DSToast.LONGER_MILLIS, DSToast.undoDeletion("Am șters", Receipt()).durationMillis)
        assertTrue(DSToast.LONGER_MILLIS > DSToast.STANDARD_MILLIS)
    }
}
