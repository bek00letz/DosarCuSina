package com.ar.dosarcusina.archive.binder

import com.ar.dosarcusina.archive.v3.CategoryBehavior
import com.ar.dosarcusina.archive.v3.ComponentDefinition
import com.ar.dosarcusina.archive.v3.FieldSection
import com.ar.dosarcusina.archive.v3.ObligationBlueprint

/**
 * The app's own built-in categories: the one seam between the archive and the catalog.
 *
 * On iOS a built-in always takes the app's own definition, whatever an archive says of it, and
 * an archive brings only the household's choices (its order, whether it shows on the binder,
 * its box and its lock); built-ins an archive doesn't mention are installed. The shared catalog
 * (`shared/catalog/`, exported by an iOS test) comes in Phase 2; until then the Android app has
 * no definitions of its own, so [UntilTheSharedCatalog] says which keys are built-ins and gives
 * no definition, and a built-in keeps the definition the archive carries. Phase 2 implements
 * this over the catalog, and the importer follows iOS with nothing else to change.
 */
interface BuiltIns {
    /** Whether [key] names one of the app's built-in categories. */
    fun isBuiltIn(key: String): Boolean

    /** The app's own definition of the built-in [key], or null where this build has none. */
    fun definition(key: String): BuiltInDefinition?

    /** Every built-in the app installs, in the catalog's order. */
    val all: List<BuiltInDefinition>
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
)

/**
 * Phase 1's built-ins: the keys the format names (shared/schemas/dosar-v3.md, "Built-in keys"),
 * and no definitions until the shared catalog comes in Phase 2.
 */
object UntilTheSharedCatalog : BuiltIns {
    val KEYS: Set<String> = setOf(
        "vehicle", "home", "documents", "pet", "health", "purchase", "subscription", "other", "bike", "plants",
        "tenancy", "member", "espresso",
    )

    override fun isBuiltIn(key: String): Boolean = key in KEYS

    override fun definition(key: String): BuiltInDefinition? = null

    override val all: List<BuiltInDefinition> = emptyList()
}
