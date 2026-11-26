package com.ar.dosarcusina.core.search

import com.ar.dosarcusina.core.text.PaymentCardNumbers.KeptWhole
import com.ar.dosarcusina.core.values.CalendarDay
import java.time.Instant
import java.util.UUID

// What search reads of each record, in plain types: the store fills them from its rows
// (store.search), and SearchEntries turns them into the index's documents. Words are as stored;
// a value is also as the app shows it ([SearchValue.shown]), which the store's wording gives.

/** A section, with what its category says about its values. */
data class SearchSection(
    val id: UUID,
    val name: String,
    /** Its category's name; null while the category's record isn't here. */
    val categoryName: String?,
    /** Each field of its category that holds a value, in the category's order. */
    val values: List<SearchValue>,
    /** Its rows under Date importante. */
    val facts: List<SearchFact>,
    val notes: String?,
    val updatedAt: Instant?,
    /** Whether its category is locked on this phone (the one answer, whether or not its record is here). */
    val isLocked: Boolean,
    /** What its own typed values keep whole in its words and its records' (a pet's microchip). */
    val keptWhole: KeptWhole,
    /** Its category's parts and jobs (`ComponentDefinition`). */
    val components: List<SearchComponent> = emptyList(),
    /** Every part or job of its records of history. */
    val parts: List<SearchPart> = emptyList(),
)

/** One field's value on a section. */
data class SearchValue(
    val label: String,
    /** The field's type, as stored (`FieldType`'s raw value). */
    val type: String,
    /** The field's role, as stored (`FieldRole`'s raw value), if it has one. */
    val role: String?,
    /** Whether the category keeps it out of search (a document number, a CNP, a medical note). */
    val isSensitive: Boolean,
    /** The value as stored, when it is text. */
    val text: String?,
    /** The value as the app shows it: a choice's label, a plate written "B-123-ABC", a sealed one masked. */
    val shown: String,
    /** The value is a number (a year), which a section's line says after its words ("Volkswagen Golf · 2018"). */
    val isNumber: Boolean = false,
) {
    /** A code kept sealed on the phone (a PIN). */
    val isSecret: Boolean get() = type == FieldTypes.SECRET

    /** Whether search may keep it: neither sensitive nor secret (the iOS app's `FieldDefinition.isIndexable`). */
    val isIndexable: Boolean get() = !isSensitive && !isSecret

    /** The field types and roles search reads, as stored. */
    object FieldTypes {
        const val SECRET = "secret"
        const val PLATE = "plate"
        const val IBAN = "iban"
        const val VIN = "vin"

        /** The codes also searched without their separators ("b123abc"). */
        val compacted: Set<String> = setOf(PLATE, IBAN, VIN)
    }

    object Roles {
        const val IDENTIFIER = "identifier"
        const val KEY_FACT = "keyFact"
        const val DOCUMENT_NUMBER = "documentNumber"
        const val SUBTITLE = "subtitle"
        const val HOLDER = "holder"
        const val ISSUER = "issuer"
        const val RETAILER = "retailer"
    }
}

/** A row under Date importante. */
data class SearchFact(val label: String, val value: String, val isSensitive: Boolean, val isSecret: Boolean)

/** A part or a job a category knows (`ComponentDefinition`). */
data class SearchComponent(val key: String, val name: String, val group: String, val synonyms: List<String>)

/** A part or a job done in one of a section's records of history. */
data class SearchPart(
    /** The part it is: a catalog key or one of the person's own (`custom.…`); none for one not followed. */
    val componentKey: String?,
    val name: String,
    /** The record of history it was done in. */
    val entryId: UUID,
    /** When that record happened. */
    val occurredAt: Instant,
    val partBrandOrCode: String?,
    val supplierName: String?,
    /** Who did the record's work, by name, in order. */
    val providerNames: List<String>,
)

/** A deadline. */
data class SearchDeadline(
    val id: UUID,
    val title: String,
    val reference: String?,
    val provider: String?,
    val notes: String?,
    val dueDay: CalendarDay,
    /** The name of the section it is in; none for one of the whole household's. */
    val sectionName: String?,
    val isLocked: Boolean,
    val keptWhole: KeptWhole,
)

/** A record of history: a visit, a repair, a purchase. */
data class SearchRecord(
    val id: UUID,
    val title: String,
    val occurredAt: Instant,
    val sectionName: String?,
    /** Its parts and jobs, each with its brand or code and its supplier's name. */
    val items: List<Item>,
    /** Who did the work, by name, in order. */
    val providerNames: List<String>,
    val note: String?,
    val reference: String?,
    val isLocked: Boolean,
    val keptWhole: KeptWhole,
) {
    data class Item(val name: String, val partBrandOrCode: String?, val supplierName: String?)
}

/** A person or firm who looks after something. */
data class SearchFirm(
    val id: UUID,
    val name: String,
    /** Its trades, by key (`ProviderTrade`). */
    val trades: List<String>,
    val phone: String?,
    /**
     * The names of the open sections it looks after, in order: a locked one is never named in a
     * firm's result (its page draws it as locked).
     */
    val sectionNames: List<String>,
    val address: String?,
    val notes: String?,
    val updatedAt: Instant?,
)

/** A document. */
data class SearchPaper(
    val id: UUID,
    val title: String?,
    val fileName: String,
    /** The name of the section it is filed in: its own, else its deadline's, record's, part's or reading's. */
    val sectionName: String?,
    val isArchived: Boolean,
    val extractedText: String?,
    /** Read off an identity document (`DocumentKind.identity`). */
    val isIdentity: Boolean,
    val documentDay: CalendarDay?,
    val createdAt: Instant?,
    /**
     * Whether it is locked on this phone by the lock its page is drawn behind: when any section it
     * belongs to is, or, naming none that can be found, while anything of the binder is.
     */
    val isLocked: Boolean,
    val keptWhole: KeptWhole,
)
