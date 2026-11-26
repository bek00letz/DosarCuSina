package com.ar.dosarcusina.catalog

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
 * (ios/DosarCuSina/Views/Dosar/BinderLayout.swift): the boxes a category's sections have when each
 * has its own ([sectionBoxes]), and the person's saved order kept around a category whose sections
 * are grouped into one box or given a box each again ([regrouped]). The grid itself (which boxes
 * show, merged with the saved order) comes with the screens.
 */
object BinderLayout {
    /** A section, as the grid places it. */
    data class SectionInfo(val id: UUID, val templateKey: String, val isTopLevel: Boolean, val createdAt: Instant)

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
