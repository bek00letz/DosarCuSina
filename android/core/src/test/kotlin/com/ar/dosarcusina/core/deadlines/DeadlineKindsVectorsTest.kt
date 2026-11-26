package com.ar.dosarcusina.core.deadlines

import com.ar.dosarcusina.core.values.ObligationKind
import com.ar.dosarcusina.core.urgency.Consequence
import com.ar.dosarcusina.core.values.CalendarDay
import com.ar.dosarcusina.core.values.VectorFolder
import com.ar.dosarcusina.core.values.bool
import com.ar.dosarcusina.core.values.ints
import com.ar.dosarcusina.core.values.isNull
import com.ar.dosarcusina.core.values.text
import com.ar.dosarcusina.core.values.textOrNull
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.jsonObject
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.DynamicTest
import org.junit.jupiter.api.Test
import org.junit.jupiter.api.TestFactory

/**
 * The deadline rules' answers, in shared/test-vectors/deadlines/, by ios/DosarCuSinaTests/DeadlineVectorsTests.swift.
 * This module reads the kinds and validity; `:catalog` reads the blueprints and facts, `:store` the
 * actions, the reminders that follow a section and deadlines closed twice.
 */
object DeadlineVectors : VectorFolder(
    folderName = "deadlines",
    files = setOf("actions", "blueprints", "double-completions", "facts", "kinds", "reminders-follow", "validity"),
    writtenBy = "the iOS DeadlineVectorsTests with TEST_RUNNER_DEADLINE_VECTORS_WRITE=1",
)

/** The iOS app's answers for a deadline's kinds, what closing each asks, and when it is valid. */
class DeadlineKindsVectorsTest {
    /** A Kotlin constant as its Swift case is spelled: `COUNTED_ON` is `countedOn`. */
    private fun swiftName(case: Enum<*>): String = case.name.lowercase().split("_")
        .mapIndexed { index, part -> if (index == 0) part else part.replaceFirstChar { it.uppercase() } }
        .joinToString("")

    private fun day(text: String): CalendarDay = requireNotNull(CalendarDay.parse(text))

    @Test
    fun everyFileOfAnswersIsReadByATest() {
        val present = DeadlineVectors.folder.listFiles { file -> file.extension == "json" }.orEmpty()
            .map { it.nameWithoutExtension }.toSet()
        assertEquals(DeadlineVectors.files, present, "Each file of answers needs its test, and each test its file")
    }

    @TestFactory
    fun kinds(): List<DynamicTest> = DeadlineVectors.tests("kinds", { it.toString().take(60) }) { case ->
        when {
            "obligationKind" in case -> obligationKind(case)
            "storedKind" in case ->
                assertEquals(case.text("reads"), ObligationKind.stored(case.textOrNull("storedKind")).raw)
            "completionKind" in case -> completionKind(case)
            "storedCompletion" in case ->
                assertEquals(case.textOrNull("reads"), CompletionKind.stored(case.textOrNull("storedCompletion"))?.raw)
            else -> error("A case of no kind: $case")
        }
    }

    private fun obligationKind(case: JsonObject) {
        val kind = ObligationKind.stored(case.text("obligationKind"))
        assertEquals(case.text("obligationKind"), kind.raw)
        assertEquals(case.bool("missedCyclesStayOwed"), kind.missedCyclesStayOwed)
        val profile = case.getValue("defaultProfile").jsonObject
        val ours = kind.defaultProfile
        assertEquals(profile.ints("leadDays"), ours.leadDays)
        assertEquals(Consequence.stored(profile.text("consequence")), ours.consequence)
        assertEquals(profile.text("graceDays").toInt(), ours.graceDays)
        assertEquals(profile.bool("followUpAfterLapse"), ours.followUpAfterLapse)
        val margin = if (profile.isNull("travelMarginDays")) 0 else profile.text("travelMarginDays").toInt()
        assertEquals(margin, ours.travelMarginDays)
        assertEquals(case.text("own"), CompletionKind.own(kind).raw)
        assertEquals(case.text("historyKindOfOwn"), HistoryKind.forCompleting(CompletionKind.own(kind)).raw)
    }

    private fun completionKind(case: JsonObject) {
        val kind = requireNotNull(CompletionKind.stored(case.text("completionKind")))
        assertEquals(case.text("record"), swiftName(kind.record))
        assertEquals(case.text("historyKind"), kind.record.historyKind.raw)
        val expected = case.getValue("shape").jsonObject
        val shape = kind.shape
        assertEquals(expected.bool("asksDate"), shape.asksDate)
        assertEquals(expected.textOrNull("cost"), shape.cost?.let(::swiftName))
        assertEquals(expected.textOrNull("newEnd"), shape.newEnd?.let(::swiftName))
        assertEquals(expected.textOrNull("counter"), shape.counter?.let(::swiftName))
        assertEquals(expected.bool("asksNote"), shape.asksNote)
        val paper = expected["paper"]?.takeUnless { it is JsonNull }?.jsonObject
        assertEquals(paper?.text("gender"), shape.paper?.gender?.let(::swiftName))
        assertEquals(paper?.text("use"), shape.paper?.use?.let(::swiftName))
        assertEquals(paper?.text("origin"), shape.paper?.origin?.let(::swiftName))
        val replacement = expected["replacement"]?.takeUnless { it is JsonNull }?.jsonObject
        assertEquals(replacement != null, shape.replacement != null)
        if (replacement != null) {
            assertEquals(replacement.bool("replacesItsSection"), shape.replacement?.replacesItsSection)
            assertEquals(replacement.textOrNull("holdersDocumentType"), shape.replacement?.holdersDocumentType)
        }
        for ((name, ours) in listOf(
            "closesOutsideTheApp" to shape.closesOutsideTheApp, "isOneTap" to shape.isOneTap,
            "replacesDocument" to shape.replacesDocument, "replacesSection" to shape.replacesSection,
            "asksNewExpiry" to shape.asksNewExpiry, "asksReading" to shape.asksReading,
            "offersNoteAfter" to shape.offersNoteAfter,
        )) {
            assertEquals(expected.bool(name), ours, "${kind.raw}: $name")
        }
    }

    @Test
    fun everyCompletionKindIsAnIosOne() {
        val ios = DeadlineVectors.cases("kinds").mapNotNull { it.textOrNull("completionKind") }
        assertEquals(ios, CompletionKind.entries.map { it.raw }, "The same kinds, in the same order")
        val obligations = DeadlineVectors.cases("kinds").mapNotNull { it.textOrNull("obligationKind") }
        assertEquals(obligations, ObligationKind.entries.map { it.raw })
        assertTrue(ios.isNotEmpty())
    }

    @TestFactory
    fun validity(): List<DynamicTest> =
        DeadlineVectors.tests("validity", { "${it.text("due")} on ${it.text("on")}" }) { case ->
        assertEquals(case.bool("isValid"), DueDayValidity.isValid(day(case.text("due")), day(case.text("on"))))
        assertEquals(case.bool("covers"), DueDayValidity.covers(day(case.text("on")), day(case.text("due"))))
    }
}
