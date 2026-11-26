package com.ar.dosarcusina.store.repairs

import com.ar.dosarcusina.store.TestBinderStore
import com.ar.dosarcusina.store.iosSources
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test
import java.io.File

/**
 * The registry is the iOS app's, step for step: the same steps in the same order, under the same
 * stored ids, each running by itself or asking, and a correction or a suggestion, as there. Read from
 * the iOS sources (ios/DosarCuSina/Services/Repairs/), so a step added there and not here fails.
 */
class DataRepairRegistryTest {
    /** One step as the iOS app declares it. */
    private data class IosStep(val id: String, val runsByItself: Boolean, val isSuggestion: Boolean)

    private val repairs = File(iosSources, "Services/Repairs")

    /** The iOS registry, in its order. */
    private fun iosSteps(): List<IosStep> {
        val registry = File(repairs, "DataRepairs.swift").readText()
        val ids = Regex("""case (\w+) = "([^"]+)"""").findAll(registry)
            .associate { it.groupValues[1] to it.groupValues[2] }
        val list = registry.substringAfter("static let steps: [any DataRepairStep] = [").substringBefore("]")
        val names = Regex("""(\w+)\(\)""").findAll(list).map { it.groupValues[1] }.toList()
        val declared = declarations(ids)
        return names.map { name -> requireNotNull(declared[name]) { "No declaration of $name in the iOS sources" } }
    }

    /** Every iOS step's declaration, by its type's name. */
    private fun declarations(ids: Map<String, String>): Map<String, IosStep> {
        val found = HashMap<String, IosStep>()
        for (file in repairs.listFiles().orEmpty().filter { it.extension == "swift" }) {
            val lines = file.readLines()
            for ((index, line) in lines.withIndex()) {
                val name = Regex("""^struct (\w+): DataRepairStep \{""").find(line)?.groupValues?.get(1) ?: continue
                val body = lines.drop(index + 1).takeWhile { it != "}" }.joinToString("\n")
                val case = Regex("""static let id = DataRepairStepID\.(\w+)""").find(body)?.groupValues?.get(1)
                found[name] = IosStep(
                    id = requireNotNull(ids[case]) { "$name has no stored id" },
                    runsByItself = "runsByItself: Bool { true }" in body,
                    isSuggestion = "isSuggestion: Bool { true }" in body,
                )
            }
        }
        return found
    }

    @Test
    fun theRegistryIsTheIosOneStepForStep() {
        val ios = iosSteps()
        assertTrue(ios.size > 30, "The iOS registry is read")
        val android = DataRepairs.steps.map { IosStep(it.id.raw, it.runsByItself, it.isSuggestion) }
        assertEquals(ios, android, "The same steps, in the same order, under the same ids, running and asking alike")
    }

    @Test
    fun everyStepHasItsOwnStoredId() {
        val ids = DataRepairs.steps.map { it.id }
        assertEquals(ids.size, ids.toSet().size)
        assertEquals(DataRepairStepId.entries.toSet(), ids.toSet())
        assertEquals(DataRepairStepId.entries.map { it.raw }.toSet().size, DataRepairStepId.entries.size)
        for (id in DataRepairStepId.entries) assertEquals(id, DataRepairs.step(id).id)
    }

    @Test
    fun aStepThatWaitsSaysOnWhatAndFindsNothing() {
        val binder = TestBinderStore()
        binder.launch.prepare()
        val list = DataRepairs(binder.unit, DataRepairLedger(file = null))
        val waiting = DataRepairs.steps.filterIsInstance<WaitingStep>()
        assertTrue(waiting.all { it.waitsFor.isNotBlank() }, "Each says what its port needs")
        assertTrue(list.detect().none { DataRepairs.step(it.step) is WaitingStep })
    }

    @Test
    fun onlyTheSuggestionsStepIsASuggestionAndTheVerbsAreTheIosOnes() {
        assertEquals(
            listOf(DataRepairStepId.SECTIONS_INTO_THEIR_HOME),
            DataRepairs.steps.filter { it.isSuggestion }.map { it.id },
        )
        val verbs = DataRepairs.steps.filter { it.applyVerb != ApplyVerb.CORRECT }.associate { it.id to it.applyVerb }
        assertEquals(
            mapOf(
                DataRepairStepId.SECTIONS_INTO_THEIR_HOME to ApplyVerb.MOVE,
                DataRepairStepId.PERSONAL_LESSON_LABELS to ApplyVerb.FORGET_LABEL,
                DataRepairStepId.LOST_RECORDS to ApplyVerb.KEEP,
            ),
            verbs,
        )
        // Two steps share a group, as their titles are one on iOS.
        assertEquals(DataRepairGroup.COUNTERS, DataRepairs.step(DataRepairStepId.HERO_FROM_READINGS).group)
        assertEquals(DataRepairGroup.COUNTERS, DataRepairs.step(DataRepairStepId.COUNTER_OUTLIERS).group)
    }
}
