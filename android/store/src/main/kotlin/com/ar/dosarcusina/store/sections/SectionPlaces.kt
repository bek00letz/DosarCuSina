package com.ar.dosarcusina.store.sections

import com.ar.dosarcusina.catalog.Behavior
import com.ar.dosarcusina.catalog.DocumentNaming
import com.ar.dosarcusina.catalog.Role
import com.ar.dosarcusina.core.values.RomanianText
import com.ar.dosarcusina.store.BinderView
import com.ar.dosarcusina.store.Tables
import com.ar.dosarcusina.store.schema.Asset
import com.ar.dosarcusina.store.schema.CategoryTemplate
import com.ar.dosarcusina.store.templates.behavior
import com.ar.dosarcusina.store.templates.byKey
import com.ar.dosarcusina.store.templates.key
import com.ar.dosarcusina.store.templates.keys
import java.util.UUID

/**
 * Where a section can be filed, as the iOS app's `AssetActions+Move.swift` and `canFile`: "Mută la…"
 * (a document under another person, a tenancy or a plant under another home), where a new section
 * goes when nobody said (a plant into the household's only home), and the one rule that nothing is
 * filed under itself. Always by what a category does (`CategoryBehavior`: the part it may belong to,
 * its role), never by its key. Read over any view of the binder: as stored, or a step's.
 */
// The iOS type's questions about where a section goes, one function each.
@Suppress("TooManyFunctions")
object SectionPlaces {
    /** The categories by key, as [view] has them, each once (`TemplateStore.templatesByKey`). */
    fun categories(view: BinderView): Map<String, CategoryTemplate> =
        view.all(Tables.templates).sortedWith(compareBy({ it.homeOrder }, { it.createdAt })).byKey()

    /**
     * The categories of the parents [child] can be filed under, from what its category does, never its
     * key: every category that plays the part it may belong to (a subscription or a plant under a
     * home), else its current parent's category, else the people a personal document filed under no
     * one goes under. Empty when it isn't something filed under something else.
     */
    fun parentKeys(view: BinderView, child: Asset): Set<String> {
        val byKey = categories(view)
        val behavior = behavior(byKey, child.templateKey)
        val role = behavior.mayBelongTo
        val parent = child.parent?.let { view.row(Tables.assets, it) }
        val holder = if (behavior.role == Role.PERSONAL_DOCUMENT) byKey.key(withRole = Role.HOLDER) else null
        return when {
            role != null -> byKey.values.keys(playing = role)
            parent != null -> setOf(parent.templateKey)
            holder != null -> setOf(holder)
            else -> emptySet()
        }
    }

    /** Whether "Mută la…" is offered: [child] is something that can be filed under something else. */
    fun canMove(view: BinderView, child: Asset): Boolean = parentKeys(view, child).isNotEmpty()

    /** Whether "O persoană nouă" is offered: only personal documents go under people. */
    fun offersNewMember(view: BinderView, child: Asset): Boolean {
        val byKey = categories(view)
        if (behavior(byKey, child.templateKey).role != Role.PERSONAL_DOCUMENT) return false
        val holder = byKey.key(withRole = Role.HOLDER) ?: return false
        return holder in parentKeys(view, child)
    }

    /** Whether standing on its own is offered: something that may belong to a home, filed under one now. */
    fun offersStandalone(view: BinderView, child: Asset): Boolean =
        child.parent != null && behavior(categories(view), child.templateKey).mayBelongTo != null

    /**
     * The other parents [child] can move to: of a category it can be filed under, never its current
     * parent, itself or anything filed under it. Examples and real records stay apart. By name.
     */
    fun moveDestinations(view: BinderView, child: Asset): List<Asset> {
        val keys = parentKeys(view, child)
        if (keys.isEmpty()) return emptyList()
        val excluded = descendants(view, child).map { it.id }.toSet() + child.id +
            listOfNotNull(child.parent?.let { view.row(Tables.assets, it) }?.id)
        return view.all(Tables.assets)
            .filter { it.templateKey in keys && it.id !in excluded && it.isExample == child.isExample }
            .sortedWith(byName)
    }

    /**
     * The sections a section of a category that may belong to another part (a plant, a subscription:
     * a home) can be filed under, by name: every section whose category plays that part. Examples and
     * real records stay apart. Empty for a category that doesn't say.
     */
    fun possibleParents(view: BinderView, behavior: Behavior, isExample: Boolean = false): List<Asset> {
        val role = behavior.mayBelongTo ?: return emptyList()
        val keys = categories(view).values.keys(playing = role)
        return view.all(Tables.assets).filter { it.templateKey in keys && it.isExample == isExample }.sortedWith(byName)
    }

    /**
     * Where a new section goes when the person didn't say: under the household's only section of the
     * part its category may belong to (a plant into the only home), when its category says so
     * (`goesUnderTheOnlyOne`). With none or several, none: it stands on its own, and "Mută la…" files
     * it later.
     */
    fun automaticParent(view: BinderView, behavior: Behavior, isExample: Boolean = false): Asset? {
        if (!behavior.goesUnderTheOnlyOne) return null
        return possibleParents(view, behavior, isExample).singleOrNull()
    }

    /**
     * The name a document would take under [newHolder], when it is named after its current holder
     * ("Carte de identitate – Manole Corina"). None otherwise.
     */
    fun renamedForHolder(view: BinderView, child: Asset, newHolder: String): String? {
        val holder = child.parent?.let { view.row(Tables.assets, it) }?.name
        return DocumentNaming.renamed(child.name, holder, newHolder)
    }

    /**
     * The one rule for filing something under something else, in the app and in a restored backup:
     * never under itself, nor under anything filed under it.
     */
    fun canFile(view: BinderView, child: Asset, parent: Asset): Boolean {
        val seen = HashSet<UUID>()
        var current: Asset? = parent
        while (current != null) {
            if (current.id == child.id || !seen.add(current.id)) return false
            current = current.parent?.let { view.row(Tables.assets, it) }
        }
        return true
    }

    /** Everything filed under [asset], at any depth, each once. */
    fun descendants(view: BinderView, asset: Asset): List<Asset> {
        val result = ArrayList<Asset>()
        val queue = ArrayDeque(children(view, asset))
        val seen = hashSetOf(asset.id)
        while (queue.isNotEmpty()) {
            val next = queue.removeLast()
            if (!seen.add(next.id)) continue
            result += next
            queue.addAll(children(view, next))
        }
        return result
    }

    private fun children(view: BinderView, asset: Asset): List<Asset> =
        view.pointingAt(Tables.assets, "parent", asset.pk).mapNotNull { view.row(Tables.assets, it) }

    private fun behavior(byKey: Map<String, CategoryTemplate>, key: String): Behavior =
        byKey[key]?.behavior ?: Behavior.STANDARD

    /** By name, as a person reads a list: case and diacritics set aside, then as written. */
    private val byName: Comparator<Asset> = compareBy<Asset>({ RomanianText.fold(it.name) }, { it.name })
}
