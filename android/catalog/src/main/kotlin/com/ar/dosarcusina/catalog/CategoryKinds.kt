package com.ar.dosarcusina.catalog

import com.ar.dosarcusina.archive.v3.CategoryBehavior
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive

// What a category does in the binder, typed, as the iOS app reads it
// (ios/DosarCuSina/Models/Templates/TemplateDefinition.swift, SectionPocket.swift, VisitKind.swift):
// the archive keeps a category's behaviour as written (com.ar.dosarcusina.archive.v3.CategoryBehavior),
// and these read it, each value this build doesn't know as the default that hides nothing. Raw
// values are part of the .dosar contract: never rename them. Kinds only; their words are the
// screens' (Phase 4).

/** A part of a section's page, in the one order pages show them (`SectionPocket`). */
enum class SectionPocket(val raw: String) {
    UPCOMING("upcoming"),
    TENANTS("tenants"),
    PRODUCTS("products"),
    SUBSCRIPTIONS("subscriptions"),
    PLANTS("plants"),
    DOCUMENTS("documents"),
    HISTORY("history"),
    PEOPLE("people"),
    MONEY("money"),
    KEY_FACTS("keyFacts"),
    ;

    companion object {
        /** What a page of a section shows when its category says nothing (`SectionPocket.standard`). */
        val STANDARD: List<SectionPocket> = listOf(UPCOMING, DOCUMENTS, HISTORY, PEOPLE, MONEY, KEY_FACTS)

        fun of(raw: String?): SectionPocket? = entries.firstOrNull { it.raw == raw }

        /** [pockets] in the one order, each once (`SectionPocket.ordered`). */
        fun ordered(pockets: Collection<SectionPocket>): List<SectionPocket> = pockets.distinct().sorted()

        /**
         * Stored pockets in the one order, each once, as raw keys: the ones this build knows in
         * their order, then any a newer build wrote, as written, so nothing it wrote is lost.
         */
        fun orderedRaw(raw: Collection<String>): List<String> {
            val known = ordered(raw.mapNotNull(::of)).map(SectionPocket::raw)
            return known + raw.filter { of(it) == null }.distinct()
        }
    }
}

/** How a category shows on the Dosar grid (`CategoryBehavior.Box`). */
enum class Box(val raw: String) {
    /** One box per top-level section: the car, the flat, PawPaw. */
    PER_SECTION("perSection"),

    /** One box for the whole category, which gathers many small records: Acte, Garanții, Abonamente. */
    WHOLE_CATEGORY("wholeCategory"),

    /** No box: its sections live inside another one (tenants in a home, people in Acte). */
    INSIDE_OTHER("insideOther"),
    ;

    companion object {
        fun of(raw: String?): Box? = entries.firstOrNull { it.raw == raw }
    }
}

/** What a category's own page lists (`CategoryBehavior.Listing`). */
enum class Listing(val raw: String) {
    PLAIN("plain"),
    BY_HOLDER("byHolder"),
    BY_WARRANTY("byWarranty"),
    BY_MONTHLY_COST("byMonthlyCost"),
    ;

    companion object {
        fun of(raw: String?): Listing? = entries.firstOrNull { it.raw == raw }
    }
}

/** The part a category plays for other categories (`CategoryBehavior.Role`). */
enum class Role(val raw: String) {
    /** A person things are filed under: their personal documents (a household member). */
    HOLDER("holder"),

    /** A personal document of a holder: an identity card, a passport. */
    PERSONAL_DOCUMENT("personalDocument"),

    /** An ongoing contract that bills and contracts file into. */
    SUBSCRIPTION("subscription"),

    /** A place the ongoing contracts tied to an address live under (a home). */
    HOME("home"),

    /** A vehicle the household keeps (a car). */
    VEHICLE("vehicle"),
    ;

    /** Whether sections of other categories can be filed under a section that plays it. */
    val holdsSections: Boolean get() = this in PARENTS

    companion object {
        /**
         * The parts another category's sections can say they belong to ("Ține de…": a home, a car,
         * a person), in the order a category of one's own offers them (`Role.parents`).
         */
        val PARENTS: List<Role> = listOf(HOME, VEHICLE, HOLDER)

        fun of(raw: String?): Role? = entries.firstOrNull { it.raw == raw }
    }
}

/**
 * Whether a category's sections each get a box on the Dosar grid or share one (`BoxGrouping`).
 * The catalog says which a category starts with ([Behavior.defaultGrouping]); the person can
 * choose the other for each category (`CategoryTemplate.boxGroupingRaw`).
 */
enum class BoxGrouping(val raw: String) {
    /** One box per section: the car, the other car. */
    SEPARATE("separate"),

    /** One box for all of the category's sections, which opens to their list ("Mașini"). */
    GROUPED("grouped"),
    ;

    companion object {
        /** The most sections a box each stays the only choice for: grouping is offered from two. */
        private const val GROUPED_FROM = 2

        fun of(raw: String?): BoxGrouping? = entries.firstOrNull { it.raw == raw }

        /**
         * The one rule for what the person is offered for a category: the other choice, or none.
         * Grouping is offered once its sections have boxes of their own and it has two or more;
         * splitting a grouped box again is always offered, so there is always a way back.
         */
        fun offer(behavior: Behavior, now: BoxGrouping, sections: Int): BoxGrouping? = when {
            !behavior.offersGrouping -> null
            now == GROUPED -> SEPARATE
            sections >= GROUPED_FROM -> GROUPED
            else -> null
        }

        /**
         * How a category's sections show on the binder: the person's choice ([chosen], a stored
         * key), else the catalog's, else one each. Only a category whose sections have boxes of
         * their own groups them; any other always reads [SEPARATE], as its box is its own (Acte has
         * one, tenants none). A choice a newer build wrote reads as the catalog's (`CategoryTemplate.grouping`).
         */
        fun of(behavior: Behavior, chosen: String?): BoxGrouping {
            if (!behavior.offersGrouping) return SEPARATE
            return of(chosen) ?: behavior.defaultGrouping ?: SEPARATE
        }
    }
}

/**
 * What a category's visits are, and so what the visit form asks (`VisitKind`). Every built-in
 * states it; a category of one's own gets it from its switches ([CategorySwitches.visit]).
 */
enum class VisitKind(val raw: String) {
    SERVICE("service"),
    JOB("job"),
    REPAIR("repair"),
    UPKEEP("upkeep"),
    DOCTOR("doctor"),
    VET("vet"),
    NOTE("note"),
    NONE("none"),
    ;

    companion object {
        /** The trades an earlier version's visit named, by the kind each reads as. */
        private val TRADES = mapOf("mechanic" to SERVICE, "vet" to VET, "doctor" to DOCTOR)

        /**
         * A stored kind, by one rule (`VisitKind(stored:)`): a name this build knows is its kind, one
         * from a newer build a job done, which hides nothing; the earlier form, an object of words,
         * the kind its trade names; nothing stated, no visits.
         */
        fun stored(value: JsonElement?): VisitKind = when {
            value is JsonPrimitive && value.isString -> entries.firstOrNull { it.raw == value.content } ?: JOB
            value is JsonObject -> {
                val trade = (value["trade"] as? JsonPrimitive)?.takeIf { it.isString }?.content
                if (trade == null) JOB else TRADES[trade] ?: JOB
            }
            else -> NONE
        }
    }
}

/**
 * What a category does in the binder, typed: the iOS app's `CategoryBehavior`, read from the
 * archive's [CategoryBehavior] by [of], each value this build doesn't know read as the default,
 * and written back by [writing] and [stored], so what a newer build wrote stays.
 */
data class Behavior(
    val box: Box = Box.PER_SECTION,
    val listing: Listing = Listing.PLAIN,
    val role: Role? = null,
    /** The pocket of a parent's page its sections show in (tenants, products, subscriptions). */
    val parentPocket: SectionPocket? = null,
    /** Its sections are only added under another section, never on their own (a tenancy). */
    val addedOnlyUnderParent: Boolean = false,
    /** Whether its sections start in one box or one each; none reads as one each. */
    val defaultGrouping: BoxGrouping? = null,
    /** What its sections are called when counted ("3 plante"), as its stored key; none counts them as sections. */
    val sectionNoun: String? = null,
    /** The part its sections may be filed under, or stand on their own ("Ține de…"). */
    val mayBelongTo: Role? = null,
    /** A new section goes under the household's only section of the [mayBelongTo] part by itself. */
    val goesUnderTheOnlyOne: Boolean = false,
    val visit: VisitKind = VisitKind.NONE,
    /** Its option in "Adaugă o secțiune", one thing rather than the category; none shows the category's name. */
    val offerTitle: String? = null,
    /** Its place among the ones most households start with, from 1. */
    val shortlistOrder: Int? = null,
    /** What one of its sections is called and that noun's gender, as stored; none for a category of one's own. */
    val singular: JsonObject? = null,
) {
    /** Whether its sections get boxes of their own on the Dosar grid. */
    val hasSectionBoxes: Boolean get() = box == Box.PER_SECTION

    /** Whether the person can choose between one box per section and one box for them all. */
    val offersGrouping: Boolean get() = hasSectionBoxes

    /**
     * Whether its sections, filed under a section of the part they may belong to, show on that
     * section's page in a pocket named after the category rather than in one of the catalog's.
     */
    val hasPocketOfItsOwn: Boolean get() = mayBelongTo != null && parentPocket == null

    /** The name one of its sections has in the binder, as declared; none for a category of one's own. */
    val singularName: String?
        get() = (singular?.get("name") as? JsonPrimitive)?.takeIf { it.isString }?.content

    /** Its option's title in "Adaugă o secțiune": its own, else the category's [name]. */
    fun offerTitle(name: String): String = offerTitle?.takeIf { it.isNotEmpty() } ?: name

    /**
     * The archive's [stored] behaviour with only what differs from what it reads as now changed,
     * so a value this build doesn't read, or one it reads as the default, stays as written.
     */
    @Suppress("CyclomaticComplexMethod") // One comparison per field, each as plain as the next.
    fun writing(stored: CategoryBehavior): CategoryBehavior {
        val read = of(stored)
        fun <T, S> changed(mine: T, theirs: T, write: S, kept: S): S = if (mine == theirs) kept else write
        return CategoryBehavior(
            box = changed(box, read.box, box.raw, stored.box),
            listing = changed(listing, read.listing, listing.raw, stored.listing),
            role = changed(role, read.role, role?.raw, stored.role),
            parentPocket = changed(parentPocket, read.parentPocket, parentPocket?.raw, stored.parentPocket),
            addedOnlyUnderParent = changed(
                addedOnlyUnderParent, read.addedOnlyUnderParent, addedOnlyUnderParent, stored.addedOnlyUnderParent,
            ),
            defaultGrouping = changed(
                defaultGrouping, read.defaultGrouping, defaultGrouping?.raw, stored.defaultGrouping,
            ),
            sectionNoun = changed(sectionNoun, read.sectionNoun, sectionNoun, stored.sectionNoun),
            mayBelongTo = changed(mayBelongTo, read.mayBelongTo, mayBelongTo?.raw, stored.mayBelongTo),
            goesUnderTheOnlyOne = changed(
                goesUnderTheOnlyOne, read.goesUnderTheOnlyOne, goesUnderTheOnlyOne, stored.goesUnderTheOnlyOne,
            ),
            visit = changed(visit, read.visit, JsonPrimitive(visit.raw), stored.visit),
            offerTitle = changed(offerTitle, read.offerTitle, offerTitle, stored.offerTitle),
            shortlistOrder = changed(shortlistOrder, read.shortlistOrder, shortlistOrder, stored.shortlistOrder),
            singular = changed(singular, read.singular, singular, stored.singular),
        )
    }

    /**
     * Written whole, as the iOS app's encoder writes a `CategoryBehavior` with nothing stored
     * before it: every value that has a default, and each optional one only when there is one.
     */
    val stored: CategoryBehavior
        get() = CategoryBehavior(
            box = box.raw,
            listing = listing.raw,
            role = role?.raw,
            parentPocket = parentPocket?.raw,
            addedOnlyUnderParent = addedOnlyUnderParent,
            defaultGrouping = defaultGrouping?.raw,
            sectionNoun = sectionNoun,
            mayBelongTo = mayBelongTo?.raw,
            goesUnderTheOnlyOne = goesUnderTheOnlyOne,
            visit = JsonPrimitive(visit.raw),
            offerTitle = offerTitle,
            shortlistOrder = shortlistOrder,
            singular = singular,
        )

    companion object {
        /**
         * Any category the person makes, before its switches (`CategoryBehavior.standard`): a box
         * per section, a plain list, no visits, its sections named after it.
         */
        val STANDARD: Behavior = Behavior()

        /** The behaviour [stored] says, each value this build can't read as the default; none is [STANDARD]. */
        fun of(stored: CategoryBehavior?): Behavior {
            if (stored == null) return STANDARD
            return Behavior(
                box = Box.of(stored.box) ?: Box.PER_SECTION,
                listing = Listing.of(stored.listing) ?: Listing.PLAIN,
                role = Role.of(stored.role),
                parentPocket = SectionPocket.of(stored.parentPocket),
                addedOnlyUnderParent = stored.addedOnlyUnderParent ?: false,
                defaultGrouping = BoxGrouping.of(stored.defaultGrouping),
                sectionNoun = stored.sectionNoun,
                mayBelongTo = Role.of(stored.mayBelongTo),
                goesUnderTheOnlyOne = stored.goesUnderTheOnlyOne ?: false,
                visit = VisitKind.stored(stored.visit),
                offerTitle = stored.offerTitle,
                shortlistOrder = stored.shortlistOrder,
                singular = (stored.singular as? JsonObject)
                    ?.takeIf { (it["name"] as? JsonPrimitive)?.isString == true },
            )
        }

        /**
         * What one of a category's sections is called (`TemplateDefinition.sectionName`): what a
         * built-in declares, else (a category of one's own, named as one thing already) the
         * category's [name]. Never the category's plural for a built-in; never a gender for one of one's own.
         */
        fun sectionName(name: String, behavior: Behavior): String =
            behavior.singularName?.takeIf { it.isNotEmpty() } ?: name.trim()
    }
}
