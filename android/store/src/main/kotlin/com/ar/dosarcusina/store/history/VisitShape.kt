package com.ar.dosarcusina.store.history

import com.ar.dosarcusina.catalog.VisitKind
import com.ar.dosarcusina.core.deadlines.HistoryKind
import com.ar.dosarcusina.store.providers.ProviderTrade

/**
 * What logging a visit asks, by its kind ([VisitKind]), as the iOS app's `VisitShape`
 * (ios/DosarCuSina/Models/Templates/VisitShape.swift): the one place that says it, as `CompletionShape` says
 * what closing a deadline asks. The visit form lays it over the category's parts and counter ([VisitForm]),
 * and what saving keeps follows it ([VisitDraft.filing]), so a value a kind doesn't ask is never written.
 *
 * Kinds and data only: every word the form says (its title, its headers, the button and the toast) is the
 * screens' (Phase 4), by the kind, from the app's strings; `docs/COPY_MATRIX.md` lists the iOS app's.
 */
data class VisitShape(
    /** What the visit is in the history. */
    val historyKind: HistoryKind,
    /** The paper it asks for; none when it asks none. */
    val paper: Paper?,
    /**
     * Whether it asks what was done: ticked on the category's parts and jobs (when it has any) and written in
     * rows of one's own for the rest. A kind that doesn't asks a note instead.
     */
    val asksWork: Boolean,
    /** Whether a ticked part asks its brand or code: only a vehicle's parts have one. */
    val asksBrand: Boolean,
    /** Whether it asks a note: what it was for, or what was fixed. */
    val asksNote: Boolean,
    /** Whether it asks the section's counter (kilometres, engine hours), where the category keeps one. */
    val asksCounter: Boolean,
    /** Whether its cost has a hint under it („Dacă ai plătit ceva.”): when what it cost may be nothing. */
    val costIsOptional: Boolean,
    /** What the rows add up to is called, under the money field. */
    val sum: Sum,
    /** Whether it says if the day falls within the product's warranty (the field whose role is `warrantyUntil`). */
    val checksWarranty: Boolean,
    /** What a firm or person added from the visit does; none when it doesn't ask who did it. */
    val providerTrade: ProviderTrade?,
    /** What must be filled before it saves: any one of these; none saves with the day alone. */
    val requirement: Set<Field>?,
) {
    /** What the form can ask, as a save requirement names them. */
    enum class Field(val raw: String) {
        /** A photo of the paper. */
        PAPER("paper"),

        /** What was done: the ticked parts and jobs, and the rows of one's own. */
        WORK("work"),

        /** A note. */
        NOTE("note"),

        /** The section's counter. */
        COUNTER("counter"),

        /** What it cost (always asked). */
        COST("cost"),

        /** Who did it. */
        PROVIDER("provider"),
    }

    /** The paper the form asks for, which says how it is named and kept. */
    enum class Paper(val raw: String) {
        /** The invoice of a service, a tradesperson or a repair shop. */
        INVOICE("invoice"),

        /** A doctor's papers: the prescription, the results, the referral. */
        MEDICAL("medical"),

        /** A vet's papers: the record, the prescription, the vaccination booklet. */
        VETERINARY("veterinary"),
        ;

        /** Whether it is an invoice: another photo of one is known by its number, day and total ([PaperIdentity]). */
        val isInvoice: Boolean get() = this == INVOICE

        /** How the paper is kept: an invoice as one (`invoice`), a doctor's or a vet's paper as a report (`report`). */
        val documentKind: String get() = if (this == INVOICE) "invoice" else "report"
    }

    /** What the rows add up to is called. */
    enum class Sum {
        /** „Piesele adună …”: a vehicle's parts. */
        PARTS,

        /** „Rândurile adună …”. */
        ROWS,
    }

    /**
     * Every field the form can show for this kind, before the category is laid over it (a counter only where
     * the category keeps one, a checklist only where it lists parts).
     */
    val fields: Set<Field>
        get() = buildSet {
            add(Field.COST)
            if (paper != null) add(Field.PAPER)
            if (asksWork) add(Field.WORK)
            if (asksNote) add(Field.NOTE)
            if (asksCounter) add(Field.COUNTER)
            if (providerTrade != null) add(Field.PROVIDER)
        }

    companion object {
        /** Each kind's shape; none for a kind with no visits ([VisitKind.NOTE], [VisitKind.NONE]). */
        fun of(kind: VisitKind): VisitShape? = when (kind) {
            VisitKind.SERVICE -> SERVICE
            VisitKind.JOB -> JOB
            VisitKind.REPAIR -> REPAIR
            VisitKind.UPKEEP -> UPKEEP
            VisitKind.DOCTOR -> DOCTOR
            VisitKind.VET -> VET
            VisitKind.NOTE, VisitKind.NONE -> null
        }

        /** Whether a visit is offered for [kind]'s sections: in their „Adaugă…” menu, Istoric and „Scriu eu”. */
        fun offersVisit(kind: VisitKind): Boolean = of(kind) != null

        /** Whether Istoric takes a dated note in place of a visit („Adaugă o notă”). */
        fun addsNote(kind: VisitKind): Boolean = kind == VisitKind.NOTE

        /** A car's or a bike's service: the invoice, the parts with price and brand, the counter, the firm. */
        private val SERVICE = VisitShape(
            historyKind = HistoryKind.MAINTENANCE, paper = Paper.INVOICE, asksWork = true, asksBrand = true,
            asksNote = false, asksCounter = true, costIsOptional = false, sum = Sum.PARTS, checksWarranty = false,
            providerTrade = ProviderTrade.MECHANIC, requirement = setOf(Field.WORK, Field.COST, Field.PAPER),
        )

        /** A tradesperson's job: what was done, who did it, what it cost, the invoice. */
        private val JOB = VisitShape(
            historyKind = HistoryKind.REPAIR, paper = Paper.INVOICE, asksWork = true, asksBrand = false,
            asksNote = false, asksCounter = false, costIsOptional = false, sum = Sum.ROWS, checksWarranty = false,
            providerTrade = ProviderTrade.HANDYMAN, requirement = setOf(Field.WORK, Field.COST, Field.PAPER),
        )

        /** Something bought, repaired: what was fixed, where, what it cost, whether it was under warranty. */
        private val REPAIR = VisitShape(
            historyKind = HistoryKind.REPAIR, paper = Paper.INVOICE, asksWork = false, asksBrand = false,
            asksNote = true, asksCounter = false, costIsOptional = true, sum = Sum.ROWS, checksWarranty = true,
            providerTrade = ProviderTrade.OTHER, requirement = setOf(Field.NOTE, Field.COST, Field.PAPER),
        )

        /** An espresso machine's upkeep: what was done and what it cost, if anything. */
        private val UPKEEP = VisitShape(
            historyKind = HistoryKind.MAINTENANCE, paper = null, asksWork = true, asksBrand = false,
            asksNote = false, asksCounter = false, costIsOptional = true, sum = Sum.ROWS, checksWarranty = false,
            providerTrade = null, requirement = setOf(Field.WORK),
        )

        /** A doctor's visit: the day, who, what for, the papers, an optional cost. Saves with the day alone. */
        private val DOCTOR = VisitShape(
            historyKind = HistoryKind.VISIT, paper = Paper.MEDICAL, asksWork = false, asksBrand = false,
            asksNote = true, asksCounter = false, costIsOptional = true, sum = Sum.ROWS, checksWarranty = false,
            providerTrade = ProviderTrade.DOCTOR, requirement = null,
        )

        /** A vet visit: the day, the vet, what was done, the papers, an optional cost. Saves with the day alone. */
        private val VET = VisitShape(
            historyKind = HistoryKind.VISIT, paper = Paper.VETERINARY, asksWork = true, asksBrand = false,
            asksNote = false, asksCounter = false, costIsOptional = true, sum = Sum.ROWS, checksWarranty = false,
            providerTrade = ProviderTrade.VET, requirement = null,
        )
    }
}
