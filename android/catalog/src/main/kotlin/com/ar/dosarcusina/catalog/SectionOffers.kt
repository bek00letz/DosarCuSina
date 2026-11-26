package com.ar.dosarcusina.catalog

import com.ar.dosarcusina.catalog.BinderLayout.CategoryInfo

/**
 * What „Adaugă o secțiune” offers, read from the categories themselves, as the iOS app's
 * `SectionOffers` (ios/DosarCuSina/Services/Templates/SectionOffers.swift): the ones most households
 * start with, in the order they declare ([Behavior.shortlistOrder]), then every other category in
 * the binder's order. A category whose sections are added only under another one (a tenancy) isn't
 * offered on its own. No screen names a built-in, so a category of the person's own is listed like
 * any other. Each option's title is [Behavior.offerTitle].
 */
data class SectionOffers(
    /** „Cele mai des folosite”. */
    val shortlist: List<CategoryInfo>,
    /** „Alte categorii”: everything else that can be added on its own. */
    val others: List<CategoryInfo>,
) {
    /** Where a category is offered. */
    enum class Group { SHORTLIST, OTHERS }

    /**
     * Every category that can be added on its own, in the order it is offered: the shortlist, then
     * the others. The binder's add box names from it ([BinderLayout.addBoxNames]).
     */
    val inOrder: List<CategoryInfo> get() = shortlist + others

    companion object {
        /** What is offered among [categories], one of each key (the first by home order, then age). */
        fun of(categories: List<CategoryInfo>): SectionOffers {
            val byHome = compareBy<CategoryInfo> { it.homeOrder }.thenBy { it.createdAt }
            val offered = oncePerKey(categories).filter { group(it.behavior) != null }.sortedWith(byHome)
            val shortlist = offered.filter { group(it.behavior) == Group.SHORTLIST }
                .sortedWith(compareBy<CategoryInfo> { it.behavior.shortlistOrder ?: 0 }.thenBy { it.homeOrder })
            return SectionOffers(shortlist, offered.filter { group(it.behavior) == Group.OTHERS })
        }

        /**
         * The one rule for where a category is offered, from what it declares: among the ones most
         * households start with when it has a place there, else with the others; null when its
         * sections are only added under another section (a tenancy, from its home).
         */
        fun group(behavior: Behavior): Group? = when {
            behavior.addedOnlyUnderParent -> null
            behavior.shortlistOrder == null -> Group.OTHERS
            else -> Group.SHORTLIST
        }

        /**
         * One category per key when the binder holds two copies of one (before they are joined): the
         * one first by home order, then the older, as the iOS app's `CategoryTemplate.oncePerKey`.
         */
        private fun oncePerKey(categories: List<CategoryInfo>): List<CategoryInfo> {
            val byHome = compareBy<CategoryInfo> { it.homeOrder }.thenBy { it.createdAt }
            val chosen = categories.groupBy { it.key }.mapValues { (_, copies) -> copies.minWith(byHome) }
            return categories.filter { chosen[it.key] === it }
        }
    }
}
