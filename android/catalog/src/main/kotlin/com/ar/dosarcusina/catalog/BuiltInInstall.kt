package com.ar.dosarcusina.catalog

import com.ar.dosarcusina.archive.CategoryOrder
import com.ar.dosarcusina.archive.binder.Binder
import com.ar.dosarcusina.archive.binder.BinderAsset
import com.ar.dosarcusina.archive.binder.BinderTemplate
import com.ar.dosarcusina.archive.v3.FieldValues
import java.time.Instant

/**
 * What installing the built-ins changes in a binder ([BuiltInInstall.plan]): each category
 * written whole, the categories that go, the sections moved onto a category that replaced
 * theirs, and the locks new built-ins start with. Nothing in it when nothing changes.
 */
data class BuiltInInstallPlan(
    /** Categories installed, given the catalog's definition, or made a category of one's own. */
    val templates: List<BinderTemplate> = emptyList(),
    /** Keys of built-ins an earlier catalog had, which go. */
    val removedTemplates: Set<String> = emptySet(),
    /** Sections moved onto the built-in that replaced their category, their values' keys renamed. */
    val assets: List<BinderAsset> = emptyList(),
    /**
     * The lock each built-in installed here starts with, the catalog's: kept only where this
     * phone hasn't chosen one for its key already (a built-in installed again after starting
     * over), as the iOS app's `SectionLocks.adopt`. Never a lock lowered.
     */
    val startingLocks: Map<String, Boolean> = emptyMap(),
) {
    val changesAnything: Boolean
        get() = templates.isNotEmpty() || removedTemplates.isNotEmpty() || assets.isNotEmpty()
}

/**
 * The iOS app's `TemplateStore.installBuiltIns`, decided without the store: installs the
 * built-ins a binder lacks and gives the installed ones the catalog's definition whenever theirs
 * is from an older catalog or was made a category of one's own, keeping the household's choices.
 * The store writes the plan in one unit of work, as the app's own step: no record's change time
 * moves (`ChangeOrigin.app`).
 *
 * - A built-in's definition is the app's own, and the newest catalog in the binder decides it: a
 *   build whose catalog is older than one already in the binder leaves every built-in as it is,
 *   so two versions never write each other's categories back and forth.
 * - Only the person's choices are theirs: a category's place, whether it shows on the binder, its
 *   box and its lock (which lives on the phone, never in the record). They stay as they are.
 * - A built-in the catalog installs starts with no known change time (`ChangeTime.unknown`), so
 *   a backup carrying the person's choices for it still wins.
 * - Built-ins of earlier catalogs: a replaced key hands its sections, their values' keys renamed,
 *   to its successor and goes; a retired key with sections becomes a category of one's own, so
 *   nothing disappears, and one without goes only once the binder has all arrived
 *   ([binderIsWhole], `CloudArrival`), or its sections might come back without it.
 */
object BuiltInInstall {
    fun plan(catalog: Catalog, binder: Binder, now: Instant, binderIsWhole: Boolean = true): BuiltInInstallPlan {
        val existing = binder.templates.sortedBy(BinderTemplate::createdAt)
        // A newer build's catalog already shaped the built-ins: this one leaves them as they are.
        val newestInBinder = existing.filter(BinderTemplate::isBuiltIn).maxOfOrNull(BinderTemplate::version) ?: 0
        if (newestInBinder > catalog.version) return BuiltInInstallPlan()
        // Copies of one key are joined by `RecordsMeet`; until they are, the first is the one read.
        val byKey = LinkedHashMap<String, BinderTemplate>()
        for (template in existing) byKey.putIfAbsent(template.key, template)

        val written = LinkedHashMap<String, BinderTemplate>()
        val removed = LinkedHashSet<String>()
        val moved = LinkedHashMap<java.util.UUID, BinderAsset>()
        retireOldBuiltIns(catalog, binder, byKey, binderIsWhole, written, removed, moved)

        val locks = LinkedHashMap<String, Boolean>()
        var nextOrder = CategoryOrder.after(existing.map(BinderTemplate::homeOrder))
        for (definition in catalog.all) {
            val installed = byKey[definition.key]
            if (installed != null) {
                // A newer catalog upgrades it, and one changed from outside is put back; an older
                // one never writes over a newer one.
                if (!installed.isBuiltIn || installed.version < definition.version) {
                    written[definition.key] = definition.template(installed, installed.createdAt)
                }
            } else {
                written[definition.key] = definition.template(null, now).copy(homeOrder = nextOrder)
                if (definition.key !in binder.locks) locks[definition.key] = definition.isSensitiveByDefault
                nextOrder += 1
            }
        }
        return BuiltInInstallPlan(written.values.toList(), removed, moved.values.toList(), locks)
    }

    @Suppress("LongParameterList")
    private fun retireOldBuiltIns(
        catalog: Catalog,
        binder: Binder,
        byKey: MutableMap<String, BinderTemplate>,
        binderIsWhole: Boolean,
        written: MutableMap<String, BinderTemplate>,
        removed: MutableSet<String>,
        moved: MutableMap<java.util.UUID, BinderAsset>,
    ) {
        for ((oldKey, newKey) in catalog.replacedKeys) {
            for (asset in binder.assets.filter { it.templateKey == oldKey }) {
                moved[asset.id] = asset.copy(
                    templateKey = newKey,
                    values = asset.values.replacingValue(renamed(asset.values.value, catalog.replacedFieldKeys)),
                )
            }
            val old = byKey[oldKey]
            if (old != null && old.isBuiltIn) {
                byKey.remove(oldKey)
                removed += oldKey
            }
        }
        for (key in catalog.retiredKeys) {
            val old = byKey[key]?.takeIf(BinderTemplate::isBuiltIn) ?: continue
            if (binder.assets.any { it.templateKey == key }) {
                val kept = old.copy(isBuiltIn = false, version = 0)
                byKey[key] = kept
                written[key] = kept
            } else if (binderIsWhole) {
                byKey.remove(key)
                removed += key
            }
        }
    }

    /** [values] with each key [renames] names under its new key; values this build can't read stay as stored. */
    private fun renamed(values: FieldValues, renames: Map<String, String>): FieldValues =
        FieldValues(values.storage.mapKeys { (key, _) -> renames[key] ?: key }).addingUnreadable(values)
}
