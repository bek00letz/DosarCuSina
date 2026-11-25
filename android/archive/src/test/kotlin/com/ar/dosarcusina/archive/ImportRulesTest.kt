// The archives here are written out as JSON, a record to a line or two, as the format shows them.
@file:Suppress("MaxLineLength")

package com.ar.dosarcusina.archive

import com.ar.dosarcusina.archive.binder.Binder
import com.ar.dosarcusina.archive.v3.ArchiveFiles
import com.ar.dosarcusina.archive.v3.AssetRecord
import com.ar.dosarcusina.archive.v3.ChangeTime
import com.ar.dosarcusina.archive.v3.DossierPackage
import com.ar.dosarcusina.archive.v3.FieldValue
import com.ar.dosarcusina.archive.v3.IssuerLessonRecord
import com.ar.dosarcusina.archive.v3.Manifest
import com.ar.dosarcusina.archive.v3.ProviderRecord
import com.ar.dosarcusina.archive.v3.TemplateRecord
import com.ar.dosarcusina.core.values.MachineText
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertFalse
import org.junit.jupiter.api.Assertions.assertNull
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test
import org.junit.jupiter.params.ParameterizedTest
import org.junit.jupiter.params.provider.EnumSource
import java.time.Instant
import java.time.ZoneOffset
import java.util.UUID

/**
 * The importer's decisions, one rule at a time, as the iOS `ArchiveMergeTests`, `BackupRulesTests`,
 * `LocalSecretsKeptTests`, `FirmCopiesTests`, `SectionLocksTests` and `ParentChildTests` pin them.
 */
class ImportRulesTest {
    private val now: Instant = moment("2026-11-26T10:00:00Z")

    private val person = "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaa01"
    private val card = "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaa02"
    private val sealedPin = "sealed:v1:AAAA"

    private val categories = """
        [{"key": "member", "name": "Persoane", "symbol": "person", "tint": "blue", "heroStyle": "standard", "isBuiltIn": true,
          "version": 27, "homeOrder": 0, "isOnHome": true, "isSensitive": false, "sections": [], "blueprints": [],
          "createdAt": "2026-01-01T00:00:00Z", "updatedAt": "0001-01-01T00:00:00Z"},
         {"key": "documents", "name": "Acte", "symbol": "doc", "tint": "blue", "heroStyle": "document", "isBuiltIn": true,
          "version": 27, "homeOrder": 1, "isOnHome": true, "isSensitive": true,
          "sections": [{"key": "main", "title": "Act", "fields": [
             {"key": "document.type", "label": "Tip", "type": "choice", "isEssential": true, "isSensitive": false,
              "options": [{"key": "documentType.idCard", "label": "Carte de identitate", "aliases": ["Buletin"]}, "Pașaport"]},
             {"key": "document.pinAuthentication", "label": "PIN", "type": "secret", "isEssential": false, "isSensitive": true,
              "appliesWhen": {"field": "document.type", "oneOf": ["documentType.idCard"]}}]}],
          "blueprints": [], "createdAt": "2026-01-01T00:00:00Z", "updatedAt": "0001-01-01T00:00:00Z"}]
    """

    private fun assets(cardUpdated: String = "2026-11-01T00:00:00Z", parentOfPerson: String? = null, cardType: String = "documentType.idCard") = """
        [{"id": "$person", "templateKey": "member", "name": "Ana", "values": {}, "isExample": false,
          ${parentOfPerson?.let { "\"parentId\": \"$it\"," } ?: ""}
          "createdAt": "2026-01-01T00:00:00Z", "updatedAt": "$cardUpdated"},
         {"id": "$card", "templateKey": "documents", "name": "Carte de identitate – Ana", "parentId": "$person", "isExample": false,
          "values": {"document.type": {"type": "text", "value": "$cardType"}, "document.number": {"type": "text", "value": "XX123456"}},
          "customFacts": [{"id": "bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbb01", "label": "Număr contract", "value": "123"}],
          "createdAt": "2026-01-01T00:00:00Z", "updatedAt": "$cardUpdated"}]
    """

    private fun pack(
        templates: String = categories,
        assets: String = assets(),
        providers: String = "[]",
        lessons: String = "[]",
    ) = DossierPackage(
        manifest = Manifest(
            "com.ar.dosarcusina.dossier", 3, "1.0", "iOS", now, Manifest.Counts(0, 0, 0, 0, 0, 0, 0, 0), emptyMap(),
        ),
        templates = records(templates, TemplateRecord::read),
        assets = records(assets, AssetRecord::read),
        obligations = emptyList(), historyEntries = emptyList(), serviceItems = emptyList(),
        providers = records(providers, ProviderRecord::read), measurements = emptyList(), attachments = emptyList(),
        issuerLessons = records(lessons, IssuerLessonRecord::read),
        files = ArchiveFiles.EMPTY,
    )

    private fun <T> records(json: String, read: (kotlinx.serialization.json.JsonElement) -> T): List<T> =
        (MachineText.parse(json) as kotlinx.serialization.json.JsonArray).map(read)

    private fun import(binder: InMemoryBinder, pack: DossierPackage, mode: ArchiveImportMode): ArchiveImportResult {
        val plan = DossierImporter(pack, binder.snapshot(), mode, now, ZoneOffset.UTC).run()
        binder.apply(plan.changes)
        return plan.result
    }

    /** A binder holding the household, with the card's PIN and a secret row sealed on this phone. */
    private fun householdWithSecrets(): InMemoryBinder {
        val binder = InMemoryBinder()
        import(binder, pack(), ArchiveImportMode.REPLACE)
        val home = binder.binder
        val cardId = UUID.fromString(card)
        val secretRow = """[{"id": "bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbb09", "label": "Cod alarmă", "value": "$sealedPin", "isSecret": true}]"""
        val withSecrets = home.assets.map { asset ->
            if (asset.id != cardId) return@map asset
            val values = asset.values.replacingValue(asset.values.value.with("document.pinAuthentication", FieldValue.Text(sealedPin)))
            val rows = com.ar.dosarcusina.core.values.KeptList.read(
                MachineText.parse(secretRow), com.ar.dosarcusina.archive.v3.CustomFact.codec, com.ar.dosarcusina.archive.v3.CustomFact::id,
            )
            asset.copy(values = values, customFacts = asset.customFacts.replacingEntries(rows))
        }
        return InMemoryBinder(home.copy(assets = withSecrets))
    }

    @Test
    fun theRuleIsTheSameForEveryRecord() {
        val earlier = moment("2026-01-01T12:00:00Z")
        val later = moment("2026-02-01T12:00:00Z")
        assertEquals(ArchiveMerge.Outcome.INSERT, ArchiveMerge.outcome(later, null))
        assertEquals(ArchiveMerge.Outcome.UPDATE, ArchiveMerge.outcome(later, earlier))
        assertEquals(ArchiveMerge.Outcome.KEEP_HERE, ArchiveMerge.outcome(earlier, later))
        assertEquals(ArchiveMerge.Outcome.KEEP_HERE, ArchiveMerge.outcome(later, later), "On a tie the phone's own copy stays")
        assertEquals(ArchiveMerge.Outcome.KEEP_HERE, ArchiveMerge.outcome(ChangeTime.UNKNOWN, ChangeTime.UNKNOWN))
        assertEquals(ArchiveMerge.Outcome.UPDATE, ArchiveMerge.outcome(earlier, ChangeTime.UNKNOWN), "Any change is newer than an unknown time")
        assertEquals(ArchiveMerge.Outcome.UPDATE, ArchiveMerge.outcome(earlier, later, ArchiveImportMode.REPLACE))
    }

    @ParameterizedTest
    @EnumSource(ArchiveImportMode::class)
    fun replacingOrMergingKeepsThePinsAndSecretRowsThisPhoneHas(mode: ArchiveImportMode) {
        val binder = householdWithSecrets()
        // The backup's copy is the newer one, so a merge takes its values too.
        import(binder, pack(assets = assets(cardUpdated = "2026-11-20T00:00:00Z")), mode)
        val card = binder.binder.assets.first { it.id == UUID.fromString(card) }
        assertEquals(FieldValue.Text(sealedPin), card.values.value["document.pinAuthentication"])
        assertEquals(setOf("Număr contract", "Cod alarmă"), card.customFacts.items.map { it.label }.toSet())
    }

    @Test
    fun aKeptPinGoesWhenItsFieldNoLongerApplies() {
        val binder = householdWithSecrets()
        import(binder, pack(assets = assets(cardUpdated = "2026-11-20T00:00:00Z", cardType = "Pașaport")), ArchiveImportMode.MERGE)
        val card = binder.binder.assets.first { it.id == UUID.fromString(card) }
        assertNull(card.values.value["document.pinAuthentication"], "A PIN goes when the card became a passport")
    }

    @Test
    fun anArchiveNeverBringsASecretAndNeverWritesOne() {
        val incoming = assets().replace(
            "\"document.number\"",
            "\"document.pinAuthentication\": {\"type\": \"text\", \"value\": \"0000\"}, \"note\": {\"type\": \"text\", \"value\": \"$sealedPin\"}, \"document.number\"",
        )
        val binder = InMemoryBinder()
        import(binder, pack(assets = incoming), ArchiveImportMode.REPLACE)
        val card = binder.binder.assets.first { it.id == UUID.fromString(card) }
        assertNull(card.values.value["document.pinAuthentication"], "A secret field's value from an archive is never read")
        assertNull(card.values.value["note"], "A sealed value is a secret wherever it sits")

        val written = ArchiveRecords.of(householdWithSecrets().binder, ZoneOffset.UTC)
        val text = written.assets.joinToString { MachineText.json(it.toJson()) }
        assertFalse(text.contains(SecretRules.SEALED_PREFIX), "Nothing sealed is written")
        assertFalse(text.contains("Cod alarmă"), "A secret row is left out")
        assertTrue(text.contains("Număr contract"))
    }

    @Test
    fun choiceTextBecomesItsOptionsKey() {
        val binder = InMemoryBinder()
        import(binder, pack(assets = assets(cardType = "buletin")), ArchiveImportMode.REPLACE)
        val card = binder.binder.assets.first { it.id == UUID.fromString(card) }
        assertEquals(FieldValue.Text("documentType.idCard"), card.values.value["document.type"])
    }

    @ParameterizedTest
    @EnumSource(ArchiveImportMode::class)
    fun aLockIsNeverMadeWeaker(mode: ArchiveImportMode) {
        val binder = InMemoryBinder()
        import(binder, pack(), ArchiveImportMode.REPLACE)
        assertEquals(true, binder.binder.locks["documents"])
        val unlocked = categories.replace("\"isSensitive\": true", "\"isSensitive\": false")
            .replace("\"type\": \"secret\"", "\"type\": \"text\"")
            .replace("\"updatedAt\": \"0001-01-01T00:00:00Z\"", "\"updatedAt\": \"2099-01-01T00:00:00Z\"")
        import(binder, pack(templates = unlocked), mode)
        assertEquals(true, binder.binder.locks["documents"], "The lock this phone had stays on")
        val documents = binder.binder.templates.first { it.key == "documents" }
        val pin = documents.sections.items.flatMap { it.fields }.first { it.key == "document.pinAuthentication" }
        assertEquals("secret", pin.type, "A field secret here stays secret")
        assertTrue(pin.isSensitive)
        assertEquals(now, documents.updatedAt, "No record's last change is later than now")
    }

    @Test
    fun aLockFromTheArchiveIsKept() {
        val binder = InMemoryBinder()
        import(binder, pack(), ArchiveImportMode.REPLACE)
        assertEquals(false, binder.binder.locks["member"])
        // The phone's copy stays (same change time), but the backup's lock still locks it.
        import(binder, pack(templates = categories.replaceFirst("\"isSensitive\": false", "\"isSensitive\": true")), ArchiveImportMode.MERGE)
        assertEquals(true, binder.binder.locks["member"])
    }

    @ParameterizedTest
    @EnumSource(ArchiveImportMode::class)
    fun sectionsFiledUnderEachOtherStayVisible(mode: ArchiveImportMode) {
        val binder = InMemoryBinder()
        import(binder, pack(), ArchiveImportMode.REPLACE)
        val result =
            import(binder, pack(assets = assets(cardUpdated = "2026-11-25T00:00:00Z", parentOfPerson = card)), mode)
        assertEquals(1, result.movedToTop)
        val parents = binder.binder.assets.associate { it.id to it.parentId }
        for (start in parents.keys) {
            val seen = HashSet<UUID>()
            var current: UUID? = start
            while (current != null) {
                assertTrue(seen.add(current), "Nothing is filed under itself")
                current = parents[current]
            }
        }
    }

    @Test
    fun aParentThatIsMissingLeavesTheSectionAtTheTop() {
        val binder = InMemoryBinder()
        val result = import(binder, pack(assets = assets().replace("\"parentId\": \"$person\"", "\"parentId\": \"${UUID.randomUUID()}\"")), ArchiveImportMode.REPLACE)
        assertEquals(1, result.movedToTop)
        assertNull(binder.binder.assets.first { it.id == UUID.fromString(card) }.parentId)
    }

    @Test
    fun replacingEverythingRemovesWhatTheArchiveLacksAndKeepsTheRestInPlace() {
        val binder = InMemoryBinder()
        import(binder, pack(), ArchiveImportMode.REPLACE)
        val onlyHere = binder.binder.assets.first().copy(id = UUID.randomUUID(), name = "Doar aici", parentId = null)
        val here = InMemoryBinder(binder.binder.copy(assets = binder.binder.assets + onlyHere))
        val result = import(here, pack(), ArchiveImportMode.REPLACE)
        assertEquals(0, result.inserted)
        assertEquals(setOf("Ana", "Carte de identitate – Ana"), here.binder.assets.map { it.name }.toSet())
    }

    @Test
    fun aNewerCopyHereTakesWhatOnlyTheBackupKnows() {
        val firm = """[{"id": "cccccccc-cccc-4ccc-8ccc-cccccccccc01", "name": "Service Exemplu", "trades": ["mechanic"],
            "phone": "0700 000 001", "email": null, "assetIds": ["$card"], "isExample": false, "taxID": "RO012345678",
            "createdAt": "2026-01-01T00:00:00Z", "updatedAt": "UPDATED"}]"""
        val binder = InMemoryBinder()
        import(binder, pack(providers = firm.replace("UPDATED", "2026-01-01T00:00:00Z")), ArchiveImportMode.REPLACE)
        assertEquals("12345678", binder.binder.providers.single().taxID, "A CUI is kept as its digits")
        val phoneCopy = binder.binder.providers.single().copy(
            phone = null, email = "nume@exemplu.ro", trades = listOf("tyreShop"), assetIds = listOf(UUID.fromString(person)),
            updatedAt = moment("2026-10-01T00:00:00Z"),
        )
        val here = InMemoryBinder(binder.binder.copy(providers = listOf(phoneCopy)))
        import(here, pack(providers = firm.replace("UPDATED", "2026-02-01T00:00:00Z")), ArchiveImportMode.MERGE)
        val joined = here.binder.providers.single()
        assertEquals("nume@exemplu.ro", joined.email, "The newer copy's details stand")
        assertEquals("0700 000 001", joined.phone, "What only the backup knows comes along")
        assertEquals(listOf("mechanic", "tyreShop"), joined.trades)
        assertEquals(setOf(UUID.fromString(person), UUID.fromString(card)), joined.assetIds.toSet())
        assertEquals(moment("2026-10-01T00:00:00Z"), joined.updatedAt, "Joining gives no change time")
    }

    @Test
    fun lessonsThatAreNoLabelOrContradictEachOtherStayOut() {
        fun lesson(id: Int, field: String, label: String) =
            """{"id": "dddddddd-dddd-4ddd-8ddd-ddddddddddd$id", "issuerKey": "name:ENGIEROMANIASA",
            "issuerName": "ENGIE Romania S.A.", "kind": "utilityInvoice", "field": "$field", "label": "$label",
            "createdAt": "2026-01-01T00:00:00Z", "updatedAt": "2026-01-01T00:00:00Z"}"""
        val binder = InMemoryBinder()
        val lessons = "[${lesson(1, "dueDate", "Ultima zi de plată")}, ${lesson(2, "total", "Total de plată")}, " +
            "${lesson(3, "issueDate", "Total de plată")}, ${lesson(4, "total", "Cod 1234")}]"
        import(binder, pack(lessons = lessons), ArchiveImportMode.REPLACE)
        assertEquals(listOf("Ultima zi de plată"), binder.binder.issuerLessons.map { it.label })
    }

    @Test
    fun aCategoryOfOnesOwnTakesItsOwnNameForItsSections() {
        val own = """[{"key": "custom.eeeeeeee-eeee-4eee-8eee-eeeeeeeeee01", "name": "Bărci", "symbol": "sailboat", "tint": "teal",
            "heroStyle": "standard", "isBuiltIn": false, "version": 3, "homeOrder": 5, "isOnHome": true, "isSensitive": false,
            "sections": [], "blueprints": [], "behavior": {"box": "perSection", "singular": {"name": "Barca", "gender": "feminine"}},
            "createdAt": "2026-01-01T00:00:00Z", "updatedAt": "2026-01-01T00:00:00Z"}]"""
        val binder = InMemoryBinder(Binder())
        import(binder, pack(templates = own, assets = "[]"), ArchiveImportMode.REPLACE)
        val boats = binder.binder.templates.single()
        assertNull(boats.behavior!!.value.singular)
        assertFalse(MachineText.json(boats.behavior.json).contains("singular"))
        assertEquals(0, boats.version, "A category of one's own has no catalog version")
        assertEquals(listOf("upcoming", "documents", "history", "people", "money", "keyFacts"), boats.pockets)
    }
}
