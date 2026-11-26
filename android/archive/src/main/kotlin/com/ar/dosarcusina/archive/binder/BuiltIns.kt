package com.ar.dosarcusina.archive.binder

import com.ar.dosarcusina.archive.v3.CategoryBehavior
import com.ar.dosarcusina.archive.v3.ChangeTime
import com.ar.dosarcusina.archive.v3.ComponentDefinition
import com.ar.dosarcusina.archive.v3.FieldSection
import com.ar.dosarcusina.archive.v3.ObligationBlueprint
import com.ar.dosarcusina.core.values.KeptList
import com.ar.dosarcusina.core.values.KeptObject
import java.time.Instant

/**
 * The app's own built-in categories: the one seam between the archive and the catalog.
 *
 * On iOS a built-in always takes the app's own definition, whatever an archive says of it, and
 * an archive brings only the household's choices (its order, whether it shows on the binder,
 * its box and its lock); built-ins an archive doesn't mention are installed. The catalog is the
 * iOS app's, exported to `shared/catalog/` by its tests and read by `android/catalog`
 * (`com.ar.dosarcusina.catalog.Catalog`), which implements this; the archive itself keeps no
 * definitions, so every importer is handed one.
 */
interface BuiltIns {
    /** The app's own definition of the built-in [key], or null when [key] names none. */
    fun definition(key: String): BuiltInDefinition?

    /** Every built-in the app installs, in the catalog's order. */
    val all: List<BuiltInDefinition>

    /** Whether [key] names one of the app's built-in categories. */
    fun isBuiltIn(key: String): Boolean = definition(key) != null
}

/** A built-in category as the catalog defines it. */
data class BuiltInDefinition(
    val key: String,
    val name: String,
    val summary: String?,
    val symbol: String,
    val tint: String,
    val heroStyle: String,
    val version: Int,
    val isOnHomeByDefault: Boolean,
    val isSensitiveByDefault: Boolean,
    val sections: List<FieldSection>,
    val blueprints: List<ObligationBlueprint>,
    val components: List<ComponentDefinition>,
    val pockets: List<String>,
    val behavior: CategoryBehavior,
) {
    /**
     * The category with this definition, whole, on the record already [here] when there is one
     * (the iOS app's `CategoryTemplate.apply` for a built-in): the household's choices stay as
     * they are there (its place, whether it shows, its box) and so does its last change, for a
     * definition the app gives is no one's change. A new one shows as the catalog says, at place
     * 0 until it is given one, and starts with no known change time.
     */
    fun template(here: BinderTemplate?, createdAt: Instant): BinderTemplate = BinderTemplate(
        key = key, name = name, summary = summary, symbol = symbol, tint = tint, heroStyle = heroStyle,
        isBuiltIn = true, version = version,
        homeOrder = here?.homeOrder ?: 0, isOnHome = here?.isOnHome ?: isOnHomeByDefault,
        sections = KeptList.made(sections, FieldSection.codec, FieldSection::key),
        blueprints = KeptList.made(blueprints, ObligationBlueprint.codec, ObligationBlueprint::key),
        components = KeptList.made(components, ComponentDefinition.codec, ComponentDefinition::key),
        pockets = pockets,
        behavior = KeptObject.made(behavior, CategoryBehavior.codec).omitted(CategoryBehavior::isStandard),
        boxGrouping = here?.boxGrouping, createdAt = createdAt, updatedAt = here?.updatedAt ?: ChangeTime.UNKNOWN,
    )
}
