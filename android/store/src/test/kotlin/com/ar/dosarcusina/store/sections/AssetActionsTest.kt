package com.ar.dosarcusina.store.sections

import com.ar.dosarcusina.archive.v3.CustomFact
import com.ar.dosarcusina.archive.v3.FieldValue
import com.ar.dosarcusina.archive.v3.FieldValues
import com.ar.dosarcusina.catalog.BuiltInTemplates
import com.ar.dosarcusina.catalog.HouseholdRules
import com.ar.dosarcusina.catalog.SubscriptionFields
import com.ar.dosarcusina.core.subscriptions.BillReminders
import com.ar.dosarcusina.core.text.SealedText
import com.ar.dosarcusina.core.values.CalendarDay
import com.ar.dosarcusina.core.values.KeptObject
import com.ar.dosarcusina.store.Tables
import com.ar.dosarcusina.store.TestBinderStore
import com.ar.dosarcusina.store.bucharest
import com.ar.dosarcusina.store.examples.ExampleSectionQuestion
import com.ar.dosarcusina.store.noon
import com.ar.dosarcusina.store.schema.Asset
import com.ar.dosarcusina.store.schema.CategoryTemplate
import com.ar.dosarcusina.store.schema.Obligation
import com.ar.dosarcusina.store.schema.keptFacts
import com.ar.dosarcusina.store.schema.keptValues
import com.ar.dosarcusina.store.schema.reminders
import com.ar.dosarcusina.store.schema.withKeptValues
import com.ar.dosarcusina.store.security.SecretFieldError
import com.ar.dosarcusina.store.security.SecretSealer
import com.ar.dosarcusina.store.templates.TemplateStore
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertFalse
import org.junit.jupiter.api.Assertions.assertNotNull
import org.junit.jupiter.api.Assertions.assertNull
import org.junit.jupiter.api.Assertions.assertThrows
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test
import java.util.Base64
import java.util.UUID

/** A sealer for tests that seals reversibly: what the Keystore's will do, without a key. */
object ReversibleSealer : SecretSealer {
    override fun seal(plain: String): String =
        SealedText.PREFIX + Base64.getEncoder().encodeToString(plain.encodeToByteArray())

    override fun open(sealed: String): String =
        Base64.getDecoder().decode(sealed.removePrefix(SealedText.PREFIX)).decodeToString()
}

/**
 * Everything a person does to a section, through the store's one `AssetActions`: making one with
 * its deadlines, its first reading and the household's deadlines; editing it, writing only what
 * changed, with its deadlines and reminders following its values; a document's name following its
 * type; secrets sealed; deleting it with what it holds. The iOS app's `ActionsTests`,
 * `ParentChildTests`, `FormsSaveWhatChangedTests`, `DeadlineRemindersTests`,
 * `BillPlaceAndDirectDebitTests` and `SecretFieldTests`, their parts below the screens. Every value
 * is a placeholder.
 */
class AssetActionsTest {
    private val today = noon("2026-11-26")
    private val binder = TestBinderStore(now = today).also { it.launch.installBuiltIns(today) }
    private val actions = AssetActions(binder.unit, ReversibleSealer, now = { today }, zone = { bucharest })
    private val templates = TemplateStore(binder.unit, binder.locks)

    private fun template(key: String): CategoryTemplate = requireNotNull(templates.template(key))

    private fun make(name: String, key: String, values: FieldValues = FieldValues(), parent: Asset? = null): Asset {
        val template = template(key)
        val plan = actions.plannedObligations(template, values)
        return actions.create(name, template, values, obligations = plan, parent = parent)
    }

    private fun obligations(asset: Asset): List<Obligation> =
        binder.snapshot().all(Tables.obligations).filter { it.asset == asset.pk }.sortedBy { it.blueprintKey }

    private fun day(iso: String) = FieldValue.Day(requireNotNull(CalendarDay.parse(iso)))

    private val idCard = "documentType.idCard"
    private val passport = "documentType.passport"

    // Making

    @Test
    fun aNewCarStartsWithTheDeadlinesWhoseDayIsKnownAndItsOdometerAsItsFirstReading() {
        val odometer = FieldValues(mapOf("vehicle.odometer" to FieldValue.Number(145_000.0)))
        val car = make("VW Golf 2018", BuiltInTemplates.Key.VEHICLE, odometer)
        val keys = obligations(car).map { it.blueprintKey }
        assertTrue("vehicle.service" in keys, "A service a year after today")
        assertFalse("vehicle.itp" in keys, "The ITP's day is the person's to give: it starts unticked")
        val readings = binder.snapshot().all(Tables.readings).filter { it.asset == car.pk }
        assertEquals(listOf(145_000.0), readings.map { it.value })
    }

    @Test
    fun aTenancyBringsTheRentalDeclarationAndDeletingItTakesItAwayUntilUndo() {
        val flat = make("Apartament Exemplu", BuiltInTemplates.Key.HOME)
        val tenancy = make("Chiriaș etaj 2", BuiltInTemplates.Key.TENANCY, parent = flat)
        val declarations = {
            val key = HouseholdRules.RENTAL_DECLARATION_KEY
            binder.snapshot().all(Tables.obligations).filter { it.blueprintKey == key }
        }
        assertEquals(1, declarations().size, "Made in the tenancy's own step")
        val receipt = actions.delete(tenancy)
        assertEquals(0, declarations().size, "Only the tenancy needed it")
        receipt.undo()
        assertEquals(1, declarations().size)
        assertNotNull(binder.snapshot().row(Tables.assets, tenancy.pk))
    }

    @Test
    fun somethingOfThePersonsNeverLandsInAnExampleWithoutAsking() {
        val example = binder.unit.perform { step ->
            step.insert(Asset(name = "Casă exemplu", templateKey = "home", isExample = true))
        }
        val before = binder.database()
        assertThrows(ExampleSectionQuestion::class.java) {
            make("Chiriaș exemplu", BuiltInTemplates.Key.TENANCY, parent = example)
        }
        assertEquals(before, binder.database(), "Nothing saved")
    }

    @Test
    fun aWarrantyIsWorkedOutFromItsDayAndTheUsualMonths() {
        val bought = FieldValues(mapOf("purchase.date" to day("2026-11-01")))
        val washer = make("Mașină de spălat", BuiltInTemplates.Key.PURCHASE, bought)
        val values = binder.stored(washer).keptValues.value
        assertEquals(FieldValue.Number(24.0), values["purchase.warrantyMonths"], "The default")
        assertEquals(day("2028-11-01"), values["purchase.warrantyUntil"], "Worked out")
        assertEquals(listOf("2028-11-01"), obligations(washer).map { it.dueDayISO })
    }

    // Editing

    @Test
    fun anEditWritesOnlyWhatItChangedOverWhatIsStoredNow() {
        val plate = FieldValues(mapOf("vehicle.plate" to FieldValue.Text("B-123-ABC")))
        val car = make("VW Golf 2018", BuiltInTemplates.Key.VEHICLE, plate)
        val opened = SectionEditStart.of(binder.stored(car))
        // Meanwhile, the notes changed elsewhere.
        actions.update(car, car.name, opened.values, "Garaj subteran")
        actions.update(car, "Golf", opened.values, opened.notes, startedFrom = opened)
        val stored = binder.stored(car)
        assertEquals("Golf", stored.name)
        assertEquals("Garaj subteran", stored.notes, "What the form left as it read it keeps what is stored now")
    }

    @Test
    fun aDocumentsRenewalMovesWithItsExpiryAndItsRemindersFollowItsType() {
        val values = FieldValues(
            mapOf("document.type" to FieldValue.Text(passport), "document.expiry" to day("2031-05-10")),
        )
        val document = make("Pașaport – Manole Corina", BuiltInTemplates.Key.DOCUMENTS, values)
        val renewal = obligations(document).single()
        assertEquals(180, renewal.reminders.travelMarginDays, "A passport stops being good for travel 6 months before")
        val edited = values.with("document.expiry", day("2032-01-15")).with("document.type", FieldValue.Text(idCard))
        actions.update(document, document.name, edited, null)
        val after = obligations(document).single()
        assertEquals(renewal.pk, after.pk)
        assertEquals("2032-01-15", after.dueDayISO, "The renewal follows the expiry")
        assertEquals(0, after.reminders.travelMarginDays, "An identity card is good for travel until it expires")
    }

    @Test
    fun aFieldThatDrivesADeadlineMakesItOnceItHasADay() {
        val washer = make("Mașină de spălat", BuiltInTemplates.Key.PURCHASE)
        assertEquals(emptyList<Obligation>(), obligations(washer))
        val values = binder.stored(washer).keptValues.value.with("purchase.date", day("2026-11-01"))
        actions.update(washer, washer.name, values, null)
        assertEquals(listOf("purchase.warrantyEnds"), obligations(washer).map { it.blueprintKey })
    }

    @Test
    fun turningOnDirectDebitPausesTheBillReminderInTheSameUndoableStep() {
        val service = FieldValues(mapOf("subscription.service" to FieldValue.Text("service.gas")))
        val gas = make("Gaz", BuiltInTemplates.Key.SUBSCRIPTION, service)
        val bill = binder.unit.perform { step ->
            step.insert(Obligation(title = "Factura de plătit", kindRaw = "payment", dueDayISO = "2026-12-10",
                blueprintKey = SubscriptionFields.BILL_BLUEPRINT, asset = gas.pk))
        }
        val values = binder.stored(gas).keptValues.value.with(SubscriptionFields.DIRECT_DEBIT, FieldValue.Toggle(true))
        val outcome = actions.update(gas, gas.name, values, null)
        assertEquals(BillReminders.Change.PAUSED, outcome.billReminder?.value)
        assertEquals("paused", binder.stored(bill).statusRaw)
        requireNotNull(outcome.billReminder).receipt.undo()
        assertEquals("active", binder.stored(bill).statusRaw, "Undo takes back the edit and the reminder together")
    }

    @Test
    fun aDocumentsNameFollowsACorrectedTypeUnlessThePersonChangedIt() {
        val other = FieldValues(mapOf("document.type" to FieldValue.Text("documentType.other")))
        val document = make("Alt document – Manole Corina", BuiltInTemplates.Key.DOCUMENTS, other)
        val corrected = other.with("document.type", FieldValue.Text(passport))
        actions.editDocument(document, DocumentEdit(document.name, corrected, null))
        assertEquals("Pașaport – Manole Corina", binder.stored(document).name)
        actions.editDocument(binder.stored(document), DocumentEdit("Pașaportul vechi", other, null))
        assertEquals("Pașaportul vechi", binder.stored(document).name, "A name the person typed is theirs")
    }

    // Secrets

    @Test
    fun aPinIsSealedBeforeItIsSavedAndNothingIsSavedWithoutAKeyToSealIt() {
        val electronic = FieldValues(
            mapOf(
                "document.type" to FieldValue.Text(idCard),
                "document.variant" to FieldValue.Text("documentVariant.idCard.electronic"),
                "document.pinAuthentication" to FieldValue.Text("0000"),
            ),
        )
        val before = binder.database()
        val withoutKey = AssetActions(binder.unit, now = { today }, zone = { bucharest })
        assertThrows(SecretFieldError.KeyUnavailable::class.java) {
            withoutKey.create("Carte de identitate", template(BuiltInTemplates.Key.DOCUMENTS), electronic)
        }
        assertEquals(before, binder.database(), "Nothing saved")
        val card = make("Carte de identitate", BuiltInTemplates.Key.DOCUMENTS, electronic)
        val pin = binder.stored(card).keptValues.value["document.pinAuthentication"]?.textValue.orEmpty()
        assertTrue(SealedText.isSealed(pin))
        assertEquals("0000", ReversibleSealer.open(pin))
    }

    @Test
    fun theStoreRefusesASecretInPlainWhoeverWritesIt() {
        val type = FieldValues(mapOf("document.type" to FieldValue.Text(idCard)))
        val card = make("Carte de identitate", BuiltInTemplates.Key.DOCUMENTS, type)
        val before = binder.database()
        assertThrows(SecretFieldError.NotSealed::class.java) {
            binder.unit.perform { step ->
                val row = requireNotNull(step.row(Tables.assets, card.pk))
                val plain = row.keptValues.value.with("document.pinSigning", FieldValue.Text("0000"))
                step.update(row.withKeptValues(KeptObject.made(plain, FieldValues.codec)))
            }
        }
        assertEquals(before, binder.database())
    }

    @Test
    fun aSecretRowIsSealedAndTheRowsWriteOnlyWhatChanged() {
        val home = make("Apartament Exemplu", BuiltInTemplates.Key.HOME)
        val wifi = CustomFact(UUID.fromString("aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaa01"), "Wi-Fi", "Rețea Exemplu")
        actions.setCustomFacts(home, listOf(wifi))
        val opened = binder.stored(home).keptFacts.items
        val code = UUID.fromString("aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaa02")
        val alarm = CustomFact(code, "Cod alarmă", "0000", isSecret = true)
        actions.setCustomFacts(home, opened + alarm, startedFrom = opened)
        val rows = binder.stored(home).keptFacts.items
        assertEquals(listOf("Wi-Fi", "Cod alarmă"), rows.map { it.label })
        assertTrue(SealedText.isSealed(rows[1].value) && rows[1].isSensitive)
        assertEquals("0000", ReversibleSealer.open(rows[1].value))
    }

    // Deleting and filing

    @Test
    fun deletingASectionKeepsOrTakesWhatIsFiledUnderIt() {
        val flat = make("Apartament Exemplu", BuiltInTemplates.Key.HOME)
        val tenancy = make("Chiriaș etaj 2", BuiltInTemplates.Key.TENANCY, parent = flat)
        actions.delete(flat).undo()
        actions.delete(flat)
        assertNull(binder.stored(tenancy).parent, "It stays, on its own")
        val house = make("Casa de la țară", BuiltInTemplates.Key.HOME)
        val second = make("Chiriaș parter", BuiltInTemplates.Key.TENANCY, parent = house)
        actions.delete(house, ChildrenOnDelete.DELETE)
        assertNull(binder.snapshot().row(Tables.assets, second.pk))
    }

    @Test
    fun nothingIsFiledUnderItselfNorUnderWhatIsFiledUnderIt() {
        val flat = make("Apartament Exemplu", BuiltInTemplates.Key.HOME)
        val tenancy = make("Chiriaș etaj 2", BuiltInTemplates.Key.TENANCY, parent = flat)
        assertThrows(AssetActionError.WouldCreateLoop::class.java) { actions.setParent(flat, tenancy) }
        assertThrows(AssetActionError.WouldCreateLoop::class.java) { actions.setParent(flat, flat) }
    }
}
