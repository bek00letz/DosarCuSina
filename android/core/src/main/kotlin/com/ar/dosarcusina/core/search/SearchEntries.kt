package com.ar.dosarcusina.core.search

import com.ar.dosarcusina.core.history.HistoryItemSnapshot
import com.ar.dosarcusina.core.history.MaintenanceLog
import com.ar.dosarcusina.core.text.PaymentCardNumbers.KeptWhole
import com.ar.dosarcusina.core.text.SealedText
import com.ar.dosarcusina.core.values.CalendarDay
import com.ar.dosarcusina.core.values.TextRules
import java.time.Instant
import java.time.ZoneId
import java.util.Locale
import java.util.UUID

/**
 * What each record gives the index, as the iOS app's `SearchIndexBuilder`
 * (ios/DosarCuSina/Services/Search/SearchIndexBuilder.swift), pinned by its answers in
 * shared/test-vectors/search/search-records.json: a section with its parts and jobs, a deadline, a
 * record of history, a firm, a document.
 *
 * What never reaches the index, whatever a record or its category says ([SearchPrivacy]): a value
 * the category keeps out of search (sensitive) or a secret, a sensitive or secret row, text read off
 * a document filed in a locked section or off an identity document, and any number shaped like a
 * CNP, any card number and any sealed value, wherever it was typed or read; what the record's
 * section keeps whole as its own (a microchip) stays.
 *
 * Days are counted in [zone], the app's calendar's ([com.ar.dosarcusina.core.values.DosarCalendar]).
 */
class SearchEntries(private val wording: SearchWording, private val zone: ZoneId) {
    /** A section's document, then one for each part or job its records of history follow. */
    fun section(section: SearchSection): List<SearchDocument> =
        (listOf(sectionDocument(section)) + componentDocuments(section)).map { redacted(it, section.keptWhole) }

    fun deadline(deadline: SearchDeadline): SearchDocument = redacted(
        SearchDocument(
            id = id(SearchResultKind.OBLIGATION, deadline.id),
            kind = SearchResultKind.OBLIGATION,
            title = deadline.title,
            subtitle = listOfNotNull(deadline.sectionName?.let(SearchDetail::Text), SearchDetail.Day(deadline.dueDay)),
            route = SearchRoute.Deadline(deadline.id),
            fields = listOf(
                SearchField(deadline.title, SearchField.Weight.TITLE),
                SearchField.of(deadline.reference, SearchField.Weight.IDENTIFIER),
                SearchField.of(deadline.provider, SearchField.Weight.LABEL),
                SearchField.of(deadline.sectionName, SearchField.Weight.LABEL),
                SearchField.of(deadline.notes, SearchField.Weight.NOTE),
            ),
            date = noon(deadline.dueDay),
            isSensitive = deadline.isLocked,
        ),
        deadline.keptWhole,
    )

    fun record(record: SearchRecord): SearchDocument = redacted(
        SearchDocument(
            id = id(SearchResultKind.HISTORY_ENTRY, record.id),
            kind = SearchResultKind.HISTORY_ENTRY,
            title = record.title,
            subtitle = listOfNotNull(
                record.sectionName?.let(SearchDetail::Text),
                SearchDetail.Day(day(record.occurredAt)),
            ),
            route = SearchRoute.HistoryEntry(record.id),
            fields = listOf(
                SearchField(record.title, SearchField.Weight.TITLE),
                SearchField(record.items.joinToString(" ") { it.name }, SearchField.Weight.LABEL),
                SearchField(record.providerNames.joinToString(" "), SearchField.Weight.LABEL),
                SearchField.of(record.sectionName, SearchField.Weight.LABEL),
                SearchField(
                    record.items.joinToString(" ") { item ->
                        listOfNotNull(item.partBrandOrCode, item.supplierName).joinToString(" ")
                    },
                    SearchField.Weight.VALUE,
                ),
                SearchField.of(record.note, SearchField.Weight.NOTE),
                SearchField.of(record.reference, SearchField.Weight.VALUE),
            ),
            date = record.occurredAt,
            isSensitive = record.isLocked,
        ),
        record.keptWhole,
    )

    /** A firm is never behind a lock, keeps nothing whole and names only the open sections it looks after. */
    fun firm(firm: SearchFirm): SearchDocument {
        val trades = firm.trades.map(wording::trade)
        return redacted(
            SearchDocument(
                id = id(SearchResultKind.PROVIDER, firm.id),
                kind = SearchResultKind.PROVIDER,
                title = firm.name,
                subtitle = if (firm.trades.isEmpty()) emptyList() else listOf(SearchDetail.Trades(firm.trades)),
                route = SearchRoute.Provider(firm.id),
                fields = listOf(
                    SearchField(firm.name, SearchField.Weight.TITLE),
                    SearchField(trades.joinToString(" "), SearchField.Weight.LABEL),
                    SearchField.of(firm.phone, SearchField.Weight.IDENTIFIER),
                    SearchField(firm.sectionNames.joinToString(" "), SearchField.Weight.VALUE),
                    SearchField(listOfNotNull(firm.address, firm.notes).joinToString(" "), SearchField.Weight.NOTE),
                ),
                date = firm.updatedAt,
            ),
            KeptWhole.NOTHING,
        )
    }

    fun paper(paper: SearchPaper): SearchDocument {
        val title = paper.title ?: paper.fileName
        // Text read off an identity document, or off anything that belongs to a locked section,
        // holds personal numbers: never indexed, whatever its kind says.
        val readText = if (paper.isLocked || paper.isIdentity) null else paper.extractedText
        return redacted(
            SearchDocument(
                id = id(SearchResultKind.DOCUMENT, paper.id),
                kind = SearchResultKind.DOCUMENT,
                title = title,
                subtitle = listOfNotNull(
                    paper.sectionName?.let(SearchDetail::Text),
                    SearchDetail.Archived.takeIf { paper.isArchived },
                ),
                route = SearchRoute.Document(paper.id),
                fields = listOf(
                    SearchField(title, SearchField.Weight.TITLE),
                    SearchField(paper.fileName, SearchField.Weight.LABEL),
                    SearchField.of(paper.sectionName, SearchField.Weight.LABEL),
                    SearchField.of(readText, SearchField.Weight.EXTRACTED),
                ),
                date = paper.documentDay?.let(::noon) ?: paper.createdAt,
                isSensitive = paper.isLocked,
            ),
            paper.keptWhole,
        )
    }

    private fun sectionDocument(section: SearchSection): SearchDocument {
        val fields = mutableListOf(
            SearchField(section.name, SearchField.Weight.TITLE),
            SearchField.of(section.categoryName, SearchField.Weight.LABEL),
        )
        // Sensitive values (document numbers, CNP, medical notes) and secrets (PIN codes) are never indexed.
        for (value in section.values.filter { it.isIndexable }) {
            val weight = weight(value.role)
            fields += SearchField("${value.label} ${value.shown}", weight)
            // Plates, IBANs and VINs are also searchable without separators ("b123abc").
            if (value.type in SearchValue.FieldTypes.compacted) {
                fields += SearchField.of(value.text?.let(::lettersAndDigits), weight)
            }
        }
        for (fact in section.facts.filter { !it.isSecret && !it.isSensitive }) {
            fields += SearchField("${fact.label} ${fact.value}", SearchField.Weight.VALUE)
        }
        fields += SearchField.of(section.notes, SearchField.Weight.NOTE)
        val line = subtitle(section.values).takeIf { section.categoryName != null } ?: section.categoryName
        return SearchDocument(
            id = id(SearchResultKind.ASSET, section.id),
            kind = SearchResultKind.ASSET,
            title = section.name,
            subtitle = listOfNotNull(line?.let(SearchDetail::Text)),
            route = SearchRoute.Section(section.id),
            fields = fields,
            date = section.updatedAt,
            isSensitive = section.isLocked,
        )
    }

    /**
     * One document for each part or job a section's records of history follow, by when it was last
     * done ("Plăcuțe frână față · VW Golf · 3 martie"): its newest occurrence, which it opens.
     */
    private fun componentDocuments(section: SearchSection): List<SearchDocument> =
        lastOccurrences(section.parts).map { last ->
            val key = requireNotNull(last.componentKey)
            val component = section.components.firstOrNull { it.key == key }
            val name = component?.name ?: last.name
            SearchDocument(
                id = "${SearchResultKind.COMPONENT.raw}:${uuid(section.id)}:$key",
                kind = SearchResultKind.COMPONENT,
                title = name,
                subtitle = listOf(SearchDetail.Text(section.name), SearchDetail.Day(day(last.occurredAt))),
                route = SearchRoute.HistoryEntry(last.entryId),
                fields = listOf(
                    SearchField(name, SearchField.Weight.TITLE),
                    SearchField.of(
                        component?.let { (listOf(it.group) + it.synonyms).joinToString(" ") },
                        SearchField.Weight.LABEL,
                    ),
                    SearchField(section.name, SearchField.Weight.LABEL),
                    SearchField(
                        (listOfNotNull(last.partBrandOrCode, last.supplierName) + last.providerNames).joinToString(" "),
                        SearchField.Weight.VALUE,
                    ),
                ),
                date = last.occurredAt,
                isSensitive = section.isLocked,
            )
        }

    private fun day(moment: Instant): CalendarDay = CalendarDay.of(moment, zone)

    /**
     * A section's line as its page says it, the iOS app's `HeroFacts.subtitle`: the subtitle values
     * in order, words together, then numbers (a year) after a dot ("Volkswagen Golf · 2018"); away
     * from the page, a value search never keeps (sensitive or secret) as a mask. Null when there is none.
     */
    private fun subtitle(values: List<SearchValue>): String? {
        val shown = values.filter { it.role == SearchValue.Roles.SUBTITLE }
        fun said(value: SearchValue) = if (value.isIndexable) value.shown else SealedText.MASK
        val words = shown.filterNot { it.isNumber }.joinToString(" ", transform = ::said)
        val parts = listOf(words).filter { it.isNotEmpty() } + shown.filter { it.isNumber }.map(::said)
        return parts.takeIf { it.isNotEmpty() }?.joinToString(" · ")
    }

    /** Noon on [day], twelve hours after it starts, as the iOS app's `CalendarDay.noonDate()`. */
    private fun noon(day: CalendarDay): Instant = day.noon(zone)

    companion object {
        /** A record's document id: its kind and its id, as the iOS app writes them ("asset:…", in capitals). */
        fun id(kind: SearchResultKind, id: UUID): String = "${kind.raw}:${uuid(id)}"

        private fun uuid(id: UUID): String = id.toString().uppercase(Locale.ROOT)

        private fun weight(role: String?): Int = when (role) {
            SearchValue.Roles.IDENTIFIER, SearchValue.Roles.KEY_FACT, SearchValue.Roles.DOCUMENT_NUMBER ->
                SearchField.Weight.IDENTIFIER
            SearchValue.Roles.SUBTITLE, SearchValue.Roles.HOLDER,
            SearchValue.Roles.ISSUER, SearchValue.Roles.RETAILER,
            ->
                SearchField.Weight.LABEL
            else -> SearchField.Weight.VALUE
        }

        private fun lettersAndDigits(text: String): String =
            TextRules.characters(text).filter { TextRules.isLetter(it) || TextRules.isNumber(it) }.joinToString("")

        /**
         * The newest occurrence of each part or job followed, newest first: the maintenance log's
         * ([MaintenanceLog.trackedComponents] and [MaintenanceLog.lastItem]), the one place that says it.
         */
        internal fun lastOccurrences(parts: List<HistoryItemSnapshot>): List<HistoryItemSnapshot> =
            MaintenanceLog.trackedComponents(parts).mapNotNull { MaintenanceLog.lastItem(it, parts) }

        /**
         * [document] with every CNP-shaped number, card number and sealed value taken out of what can be
         * matched ([SearchPrivacy.redacting]) and of every line its row shows, its title and the line
         * under it ([SearchPrivacy.shown], which keeps what is already masked; a part left empty goes);
         * what its section keeps whole ([kept]) stays, as it is stored.
         */
        private fun redacted(document: SearchDocument, kept: KeptWhole): SearchDocument = document.copy(
            title = SearchPrivacy.shown(document.title, kept),
            fields = document.fields.map { it.copy(text = SearchPrivacy.redacting(it.text, kept)) },
            subtitle = document.subtitle.mapNotNull { detail ->
                when (detail) {
                    is SearchDetail.Text ->
                        SearchPrivacy.shown(detail.text, kept).takeIf { it.isNotEmpty() }?.let(SearchDetail::Text)
                    else -> detail
                }
            },
        )
    }
}
