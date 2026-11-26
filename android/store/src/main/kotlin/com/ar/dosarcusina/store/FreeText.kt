package com.ar.dosarcusina.store

import com.ar.dosarcusina.archive.SecretRules
import com.ar.dosarcusina.archive.v3.CustomFact
import com.ar.dosarcusina.archive.v3.FieldValue
import com.ar.dosarcusina.archive.v3.FieldValues
import com.ar.dosarcusina.core.text.FreeTextMasking
import com.ar.dosarcusina.core.text.PaymentCardNumbers
import com.ar.dosarcusina.core.text.PaymentCardNumbers.KeptWhole
import com.ar.dosarcusina.core.values.KeptList
import com.ar.dosarcusina.core.values.MachineText
import com.ar.dosarcusina.store.schema.Asset
import com.ar.dosarcusina.store.schema.Attachment
import com.ar.dosarcusina.store.schema.AttachmentPage
import com.ar.dosarcusina.store.schema.CategoryTemplate
import com.ar.dosarcusina.store.schema.HistoryEntry
import com.ar.dosarcusina.store.schema.IssuerLesson
import com.ar.dosarcusina.store.schema.MeasurementLog
import com.ar.dosarcusina.store.schema.Obligation
import com.ar.dosarcusina.store.schema.Provider
import com.ar.dosarcusina.store.schema.ServiceItem
import com.ar.dosarcusina.store.schema.keptFacts
import com.ar.dosarcusina.store.schema.keptSections
import com.ar.dosarcusina.store.schema.keptValues
import com.ar.dosarcusina.store.schema.withKeptFacts
import com.ar.dosarcusina.store.schema.withKeptValues
import kotlinx.serialization.json.JsonElement

/**
 * One stored property of a kind of record that holds words: what a person typed or a reader read
 * (a name, a note, a section's values, its rows under Date importante, a document's text), as
 * opposed to ids, keys, hashes, content types and pictures, as the iOS app's `FreeTextProperty`.
 * [mask] gives the record with every card number in it masked, or null when it holds none; what
 * the record's section keeps whole ([FreeText.Words.keptWhole]) is read only when something would be.
 */
class FreeTextProperty<R : Any> internal constructor(
    val name: String,
    internal val mask: (R, FreeText.Words) -> R?,
)

/**
 * A bank card's full number is never kept in the binder, whoever wrote it and from wherever: a
 * row typed under Date importante, a note, a visit's title, a firm's address, a document's text,
 * a backup brought in. The unit of work masks every card number in the words of every record it
 * saves, just before it saves, by the one rule (`PaymentCardNumbers`, `FreeTextMasking`): only
 * the last four digits stay ("•••• 1111"). Every save goes through the unit of work and every
 * stored text is listed ([lists], pinned by `FreeTextTest`), so a new action or a new column
 * can't go around it, as the iOS app's `FreeText` (ios/DosarCuSina/Services/Persistence/FreeText.swift).
 *
 * A secret (a PIN, a code row) is sealed before it is saved and masked first; its sealed text is
 * never rewritten here ([SecretRules.isSealed]).
 */
// One rule for each kind of words, and the lists of the schema's ten models.
@Suppress("TooManyFunctions")
object FreeText {
    /**
     * Which stored texts of a kind of record are words, and which never are (ids, keys, raw
     * choices, digests, the app's own JSON).
     */
    class Lists<R : Any> internal constructor(
        val table: Table<R>,
        val freeText: List<FreeTextProperty<R>>,
        val machineText: Set<String>,
        /** What its words keep whole: the digits its section's own typed values hold, such as a pet's microchip. */
        internal val keptWhole: (R, BinderView) -> KeptWhole,
        /** The fields of its category, for a section's values: key and type, in order. */
        internal val fields: (R, BinderView) -> List<PaymentCardNumbers.TypedField> = { _, _ -> emptyList() },
    ) {
        internal fun words(record: R, view: BinderView) = Words({ keptWhole(record, view) }, { fields(record, view) })
    }

    /** What a mask reads beside a record's words, each read once and only when something would be masked. */
    class Words internal constructor(keptWhole: () -> KeptWhole, fields: () -> List<PaymentCardNumbers.TypedField>) {
        /** What the record's section keeps whole. */
        val keptWhole: KeptWhole by lazy(keptWhole)

        /** The fields of the section's category, by key and type. */
        val fields: List<PaymentCardNumbers.TypedField> by lazy(fields)
    }

    /** Masks every card number in the words of every record [step] is about to save. */
    internal fun mask(step: Step) {
        for (list in lists) mask(step, list)
    }

    private fun <R : Any> mask(step: Step, list: Lists<R>) {
        for (record in step.changes(list.table).saved) {
            val masked = masked(record, list, step)
            if (masked != record) step.update(masked)
        }
    }

    /** [record] with every card number in its words masked. */
    fun <R : Any> masked(record: R, list: Lists<R>, view: BinderView): R {
        var result = record
        for (property in list.freeText) property.mask(result, list.words(result, view))?.let { result = it }
        return result
    }

    /** The names of the properties of [record] that hold a card number. */
    fun <R : Any> holding(record: R, list: Lists<R>, view: BinderView): List<String> =
        list.freeText.filter { it.mask(record, list.words(record, view)) != null }.map { it.name }

    // The kinds of words

    private fun <R : Any> text(name: String, get: (R) -> String?, set: (R, String) -> R) =
        FreeTextProperty<R>(name) { record, words ->
            get(record)?.let { FreeTextMasking.masked(it) { words.keptWhole } }?.let { set(record, it) }
        }

    private fun <R : Any> texts(name: String, get: (R) -> List<String>, set: (R, List<String>) -> R) =
        FreeTextProperty<R>(name) { record, words ->
            FreeTextMasking.masked(get(record)) { words.keptWhole }?.let { set(record, it) }
        }

    /**
     * JSON with words inside: every string in it, sealed codes left alone, written again only when
     * something was masked.
     */
    private fun <R : Any> json(name: String, get: (R) -> String?, set: (R, String) -> R) =
        FreeTextProperty<R>(name) { record, _ ->
            val raw = get(record)?.let(MachineText::parseOrNull)
            raw?.let { FreeTextMasking.masked(it, SecretRules::isSealed) }?.let { set(record, MachineText.json(it)) }
        }

    /**
     * A section's values by the rule for fields (`PaymentCardNumbers.sanitizing`): a bank card's
     * last digits cut to four, sealed codes left alone, a value its own field type tells apart
     * from a card (an IBAN, a microchip) kept whole; what a newer build wrote is masked too, and kept.
     */
    private val values = FreeTextProperty<Asset>("valuesData") { asset, words ->
        if (asset.valuesData == null) return@FreeTextProperty null
        val kept = asset.keptValues
        val changes = PaymentCardNumbers.sanitizing(texts(kept.value), { words.fields }, SecretRules::isSealed)
        var values: FieldValues = kept.value.mappingUnreadable(::redacting)
        for ((key, text) in changes) values = values.with(key, text?.let(FieldValue::Text))
        val masked = kept.replacingValue(values).mappingKept(::redacting)
        if (masked == kept) null else asset.withKeptValues(masked)
    }

    /**
     * Rows under Date importante, labels and values, with the rows a newer build wrote: a secret
     * row's sealed code is left alone, and what the section keeps whole stays. Checked first with
     * nothing kept whole, so what the section keeps is read only when something would be masked.
     */
    private val facts = FreeTextProperty<Asset>("customFactsData") { asset, words ->
        if (asset.customFactsData == null) return@FreeTextProperty null
        val facts = asset.keptFacts
        if (maskedFacts(facts, KeptWhole.NOTHING) == facts) return@FreeTextProperty null
        val masked = maskedFacts(facts, words.keptWhole)
        if (masked == facts) null else asset.withKeptFacts(masked)
    }

    private fun maskedFacts(facts: KeptList<CustomFact>, kept: KeptWhole): KeptList<CustomFact> {
        val masked = facts.items.map { fact ->
            fact.copy(
                label = PaymentCardNumbers.redact(fact.label, keeping = kept),
                value = if (SecretRules.isSealed(fact.value)) {
                    fact.value
                } else {
                    PaymentCardNumbers.redact(fact.value, keeping = kept)
                },
            )
        }
        return facts.replacingItems(masked).mappingKept(::redacting)
    }

    /** Raw JSON a newer build wrote, its strings masked, sealed codes left alone. */
    private fun redacting(raw: JsonElement): JsonElement = PaymentCardNumbers.redacting(raw, SecretRules::isSealed)

    /** A section's text values by key, sealed ones included. */
    private fun texts(values: FieldValues): Map<String, String> =
        values.storage.mapNotNull { (key, value) -> value.textValue?.let { key to it } }.toMap()

    /** The fields [asset]'s category defines, so a value its own type tells apart from a card number stays whole. */
    internal fun fields(asset: Asset, view: BinderView): List<PaymentCardNumbers.TypedField> {
        val template = view.all(Tables.templates).firstOrNull { it.key == asset.templateKey } ?: return emptyList()
        return template.keptSections.items.flatMap { it.fields }.map { PaymentCardNumbers.TypedField(it.key, it.type) }
    }

    /** What a section keeps whole: its text values, through its category's fields. */
    internal fun keptWhole(asset: Asset, view: BinderView): KeptWhole {
        return KeptWhole.of(texts(asset.keptValues.value), fields(asset, view))
    }

    private fun sectionKept(asset: Long?, view: BinderView): KeptWhole =
        asset?.let { view.row(Tables.assets, it) }?.let { keptWhole(it, view) } ?: KeptWhole.NOTHING

    /** The section a document is filed in: its own, else its deadline's, its record's, its part's or its reading's. */
    internal fun section(of: Attachment, view: BinderView): Long? =
        of.asset
            ?: of.obligation?.let { view.row(Tables.obligations, it) }?.asset
            ?: of.historyEntry?.let { view.row(Tables.history, it) }?.asset
            ?: of.serviceItem?.let { view.row(Tables.items, it) }?.entry?.let { view.row(Tables.history, it) }?.asset
            ?: of.measurement?.let { view.row(Tables.readings, it) }?.asset

    // The schema's words

    val assets: Lists<Asset> = Lists(
        table = Tables.assets,
        freeText = listOf(
            text("name", { it.name }) { r, v -> r.copy(name = v) },
            text("notes", { it.notes }) { r, v -> r.copy(notes = v) },
            values,
            facts,
        ),
        machineText = setOf("templateKey", "symbolOverride", "tintOverrideRaw", "photoData"),
        keptWhole = ::keptWhole,
        fields = ::fields,
    )

    val obligations: Lists<Obligation> = Lists(
        table = Tables.obligations,
        // A recurrence and the reminders are the app's own words, but what a newer build wrote inside them may not be.
        freeText = listOf(
            text("title", { it.title }) { r, v -> r.copy(title = v) },
            text("notes", { it.notes }) { r, v -> r.copy(notes = v) },
            text("provider", { it.provider }) { r, v -> r.copy(provider = v) },
            text("reference", { it.reference }) { r, v -> r.copy(reference = v) },
            json("recurrenceData", { it.recurrenceData }) { r, v -> r.copy(recurrenceData = v) },
            json("remindersData", { it.remindersData }) { r, v -> r.copy(remindersData = v) },
        ),
        machineText = setOf(
            "blueprintKey", "kindRaw", "dueDayISO", "consequenceRaw", "estimatedCostCurrency", "statusRaw",
            "snoozedUntilISO",
        ),
        keptWhole = { record, view -> sectionKept(record.asset, view) },
    )

    val history: Lists<HistoryEntry> = Lists(
        table = Tables.history,
        freeText = listOf(
            text("title", { it.title }) { r, v -> r.copy(title = v) },
            text("note", { it.note }) { r, v -> r.copy(note = v) },
            text("reference", { it.reference }) { r, v -> r.copy(reference = v) },
        ),
        machineText = setOf("kindRaw", "totalCostCurrency", "cycleDueDayISO", "nextDueDayISO", "previousStatusRaw"),
        keptWhole = { record, view -> sectionKept(record.asset, view) },
    )

    val items: Lists<ServiceItem> = Lists(
        table = Tables.items,
        freeText = listOf(
            text("name", { it.name }) { r, v -> r.copy(name = v) },
            text("group", { it.group }) { r, v -> r.copy(group = v) },
            text("partBrandOrCode", { it.partBrandOrCode }) { r, v -> r.copy(partBrandOrCode = v) },
            text("partSerialNumber", { it.partSerialNumber }) { r, v -> r.copy(partSerialNumber = v) },
            text("batchOrTicket", { it.batchOrTicket }) { r, v -> r.copy(batchOrTicket = v) },
            text("locationDetail", { it.locationDetail }) { r, v -> r.copy(locationDetail = v) },
            text("notes", { it.notes }) { r, v -> r.copy(notes = v) },
        ),
        machineText = setOf("componentKey", "currency"),
        keptWhole = { record, view -> sectionKept(record.entry?.let { view.row(Tables.history, it) }?.asset, view) },
    )

    val readings: Lists<MeasurementLog> = Lists(
        table = Tables.readings,
        freeText = listOf(
            text("name", { it.name }) { r, v -> r.copy(name = v) },
            text("source", { it.source }) { r, v -> r.copy(source = v) },
            text("notes", { it.notes }) { r, v -> r.copy(notes = v) },
        ),
        machineText = setOf("kindRaw", "unit", "unitPriceCurrency", "basisRaw"),
        keptWhole = { record, view -> sectionKept(record.asset, view) },
    )

    val attachments: Lists<Attachment> = Lists(
        table = Tables.attachments,
        // A framing is numbers, but what a newer build wrote inside it may not be.
        freeText = listOf(
            text("title", { it.title }) { r, v -> r.copy(title = v) },
            text("fileName", { it.fileName }) { r, v -> r.copy(fileName = v) },
            text("extractedText", { it.extractedText }) { r, v -> r.copy(extractedText = v) },
            json("framingData", { it.framingData }) { r, v -> r.copy(framingData = v) },
        ),
        machineText = setOf(
            "kindRaw", "contentType", "fileData", "thumbnailData", "sha256", "documentDayISO", "validUntilISO",
            "documentID",
        ),
        keptWhole = { record, view -> sectionKept(section(record, view), view) },
    )

    val pages: Lists<AttachmentPage> = Lists(
        table = Tables.pages,
        freeText = emptyList(),
        machineText = setOf("imageData"),
        keptWhole = { _, _ -> KeptWhole.NOTHING },
    )

    val providers: Lists<Provider> = Lists(
        table = Tables.providers,
        freeText = listOf(
            text("name", { it.name }) { r, v -> r.copy(name = v) },
            texts("trades", { it.trades }) { r, v -> r.copy(trades = v) },
            text("phone", { it.phone }) { r, v -> r.copy(phone = v) },
            text("email", { it.email }) { r, v -> r.copy(email = v) },
            text("address", { it.address }) { r, v -> r.copy(address = v) },
            text("notes", { it.notes }) { r, v -> r.copy(notes = v) },
        ),
        // A tax ID is a CUI, digits only and at most ten of them.
        machineText = setOf("contactIdentifier", "taxID"),
        keptWhole = { _, _ -> KeptWhole.NOTHING },
    )

    val lessons: Lists<IssuerLesson> = Lists(
        table = Tables.lessons,
        // The issuer's name and the label are words, though a lesson keeps no digits of a label.
        freeText = listOf(
            text("issuerName", { it.issuerName }) { r, v -> r.copy(issuerName = v) },
            text("label", { it.label }) { r, v -> r.copy(label = v) },
        ),
        machineText = setOf("issuerKey", "kindRaw", "fieldKey", "categoryKey"),
        keptWhole = { _, _ -> KeptWhole.NOTHING },
    )

    val templates: Lists<CategoryTemplate> = Lists(
        table = Tables.templates,
        freeText = listOf(
            text("name", { it.name }) { r, v -> r.copy(name = v) },
            text("summary", { it.summary }) { r, v -> r.copy(summary = v) },
            json("sectionsData", { it.sectionsData }) { r, v -> r.copy(sectionsData = v) },
            json("blueprintsData", { it.blueprintsData }) { r, v -> r.copy(blueprintsData = v) },
            json("componentsData", { it.componentsData }) { r, v -> r.copy(componentsData = v) },
            json("behaviorData", { it.behaviorData }) { r, v -> r.copy(behaviorData = v) },
        ),
        machineText = setOf("key", "symbol", "tintRaw", "heroStyleRaw", "pocketsRaw", "boxGroupingRaw"),
        keptWhole = { _, _ -> KeptWhole.NOTHING },
    )

    /** Every kind of record's lists, in the iOS schema's order. */
    val lists: List<Lists<*>> =
        listOf(templates, assets, obligations, history, items, readings, attachments, pages, providers, lessons)
}
