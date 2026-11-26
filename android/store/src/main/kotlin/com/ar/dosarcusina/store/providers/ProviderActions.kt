package com.ar.dosarcusina.store.providers

import com.ar.dosarcusina.archive.FieldFormatter
import com.ar.dosarcusina.archive.ProviderTaxID
import com.ar.dosarcusina.core.search.SearchText
import com.ar.dosarcusina.core.values.ThreeWay
import com.ar.dosarcusina.store.Step
import com.ar.dosarcusina.store.Tables
import com.ar.dosarcusina.store.UndoReceipt
import com.ar.dosarcusina.store.UnitOfWork
import com.ar.dosarcusina.store.schema.Asset
import com.ar.dosarcusina.store.schema.Provider
import com.ar.dosarcusina.store.schema.StoredMoment
import java.time.Instant

/** What a person or firm does for the household (`ProviderTrade`); [raw] is stored in `Provider.trades`. */
enum class ProviderTrade(val raw: String) {
    MECHANIC("mechanic"),
    TYRE_SHOP("tyreShop"),
    INSPECTION_STATION("inspectionStation"),
    BODY_SHOP("bodyShop"),
    PLUMBER("plumber"),
    ELECTRICIAN("electrician"),
    GAS_TECHNICIAN("gasTechnician"),
    BOILER_TECHNICIAN("boilerTechnician"),
    HVAC_TECHNICIAN("hvacTechnician"),
    HANDYMAN("handyman"),
    VET("vet"),
    DOCTOR("doctor"),
    DENTIST("dentist"),
    INSURANCE_AGENT("insuranceAgent"),

    /** The insurance company that issued a policy (RCA, CASCO, PAD). */
    INSURER("insurer"),
    ACCOUNTANT("accountant"),
    TENANT("tenant"),
    EMERGENCY_CONTACT("emergencyContact"),
    OTHER("other"),
    ;

    companion object {
        fun of(raw: String): ProviderTrade? = entries.firstOrNull { it.raw == raw }
    }
}

/** What the person can change on a provider's card, as the iOS app's `ProviderDetails`. */
data class ProviderDetails(
    val name: String,
    val trades: List<String> = emptyList(),
    val phone: String? = null,
    val email: String? = null,
    val address: String? = null,
    val notes: String? = null,
    val contactIdentifier: String? = null,
) {
    /** The details as they are kept: phone and e-mail cleaned as [ProviderActions.create] does, empty text as none. */
    val kept: ProviderDetails
        get() = ProviderDetails(
            name = name.trim(),
            trades = trades,
            phone = clean(phone)?.let(FieldFormatter::normalizePhone),
            email = clean(email)?.let(FieldFormatter::normalizeEmail),
            address = clean(address),
            notes = clean(notes),
            contactIdentifier = contactIdentifier,
        )

    companion object {
        /** What the card shows of [provider], as stored. */
        fun of(provider: Provider) = ProviderDetails(
            provider.name, provider.trades, provider.phone, provider.email, provider.address, provider.notes,
            provider.contactIdentifier,
        )

        private fun clean(text: String?): String? = text?.trim()?.takeIf { it.isNotEmpty() }
    }
}

/**
 * Creating and editing the people and businesses the household relies on, as the iOS app's
 * `ProviderActions` (ios/DosarCuSina/Services/History/ProviderDirectory.swift and
 * ProviderActions+Edit.swift): each a step of the unit of work, which joins a step it runs inside
 * (capture filing a document with its issuer).
 */
// The iOS type's surface, one function per job.
@Suppress("TooManyFunctions")
class ProviderActions(
    private val unit: UnitOfWork,
    /** The step's clock: the change time it gives. */
    private val now: () -> Instant = unit.clock,
) {
    /** Makes a person or firm, linked to [linkedTo]; an example only when every section it is linked to is. */
    @Suppress("LongParameterList") // The iOS action's own questions.
    fun create(
        name: String,
        trades: List<ProviderTrade>,
        phone: String? = null,
        email: String? = null,
        address: String? = null,
        notes: String? = null,
        contactIdentifier: String? = null,
        linkedTo: List<Asset> = emptyList(),
    ): Provider = unit.perform(now = now()) { step ->
        make(step, name, trades.map { it.raw }, phone, email, address, notes, contactIdentifier, linkedTo, null)
    }

    /**
     * The one way capture and the visit form name who issued a document or did a job: the firm
     * already in Agendă, or a new one. A firm is the same when it has the CUI read off the document
     * ([taxID], as [ProviderTaxID] keeps it), whatever its name says; without a CUI match, when its
     * name reads the same once case, diacritics and spacing are set aside ([SearchText.normalize])
     * and it has no other CUI. A firm found keeps the CUI it lacked. Either way it is linked to
     * [linkedTo]. None for a name with nothing in it.
     */
    fun findOrCreate(
        name: String,
        taxID: String? = null,
        trade: ProviderTrade,
        phone: String? = null,
        linkedTo: Asset? = null,
    ): Provider? {
        val trimmed = name.trim()
        if (trimmed.isEmpty()) return null
        val cui = ProviderTaxID.normalized(taxID)
        return unit.perform(now = now()) { step ->
            val existing = find(step, trimmed, cui)
            if (existing == null) {
                make(step, trimmed, listOf(trade.raw), phone, null, null, null, null, listOfNotNull(linkedTo), cui)
            } else {
                linkedTo?.let { link(step, existing, it) }
                val kept = if (existing.taxID == null && cui != null) existing.copy(taxID = cui) else existing
                if (kept != existing) step.update(kept)
                kept
            }
        }
    }

    /** The firm [findOrCreate] finds for [name] and [taxID] (as stored), in [step]; none when it makes one. */
    fun find(step: Step, name: String, taxID: String?): Provider? {
        val providers = step.all(Tables.providers)
        val wanted = SearchText.normalize(name)
        val byTaxID = taxID?.let { id -> providers.firstOrNull { it.taxID == id } }
        return byTaxID ?: providers.firstOrNull {
            SearchText.normalize(it.name) == wanted && (it.taxID == null || taxID == null || it.taxID == taxID)
        }
    }

    /** Links [provider] to the section [asset]: it looks after it. */
    fun link(provider: Provider, asset: Asset) = unit.perform(now = now()) { step -> link(step, provider, asset) }

    /** Unlinks [provider] from the section [asset]. */
    fun unlink(provider: Provider, asset: Asset) = unit.perform(now = now()) { step ->
        val row = fresh(step, provider)
        step.setLinked(Tables.providerAssets, row.pk, step.linked(Tables.providerAssets, row.pk) - asset.pk)
    }

    /** The person's own 1–5 rating, or none; job ratings take precedence when there are any. */
    fun setRating(provider: Provider, rating: Int?) = unit.perform(now = now()) { step ->
        step.update(fresh(step, provider).copy(manualRating = rating?.coerceIn(LOWEST_RATING, HIGHEST_RATING)))
    }

    fun setWouldCallAgain(provider: Provider, value: Boolean?) = unit.perform(now = now()) { step ->
        step.update(fresh(step, provider).copy(wouldCallAgain = value))
    }

    /**
     * Writes a provider's details, as kept ([ProviderDetails.kept]). Only what the edit changed from
     * the details it started from ([startedFrom], else the provider as stored now) is written,
     * detail by detail ([ThreeWay]): a phone number added meanwhile on another device stays.
     */
    fun update(provider: Provider, details: ProviderDetails, startedFrom: ProviderDetails? = null) =
        unit.perform(now = now()) { step ->
            val row = fresh(step, provider)
            val stored = ProviderDetails.of(row)
            val edited = details.kept
            val base = (startedFrom ?: stored).kept
            val contact = ThreeWay.value(edited.contactIdentifier, stored.contactIdentifier, base.contactIdentifier)
            step.update(
                row.copy(
                    name = ThreeWay.value(edited.name, stored.name, base.name),
                    trades = ThreeWay.value(edited.trades, stored.trades, base.trades),
                    phone = ThreeWay.value(edited.phone, stored.phone, base.phone),
                    email = ThreeWay.value(edited.email, stored.email, base.email),
                    address = ThreeWay.value(edited.address, stored.address, base.address),
                    notes = ThreeWay.value(edited.notes, stored.notes, base.notes),
                    contactIdentifier = contact,
                ),
            )
        }

    /**
     * Deletes a firm or a person from Agendă. Undoable: the receipt brings them back with every link
     * (the sections they look after, their jobs, the parts they supplied, the documents they issued),
     * which the delete only lets go of.
     */
    fun delete(provider: Provider): UndoReceipt = unit.performUndoable(now()) { step ->
        step.delete(fresh(step, provider))
    }.receipt

    // Inside

    @Suppress("LongParameterList") // What a new provider is made of.
    private fun make(
        step: Step,
        name: String,
        trades: List<String>,
        phone: String?,
        email: String?,
        address: String?,
        notes: String?,
        contactIdentifier: String?,
        linkedTo: List<Asset>,
        taxID: String?,
    ): Provider {
        val made = StoredMoment.kept(now())
        val provider = step.insert(
            Provider(
                name = name,
                trades = trades,
                phone = phone?.let(FieldFormatter::normalizePhone),
                email = email?.let(FieldFormatter::normalizeEmail),
                address = address,
                notes = notes,
                contactIdentifier = contactIdentifier,
                taxID = taxID,
                isExample = linkedTo.isNotEmpty() && linkedTo.all { it.isExample },
                createdAt = made,
                updatedAt = made,
            ),
        )
        if (linkedTo.isNotEmpty()) step.setLinked(Tables.providerAssets, provider.pk, linkedTo.map { it.pk })
        return provider
    }

    private fun link(step: Step, provider: Provider, asset: Asset) {
        val row = fresh(step, provider)
        val linked = step.linked(Tables.providerAssets, row.pk)
        if (asset.pk !in linked) step.setLinked(Tables.providerAssets, row.pk, linked + asset.pk)
    }

    private fun fresh(step: Step, provider: Provider): Provider =
        step.row(Tables.providers, provider.pk) ?: throw NoSuchElementException("The firm isn't in the binder")

    private companion object {
        const val LOWEST_RATING = 1
        const val HIGHEST_RATING = 5
    }
}
