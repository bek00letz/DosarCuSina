package com.ar.dosarcusina.core.subscriptions

import com.ar.dosarcusina.core.values.NamedChoice
import com.ar.dosarcusina.core.values.RecurrenceInterval
import com.ar.dosarcusina.core.values.option

/**
 * Where a subscription is listed in Abonamente, as the iOS app's `SubscriptionGroup`: what it is, grouped. Each
 * service declares its group ([Service.group]); the person can move one to another group, and that choice is the
 * subscription's own value, so a newer catalog never moves it. [key] is stored. The groups and their order are the
 * catalog's ([SubscriptionCatalog.groups]).
 */
data class SubscriptionGroup(override val key: String, override val label: String) : NamedChoice {
    override val aliases: List<String> get() = emptyList()

    override fun toString(): String = key

    /** What a subscription's values say about where it is listed: its stored group and service, as stored. */
    data class Stored(val group: String?, val service: String?)

    /** One group's items, as listed; [group] null for the one list of a category that keeps no group. */
    data class Listed<T>(val group: SubscriptionGroup?, val items: List<T>)

    /** A row a pocket shows: its item, and the group it opens when it is the first of its group. */
    data class FirstRow<T>(val opens: SubscriptionGroup?, val item: T)

    companion object {
        /** Every group, in the order subscriptions are listed under them. */
        val all: List<SubscriptionGroup> get() = SubscriptionCatalog.builtIn.groups

        /** The group a stored or typed value names; null for none. */
        fun stored(text: String?): SubscriptionGroup? = text?.let { all.option(it) }

        /** The group of what a service is; the unspecified group when it isn't known. */
        fun of(service: String?): SubscriptionGroup =
            ServiceKind.service(service)?.group ?: SubscriptionCatalog.builtIn.unspecifiedGroup

        /** Where a subscription is listed: the group it was put in, else its service's, else the unspecified one. */
        fun listedIn(values: Stored): SubscriptionGroup = stored(values.group) ?: of(values.service)

        /**
         * [items] under their groups, in the groups' order, each keeping the order it came in; empty groups left out.
         */
        fun <T> grouping(items: List<T>, values: (T) -> Stored): List<Listed<T>> {
            val placed = items.map { listedIn(values(it)) to it }
            return all.mapNotNull { group ->
                val members = placed.filter { it.first == group }.map { it.second }
                if (members.isEmpty()) null else Listed(group, members)
            }
        }

        /**
         * A category's sections as every list of them shows them: under their groups ([grouping]) when the category
         * keeps the group field ([keepsGroups]: Abonamente), else as one list with no group. The one listing for
         * Abonamente's page, a home's Abonamente pocket and its full list.
         */
        fun <T> listing(items: List<T>, keepsGroups: Boolean, values: (T) -> Stored): List<Listed<T>> = when {
            keepsGroups -> grouping(items, values)
            items.isEmpty() -> emptyList()
            else -> listOf(Listed(null, items))
        }

        /**
         * The first [limit] items of [listing] in its order, for a pocket that shows only a few, each with the group it
         * opens: the first item of each group, when the listing has more than one group to tell apart; null otherwise.
         */
        fun <T> firstRows(listing: List<Listed<T>>, limit: Int): List<FirstRow<T>> {
            val headed = listing.size > 1
            return listing.flatMap { listed ->
                listed.items.mapIndexed { index, item ->
                    FirstRow(if (headed && index == 0) listed.group else null, item)
                }
            }.take(limit.coerceAtLeast(0))
        }
    }
}

/**
 * How often a subscription is paid, as the iOS app's `BillingCycle`: stored by [key]; what one cycle lasts is its
 * [interval], the one rule the monthly cost ([SubscriptionMath]) and the missing bill ([BillHistory]) read.
 */
data class BillingCycle(
    override val key: String,
    override val label: String,
    override val aliases: List<String>,
    val interval: RecurrenceInterval,
) : NamedChoice {
    companion object {
        /** Every cycle, in the order they are offered. */
        val all: List<BillingCycle> get() = SubscriptionCatalog.builtIn.billingCycles

        /** How long one cycle of the stored or typed [text] lasts; the catalog's unknown cycle (a month) otherwise. */
        fun interval(text: String?): RecurrenceInterval =
            text?.let { all.option(it) }?.interval ?: SubscriptionCatalog.builtIn.unknownCycle
    }
}
