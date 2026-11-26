package com.ar.dosarcusina.catalog

import com.ar.dosarcusina.archive.v3.Condition
import com.ar.dosarcusina.archive.v3.FieldValue
import com.ar.dosarcusina.archive.v3.FieldValues
import com.ar.dosarcusina.core.values.CalendarDay
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertFalse
import org.junit.jupiter.api.Assertions.assertNull
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test

/**
 * What a personal document can be, read from the shared catalog's `documents.json`: the same types
 * and variants the documents category offers, the names they give, and the rules declared on them.
 * The full answers are the iOS app's shared cases (`SectionVectorsTest`, in :store).
 */
class DocumentTypesTest {
    private val catalog = Catalog.builtIn
    private val types = catalog.documentTypes

    @Test
    fun theTypesAndVariantsAreTheOnesTheDocumentsCategoryOffers() {
        val fields = requireNotNull(catalog.definition(BuiltInTemplates.Key.DOCUMENTS)).sections.flatMap { it.fields }
        val type = fields.single { it.key == types.typeFieldKey }
        val offered = type.options?.map { Triple(it.key, it.label, it.aliases) }
        assertEquals(offered, types.types.map { Triple(it.key, it.label, it.aliases) })
        val variant = fields.single { it.key == types.variantFieldKey }
        assertEquals(variant.options?.map { it.key }, types.variants.map { it.key })
        for (option in variant.options.orEmpty()) {
            val spec = types.variants.single { it.key == option.key }
            val condition = requireNotNull(option.appliesWhen?.let(Condition::read))
            assertEquals(listOf(spec.type), condition.oneOf, "${option.key} is offered for its own type")
            assertEquals(option.label, spec.label)
        }
    }

    @Test
    fun aDocumentIsNamedByItsVariantElseItsType() {
        val fiscal = types.documentName("documentType.criminalRecord", "documentVariant.criminalRecord.fiscal")
        assertEquals("Cazier fiscal", fiscal)
        val electronic = types.documentName("documentType.idCard", "documentVariant.idCard.electronic")
        assertEquals("Carte de identitate", electronic)
        assertEquals(types.unnamed, types.documentName("documentType.somethingNewer", null))
        val label = FieldValues(mapOf(types.typeFieldKey to FieldValue.Text("Pasaport")))
        assertEquals("Pașaport", types.documentName(label))
        assertNull(types.documentName(FieldValues()))
    }

    @Test
    fun theRulesAreTheTypesOwnData() {
        assertTrue(types.keepsBackSide(null), "A document with no type yet counts as Alt document")
        assertFalse(types.keepsBackSide("documentType.bankCard"), "Its back shows the security code")
        assertEquals(180, types.travelMarginDays("Pasaport"))
        assertEquals(0, types.travelMarginDays("documentType.idCard"))
        val issued = requireNotNull(CalendarDay.parse("2026-08-31"))
        val until = types.validUntil(issued, "documentType.criminalRecord", "documentVariant.criminalRecord.judicial")
        assertEquals("2027-02-28", until?.isoString, "Six months, the shorter month's last day")
        assertNull(types.validUntil(issued, "documentType.criminalRecord", "documentVariant.criminalRecord.fiscal"))
        assertTrue(types.isDatedByIssue("documentType.criminalRecord"))
        assertTrue(types.isReadOnPhoneOnly("documentType.bankCard"))
    }

    @Test
    fun recuperateIsTheSameCategoryOnBothApps() {
        val recovered = catalog.ownCategories.recovered
        assertEquals("custom.recovered", recovered.key)
        assertEquals("Recuperate", recovered.name)
        assertEquals(listOf("upcoming", "documents", "history"), recovered.pockets)
    }
}
