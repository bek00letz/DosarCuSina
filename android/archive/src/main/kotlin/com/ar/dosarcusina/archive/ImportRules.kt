package com.ar.dosarcusina.archive

import com.ar.dosarcusina.archive.binder.BinderProvider
import com.ar.dosarcusina.archive.v3.FieldDefinition
import com.ar.dosarcusina.archive.v3.FieldValue
import com.ar.dosarcusina.archive.v3.FieldValues
import com.ar.dosarcusina.archive.v3.ProviderRecord
import com.ar.dosarcusina.core.values.RomanianText
import java.time.Instant
import java.util.UUID

// The rules an import shares with the rest of the iOS app, each ported as one small rule, so the
// importer reads as DossierImporter.swift does. Phase 2 moves each beside its own job (the
// category store, the firms, capture's lessons) when those come to Android.

/**
 * "Adaugă" keeps the phone's records and takes the archive's newer copies; "Înlocuiește tot" replaces the binder with
 * the archive, in place.
 */
enum class ArchiveImportMode { MERGE, REPLACE }

/** What an import did, record by record. */
data class ArchiveImportResult(
    val inserted: Int = 0,
    val updated: Int = 0,
    val skipped: Int = 0,
    /** Sections whose place in the archive couldn't be used (filed under themselves, or under something missing). */
    val movedToTop: Int = 0,
)

/**
 * The one rule an import follows for a record that is both on the phone and in the archive,
 * whatever its type, as the iOS app's `ArchiveMerge`: the archive's copy replaces the phone's
 * only when it changed later. A change time a record doesn't carry is unknown, older than any
 * change; on a tie the phone's own copy stays. "Înlocuiește tot" writes the archive's copy over
 * the phone's, whenever it changed, on the same record.
 */
object ArchiveMerge {
    enum class Outcome {
        /** Not on the phone: the archive's copy is added. */
        INSERT,

        /** The archive's copy changed later: it replaces the phone's. */
        UPDATE,

        /** The phone's copy is as new or newer: it stays. */
        KEEP_HERE,
    }

    fun outcome(archive: Instant, here: Instant?, mode: ArchiveImportMode = ArchiveImportMode.MERGE): Outcome = when {
        here == null -> Outcome.INSERT
        mode == ArchiveImportMode.REPLACE -> Outcome.UPDATE
        archive > here -> Outcome.UPDATE
        else -> Outcome.KEEP_HERE
    }
}

/**
 * A category's place on the binder, as the iOS app's `CategoryOrder`: within a range, so the place after the last is
 * always a number.
 */
object CategoryOrder {
    private const val FARTHEST = 1 shl 20

    /** [order] as a place can be. */
    fun place(order: Int): Int = order.coerceIn(-FARTHEST, FARTHEST)

    /** The place after every one of [orders]: a new category goes last. */
    fun after(orders: Collection<Int>): Int = place(orders.maxOrNull() ?: -1) + 1
}

/**
 * Choice values written as display text (version 2 backups, older builds) become option keys, as the iOS app's
 * `FieldValues.normalizingChoices`: the one rule, for an import and for the store's repair list (`ChoiceKeysStep`).
 */
object ChoiceKeys {
    fun normalizing(values: FieldValues, fields: List<FieldDefinition>): FieldValues {
        var result = values
        for (field in fields) {
            if (field.options == null) continue
            val value = values[field.key]
            result = when {
                field.type == FieldDefinition.CHOICE && value is FieldValue.Text ->
                    result.with(field.key, FieldValue.Text(field.choiceKey(value.value)))
                field.type == FieldDefinition.MULTI_CHOICE && value is FieldValue.Choices ->
                    result.with(field.key, FieldValue.Choices(value.value.map(field::choiceKey)))
                field.type == FieldDefinition.MULTI_CHOICE && value is FieldValue.Text ->
                    result.with(field.key, FieldValue.Choices(listOf(field.choiceKey(value.value))))
                else -> result
            }
        }
        return result
    }
}

/**
 * A firm's tax ID (CUI) as stored, as the iOS app's `ProviderTaxID`: 2 to 10 digits without `RO` or leading zeros, or
 * none.
 */
internal object ProviderTaxID {
    private val DIGIT_COUNT = 2..10

    fun normalized(text: String?): String? {
        var rest = text?.trim()?.uppercase() ?: return null
        if (rest.startsWith("RO")) rest = rest.drop(2)
        val digits = rest.filter { !it.isWhitespace() && it != '.' && it != '-' }
        if (digits.length !in DIGIT_COUNT || !digits.all { it in '0'..'9' }) return null
        return digits.trimStart('0').ifEmpty { null }
    }
}

/**
 * What two copies of one firm bring together on the one that stays, as the iOS app's
 * `FirmCopies`: a detail the copy that stays lacks comes from the other, its trades are both
 * copies' trades and so are the sections it works on. Nothing is ever emptied.
 */
internal object FirmCopies {
    data class Details(
        val trades: List<String>,
        val phone: String?,
        val email: String?,
        val address: String?,
        val notes: String?,
        val manualRating: Int?,
        val wouldCallAgain: Boolean?,
        val taxID: String?,
        val contactIdentifier: String? = null,
    )

    fun details(provider: BinderProvider) = Details(
        provider.trades, provider.phone, provider.email, provider.address, provider.notes, provider.manualRating,
        provider.wouldCallAgain, provider.taxID, provider.contactIdentifier,
    )

    fun details(archived: ProviderRecord) = Details(
        archived.trades, archived.phone, archived.email, archived.address, archived.notes, archived.manualRating,
        archived.wouldCallAgain, ProviderTaxID.normalized(archived.taxID),
    )

    fun gather(other: Details, kept: BinderProvider): BinderProvider {
        val trades = kept.trades + other.trades.filter { it !in kept.trades }
        return kept.copy(
            trades = if (trades != kept.trades) trades.sorted() else kept.trades,
            phone = filled(kept.phone, other.phone),
            email = filled(kept.email, other.email),
            address = filled(kept.address, other.address),
            notes = filled(kept.notes, other.notes),
            manualRating = kept.manualRating ?: other.manualRating,
            wouldCallAgain = kept.wouldCallAgain ?: other.wouldCallAgain,
            taxID = filled(kept.taxID, other.taxID),
            contactIdentifier = filled(kept.contactIdentifier, other.contactIdentifier),
        )
    }

    /** The sections both copies work on, the kept copy's first. */
    fun sections(kept: List<UUID>, other: List<UUID>): List<UUID> = kept + other.filter { it !in kept }

    /** [kept], unless it says nothing (none, or only spaces). */
    private fun filled(kept: String?, other: String?): String? = if (kept.isNullOrBlank()) other ?: kept else kept
}

/**
 * What capture learned, as far as an import reads it (the iOS app's `CaptureLessonLearner.isLabelShaped`
 * and `LessonBook.contradicted`): a label of one to four words with no digits, and two lessons
 * that give one label of one issuer's kind to two fields contradict each other.
 */
internal object LessonRules {
    private const val LONGEST_LABEL = 4

    /**
     * The capture kinds this build reads (the iOS app's `CaptureDocumentKind`); a lesson of
     * another kind is kept, unread, and never counted against another. Capture (Phase 5)
     * brings the kinds themselves.
     */
    val KNOWN_KINDS: Set<String> = setOf(
        "passport", "identityCard", "residencePermit", "drivingLicence", "criminalRecord", "healthInsuranceCard",
        "bankCard", "greenCard", "electronicSignature", "vehicleRegistration", "rcaPolicy", "insurancePolicy",
        "utilityInvoice", "contract", "serviceInvoice", "fiscalReceipt", "warrantyCertificate", "itpReport",
        "veterinaryRecord", "medicalResult", "other",
    )

    fun isLabelShaped(label: String): Boolean {
        val words = Words.of(label)
        return words.size in 1..LONGEST_LABEL && label.codePoints().noneMatch(Words::isNumber)
            && words.any { it.codePointCount(0, it.length) >= 2 }
    }

    /** The lessons a label two fields claim takes out: one issuer, one kind, one folded label, more than one field. */
    fun contradicted(lessons: List<Lesson>): Set<UUID> = lessons
        .filter {
            it.kind in KNOWN_KINDS && it.issuerKey.isNotEmpty() && it.field.isNotEmpty() && it.label.isNotEmpty()
        }
        .groupBy { Triple(it.issuerKey, it.kind, RomanianText.fold(it.label)) }
        .values
        .filter { group -> group.map(Lesson::field).toSet().size > 1 }
        .flatten()
        .map(Lesson::id)
        .toSet()

    data class Lesson(val id: UUID, val issuerKey: String, val kind: String, val field: String, val label: String)
}

/** The folded words of a text, as the iOS app's `RomanianText.words`: runs of letters and digits. */
internal object Words {
    fun of(text: String): List<String> {
        val words = ArrayList<String>()
        val word = StringBuilder()
        val folded = RomanianText.fold(text)
        var at = 0
        while (at < folded.length) {
            val codePoint = folded.codePointAt(at)
            at += Character.charCount(codePoint)
            if (isWordPart(codePoint)) {
                word.appendCodePoint(codePoint)
            } else if (word.isNotEmpty()) {
                words += word.toString()
                word.clear()
            }
        }
        if (word.isNotEmpty()) words += word.toString()
        return words
    }

    /** A letter or a number, as Swift's `Character.isLetter` and `isNumber` read one. */
    private fun isWordPart(codePoint: Int): Boolean = Character.isLetter(codePoint) || isNumber(codePoint)

    /** A digit or another number character, as Swift's `Character.isNumber`. */
    fun isNumber(codePoint: Int): Boolean {
        val type = Character.getType(codePoint)
        return type == Character.DECIMAL_DIGIT_NUMBER.toInt() || type == Character.LETTER_NUMBER.toInt() ||
            type == Character.OTHER_NUMBER.toInt()
    }
}
