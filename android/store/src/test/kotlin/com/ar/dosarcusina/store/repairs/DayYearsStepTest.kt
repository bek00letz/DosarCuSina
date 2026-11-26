package com.ar.dosarcusina.store.repairs

import com.ar.dosarcusina.archive.v3.FieldValue
import com.ar.dosarcusina.core.values.CalendarDay
import com.ar.dosarcusina.store.Tables
import com.ar.dosarcusina.store.TestBinderStore
import com.ar.dosarcusina.store.noon
import com.ar.dosarcusina.store.schema.Asset
import com.ar.dosarcusina.store.schema.Attachment
import com.ar.dosarcusina.store.schema.Obligation
import com.ar.dosarcusina.store.schema.keptValues
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test
import org.junit.jupiter.params.ParameterizedTest
import org.junit.jupiter.params.provider.CsvSource

/**
 * A day kept with another calendar's year is offered back in its Gregorian year, asking first; a year
 * that can't be worked back safely is only listed; a day its month doesn't have is offered as the
 * month's last (the iOS app's `DayYearsRepairTests` and `ImpossibleDaysTests`). Placeholders only.
 */
class DayYearsStepTest {
    private val long = noon("2025-06-01")
    private val today = noon("2026-11-26")
    private val binder = TestBinderStore(now = today).also { it.launch.installBuiltIns(today) }

    private fun day(iso: String) = requireNotNull(CalendarDay.parse(iso))

    @ParameterizedTest
    @CsvSource(
        "2026-03-31, possible,",
        "2226-03-31, possible,",
        "1890-06-01, possible,",
        "2569-03-31, means, 2026-03-31",
        "2483-05-01, means, 1940-05-01",
        "2567-02-29, means, 2024-02-29",
        "2227-01-01, unknown,",
        "1484-03-31, unknown,",
        "0008-03-31, unknown,",
        "5787-01-01, unknown,",
        "2026-02-30, missing, 2026-02-28",
        "2024-02-30, missing, 2024-02-29",
        "2026-06-31, missing, 2026-06-30",
        "2026-02-28, possible,",
        "2568-02-30, unknown,",
    )
    fun whichDaysCantBeAndWhatTheyMean(iso: String, verdict: String, meant: String?) {
        val expected = when (verdict) {
            "possible" -> DayYearsStep.Verdict.Possible
            "means" -> DayYearsStep.Verdict.Means(day(meant!!))
            "missing" -> DayYearsStep.Verdict.Missing(day(meant!!))
            else -> DayYearsStep.Verdict.Unknown
        }
        assertEquals(expected, DayYearsStep.verdict(day(iso), thisYear = 2026), iso)
    }

    private fun passport(vararg values: Pair<String, FieldValue>): Asset = binder.unit.performPrivate { step ->
        step.insert(Asset(name = "Pașaport", templateKey = "documents", updatedAt = long).with(*values))
    }

    @Test
    fun aBuddhistYearIsOfferedBackAskingFirstAndOnce() {
        val document = passport(
            "document.expiry" to FieldValue.Day(day("2574-03-31")),
            "document.issueDate" to FieldValue.Day(day("2021-04-01")),
        )
        val renewal = binder.unit.performPrivate { step ->
            step.insert(
                Obligation(title = "Reînnoire", kindRaw = "renewal", dueDayISO = "2574-03-31", asset = document.pk),
            )
        }
        val found = repairs(binder).detect().filter { it.step == DataRepairStepId.DAY_YEARS }
        assertEquals(2, found.size)
        assertTrue(found.all { it.isFixable })
        val subjects = found.map { it.subject as DataRepairSubject.DayYear }
        assertTrue(subjects.all { it.from == day("2574-03-31") && it.to == day("2031-03-31") })
        assertEquals(
            DataRepairSubject.DayYear(
                DayYearsStep.Place.Field(document.id, "document.expiry"), day("2574-03-31"), day("2031-03-31"),
                DayYearsStep.Verdict.Means(day("2031-03-31")), "Valabil până la", "Pașaport",
            ),
            subjects.first(),
            "Named by its field's label, under its section",
        )
        val expiry = values(document)["document.expiry"]
        assertEquals(FieldValue.Day(day("2574-03-31")), expiry, "Nothing changes before the owner says so")

        applyTwice(binder, DataRepairStepId.DAY_YEARS) {
            assertEquals(FieldValue.Day(day("2031-03-31")), values(document)["document.expiry"])
            val issued = values(document)["document.issueDate"]
            assertEquals(FieldValue.Day(day("2021-04-01")), issued, "A day that can be stays")
            assertEquals("2031-03-31", binder.stored(renewal).dueDayISO)
            assertEquals(long, binder.stored(document).updatedAt, "A repair isn't the person's change")
        }
    }

    @Test
    fun aYearThatCantBeWorkedBackOnlySaysWhatToCheck() {
        val document = passport("document.expiry" to FieldValue.Day(day("0008-03-31")))
        val policy = binder.unit.performPrivate { step ->
            step.insert(
                Attachment(
                    title = "Poliță", fileName = "polita.pdf", kindRaw = "policy", validUntilISO = "1484-03-31",
                    asset = document.pk,
                ),
            )
        }
        val list = repairs(binder)
        val found = list.detect().filter { it.step == DataRepairStepId.DAY_YEARS }
        assertEquals(2, found.size)
        assertTrue(found.none { it.isFixable })
        val before = binder.database()
        list.apply(found)
        assertEquals(before, binder.database(), "Nothing it can't decide changes")
        assertEquals("1484-03-31", binder.stored(policy).validUntilISO)
    }

    @Test
    fun aDayChangedSinceItWasFoundStays() {
        val document = passport("document.expiry" to FieldValue.Day(day("2574-03-31")))
        val list = repairs(binder)
        val found = list.detect().filter { it.step == DataRepairStepId.DAY_YEARS }
        assertEquals(1, found.size)
        val changed = FieldValue.Day(day("2032-01-15"))
        binder.unit.perform { step ->
            step.update(step.row(Tables.assets, document.pk)!!.with("document.expiry" to changed))
        }
        list.apply(found)
        assertEquals(FieldValue.Day(day("2032-01-15")), values(document)["document.expiry"])
    }

    @Test
    fun aMissingDayIsOfferedAsTheMonthsLast() {
        val car = binder.unit.performPrivate { step ->
            step.insert(Asset(name = "VW Golf 2018", templateKey = "vehicle"))
        }
        val itp = binder.unit.performPrivate { step ->
            step.insert(Obligation(title = "ITP", kindRaw = "legal", dueDayISO = "2026-02-30", asset = car.pk))
        }
        assertEquals("2026-02-30", binder.stored(itp).dueDayISO, "Kept as written")
        val found = applyTwice(binder, DataRepairStepId.DAY_YEARS) {
            assertEquals("2026-02-28", binder.stored(itp).dueDayISO)
        }
        val subject = found.single().subject as DataRepairSubject.DayYear
        assertEquals(DayYearsStep.Verdict.Missing(day("2026-02-28")), subject.verdict)
        assertEquals("ITP" to "VW Golf 2018", subject.name to subject.section)
    }

    private fun values(asset: Asset) = binder.stored(asset).keptValues.value
}
