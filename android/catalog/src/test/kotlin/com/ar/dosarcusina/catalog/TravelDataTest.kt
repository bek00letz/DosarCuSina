package com.ar.dosarcusina.catalog

import com.ar.dosarcusina.archive.v3.ChoiceOption
import com.ar.dosarcusina.core.readiness.TravelData
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test

/**
 * The travel data the readiness checks read (shared/travel/, `TravelData`) agrees with the
 * catalog (shared/catalog/): both are exported by the iOS tests from the same code, so a key or a
 * choice one names and the other doesn't is an export out of step.
 */
class TravelDataTest {
    private val travel = TravelData.builtIn
    private val catalog = Catalog.builtIn

    private fun options(category: String, field: String): List<ChoiceOption> =
        catalog.definition(category)?.sections.orEmpty().flatMap { it.fields }
            .firstOrNull { it.key == field }?.options.orEmpty()

    private fun named(options: List<ChoiceOption>) = options.map { Triple(it.key, it.label, it.aliases) }

    @Test
    fun everyKeyTheChecksReadIsOneTheCatalogNames() {
        val exported = BuiltInKeysTest.exported()
        for ((type, keys) in travel.keys.all.filterKeys { it in exported }) {
            for ((name, key) in keys) {
                assertEquals(exported.getValue(type)[name], key, "$type.$name in rules.json and keys.json")
            }
        }
        val types = travel.documents.types.map { it.key }.toSet()
        val named = travel.keys.all.getValue("DocumentType").values
        assertTrue(types.containsAll(named), "Every document type the checks name is one documents.json lists")
    }

    @Test
    fun theCountriesAreTheCitizenshipFieldsChoice() {
        val choice = named(options(BuiltInTemplates.Key.MEMBER, MemberFields.CITIZENSHIP))
        assertEquals(choice, travel.citizenship.options.map { Triple(it.key, it.label, it.aliases) })
    }

    @Test
    fun theDocumentTypesAreTheTypeFieldsChoice() {
        val types = named(options(BuiltInTemplates.Key.DOCUMENTS, travel.documents.typeField))
        assertEquals(types, travel.documents.types.map { Triple(it.key, it.label, it.aliases) })
        val variants = options(BuiltInTemplates.Key.DOCUMENTS, travel.documents.variantField).map { it.key }
        assertEquals(variants, travel.documents.variants.map { it.key })
    }
}
