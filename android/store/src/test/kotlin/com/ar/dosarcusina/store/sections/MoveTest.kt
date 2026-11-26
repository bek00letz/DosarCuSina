package com.ar.dosarcusina.store.sections

import com.ar.dosarcusina.archive.v3.FieldValue
import com.ar.dosarcusina.archive.v3.FieldValues
import com.ar.dosarcusina.catalog.BuiltInTemplates
import com.ar.dosarcusina.catalog.DocumentNaming
import com.ar.dosarcusina.store.Tables
import com.ar.dosarcusina.store.TestBinderStore
import com.ar.dosarcusina.store.bucharest
import com.ar.dosarcusina.store.noon
import com.ar.dosarcusina.store.schema.Asset
import com.ar.dosarcusina.store.templates.TemplateStore
import com.ar.dosarcusina.store.templates.behavior
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertFalse
import org.junit.jupiter.api.Assertions.assertNull
import org.junit.jupiter.api.Assertions.assertThrows
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test

/**
 * "Mută la…": a document under another person, renamed for them; a tenancy under another home; a new
 * person and the move as one step that undo takes back whole; nothing changed when the save fails.
 * The iOS app's `MoveTests`. Every value is a placeholder.
 */
class MoveTest {
    private val today = noon("2026-11-02")
    private val binder = TestBinderStore(now = today).also { it.launch.installBuiltIns(today) }
    private val actions = AssetActions(binder.unit, now = { today }, zone = { bucharest })
    private val templates = TemplateStore(binder.unit, binder.locks)

    private fun add(name: String, key: String, values: FieldValues = FieldValues(), parent: Asset? = null): Asset =
        actions.create(name, requireNotNull(templates.template(key)), values, parent = parent)

    private val corina = add("Manole Corina", BuiltInTemplates.Key.MEMBER)
    private val ion = add("Popescu Ion", BuiltInTemplates.Key.MEMBER)
    private val card = add(
        "Carte de identitate – Manole Corina", BuiltInTemplates.Key.DOCUMENTS,
        FieldValues(mapOf("document.type" to FieldValue.Text("documentType.idCard"))), corina,
    )
    private val flat = add("Apartament", BuiltInTemplates.Key.HOME)
    private val house = add("Casa de la țară", BuiltInTemplates.Key.HOME)
    private val tenancy = add("Chiriaș etaj 2", BuiltInTemplates.Key.TENANCY, parent = flat)

    private fun stored(asset: Asset): Asset = binder.stored(asset)

    @Test
    fun destinationsAreTheOtherParentsOfTheSameKind() {
        val view = binder.snapshot()
        assertEquals(listOf("Popescu Ion"), SectionPlaces.moveDestinations(view, card).map { it.name })
        assertEquals(listOf("Casa de la țară"), SectionPlaces.moveDestinations(view, tenancy).map { it.name })
        assertTrue(SectionPlaces.offersNewMember(view, card))
        assertFalse(SectionPlaces.offersNewMember(view, tenancy))
        assertFalse(SectionPlaces.canMove(view, flat), "A top-level home has nowhere to move")
    }

    @Test
    fun movingADocumentFilesItUnderTheOtherPersonAndRenamesIt() {
        val proposed = SectionPlaces.renamedForHolder(binder.snapshot(), card, ion.name)
        assertEquals("Carte de identitate – Popescu Ion", proposed)
        val receipt = actions.move(card, MoveTarget.ToSection(ion.id), proposed)
        assertEquals(ion.pk, stored(card).parent)
        assertEquals("Carte de identitate – Popescu Ion", stored(card).name)
        receipt.undo()
        assertEquals(corina.pk, stored(card).parent)
        assertEquals("Carte de identitate – Manole Corina", stored(card).name)
    }

    @Test
    fun keepingTheNameMovesOnly() {
        actions.move(tenancy, MoveTarget.ToSection(house.id))
        assertEquals(house.pk, stored(tenancy).parent)
        assertEquals("Chiriaș etaj 2", stored(tenancy).name)
    }

    @Test
    fun aNameThePersonChoseIsNeverRewritten() {
        assertNull(DocumentNaming.renamed("Buletinul vechi", "Manole Corina", "Popescu Ion"))
        val renamed = DocumentNaming.renamed("Pașaport – manole corina", "Manole Corina", "Popescu Ion")
        assertEquals("Pașaport – Popescu Ion", renamed)
        assertNull(DocumentNaming.renamed("Pașaport – Popescu Ion", "Popescu Ion", "Popescu Ion"))
        assertEquals("Cazier judiciar – Manole Corina", DocumentNaming.name("Cazier judiciar", "Manole Corina"))
    }

    @Test
    fun aNewPersonAndTheMoveAreOneStepAndUndoRemovesThePerson() {
        val receipt = actions.move(card, MoveTarget.NewMember("Manole Ana"), "Carte de identitate – Manole Ana")
        val ana = requireNotNull(stored(card).parent?.let { binder.stored(Tables.assets, it) })
        assertEquals("Manole Ana", ana.name)
        assertEquals(BuiltInTemplates.Key.MEMBER, ana.templateKey)
        receipt.undo()
        assertFalse(binder.snapshot().all(Tables.assets).any { it.name == "Manole Ana" })
        assertEquals(corina.pk, stored(card).parent)
    }

    @Test
    fun aFailedMoveLeavesEverythingAsItWas() {
        val before = binder.database()
        binder.unit.failNextCommitForTesting(IllegalStateException("The disk is full"))
        assertThrows(IllegalStateException::class.java) {
            actions.move(card, MoveTarget.NewMember("Manole Ana"), "Carte de identitate – Manole Ana")
        }
        assertEquals(before, binder.database())
    }

    @Test
    fun aNewPersonNeedsAName() {
        assertThrows(AssetActionError.MissingName::class.java) { actions.move(card, MoveTarget.NewMember("  ")) }
    }

    @Test
    fun aPlantGoesUnderTheOnlyHomeWhenNobodySaid() {
        val plants = requireNotNull(templates.template(BuiltInTemplates.Key.PLANTS))
        val behavior = plants.behavior
        assertNull(SectionPlaces.automaticParent(binder.snapshot(), behavior), "Two homes: the person says which")
        actions.delete(house)
        assertEquals("Apartament", SectionPlaces.automaticParent(binder.snapshot(), behavior)?.name)
    }
}
