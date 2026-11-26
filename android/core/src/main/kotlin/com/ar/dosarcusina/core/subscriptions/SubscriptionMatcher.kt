package com.ar.dosarcusina.core.subscriptions

import com.ar.dosarcusina.core.values.RomanianText
import com.ar.dosarcusina.core.values.TextRules
import java.util.UUID

/**
 * Finds the ongoing contract a bill or a contract belongs to, or says where a new one goes, as the iOS app's
 * `SubscriptionMatcher` (ios/DosarCuSina/Services/Subscriptions/SubscriptionMatcher.swift). One record per
 * contract: the first document from a provider makes it, and later ones find it by the codes they print.
 *
 * - The codes decide first, only those the service has ([Service.codes]). A code that names one consumption point
 *   or one line ([SubscriptionCode.namesOnePoint]) that differs is never the one.
 * - Without a code, the provider (and the service, when both are known) decides, but only inside one house: two
 *   homes with ENGIE gas never merge. The house is the one whose own codes the document prints, else the one at the
 *   supply address it prints ([house]), else the only home there is.
 * - A new subscription for a service supplied at an address ([Service.isTiedToHome]) goes under its house; anything
 *   else stands on its own. When the house can't be told, nothing is guessed: the person picks.
 *
 * Pure: plain values the store fills, a decision out.
 */
object SubscriptionMatcher {
    /** An existing subscription: its provider and service as stored, and its codes ([SubscriptionCode.kept]). */
    data class Subscription(
        val id: UUID,
        val parentId: UUID?,
        val provider: String?,
        val service: String?,
        val codes: Map<SubscriptionCode, String>,
    )

    /** A home: where it is, as the person wrote it, and its fields' texts by key (the codes kept on it). */
    data class Home(val id: UUID, val address: String?, val fields: Map<String, String> = emptyMap())

    /** What a bill or a contract says about its contract. Only the codes its service has are kept ([codes]). */
    class Reading(
        val provider: String?,
        /** A service's key, or what the paper named. */
        val service: String?,
        codes: Map<SubscriptionCode, String>,
        /** A bill (true) or a contract: a bill with no service named is still a utility's. */
        val isBill: Boolean,
        /** Where the service is supplied ("Adresa locului de consum"), never the payer's billing address. */
        val supplyAddress: String? = null,
    ) {
        val codes: Map<SubscriptionCode, String> = run {
            val carried = ServiceKind.service(service)?.codes?.toSet()
            codes.filter { (code, value) -> code.normalized(value).isNotEmpty() && (carried?.contains(code) ?: true) }
        }

        /** Whether the contract is supplied at an address and so belongs under a home. */
        val isTiedToHome: Boolean
            get() = when {
                service != null -> ServiceKind.isTiedToHome(service)
                codes.keys.any { it.family == SubscriptionCode.Family.CONSUMPTION_POINT } -> true
                codes.keys.any { it.family == SubscriptionCode.Family.LINE } -> false
                else -> isBill
            }
    }

    sealed interface Decision {
        /** The document belongs to this subscription. */
        data class Existing(val id: UUID) : Decision

        /** A new subscription under this home. */
        data class NewUnder(val home: UUID) : Decision

        /** A new subscription on its own, in Abonamente. */
        data object NewStandalone : Decision

        /** It can't be told which house or which contract: the person picks. */
        data object Undecided : Decision
    }

    /** Why the house a decision chose is worth a look ("Verifică"). */
    enum class HouseCheck {
        /** The address the paper names only partly agrees with the home's, or another home is close too. */
        ADDRESS_PARTLY_AGREES,

        /** The only home is at another address than the one the paper names. */
        ADDRESS_DIFFERS,
    }

    /** Where the document goes, and whether the house it was put in needs a look. */
    data class Placement(val decision: Decision, val check: HouseCheck? = null)

    /** A home an address picks, and what is worth a look about it. */
    data class HousePick(val id: UUID, val check: HouseCheck?)

    /** Where the document goes. [within], when given, limits the search to what is filed under that home. */
    fun match(reading: Reading, subscriptions: List<Subscription>, homes: List<Home>, within: UUID? = null): Decision =
        place(reading, subscriptions, homes, within).decision

    /**
     * The one rule for which home a supply address picks, when no code decides: a home at the same place is picked
     * by itself only when it is the only one and no other home is even likely; with another likely too, or when only
     * one home is likely, that home is suggested, marked [HouseCheck.ADDRESS_PARTLY_AGREES]; otherwise the address
     * can't tell (null).
     */
    fun house(address: String?, homes: List<Home>): HousePick? {
        val named = address?.let(PostalAddress::read) ?: return null
        val rated = homes.mapNotNull { home ->
            home.address?.let(PostalAddress::read)?.let { home.id to named.agreement(it) }
        }
        val same = rated.filter { it.second == PostalAddress.Agreement.SAME }
        val likely = rated.filter { it.second == PostalAddress.Agreement.LIKELY }
        return when {
            same.size == 1 -> HousePick(same[0].first, if (likely.isEmpty()) null else HouseCheck.ADDRESS_PARTLY_AGREES)
            same.isEmpty() && likely.size == 1 -> HousePick(likely[0].first, HouseCheck.ADDRESS_PARTLY_AGREES)
            else -> null
        }
    }

    /**
     * The home a paper's address names (a bill's supply address, a policy's insured home): the one at that address
     * ([house]), else the only home, marked when it is at another address. Null with several homes the address can't
     * tell apart.
     */
    fun home(address: String?, homes: List<Home>): HousePick? =
        house(address, homes) ?: homes.singleOrNull()?.let { only ->
            val named = address?.let(PostalAddress::read)
            val kept = only.address?.let(PostalAddress::read)
            val differs = named != null && kept != null && named.agreement(kept) == PostalAddress.Agreement.DIFFERENT
            HousePick(only.id, if (differs) HouseCheck.ADDRESS_DIFFERS else null)
        }

    /** [match], with what the person should check about the house it chose. */
    fun place(reading: Reading, subscriptions: List<Subscription>, homes: List<Home>, within: UUID? = null): Placement {
        val candidates = within?.let { parent -> subscriptions.filter { it.parentId == parent } } ?: subscriptions
        val compatible = candidates.filter { isCompatible(it, reading) }
        byCodes(reading, compatible, homes, within)?.let { return Placement(it) }

        // 2. The house: its own codes, else the supply address, else the only home.
        val house: HousePick? = when {
            within != null -> HousePick(within, null)
            !reading.isTiedToHome -> null
            else -> homeNamed(reading, homes)?.let { HousePick(it, null) } ?: home(reading.supplyAddress, homes)
        }
        return when (val decision = decide(reading, compatible, house?.id, within, homes)) {
            is Decision.Existing, is Decision.NewUnder -> Placement(decision, house?.check)
            Decision.NewStandalone, Decision.Undecided -> Placement(decision)
        }
    }

    /**
     * 1. The codes: the subscription they say it is, or undecided between several; null when no code decides. A client
     * code alone covers every place a customer has with the provider, so with several homes it can't tell them apart.
     */
    private fun byCodes(reading: Reading, compatible: List<Subscription>, homes: List<Home>, within: UUID?): Decision? {
        val scored = compatible.map { it to score(it, reading) }.filter { it.second > 0 }
        val best = scored.maxOfOrNull { it.second } ?: return null
        val customerOnly = best < contractWeight
        val cantTellHomesApart = customerOnly && reading.isTiedToHome && homes.size > 1 && within == null
        val top = scored.filter { it.second == best }
        return when {
            cantTellHomesApart -> null
            top.size == 1 -> Decision.Existing(top[0].first.id)
            else -> Decision.Undecided
        }
    }

    /** Steps 3 and 4: the provider inside the house, or a new subscription. */
    private fun decide(
        reading: Reading,
        compatible: List<Subscription>,
        house: UUID?,
        within: UUID?,
        homes: List<Home>,
    ): Decision {
        val inAHouse = reading.isTiedToHome || within != null
        // 3. The provider, inside that house (or, for a phone plan, among those on their own).
        val provider = reading.provider?.let(::providerWords).orEmpty()
        val place = when {
            provider.isEmpty() -> emptyList()
            inAHouse -> house?.let { home -> compatible.filter { it.parentId == home } }.orEmpty()
            else -> compatible.filter { it.parentId == null }
        }
        val sameProvider = place.filter { subscription ->
            subscription.provider?.let { theirs -> providerWords(theirs).any { it in provider } } ?: false
        }
        // 4. Else a new one.
        return when {
            sameProvider.size == 1 -> Decision.Existing(sameProvider[0].id)
            sameProvider.size > 1 -> Decision.Undecided
            !inAHouse -> Decision.NewStandalone
            house != null -> Decision.NewUnder(house)
            homes.isEmpty() -> Decision.NewStandalone
            else -> Decision.Undecided
        }
    }

    /** What a contract number weighs: below it, only codes that name the customer agree. */
    private val contractWeight: Int
        get() = SubscriptionCode.all.first { it.family == SubscriptionCode.Family.CONTRACT }.weight

    /** How strongly the codes say this is the document's contract; 0 when none agree. */
    internal fun score(subscription: Subscription, reading: Reading): Int = SubscriptionCode.all.sumOf { code ->
        val read = reading.codes[code]
        val kept = subscription.codes[code]
        if (read != null && kept != null && code.normalized(kept) == code.normalized(read)) code.weight else 0
    }

    /** Never the one: a different consumption point or line, or another service. */
    internal fun isCompatible(subscription: Subscription, reading: Reading): Boolean {
        val pointDiffers = SubscriptionCode.all.filter { it.namesOnePoint }.any { code ->
            val read = reading.codes[code]
            val kept = subscription.codes[code]
            read != null && kept != null && code.normalized(kept) != code.normalized(read)
        }
        if (pointDiffers) return false
        val unspecified = ServiceKind.unspecified.key
        // Both through the service's one resolver, so a paper's "Gaze naturale" and a subscription's key name the
        // same service; a name it doesn't know tells nothing apart.
        val service = ServiceKind.service(reading.service)?.key
        val theirs = ServiceKind.service(subscription.service)?.key
        return service == null || theirs == null || service == theirs || service == unspecified || theirs == unspecified
    }

    /** The home whose own codes the document prints. */
    internal fun homeNamed(reading: Reading, homes: List<Home>): UUID? = homes.filter { home ->
        reading.codes.any { (code, read) ->
            code.homeFieldKeys.any { key -> home.fields[key]?.let(code::normalized) == code.normalized(read) }
        }
    }.singleOrNull()?.id

    /** Words in a provider's name that don't tell providers apart. */
    private val providerFillers =
        setOf("sa", "srl", "s", "a", "romania", "energie", "energy", "furnizare", "servicii", "si", "de", "the")

    /** The provider as people say it: "ENGIE Romania S.A." is "ENGIE". */
    fun shortProviderName(name: String): String {
        val kept = name.split(" ").filter { it.isNotEmpty() }.filter { word ->
            val folded = RomanianText.fold(word).replace(".", "")
            val named = TextRules.characters(folded).any { TextRules.isLetter(it) || TextRules.isNumber(it) }
            named && folded !in providerFillers
        }
        return if (kept.isEmpty()) name else kept.joinToString(" ")
    }

    /**
     * The words that name a provider, without the company form or the country: "ENGIE Romania S.A." and "Engie" agree.
     */
    fun providerWords(name: String): Set<String> {
        val words = mutableSetOf<String>()
        val current = StringBuilder()
        fun flush() {
            val word = current.toString()
            if (TextRules.characters(word).size >= 2 && word !in providerFillers) words.add(word)
            current.clear()
        }
        for (character in TextRules.characters(RomanianText.fold(name).replace(".", ""))) {
            if (TextRules.isLetter(character) || TextRules.isNumber(character)) current.append(character) else flush()
        }
        flush()
        return words
    }
}
