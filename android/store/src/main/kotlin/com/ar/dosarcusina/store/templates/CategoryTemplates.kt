package com.ar.dosarcusina.store.templates

import com.ar.dosarcusina.archive.v3.CategoryBehavior
import com.ar.dosarcusina.catalog.Behavior
import com.ar.dosarcusina.catalog.Box
import com.ar.dosarcusina.catalog.BoxGrouping
import com.ar.dosarcusina.catalog.CategoryParts
import com.ar.dosarcusina.catalog.CategorySwitches
import com.ar.dosarcusina.core.values.KeptObject
import com.ar.dosarcusina.store.schema.CategoryTemplate
import com.ar.dosarcusina.store.schema.keptBehavior
import com.ar.dosarcusina.store.schema.keptBlueprints
import com.ar.dosarcusina.store.schema.keptComponents
import com.ar.dosarcusina.store.schema.keptSections
import com.ar.dosarcusina.store.schema.withDefinition

// A category as the rules read it, over its stored columns (schema/KeptValues.kt): what it does
// (its typed behaviour), its parts the switches read and write, its box on the binder, and finding
// a category by the part it plays (the iOS app's CategoryRoles.swift), never by its key.

/** What the category does in the binder (`CategoryTemplate.behavior`); the standard behaviour when it says nothing. */
val CategoryTemplate.behavior: Behavior
    get() = Behavior.of(keptBehavior?.value)

/** The parts of its definition its switches read and write. */
val CategoryTemplate.parts: CategoryParts
    get() = CategoryParts(keptSections.items, keptBlueprints.items, pocketsRaw, behavior)

/** The person's choice of one box or one each; none while they haven't chosen, or for one a newer build wrote. */
val CategoryTemplate.chosenGrouping: BoxGrouping?
    get() = BoxGrouping.of(boxGroupingRaw)

/** How the category's sections show on the binder: the person's choice, else the catalog's (`BoxGrouping.of`). */
val CategoryTemplate.grouping: BoxGrouping
    get() = BoxGrouping.of(behavior, boxGroupingRaw)

/** Whether the category's sections share one box on the binder, which lists them all, wherever they are filed. */
val CategoryTemplate.groupsSections: Boolean
    get() = grouping == BoxGrouping.GROUPED

/** What the person is offered for the category now that it has [sections] sections ([BoxGrouping.offer]). */
fun CategoryTemplate.groupingOffer(sections: Int): BoxGrouping? = BoxGrouping.offer(behavior, grouping, sections)

/**
 * Whether a section of this category filed under the section in row [forSectionUnder] (none: on its own)
 * shows in a box on the binder: its own box on its own, or its category's when they share one.
 */
fun CategoryTemplate.hasBox(forSectionUnder: Long?): Boolean =
    behavior.hasSectionBoxes && (forSectionUnder == null || groupsSections)

/**
 * The switches a category answers (`CategorySwitches(reading:)`): its parts, and the household's
 * choice of one box. A category an earlier version made with one box of the whole category's
 * answers one box too.
 */
val CategoryTemplate.switches: CategorySwitches
    get() = CategorySwitches.reading(parts, if (behavior.box == Box.WHOLE_CATEGORY) BoxGrouping.GROUPED else grouping)

/**
 * A category of one's own with [parts] (`CategoryTemplate.apply` for one of one's own): the sections,
 * deadlines and behaviour a newer build wrote that this one can't read stay, and only what this
 * build reads differently is written. A built-in is always the catalog's definition, whole.
 */
fun CategoryTemplate.withParts(parts: CategoryParts): CategoryTemplate {
    check(!isBuiltIn) { "A built-in's definition is the catalog's" }
    return withBehavior(parts.behavior).let { row ->
        row.withDefinition(
            keptSections.replacingItems(parts.sections),
            keptBlueprints.replacingItems(parts.blueprints),
            keptComponents,
            row.keptBehavior,
        ).copy(pocketsRaw = parts.pockets, builtInVersion = 0)
    }
}

/**
 * A category of one's own doing [behavior]: what it keeps that this build doesn't read stays; the
 * standard behaviour with nothing more is stored as none.
 */
fun CategoryTemplate.withBehavior(behavior: Behavior): CategoryTemplate {
    check(!isBuiltIn) { "A built-in's behaviour is the catalog's" }
    val stored = keptBehavior
    val written = stored?.value?.let(behavior::writing) ?: behavior.stored
    val kept = (stored ?: KeptObject.made(CategoryBehavior(), CategoryBehavior.codec)).replacingValue(written)
        .omitted { Behavior.of(it) == Behavior.STANDARD }
    return withDefinition(keptSections, keptBlueprints, keptComponents, kept)
}

/**
 * The category with the person's choice of [grouping] (`TemplateStore.setGrouping`'s rule), kept
 * even when it is what the catalog says, so a later catalog never turns it back; none when the
 * category has no such choice (its box isn't one per section) or chose it already.
 */
fun CategoryTemplate.choosingGrouping(grouping: BoxGrouping): CategoryTemplate? {
    if (!behavior.offersGrouping || chosenGrouping == grouping) return null
    return copy(boxGroupingRaw = grouping.raw)
}

/**
 * A category of one's own an earlier version made with one box of its own for the whole category,
 * with its box one per section and grouped instead, which looks the same
 * ([CategorySwitches.boxAsGrouping], the iOS app's `TemplateStore.takeBoxAsGrouping`); none when
 * nothing changes.
 */
fun CategoryTemplate.takingBoxAsGrouping(): CategoryTemplate? =
    CategorySwitches.boxAsGrouping(parts, isBuiltIn, chosenGrouping)?.let { taken ->
        withBehavior(taken.behavior).copy(boxGroupingRaw = taken.grouping.raw)
    }
