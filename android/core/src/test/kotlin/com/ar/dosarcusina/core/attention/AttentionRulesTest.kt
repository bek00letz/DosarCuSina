package com.ar.dosarcusina.core.attention

import com.ar.dosarcusina.core.urgency.Consequence
import com.ar.dosarcusina.core.urgency.DeadlineSnapshot
import com.ar.dosarcusina.core.urgency.NeedsAction
import com.ar.dosarcusina.core.urgency.ReminderProfile
import com.ar.dosarcusina.core.values.CalendarDay
import com.ar.dosarcusina.core.values.Money
import com.ar.dosarcusina.core.values.MoneyTotals
import com.ar.dosarcusina.core.values.ObligationStatus
import java.math.BigDecimal
import java.util.UUID
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertNull
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test

/** The attention rules' invariants, beside the iOS app's answers. Placeholder data only. */
class AttentionRulesTest {
    private val today = CalendarDay(2026, 11, 26)

    private fun deadline(
        n: Long,
        due: CalendarDay,
        status: ObligationStatus = ObligationStatus.ACTIVE,
        section: UUID? = null,
    ) = DeadlineSnapshot(
        id = UUID(0, n),
        status = status,
        dueDay = due,
        reminders = ReminderProfile(listOf(30, 7, 0), Consequence.LEGAL),
        title = "Termen $n",
        sectionId = section,
        sectionName = section?.let { "Secțiune $n" },
    )

    @Test
    fun `the list's count is the badge's one count`() {
        val deadlines = listOf(
            deadline(1, today.addingDays(-3)),
            deadline(2, today),
            deadline(3, today.addingDays(-3), ObligationStatus.PAUSED),
            deadline(4, today.addingDays(-3), ObligationStatus.DONE),
            deadline(5, today.addingDays(4)),
        )
        val digest = AttentionModel.digest(deadlines, today, unassignedName = "")
        assertEquals(NeedsAction.count(deadlines, today), digest.needsActionCount)
        assertEquals(2, digest.needsActionCount)
        assertEquals(1, digest.hiddenCount, "Paused is hidden; done is left out")
    }

    @Test
    fun `a box shows what Acum would show first`() {
        val section = UUID(1, 1)
        val deadlines = listOf(
            deadline(1, today.addingDays(5), section = section),
            deadline(2, today, section = section),
        )
        val box = BoxStatus.make(forSection = section, deadlines = deadlines, today = today)
        assertEquals(AttentionModel.digest(deadlines, today, "").now.first(), box.entry)
        assertTrue(box.isAlarming)
        val elsewhere = BoxStatus.make(forSection = UUID(2, 2), deadlines = deadlines, today = today)
        assertEquals(BoxLine.AllGood, elsewhere.line(false))
    }

    @Test
    fun `money is summed by currency, the default first`() {
        val costs = listOf(Money(BigDecimal("28"), "EUR"), Money(BigDecimal("1200")), Money(BigDecimal("2"), "eur"))
        val totals = MoneyTotals.of(costs)
        assertEquals(listOf(Money(BigDecimal("1200")), Money(BigDecimal("30"), "EUR")), totals.amounts)
        assertEquals(0, totals.amount("eur").compareTo(BigDecimal("30")))
        assertTrue(MoneyTotals.EMPTY.isEmpty)
    }

    @Test
    fun `a noun this build doesn't know counts sections as sections`() {
        assertNull(SectionNoun.of("boat"))
        assertNull(SectionNoun.of(null))
        assertEquals(SectionNoun.CAR, SectionNoun.of("car"))
    }

    @Test
    fun `no suggestions, no note`() {
        assertNull(AttentionModel.suggestionNote(0, listOf("Ce ține de altă secțiune")))
        val notes = AttentionModel.calmNotes(emptyList(), AttentionModel.suggestionNote(2, emptyList()))
        assertEquals(listOf(CalmNote.Suggestions(2, emptyList())), notes)
    }
}
