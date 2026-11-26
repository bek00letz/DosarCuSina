package com.ar.dosarcusina.store

import com.ar.dosarcusina.archive.ArchiveImportMode
import com.ar.dosarcusina.archive.DossierArchiveService
import com.ar.dosarcusina.archive.MemoryByteSource
import com.ar.dosarcusina.archive.SecretRules
import com.ar.dosarcusina.archive.binder.Binder
import com.ar.dosarcusina.archive.binder.BinderChanges
import com.ar.dosarcusina.archive.binder.Removed
import com.ar.dosarcusina.archive.fixtureArchive
import com.ar.dosarcusina.archive.moment
import com.ar.dosarcusina.archive.v3.CustomFact
import com.ar.dosarcusina.archive.v3.FieldDefinition
import com.ar.dosarcusina.archive.v3.FieldSection
import com.ar.dosarcusina.archive.v3.FieldValue
import com.ar.dosarcusina.archive.v3.FieldValues
import com.ar.dosarcusina.catalog.Catalog
import com.ar.dosarcusina.core.values.KeptList
import com.ar.dosarcusina.core.values.KeptObject
import com.ar.dosarcusina.store.schema.Asset
import com.ar.dosarcusina.store.schema.Attachment
import com.ar.dosarcusina.store.schema.CategoryTemplate
import com.ar.dosarcusina.store.schema.HistoryEntry
import com.ar.dosarcusina.store.schema.MeasurementLog
import com.ar.dosarcusina.store.schema.Obligation
import com.ar.dosarcusina.store.schema.Provider
import com.ar.dosarcusina.store.schema.ServiceItem
import com.ar.dosarcusina.store.schema.keptFacts
import com.ar.dosarcusina.store.schema.keptSections
import com.ar.dosarcusina.store.schema.keptValues
import com.ar.dosarcusina.store.schema.withDefinition
import com.ar.dosarcusina.store.schema.withKeptFacts
import com.ar.dosarcusina.store.schema.withKeptValues
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test
import org.junit.jupiter.api.io.TempDir
import java.io.File
import java.lang.reflect.Modifier
import java.lang.reflect.ParameterizedType
import java.time.Clock
import java.time.ZoneId
import java.time.ZoneOffset
import java.util.UUID

/**
 * A bank card's full number is never kept, from any path: a row typed under Date importante, a
 * section's notes and values, a visit and its line items, a reading, a deadline, a firm, a
 * document, a category of one's own, a backup brought in. The unit of work masks it as it saves
 * ([FreeText]). Card numbers are the networks' published test numbers only (the iOS app's
 * `CardNumbersKeptOutTests`).
 */
class FreeTextTest {
    @TempDir
    lateinit var staging: File

    private val binder = TestBinderStore()
    private val unit = binder.unit

    private companion object {
        const val VISA = "4111 1111 1111 1111"
        const val MASTERCARD = "5555555555554444"
        const val VISA_MASKED = "•••• 1111"
        const val MASTERCARD_MASKED = "•••• 4444"

        /** Whether [text] still holds either test number, however it is spaced. */
        fun holdsNumber(text: String?): Boolean {
            val digits = text.orEmpty().filter { it.isDigit() }
            return "4111111111111111" in digits || "5555555555554444" in digits
        }

        /** [digits] with the Luhn check digit after them, so they pass as a card number. */
        fun withCheckDigit(digits: String): String {
            val sum = digits.reversed().mapIndexed { index, char ->
                val value = char.digitToInt()
                if (index % 2 == 0) (value * 2).let { if (it > 9) it - 9 else it } else value
            }.sum()
            return digits + ((10 - sum % 10) % 10)
        }
    }

    private fun category(
        key: String,
        vararg fields: FieldDefinition,
    ) = CategoryTemplate(key = key, name = "Categorie").withDefinition(
        KeptList.made(
            listOf(FieldSection("$key.main", "Principal", fields.toList())),
            FieldSection.codec,
            FieldSection::key,
        ),
        KeptList.made(emptyList(), com.ar.dosarcusina.archive.v3.ObligationBlueprint.codec, { it.key }),
        KeptList.made(emptyList(), com.ar.dosarcusina.archive.v3.ComponentDefinition.codec, { it.key }),
        null,
    )

    private fun values(vararg pairs: Pair<String, String>) =
        KeptObject.made(FieldValues(pairs.associate { (key, text) -> key to FieldValue.Text(text) }), FieldValues.codec)

    private fun facts(vararg facts: CustomFact) = KeptList.made(facts.toList(), CustomFact.codec, CustomFact::id)

    // Every stored text is listed

    @Test
    fun everyStoredTextOfEveryModelIsWordsOrNeverWords() {
        assertEquals(Tables.all, FreeText.lists.map { it.table }, "Every model says which of its texts are words")
        for (list in FreeText.lists) {
            val words = list.freeText.map { it.name }.toSet()
            assertTrue(
                words.intersect(list.machineText).isEmpty(),
                "${list.table}: a property is words or not, never both",
            )
            val texts = list.table.kind.java.declaredFields
                .filter { !Modifier.isStatic(it.modifiers) }
                .filter { field ->
                    field.type == String::class.java ||
                        (List::class.java.isAssignableFrom(field.type) &&
                            (field.genericType as? ParameterizedType)?.actualTypeArguments?.singleOrNull()?.typeName ==
                            String::class.java.name)
                }
                .map { it.name }.toSet()
            assertEquals(texts, words + list.machineText, "${list.table}: every stored text property is listed once")
        }
    }

    // Every record's words, from any path

    @Test
    fun everyRecordsWordsAreMaskedWhereverTheyAreWritten() {
        writeEveryKindOfRecord(VISA)
        // Read from the store: what is really kept.
        val saved = binder.snapshot()
        for (list in FreeText.lists) assertNothingHeld(list, saved)
        val lake = saved.all(Tables.templates).single()
        assertEquals("Bărci $VISA_MASKED", lake.name)
        assertEquals(
            "Cod $VISA_MASKED",
            lake.keptSections.items.single().fields.single().label,
            "A category still reads after its words are masked",
        )
        assertEquals("card $VISA_MASKED.pdf", saved.all(Tables.attachments).single().fileName)
        assertEquals(listOf("mechanic", "Bărci $VISA_MASKED"), saved.all(Tables.providers).single().trades)
    }

    /** One record of every kind with [number] in each of its words, saved as one step. */
    private fun writeEveryKindOfRecord(number: String) {
        unit.perform { step ->
            val lake = step.insert(
                category("custom.boats", FieldDefinition("boat.code", "Cod $number", "text"))
                    .copy(name = "Bărci $number", summary = "Card $number"),
            )
            val boat = step.insert(Asset(name = "Barca de pe lac", templateKey = lake.key))
            step.insert(
                Obligation(
                    title = "Service $number",
                    notes = number,
                    provider = "Service $number",
                    reference = number,
                    asset = boat.pk,
                ),
            )
            val visit = step.insert(HistoryEntry(
                kindRaw = "repair",
                title = "Rotor $number",
                note = number,
                reference = number,
                asset = boat.pk,
            ))
            step.insert(
                ServiceItem(
                    name = "Rotor $number", group = number, partBrandOrCode = number, partSerialNumber = number,
                    batchOrTicket = number, locationDetail = number, notes = number, entry = visit.pk,
                ),
            )
            step.insert(MeasurementLog(
                kindRaw = "engineHours",
                name = "Ore $number",
                value = 210.0,
                source = number,
                notes = number,
                asset = boat.pk,
            ))
            step.insert(
                Provider(
                    name = "Service $number",
                    trades = listOf("mechanic", "Bărci $number"),
                    phone = number,
                    email = number,
                    address = number,
                    notes = number,
                ),
            )
            step.insert(
                Attachment(
                    fileName = "card $number.pdf", contentType = "com.adobe.pdf", title = "Card $number",
                    extractedText = "Titular EXEMPLU\nCard $number", asset = boat.pk,
                ),
            )
        }
    }

    private fun <R : Any> assertNothingHeld(list: FreeText.Lists<R>, view: BinderView) {
        for (record in view.all(list.table)) {
            assertEquals(
                emptyList<String>(),
                FreeText.holding(record, list, view),
                "${list.table} keeps no card number",
            )
        }
    }

    @Test
    fun wordsWithoutACardNumberAreKeptExactlyAsWritten() {
        // A CNP, an IBAN, a phone number, a run of 15 digits that fails the check digit, a plate.
        val texts = listOf(
            "1800101990006",
            "RO49 AAAA 1B31 0075 9384 0000",
            "0700 000 000",
            "B-123-ABC",
            "123456789012345",
        )
        val firm = unit.perform { step ->
            step.insert(Provider(name = "ENGIE Romania S.A.", notes = texts.joinToString("\n")))
        }
        assertEquals(texts.joinToString("\n"), binder.stored(firm).notes)
        assertEquals(emptyList<String>(), FreeText.holding(binder.stored(firm), FreeText.providers, binder.snapshot()))
    }

    // A section's rows, values and notes

    @Test
    fun aRowTypedUnderDateImportanteKeepsOnlyTheLastFourDigits() {
        val sealed = SecretRules.SEALED_PREFIX + "AAAA"
        val home = unit.perform { step ->
            step.insert(
                Asset(name = "Casa din exemplu", templateKey = "other").withKeptFacts(
                    facts(
                        CustomFact(UUID.randomUUID(), "Card de rezervă $VISA", VISA),
                        CustomFact(UUID.randomUUID(), "Contract apă", "EXM 0000001"),
                        CustomFact(UUID.randomUUID(), "Cod alarmă", sealed, isSecret = true),
                    ),
                ),
            )
        }
        val stored = binder.stored(home)
        assertEquals(
            listOf("Card de rezervă $VISA_MASKED", "Contract apă", "Cod alarmă"),
            stored.keptFacts.items.map { it.label },
        )
        assertEquals(
            listOf(VISA_MASKED, "EXM 0000001", sealed),
            stored.keptFacts.items.map { it.value },
            "A sealed code is the secret's own business",
        )
        assertTrue(!holdsNumber(stored.customFactsData), "Not even the stored JSON holds it")
    }

    @Test
    fun aSectionsNameNotesAndFieldsKeepNoCardNumber() {
        val card = unit.perform { step ->
            step.insert(
                Asset(name = "Card Visa $VISA", templateKey = "documents", notes = "Rezervă: $MASTERCARD")
                    .withKeptValues(values("document.cardLastFour" to VISA)),
            )
        }
        val stored = binder.stored(card)
        assertEquals("Card Visa $VISA_MASKED", stored.name)
        assertEquals("Rezervă: $MASTERCARD_MASKED", stored.notes)
        assertEquals(
            "1111",
            stored.keptValues.value["document.cardLastFour"]?.textValue,
            "The last digits field keeps only the last four",
        )

        val boat = unit.perform { step ->
            step.insert(category("custom.boats", FieldDefinition("boat.code", "Cod", "text")))
            val values = values("boat.code" to "Plătit cu $VISA")
            step.insert(Asset(name = "Barca de pe lac", templateKey = "custom.boats").withKeptValues(values))
        }
        assertEquals("Plătit cu $VISA_MASKED", binder.stored(boat).keptValues.value["boat.code"]?.textValue)
    }

    @Test
    fun ibansAndAPetsMicrochipAreKeptWholeWhereverTheyAreTyped() {
        // A pet's microchip whose digits would pass as a Maestro card: whole in its own field, and
        // in the section's notes, where its field says what those digits are. Other digits shaped
        // the same way, and a card number, are still masked there.
        val chip = withCheckDigit("642" + "0".repeat(8) + "123")
        val other = withCheckDigit("642" + "0".repeat(8) + "456")
        val pet = unit.perform { step ->
            step.insert(category("custom.pets", FieldDefinition("pet.chip", "Microcip", "microchip")))
            step.insert(
                Asset(
                    name = "Motănelul din exemplu",
                    templateKey = "custom.pets",
                    notes = "Cip $chip\nAlt cip $other\nCard $VISA",
                )
                    .withKeptValues(values("pet.chip" to chip)),
            )
        }
        val stored = binder.stored(pet)
        assertEquals(chip, stored.keptValues.value["pet.chip"]?.textValue)
        assertEquals("Cip $chip\nAlt cip •••• ${other.takeLast(4)}\nCard $VISA_MASKED", stored.notes)

        // What the pet's other records say keeps it whole too: its visits, the text read off its documents.
        val visit = unit.perform { step ->
            step.insert(HistoryEntry(title = "Vaccin", note = "Cip $chip", asset = pet.pk))
        }
        assertEquals("Cip $chip", binder.stored(visit).note)

        // An IBAN field of one's own whose account is the test card number: it passes its own check.
        val iban = "RO49 AAAA 1B31 0075 9384 0000"
        val flat = unit.perform { step ->
            step.insert(category("custom.rent", FieldDefinition("rent.iban", "IBAN", "iban")))
            val values = values("rent.iban" to iban)
            step.insert(Asset(name = "Apartament", templateKey = "custom.rent").withKeptValues(values))
        }
        assertEquals(iban, binder.stored(flat).keptValues.value["rent.iban"]?.textValue)
    }

    // A backup brought in

    @Test
    fun aBackupBringsNoCardNumberIn() {
        val target = binder.target
        DossierArchiveService(
            target,
            Catalog.builtIn,
            clock = Clock.fixed(moment("2026-11-26T10:00:00Z"), ZoneOffset.UTC),
            zone = { ZoneId.of("Europe/Bucharest") },
        )
            .importArchive(
                MemoryByteSource(fixtureArchive("dosar-v3/household")),
                mode = ArchiveImportMode.REPLACE,
                staging = staging,
            )
        val asset = target.snapshot().assets.first()
        // A record as a phone from before kept it, card number and all, written again by an import.
        target.apply(BinderChanges(Binder(assets = listOf(asset.copy(notes = "Card $VISA"))), Removed(), emptyMap()))
        assertEquals("Card $VISA_MASKED", target.snapshot().assets.first { it.id == asset.id }.notes)
    }
}
