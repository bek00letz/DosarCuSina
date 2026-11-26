package com.ar.dosarcusina.catalog

import com.ar.dosarcusina.core.attention.SectionNoun
import java.time.Instant
import java.util.UUID

/** One box on the Dosar grid, as the iOS app's `BinderBoxID`, and how it is written in the saved order. */
sealed interface BinderBoxID {
    /** How the box is written in the saved order (`storageKey`). */
    val storageKey: String

    /** A top-level section: the car, the flat, PawPaw. */
    data class Section(val id: UUID) : BinderBoxID {
        override val storageKey: String get() = "$SECTION_PREFIX${id.toString().lowercase()}"
    }

    /** A box that gathers one category: Acte, Garanții, Abonamente, or a category's grouped sections. */
    data class Category(val key: String) : BinderBoxID {
        override val storageKey: String get() = "$CATEGORY_PREFIX$key"
    }

    /** People and firms. */
    data object Agenda : BinderBoxID {
        override val storageKey: String get() = AGENDA
    }

    companion object {
        private const val AGENDA = "agenda"
        private const val SECTION_PREFIX = "asset:"
        private const val CATEGORY_PREFIX = "category:"
        private val ID = Regex("[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}")

        /** The box a saved order names; none for anything else. */
        fun of(storageKey: String): BinderBoxID? = when {
            storageKey == AGENDA -> Agenda
            storageKey.startsWith(SECTION_PREFIX) ->
                storageKey.removePrefix(SECTION_PREFIX).takeIf(ID::matches)?.let { Section(UUID.fromString(it)) }
            storageKey.startsWith(CATEGORY_PREFIX) ->
                storageKey.removePrefix(CATEGORY_PREFIX).takeIf { it.isNotEmpty() }?.let(::Category)
            else -> null
        }
    }
}

/**
 * The binder's boxes, the part the data side needs, as the iOS app's `BinderLayout`
 * (ios/DosarCuSina/Views/Dosar/BinderLayout.swift). What each category gets is its own data
 * ([Behavior.box]), never its key:
 * - a category with many small records (Acte, Garanții, Abonamente) gets one box, once it holds
 *   something ([holds]: a person's documents' box holds the people too);
 * - every other category on the home screen gets one box per top-level section ([sectionBoxes]),
 *   or, when its sections are grouped, one box for all of them, wherever they are filed, once it
 *   has any;
 * - a category that lives inside another (tenancies in a home, people in Acte) gets none;
 * - Agenda comes last, once it holds someone;
 * - a category with nothing yet has no box: it is folded into the add box, which names it
 *   ([addBoxNames]), so the binder still shows what it can hold.
 *
 * [defaultOrder] is the order before the person rearranges the boxes, and [regrouped] keeps their
 * saved order around a category whose sections are grouped into one box or given a box each again.
 * Merging the saved order with the boxes that exist, and dragging, come with the screens.
 */
object BinderLayout {
    /** A section, as the grid places it. */
    data class SectionInfo(val id: UUID, val templateKey: String, val isTopLevel: Boolean, val createdAt: Instant)

    /** A category, as the grid and „Adaugă o secțiune” read it (the iOS app's `TemplateInfo`). */
    data class CategoryInfo(
        val key: String,
        /** Its name, as the add box writes it („Garanții”): the category's own words. */
        val name: String,
        val homeOrder: Int,
        val isOnHome: Boolean,
        val behavior: Behavior,
        /** Its sections share one box ([BoxGrouping.of] is [BoxGrouping.GROUPED]). */
        val groupsSections: Boolean = false,
        val createdAt: Instant = Instant.EPOCH,
    )

    /** The most the add box names before it says there is more („…”). */
    const val ADD_BOX_NAME_LIMIT: Int = 4

    /** What the add box names, at most [ADD_BOX_NAME_LIMIT], and whether there are more. */
    data class AddBoxNames(val names: List<String>, val more: Boolean)

    /**
     * Whether [category]'s one box holds a section of the category [sectionKey] names (whose
     * category is [sectionCategory], when it is installed): its own sections, and, for the box of
     * personal documents (Acte), the people they are filed under. The one rule the grid's boxes and
     * their lines read.
     */
    fun holds(category: CategoryInfo, sectionCategory: CategoryInfo?, sectionKey: String): Boolean =
        sectionKey == category.key ||
            (category.behavior.role == Role.PERSONAL_DOCUMENT && sectionCategory?.behavior?.role == Role.HOLDER)

    /** Whether [category] has anything on the binder yet, by [holds]. */
    fun holdsAnything(
        category: CategoryInfo,
        categories: Map<String, CategoryInfo>,
        sections: List<SectionInfo>,
    ): Boolean = sections.any { holds(category, categories[it.templateKey], it.templateKey) }

    /**
     * What the add box names: the categories on the binder that have no box yet, only those
     * „Adaugă o secțiune” offers ([offered], [SectionOffers.inOrder]): first the boxes folded into it
     * (a whole category's: Acte, Garanții, Abonamente), where the binder would show them, then the
     * rest in the order they are offered; at most [ADD_BOX_NAME_LIMIT], and whether there are more.
     * A category without a box of its own (tenants, people) is never named: its sections live inside
     * another. Empty once everything has a box.
     */
    fun addBoxNames(
        offered: List<CategoryInfo>,
        categories: List<CategoryInfo>,
        sections: List<SectionInfo>,
    ): AddBoxNames {
        val byKey = byKey(categories)
        val waiting = offered.filter {
            it.isOnHome && it.behavior.box != Box.INSIDE_OTHER && !holdsAnything(it, byKey, sections)
        }
        val (folded, rest) = waiting.partition { it.behavior.box == Box.WHOLE_CATEGORY }
        val ordered = folded.sortedBy { it.homeOrder } + rest
        return AddBoxNames(ordered.take(ADD_BOX_NAME_LIMIT).map { it.name }, ordered.size > ADD_BOX_NAME_LIMIT)
    }

    /**
     * The boxes the grid shows, in the order it shows them before the person rearranges them: the
     * categories by their home order, each as its box says, then the top-level sections whose
     * category isn't installed (as a standard box), then Agenda when [hasContacts].
     */
    fun defaultOrder(
        categories: List<CategoryInfo>,
        sections: List<SectionInfo>,
        hasContacts: Boolean,
    ): List<BinderBoxID> {
        val byKey = byKey(categories)
        val topLevel = sections.filter { it.isTopLevel }.sortedBy { it.createdAt }
        val boxes = mutableListOf<BinderBoxID>()
        for (category in categories.sortedBy { it.homeOrder }.filter { it.isOnHome }) {
            boxes += boxesOf(category, byKey, sections, topLevel)
        }
        boxes += topLevel.filter { it.templateKey !in byKey }.map { BinderBoxID.Section(it.id) }
        if (hasContacts) boxes += BinderBoxID.Agenda
        return boxes
    }

    /** The boxes one category on the home screen has. */
    private fun boxesOf(
        category: CategoryInfo,
        byKey: Map<String, CategoryInfo>,
        sections: List<SectionInfo>,
        topLevel: List<SectionInfo>,
    ): List<BinderBoxID> = when {
        // Folded into the add box until it holds something.
        category.behavior.box == Box.WHOLE_CATEGORY ->
            listOfNotNull(BinderBoxID.Category(category.key).takeIf { holdsAnything(category, byKey, sections) })
        category.behavior.box == Box.INSIDE_OTHER -> emptyList()
        category.groupsSections -> {
            val hasAny = sections.any { it.templateKey == category.key }
            listOfNotNull(BinderBoxID.Category(category.key).takeIf { hasAny })
        }
        else -> sectionBoxes(category.key, topLevel)
    }

    /** The categories by key, the first of each kept. */
    private fun byKey(categories: List<CategoryInfo>): Map<String, CategoryInfo> {
        val byKey = LinkedHashMap<String, CategoryInfo>()
        for (category in categories) byKey.putIfAbsent(category.key, category)
        return byKey
    }

    /** The boxes a category's sections have when each has its own: the top-level ones, oldest first. */
    fun sectionBoxes(key: String, sections: List<SectionInfo>): List<BinderBoxID> =
        sections.filter { it.isTopLevel && it.templateKey == key }.sortedBy { it.createdAt }
            .map { BinderBoxID.Section(it.id) }

    /**
     * The saved order once a category's section boxes ([members], in the order they show) are
     * grouped into its one box, or that box is split into them again: the new box takes the place of
     * the first of the old ones, so nothing else moves. An order that holds none of them stays as it
     * is, and the grid puts the new box where its defaults say.
     */
    fun regrouped(
        saved: List<BinderBoxID>,
        key: String,
        members: List<BinderBoxID>,
        grouped: Boolean,
    ): List<BinderBoxID> {
        val box = BinderBoxID.Category(key)
        val sections = members.toSet()
        return when {
            grouped && saved.none { it in sections } -> saved
            grouped -> grouping(saved, box, sections)
            box !in saved -> saved
            else -> splitting(saved, box, members)
        }
    }

    /** [saved] with the first of [sections] made [box], and the others gone. */
    private fun grouping(saved: List<BinderBoxID>, box: BinderBoxID, sections: Set<BinderBoxID>) = buildList {
        for (id in saved.filter { it != box }) {
            if (id !in sections) add(id) else if (box !in this) add(box)
        }
    }

    /** [saved] with [box] made its [members] again. */
    private fun splitting(saved: List<BinderBoxID>, box: BinderBoxID, members: List<BinderBoxID>) = buildList {
        for (id in saved.filter { it !in members }) {
            if (id == box) addAll(members) else add(id)
        }
    }
}

/** What [this] category's sections are called when a box counts them; none counts them as sections. */
val Behavior.noun: SectionNoun? get() = SectionNoun.of(sectionNoun)
