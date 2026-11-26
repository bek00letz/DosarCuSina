package com.ar.dosarcusina.store.history

import com.ar.dosarcusina.catalog.Catalog
import com.ar.dosarcusina.catalog.ComponentCatalog
import com.ar.dosarcusina.catalog.VisitKind
import com.ar.dosarcusina.core.deadlines.CompletionKind
import com.ar.dosarcusina.core.deadlines.CompletionShape
import com.ar.dosarcusina.core.deadlines.HistoryKind
import com.ar.dosarcusina.core.values.CalendarDay
import com.ar.dosarcusina.store.Tables
import com.ar.dosarcusina.store.TestBinderStore
import com.ar.dosarcusina.store.schema.CategoryTemplate
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonPrimitive
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.DynamicTest
import org.junit.jupiter.api.TestFactory
import java.util.Locale

/**
 * The iOS app's answers for what a visit's form asks by its kind, a record's title, the same paper and a
 * record's page (shared/test-vectors/history/), given by this store's [VisitShape], [VisitForm], [EntryTitle],
 * [PaperIdentity] and [HistoryEntryShape] over the catalog's categories as the store installs them. The words
 * are the iOS app's, carried by the files: Android's own come with the screens (Phase 4).
 */
class HistoryVectorsTest {
    private val templates: Map<String, CategoryTemplate> by lazy {
        val binder = TestBinderStore()
        binder.launch.installBuiltIns(binder.now)
        binder.snapshot().all(Tables.templates).associateBy { it.key }
    }

    private fun kind(raw: String?): VisitKind? = raw?.let { name -> VisitKind.entries.first { it.raw == name } }

    private fun fields(fields: Set<VisitShape.Field>): List<String> = fields.map { it.raw }.sorted()

    // What a visit's form asks

    private fun shape(json: JsonObject?, shape: VisitShape?) {
        assertEquals(json == null, shape == null, "A shape where iOS has one")
        if (json == null || shape == null) return
        assertEquals(json.text("historyKind"), shape.historyKind.raw)
        assertEquals(json.textOrNull("paper"), shape.paper?.raw)
        assertEquals(json.bool("paperIsInvoice"), shape.paper?.isInvoice ?: false)
        assertEquals(json.textOrNull("documentKind"), shape.paper?.documentKind)
        assertEquals(json.bool("asksWork"), shape.asksWork)
        assertEquals(json.bool("asksBrand"), shape.asksBrand)
        assertEquals(json.bool("asksNote"), shape.asksNote)
        assertEquals(json.bool("asksCounter"), shape.asksCounter)
        assertEquals(json.bool("costIsOptional"), shape.costIsOptional)
        assertEquals(json.text("sum"), shape.sum.name.lowercase(Locale.ROOT))
        assertEquals(json.bool("checksWarranty"), shape.checksWarranty)
        assertEquals(json.textOrNull("providerTrade"), shape.providerTrade?.raw)
        val requirement = (json["requirement"] as? JsonArray)?.map { it.jsonPrimitive.content }
        assertEquals(requirement, shape.requirement?.let(::fields))
        assertEquals(json.texts("fields"), fields(shape.fields))
    }

    @TestFactory
    fun visitKinds(): List<DynamicTest> = HistoryVectorFiles.cases("visit-kinds").map { case ->
        DynamicTest.dynamicTest(case.textOrNull("category") ?: case.text("visitKind")) {
            val kind = requireNotNull(kind(case.text("visitKind")))
            val category = case.textOrNull("category")
            if (category == null) {
                shape(case.obj("shape"), VisitShape.of(kind))
                assertEquals(case.bool("offersVisit"), VisitShape.offersVisit(kind))
                assertEquals(case.bool("addsNote"), VisitShape.addsNote(kind))
                return@dynamicTest
            }
            val template = templates.getValue(category)
            val form = VisitForm.of(template)
            val json = case.obj("form")
            assertEquals(json == null, form == null, "A form where iOS has one")
            if (json != null && form != null) {
                assertEquals(json.texts("fields"), fields(form.fields))
                assertEquals(json.bool("hasChecklist"), form.hasChecklist)
                assertEquals(json.bool("hasRows"), form.hasRows)
                assertEquals(json.bool("rowsAreParts"), form.rowsAreParts)
                assertEquals(json.texts("components"), form.components.map { it.key })
                assertEquals(json.textOrNull("counterField"), form.counterField?.key)
                assertEquals(json.textOrNull("warrantyField"), form.warrantyField?.key)
                assertEquals(json.texts("paperFacts"), form.paperFacts.map { it.name.lowercase(Locale.ROOT) })
            }
            assertEquals(case.bool("listsParts"), VisitForm.listsParts(template))
        }
    }

    // A record's title

    @TestFactory
    fun titles(): List<DynamicTest> = HistoryVectorFiles.split("titles").second.map { case ->
        DynamicTest.dynamicTest(case.text("name")) {
            val items = case.texts("items")
            case.textOrNull("visitTitle")?.let { assertEquals(it, vectorWording.title(EntryTitle.of(items))) }
            case.textOrNull("category")?.let { category ->
                val form = requireNotNull(VisitForm.of(templates.getValue(category)))
                assertEquals(case.text("entryTitle"), vectorWording.title(form.entryTitle(items)))
            }
        }
    }

    // Labour among a category's parts

    @TestFactory
    fun partKeys(): List<DynamicTest> = HistoryVectorFiles.cases("labour").filter { "partName" in it }.map { case ->
        DynamicTest.dynamicTest(case.text("partName")) {
            val parts = requireNotNull(Catalog.builtIn.definition(case.text("category"))).components
            assertEquals(case.text("key"), ComponentCatalog.key(case.text("partName"), parts))
        }
    }

    // The same paper

    private fun paper(json: JsonObject): PaperIdentity {
        val day = requireNotNull(CalendarDay.parse(json.text("day")))
        val total = json.money("total")
        val issuer = json.textOrNull("issuer")
        return if (issuer == "section") {
            PaperIdentity.bill(json.textOrNull("number"), day, total)
        } else {
            PaperIdentity(json.textOrNull("number"), day, total, PaperIdentity.Issuer.Named(issuer))
        }
    }

    private fun match(match: PaperIdentity.Match?): String? = when (match) {
        PaperIdentity.Match.NUMBER -> "number"
        PaperIdentity.Match.NUMBER_ONLY -> "numberOnly"
        PaperIdentity.Match.DAY_AND_TOTAL -> "dayAndTotal"
        null -> null
    }

    @TestFactory
    fun paperIdentity(): List<DynamicTest> = HistoryVectorFiles.cases("paper-identity").map { case ->
        DynamicTest.dynamicTest(case.text("name")) {
            val paper = paper(requireNotNull(case.obj("paper")))
            val other = case.obj("other")
            if (other != null) {
                assertEquals(case.textOrNull("match"), match(paper.match(paper(other))))
            } else {
                val among = case.objects("among").map(::paper)
                val found = paper.filed(among.indices.toList()) { among[it] }
                assertEquals(case.intOrNull("found"), found?.first)
                assertEquals(case.textOrNull("foundMatch"), match(found?.second))
            }
        }
    }

    // A record's page

    /** A shape in the iOS app's words ([words]), as its page would say it. */
    private class PageWords(private val words: JsonObject, private val visit: VisitKind?) {
        private val own: JsonObject? = visit?.let { words.obj("visits")?.obj(it.raw) }

        fun items(items: HistoryEntryShape.Items): String = when (items) {
            HistoryEntryShape.Items.VISIT_WORK -> requireNotNull(own?.textOrNull("work"))
            else -> words.text(camel(items.name))
        }

        fun who(who: HistoryEntryShape.Who?): String? = when (who) {
            null -> null
            HistoryEntryShape.Who.VisitProvider -> requireNotNull(own?.textOrNull("provider"))
            is HistoryEntryShape.Who.From -> requireNotNull(words.obj("from")).text(from(who.paper))
            else -> words.text(camel(requireNotNull(who::class.simpleName)))
        }

        fun stars(header: HistoryEntryShape.RatingHeader): String = when (header) {
            HistoryEntryShape.RatingHeader.VISIT -> requireNotNull(own?.textOrNull("rating"))
            HistoryEntryShape.RatingHeader.HOW_IT_WENT -> words.text("howItWent")
        }

        private fun from(paper: CompletionShape.Paper?): String = paper?.let {
            "${it.origin.name.lowercase(Locale.ROOT)}.${it.gender.name.lowercase(Locale.ROOT)}"
        } ?: "none"
    }

    @TestFactory
    fun entryShapes(): List<DynamicTest> {
        val (words, cases) = HistoryVectorFiles.split("entry-shapes")
        return cases.map { case ->
            val record = case.textOrNull("historyKind") ?: case.text("completing")
            DynamicTest.dynamicTest("$record in ${case.textOrNull("visit")}, parts: ${case.text("listsParts")}") {
                val visit = kind(case.textOrNull("visit"))
                val listsParts = case.bool("listsParts")
                val stored = case.textOrNull("historyKind")?.let(HistoryKind::stored)
                val shape = if (stored != null) {
                    HistoryEntryShape.of(stored, visit, listsParts)
                } else {
                    HistoryEntryShape.completing(requireNotNull(CompletionKind.stored(record)), visit, listsParts)
                }
                val json = requireNotNull(case.obj("shape"))
                val page = PageWords(words, visit)
                assertEquals(json.text("items"), page.items(shape.items), "Above its rows")
                assertEquals(json.textOrNull("provider"), page.who(shape.provider), "Above who did it")
                assertEquals(json.text("reference"), shape.reference.name.lowercase(Locale.ROOT))
                assertEquals(json.text("rating"), camel(shape.rating.name))
                assertEquals(json.text("ratingHeader"), page.stars(shape.ratingHeader), "Above the stars")
                assertEquals(json.bool("rowsAreParts"), shape.rowsAreParts)
                val asks = listOf(false to false, false to true, true to false, true to true)
                    .map { (completion, someone) -> shape.asksRating(completion, someone) }
                val expected = json.getValue("asksRating").jsonArray.map { it.jsonPrimitive.content.toBooleanStrict() }
                assertEquals(expected, asks)
            }
        }
    }

    private companion object {
        /** A Kotlin name as Swift writes it: `WHAT_WAS_DONE` and `WhatWasDone` are `whatWasDone`. */
        fun camel(name: String): String {
            if (!name.contains('_') && name.any { it.isLowerCase() }) return name.replaceFirstChar { it.lowercase() }
            return name.lowercase(Locale.ROOT).split('_')
                .mapIndexed { index, part -> if (index == 0) part else part.replaceFirstChar { it.uppercase() } }
                .joinToString("")
        }
    }
}
