package com.ar.dosarcusina.store.repairs

import com.ar.dosarcusina.archive.ArchiveImportMode
import com.ar.dosarcusina.archive.DossierArchiveService
import com.ar.dosarcusina.archive.MemoryByteSource
import com.ar.dosarcusina.archive.fixtureArchive
import com.ar.dosarcusina.archive.moment
import com.ar.dosarcusina.archive.v3.FieldValue
import com.ar.dosarcusina.archive.v3.RecurrenceRule
import com.ar.dosarcusina.catalog.Catalog
import com.ar.dosarcusina.core.values.KeptObject
import com.ar.dosarcusina.store.ChangeOrigin
import com.ar.dosarcusina.store.Tables
import com.ar.dosarcusina.store.TestBinderStore
import com.ar.dosarcusina.store.bucharest
import com.ar.dosarcusina.store.noon
import com.ar.dosarcusina.store.schema.Asset
import com.ar.dosarcusina.store.schema.IssuerLesson
import com.ar.dosarcusina.store.schema.Obligation
import com.ar.dosarcusina.store.schema.keptRecurrence
import com.ar.dosarcusina.store.schema.keptValues
import com.ar.dosarcusina.store.schema.withKeptRecurrence
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertFalse
import org.junit.jupiter.api.Assertions.assertNull
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test
import org.junit.jupiter.api.io.TempDir
import java.io.File
import java.time.Clock
import java.time.ZoneOffset

/**
 * The repair list: each step finds its fixture, changes it only when applied, as the app's own step,
 * and finds nothing the second time; applying the same finding twice changes nothing more (the iOS
 * app's `DataRepairTests`). Every value is a placeholder.
 */
class DataRepairsTest {
    @TempDir
    lateinit var staging: File

    private val long = noon("2025-06-01")
    private val binder = TestBinderStore().also { it.launch.installBuiltIns(noon("2026-11-26")) }

    /** A first-version copy's plain interval. */
    private val everyTwoYears = RecurrenceRule.Interval(730, "day", "dueDate")

    private fun golf(): Asset = binder.unit.performPrivate { step ->
        step.insert(Asset(name = "VW Golf 2018", templateKey = "vehicle", updatedAt = long))
    }

    // Deadlines from a first-version copy

    @Test
    fun aFirstVersionItpGetsItsBlueprintAndTheLegalRule() {
        val car = golf()
        val itp = binder.unit.performPrivate { step ->
            step.insert(
                Obligation(title = "ITP", kindRaw = "legal", dueDayISO = "2027-05-01", asset = car.pk, updatedAt = long)
                    .withKeptRecurrence(KeptObject.made(everyTwoYears, RecurrenceRule.codec)),
            )
        }
        val found = applyTwice(binder, DataRepairStepId.FIRST_VERSION_DEADLINES) {
            val stored = binder.stored(itp)
            assertEquals("vehicle.itp", stored.blueprintKey)
            assertEquals(RecurrenceRule.Legal("vehicleITP"), stored.keptRecurrence.value)
            assertEquals("2027-05-01", stored.dueDayISO, "The date the person has stays")
            assertEquals(long, stored.updatedAt, "A repair isn't the person's change")
        }
        assertEquals(
            listOf(DataRepairSubject.Blueprint(itp.id, "vehicle.itp", "ITP", "VW Golf 2018")),
            found.map { it.subject },
        )
    }

    @Test
    fun aFirstVersionBackupsDeadlinesAreOfferedAndTheImportLooksForThem() {
        val fresh = TestBinderStore()
        DossierArchiveService(
            fresh.target,
            Catalog.builtIn,
            clock = Clock.fixed(moment("2026-11-26T10:00:00Z"), ZoneOffset.UTC),
            zone = { bucharest },
        ).importArchive(
            MemoryByteSource(fixtureArchive("dosar-v2/ios-export")),
            mode = ArchiveImportMode.REPLACE,
            staging = staging,
        )
        val rca = fresh.snapshot().all(Tables.obligations).first { it.title == "RCA" }
        assertNull(rca.blueprintKey)
        assertTrue(
            fresh.repairs.pending.any { it.step == DataRepairStepId.FIRST_VERSION_DEADLINES },
            "Every import has the repair list look again",
        )
        assertTrue(fresh.repairs.announcement.isNotEmpty(), "And the calm prompt says so")
        applyTwice(fresh, DataRepairStepId.FIRST_VERSION_DEADLINES) {
            assertEquals("vehicle.rca", fresh.stored(rca).blueprintKey)
        }
    }

    @Test
    fun aDeadlineOfAnotherKindOrWithItsBlueprintIsLeftAlone() {
        val car = golf()
        binder.unit.performPrivate { step ->
            step.insert(Obligation(title = "ITP", kindRaw = "routine", dueDayISO = "2027-05-01", asset = car.pk))
            step.insert(Obligation(title = "RCA", kindRaw = "insurance", asset = car.pk, statusRaw = "done"))
            step.insert(Obligation(title = "Rovinietă", kindRaw = "legal", asset = car.pk, isExample = true))
        }
        assertTrue(repairs(binder).detect().none { it.step == DataRepairStepId.FIRST_VERSION_DEADLINES })
    }

    // Steps that run by themselves

    @Test
    fun choiceKeysRunByThemselvesWithDetection() {
        val car = binder.earlier { database ->
            database.assets().insert(Asset(name = "VW Golf 2018", templateKey = "vehicle", updatedAt = long)
                .with("vehicle.fuel" to FieldValue.Text("Benzină")))
        }
        val ion = binder.earlier { database ->
            database.assets().insert(Asset(name = "Ion Exemplu", templateKey = "member", updatedAt = long)
                .with("member.citizenship" to FieldValue.Text("country.MD")))
        }
        assertEquals(emptyList<DataRepairFinding>(), repairs(binder).detect(), "Nothing to ask")
        val storedCar = binder.stored(Tables.assets, car)!!
        assertEquals(FieldValue.Text("fuel.petrol"), storedCar.keptValues.value["vehicle.fuel"])
        assertEquals(long, storedCar.updatedAt, "The app's own step: no change time")
        assertEquals(
            FieldValue.Choices(listOf("country.MD")),
            binder.stored(Tables.assets, ion)!!.keptValues.value["member.citizenship"],
            "A single value an earlier version kept becomes a list of one",
        )
        val before = binder.database()
        val again = binder.unit.perform(ChangeOrigin.APP) { ChoiceKeysStep.runByItself(it, context()) }
        assertEquals(0, again, "A second run changes nothing")
        assertEquals(before, binder.database())
    }

    private fun context() = DataRepairContext(bucharest, binder.now, Catalog.builtIn, binder.locks)

    // The list itself

    @Test
    fun aDismissalIsRememberedOnThisPhoneOnly() {
        val car = golf()
        binder.unit.performPrivate { step ->
            step.insert(Obligation(title = "ITP", kindRaw = "legal", dueDayISO = "2027-05-01", asset = car.pk))
        }
        val ledger = DataRepairLedger(File(staging, "binder.sqlite.repairs.json"))
        val list = repairs(binder, ledger)
        val found = list.detect()
        assertEquals(1, found.size)
        list.dismiss(found)
        assertEquals(emptyList<DataRepairFinding>(), list.detect())
        val again = repairs(binder, DataRepairLedger(ledger.file))
        assertEquals(emptyList<DataRepairFinding>(), again.detect(), "Kept in its file")
        assertEquals(1, repairs(binder).detect().size, "Another phone's list would still show it")
        assertNull(binder.snapshot().all(Tables.obligations).single().blueprintKey, "Lasă așa changes nothing")
    }

    @Test
    fun aLedgerThatCantBeReadShowsEverythingAgain() {
        val file = File(staging, "binder.sqlite.repairs.json").apply { writeText("{ not json") }
        val ledger = DataRepairLedger(file)
        assertEquals(emptySet<String>(), ledger.dismissed)
        ledger.dismiss(listOf("card-numbers:Asset:1"))
        assertEquals(setOf("card-numbers:Asset:1"), DataRepairLedger(file).dismissed, "Written whole once it changes")
    }

    @Test
    fun thePromptAnnouncesOnlyWhatIsNew() {
        val car = golf()
        binder.unit.performPrivate { step ->
            step.insert(Obligation(title = "ITP", kindRaw = "legal", dueDayISO = "2027-05-01", asset = car.pk))
        }
        val center = DataRepairCenter(repairs(binder))
        center.refresh(announce = true)
        assertEquals(1, center.announcement.size)
        center.announcementShown()
        center.refresh(announce = true)
        assertTrue(center.announcement.isEmpty(), "Said once")
        assertEquals(1, center.pending.size, "Still in the list")
        assertEquals(listOf(DataRepairGroup.OLD_BACKUP_DEADLINES), center.groups.map { it.group })
        assertTrue(center.suggestions.isEmpty() && center.suggestionTopics.isEmpty())

        center.apply(center.pending)
        assertTrue(center.pending.isEmpty(), "Applied, the list looks again")
    }

    // Lessons whose label is the household's

    private fun lesson(label: String, issuer: String, category: String) = IssuerLesson(
        issuerKey = "cui:12345674", issuerName = issuer, kindRaw = "utilityInvoice", fieldKey = "total",
        label = label, categoryKey = category,
    )

    @Test
    fun lessonsHoldingTheHouseholdsValuesAreForgotten() {
        binder.unit.performPrivate { step ->
            step.insert(Asset(name = "Ion Exemplu", templateKey = "member"))
            val address = FieldValue.Text("Strada Exemplu nr. 1, Exempluville")
            step.insert(Asset(name = "Apartament", templateKey = "home").with("home.address" to address))
            val plate = FieldValue.Text("B-123-ABC")
            step.insert(Asset(name = "VW Golf 2018", templateKey = "vehicle").with("vehicle.plate" to plate))
            step.insert(lesson("Ultima zi de plată", "ENGIE Romania S.A.", "subscription"))
            step.insert(lesson("Titular Exemplu", "ENGIE Romania S.A.", "subscription"))
            step.insert(lesson("Exempluville", "ENGIE Romania S.A.", "subscription"))
            step.insert(lesson("Mașina ABC", "Service Exemplu SRL", "vehicle"))
        }
        val found = applyTwice(binder, DataRepairStepId.PERSONAL_LESSON_LABELS) {
            assertEquals(listOf("Ultima zi de plată"), binder.snapshot().all(Tables.lessons).map { it.label })
        }
        assertEquals(3, found.size)
        assertTrue(found.all { it.isFixable })
        assertFalse(DataRepairs.step(DataRepairStepId.PERSONAL_LESSON_LABELS).isSuggestion)
        assertTrue(
            found.any { (it.subject as DataRepairSubject.LessonLabel).named?.label == "Titular Exemplu" },
            "Named, from an open category's papers",
        )
    }

    @Test
    fun aLockedCategorysLessonIsOfferedWithoutNamingItsIssuer() {
        binder.unit.performPrivate { step ->
            step.insert(Asset(name = "Ion Exemplu", templateKey = "member"))
            step.insert(lesson("Pacient Exemplu", "Clinica Exemplu SRL", "health"))
            step.insert(lesson("Titular Exemplu", "", "subscription"))
            step.insert(lesson("Client Exemplu", "Service Exemplu SRL", "subscription").copy(categoryKey = null))
        }
        val found = repairs(binder).detect().filter { it.step == DataRepairStepId.PERSONAL_LESSON_LABELS }
        assertEquals(3, found.size)
        assertTrue(
            found.all { (it.subject as DataRepairSubject.LessonLabel).named == null },
            "A locked category's, one with no issuer's name, and one whose category isn't known while a lock is on",
        )
    }
}
