package com.ar.dosarcusina.store.providers

import com.ar.dosarcusina.store.Tables
import com.ar.dosarcusina.store.TestBinderStore
import com.ar.dosarcusina.store.noon
import com.ar.dosarcusina.store.schema.Asset
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertNotEquals
import org.junit.jupiter.api.Assertions.assertNull
import org.junit.jupiter.api.Test

/**
 * The people and firms in the binder: one way to name who issued a document or did a job (by its
 * CUI, then by its name), a card's details written only where the edit changed them, and a firm
 * deleted with undo bringing back every link. The iOS app's `HistoryAndProvidersTests` and
 * `FormsSaveWhatChangedTests`, their parts below the screens. Every value is a placeholder.
 */
class ProviderActionsTest {
    private val binder = TestBinderStore(now = noon("2026-11-26"))
    private val actions = ProviderActions(binder.unit)

    private fun section(name: String): Asset = binder.unit.perform { step ->
        step.insert(Asset(name = name, templateKey = "vehicle"))
    }

    @Test
    fun aFirmIsFoundByItsCuiWhateverItsNameSaysAndLinkedToTheSection() {
        val engie = requireNotNull(actions.findOrCreate("ENGIE Romania S.A.", "RO12345678", ProviderTrade.OTHER))
        val car = section("VW Golf 2018")
        val found = actions.findOrCreate("Furnizor Gaz Exemplu", "12345678", ProviderTrade.MECHANIC, linkedTo = car)
        assertEquals(engie.pk, found?.pk)
        assertEquals(listOf(car.pk), binder.snapshot().linked(Tables.providerAssets, engie.pk))
        assertEquals(1, binder.snapshot().all(Tables.providers).size)
    }

    @Test
    fun aFirmFoundByItsNameKeepsTheCuiItLacked() {
        val service = actions.create("Service Exemplu SRL", listOf(ProviderTrade.MECHANIC), phone = "0040 700 000 000")
        assertEquals("+40700000000", binder.stored(service).phone, "A phone as stored")
        val found = actions.findOrCreate("  SERVICE exemplu   srl ", "RO 1234 5678", ProviderTrade.MECHANIC)
        assertEquals(service.pk, found?.pk)
        assertEquals("12345678", binder.stored(service).taxID)
    }

    @Test
    fun theSameNameWithAnotherCuiIsAnotherFirm() {
        val first = requireNotNull(actions.findOrCreate("Service Exemplu SRL", "87654321", ProviderTrade.MECHANIC))
        val second = requireNotNull(actions.findOrCreate("Service Exemplu SRL", "12345678", ProviderTrade.MECHANIC))
        assertNotEquals(first.pk, second.pk)
        assertNull(actions.findOrCreate("   ", "12345678", ProviderTrade.MECHANIC), "Nothing in the name finds nothing")
    }

    @Test
    fun anEditWritesOnlyTheDetailsItChanged() {
        val firm = actions.create("Instal Exemplu SRL", listOf(ProviderTrade.PLUMBER))
        val opened = ProviderDetails.of(binder.stored(firm))
        // Meanwhile, a phone number was added elsewhere.
        actions.update(firm, opened.copy(phone = "0700 000 001"))
        val edited = opened.copy(notes = "  Vine doar dimineața  ", email = " Nume@Exemplu.ro ")
        actions.update(firm, edited, startedFrom = opened)
        val stored = binder.stored(firm)
        assertEquals("0700000001", stored.phone, "Left as it was read, it keeps what is stored now")
        assertEquals("Vine doar dimineața", stored.notes)
        assertEquals("nume@exemplu.ro", stored.email)
    }

    @Test
    fun deletingAFirmIsUndoneWithItsLinks() {
        val car = section("VW Golf 2018")
        val firm = actions.create("Service Exemplu SRL", listOf(ProviderTrade.MECHANIC), linkedTo = listOf(car))
        actions.delete(firm).undo()
        assertEquals(listOf(car.pk), binder.snapshot().linked(Tables.providerAssets, firm.pk))
        actions.setRating(firm, 9)
        assertEquals(5, binder.stored(firm).manualRating)
    }
}
