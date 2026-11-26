package com.ar.dosarcusina.store.repairs

import com.ar.dosarcusina.archive.v3.CustomFact
import com.ar.dosarcusina.core.values.KeptList
import com.ar.dosarcusina.store.Tables
import com.ar.dosarcusina.store.TestBinderStore
import com.ar.dosarcusina.store.noon
import com.ar.dosarcusina.store.schema.Asset
import com.ar.dosarcusina.store.schema.HistoryEntry
import com.ar.dosarcusina.store.schema.keptFacts
import com.ar.dosarcusina.store.schema.withKeptFacts
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertFalse
import org.junit.jupiter.api.Test
import java.util.UUID

/**
 * Whole card numbers an earlier version kept are offered, and masked only with the owner's OK; the
 * list never shows or stores the number (the iOS app's `CardNumbersKeptOutTests`, its repair part).
 * Card numbers are the networks' published test numbers only.
 */
class CardNumbersStepTest {
    private val long = noon("2025-06-01")
    private val binder = TestBinderStore()

    private companion object {
        const val VISA = "4111 1111 1111 1111"
        const val MASTERCARD = "5555555555554444"
        const val VISA_MASKED = "•••• 1111"
        const val MASTERCARD_MASKED = "•••• 4444"

        fun holdsNumber(text: String): Boolean {
            val digits = text.filter { it.isDigit() }
            return "4111111111111111" in digits || "5555555555554444" in digits
        }
    }

    @Test
    fun numbersAnEarlierVersionKeptAreOfferedAndMaskedOnlyWithTheOwnersOk() {
        val fact = CustomFact(UUID.fromString("00000000-0000-4000-8000-0000000000f1"), "Card", VISA)
        // Saved as an earlier version did, around the unit of work.
        val boat = binder.earlier { database ->
            database.assets().insert(
                Asset(name = "Barca de pe lac", templateKey = "other", updatedAt = long)
                    .withKeptFacts(KeptList.made(listOf(fact), CustomFact.codec, CustomFact::id)),
            )
        }
        val visit = binder.earlier { database ->
            database.history().insert(
                HistoryEntry(title = "Plată", note = "Card $MASTERCARD", asset = boat, updatedAt = long),
            )
        }
        binder.earlier { database ->
            database.assets().insert(Asset(name = "VW Golf 2018", templateKey = "other", notes = "B-123-ABC"))
        }

        val found = repairs(binder).detect().filter { it.step == DataRepairStepId.CARD_NUMBERS }
        val boatKey = RecordKey("Asset", binder.stored(Tables.assets, boat)!!.id.toString())
        val visitKey = RecordKey("HistoryEntry", binder.stored(Tables.history, visit)!!.id.toString())
        assertEquals(
            setOf(
                DataRepairSubject.CardNumbers(boatKey, "Barca de pe lac", null),
                DataRepairSubject.CardNumbers(visitKey, "Plată", "Barca de pe lac"),
            ),
            found.map { it.subject }.toSet(),
            "The section with the row and the visit, nothing else",
        )
        for (finding in found) assertFalse(holdsNumber(finding.toString()), "The list never shows or stores the number")
        val kept = binder.stored(Tables.assets, boat)!!.keptFacts.items.single().value
        assertEquals(VISA, kept, "Nothing changes before the owner says so")

        applyTwice(binder, DataRepairStepId.CARD_NUMBERS) {
            val section = binder.stored(Tables.assets, boat)!!
            assertEquals(VISA_MASKED, section.keptFacts.items.single().value)
            assertEquals("Card $MASTERCARD_MASKED", binder.stored(Tables.history, visit)!!.note)
            assertEquals(long, section.updatedAt, "A repair isn't the person's change")
        }
    }

    @Test
    fun aNameThatHoldsTheNumberIsShownMasked() {
        binder.earlier { database -> database.assets().insert(Asset(name = "Card $VISA", templateKey = "other")) }
        val finding = repairs(binder).detect().single { it.step == DataRepairStepId.CARD_NUMBERS }
        assertEquals("Card $VISA_MASKED", (finding.subject as DataRepairSubject.CardNumbers).name)
    }
}
