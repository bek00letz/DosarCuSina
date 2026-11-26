package com.ar.dosarcusina.store.history

import com.ar.dosarcusina.core.deadlines.HistoryKind
import com.ar.dosarcusina.core.readings.ReadingSource
import com.ar.dosarcusina.core.values.Money
import com.ar.dosarcusina.store.providers.ProviderTrade
import com.ar.dosarcusina.store.schema.Asset
import com.ar.dosarcusina.store.schema.Provider
import java.math.BigDecimal
import java.time.Instant

/**
 * A visit being filled in, as the iOS app's `VisitDraft` (ios/DosarCuSina/Views/Add/Visit/VisitDraft.swift),
 * as far as saving reads it: the ticked rows, anything else done, a note, the day, the counter, the total
 * and the rating. Its form ([VisitForm], by the category's visit kind) says which of these are asked; saving
 * keeps only those ([filing]). Filling it from a captured paper comes with capture (Phase 5).
 */
data class VisitDraft(
    val date: Instant,
    /** Ticked rows by part key, in the order they were ticked. */
    val ticked: List<String> = emptyList(),
    val parts: Map<String, Part> = emptyMap(),
    val extras: List<Extra> = emptyList(),
    /** The counter as typed or read off the invoice; none until then. An estimate is never saved. */
    val odometer: Double? = null,
    /** Where [odometer] came from: the invoice, until the person types over it. */
    val odometerSource: ReadingSource = ReadingSource.PERSON,
    val total: BigDecimal? = null,
    val currency: String = Money.DEFAULT_CURRENCY,
    /** What it was for, or what was fixed ([VisitShape.asksNote]). */
    val note: String = "",
    /** Whether a firm or a person is chosen or named. */
    val hasProvider: Boolean = false,
    val rating: Int? = null,
    /** Whether a paper (the invoice, a doctor's or a vet's papers) is attached: capture's (Phase 5). */
    val hasPaper: Boolean = false,
    /** The invoice's number as read, by which another photo of it is known ([PaperIdentity]). */
    val reference: String? = null,
) {
    /** A ticked part: what it cost and its brand or code, when typed. */
    data class Part(val cost: BigDecimal? = null, val brand: String = "")

    /** A row of one's own: what was done and what it cost. */
    data class Extra(val name: String, val cost: BigDecimal? = null)

    private val hasRows: Boolean get() = extras.any { it.name.isNotBlank() }

    private val hasNote: Boolean get() = note.isNotBlank()

    /** Whether [field] is filled in. */
    fun fills(field: VisitShape.Field): Boolean = when (field) {
        VisitShape.Field.PAPER -> hasPaper
        VisitShape.Field.WORK -> ticked.isNotEmpty() || hasRows
        VisitShape.Field.NOTE -> hasNote
        VisitShape.Field.COUNTER -> odometer != null
        VisitShape.Field.COST -> total != null
        VisitShape.Field.PROVIDER -> hasProvider
    }

    /**
     * Whether the form can save: any one of what its kind requires is filled in, or the kind requires nothing
     * (a doctor's visit saves with its day alone).
     */
    fun satisfies(form: VisitForm): Boolean {
        val requirement = form.shape.requirement ?: return true
        return requirement.any { it in form.fields && fills(it) }
    }

    /** The draft with [key] ticked, or not any more. */
    fun toggling(key: String): VisitDraft = copy(ticked = if (key in ticked) ticked - key else ticked + key)

    /** The ticked rows as the actions take them: each with its cost and its brand, when typed. */
    val checklistItems: List<ChecklistItem>
        get() = ticked.map { key ->
            val part = parts[key]
            val brand = part?.brand?.trim().orEmpty()
            ChecklistItem(key, part?.cost?.let { Money(it, currency) }, brand.ifEmpty { null })
        }

    /** The rows of one's own that name something, as the actions take them. */
    val extraItems: List<LineItemDraft>
        get() = extras.mapNotNull { extra ->
            val name = extra.name.trim()
            if (name.isEmpty()) null else LineItemDraft(name = name, cost = extra.cost?.let { Money(it, currency) })
        }

    /** The total written: the one typed, else none (the parts add up on their own). */
    val totalMoney: Money? get() = total?.let { Money(it, currency) }

    /** What the parts' and rows' costs add up to, shown under the total. */
    val partsSum: BigDecimal?
        get() {
            val costs = ticked.mapNotNull { parts[it]?.cost } + extras.mapNotNull { it.cost }
            return if (costs.isEmpty()) null else costs.fold(BigDecimal.ZERO, BigDecimal::add)
        }

    /**
     * The visit saving files, from the draft as it stands: only what [form] asks, so a value its kind doesn't
     * ask (a doctor's counter, a repair's parts) is never written. [provider] is who did it, as the screen
     * resolved the choice.
     */
    fun filing(asset: Asset, form: VisitForm, provider: VisitFiling.Who): VisitFiling {
        val asks = form.fields
        val checklist = if (VisitShape.Field.WORK in asks && form.hasChecklist) {
            checklistItems.map { if (form.shape.asksBrand) it else it.copy(partBrandOrCode = null) }
        } else {
            emptyList()
        }
        val extras = if (VisitShape.Field.WORK in asks) extraItems else emptyList()
        val names = checklist.map { item -> form.components.firstOrNull { it.key == item.componentKey }?.name
            ?: item.componentKey } + extras.map { it.name }
        val asksWho = VisitShape.Field.PROVIDER in asks
        return VisitFiling(
            asset = asset,
            kind = form.shape.historyKind,
            title = form.entryTitle(names),
            occurredAt = date,
            checklist = checklist,
            extraItems = extras,
            totalCost = totalMoney,
            odometer = if (VisitShape.Field.COUNTER in asks) odometer else null,
            odometerSource = odometerSource,
            provider = if (asksWho) provider else VisitFiling.Who.None,
            rating = if (asksWho) rating else null,
            note = if (VisitShape.Field.NOTE in asks && hasNote) note.trim() else null,
            reference = reference,
            paper = form.shape.paper ?: VisitShape.Paper.INVOICE,
        )
    }
}

/**
 * A visit as its form files it ([VisitDraft.filing], [HistoryActions.file]), as the iOS app's
 * `CaptureFiler.Visit` without its paper: the paper's photo, its kept copy and another photo of an invoice
 * already filed come with capture (Phase 5).
 */
data class VisitFiling(
    val asset: Asset,
    val kind: HistoryKind,
    /** The record's title in Istoric ([VisitForm.entryTitle]), worded by the app. */
    val title: EntryTitle,
    val occurredAt: Instant,
    val checklist: List<ChecklistItem>,
    val extraItems: List<LineItemDraft> = emptyList(),
    val totalCost: Money? = null,
    val odometer: Double? = null,
    /** Read off the invoice or typed; an estimate never reaches the filer. */
    val odometerSource: ReadingSource = ReadingSource.PERSON,
    val provider: Who = Who.None,
    val rating: Int? = null,
    /** What it was for, or what was fixed, as the kind asks it. */
    val note: String? = null,
    /** The invoice's number as read. */
    val reference: String? = null,
    /** The paper it keeps: an invoice, known by its number, day and total; a doctor's or a vet's paper. */
    val paper: VisitShape.Paper = VisitShape.Paper.INVOICE,
) {
    /** Who did it, as the form leaves it. */
    sealed interface Who {
        data object None : Who

        /** A firm or a person already in Agendă. */
        data class Existing(val provider: Provider) : Who

        /** Typed or read off the invoice, with the CUI read: a firm with this name or CUI is used before a new one. */
        data class Named(val name: String, val trade: ProviderTrade, val taxID: String? = null) : Who
    }

    /** The visit [HistoryActions.recordVisit] records, with [provider] found and its title in [wording]'s words. */
    fun record(provider: Provider?, wording: HistoryWording): VisitRecord = VisitRecord(
        kind = kind, title = wording.title(title), occurredAt = occurredAt, checklist = checklist,
        extraItems = extraItems, totalCost = totalCost, odometer = odometer, odometerSource = odometerSource,
        provider = provider, note = note, reference = reference, rating = rating,
    )
}
