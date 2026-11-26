package com.ar.dosarcusina.catalog

import com.ar.dosarcusina.archive.v3.FieldDefinition
import com.ar.dosarcusina.archive.v3.FieldSection
import com.ar.dosarcusina.archive.v3.ObligationBlueprint
import com.ar.dosarcusina.archive.v3.RecurrenceRule
import com.ar.dosarcusina.core.values.MachineText
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import java.util.UUID
import kotlin.math.floor
import kotlin.math.max

/**
 * The parts of a category's definition its switches read and write ([CategorySwitches]): its
 * field sections, its deadlines, its pockets (as stored keys) and what it does in the binder.
 * Everything else of a category (its name, its look, its parts and jobs) is no switch's.
 */
data class CategoryParts(
    val sections: List<FieldSection> = emptyList(),
    val blueprints: List<ObligationBlueprint> = emptyList(),
    /** `SectionPocket` keys, as stored: one a newer build wrote stays. */
    val pockets: List<String> = SectionPocket.STANDARD.map(SectionPocket::raw),
    val behavior: Behavior = Behavior.STANDARD,
)

/**
 * The few plain questions a category of the person's own answers ("Are acte", "Are facturi și
 * contracte", "Are revizii sau lucrări" and how often, "Ține de…", one box or one each), read from
 * and written to the category's own data, as the iOS app's `CategorySwitches`
 * (ios/DosarCuSina/Services/Templates/CategorySwitches.swift): its pockets, its behaviour (its
 * visits' kind among it, [visit]), a counter field and a service deadline ([CategoryParts]), and
 * the household's choice of one box for its sections (`CategoryTemplate.boxGroupingRaw`, the same
 * choice a box's menu makes). Nothing stores the switches themselves, so there is one source of
 * truth and a category of one's own behaves exactly like a built-in with the same data.
 *
 * Each switch touches only what it owns. Pockets it doesn't own, fields and deadlines the category
 * had before stay as they are, and applying the switches a category reads changes nothing. Turning
 * a switch off never deletes anything: a hidden pocket's records stay, a counter's values stay
 * under their own key, and the deadlines it made keep going until the person says otherwise
 * (`TemplateStore.editCustom`). The words and the deadline a service brings are the iOS app's,
 * from the shared catalog ([OwnCategories]).
 */
class CategorySwitches(
    /** Its sections keep photos and PDFs (the Acte pocket). */
    val hasDocuments: Boolean = true,
    /**
     * Its sections keep ongoing contracts with their bills (the Abonamente pocket), and bills and
     * contracts read from a photo can be filed under them, as under a home.
     */
    val hasBills: Boolean = false,
    /** Its sections have a regular service or job, logged as visits; none for none, and then no visits either. */
    val service: Service? = null,
    belongsTo: Role? = null,
    /**
     * One box for all its sections on the Dosar grid, wherever they are filed, or one each: the
     * category's grouping, the one choice a box's menu, the category's page and Setări make too.
     */
    val grouping: BoxGrouping = BoxGrouping.SEPARATE,
) {
    /**
     * What its sections belong to ("Ține de…": a home, a car, a person), or none. Only a part that
     * holds sections ([Role.holdsSections]): any other reads as none.
     */
    val belongsTo: Role? = belongsTo?.takeIf(Role::holdsSections)

    /** What a service is counted by. Raw values name the service deadline (`custom.service.<raw>`). */
    enum class Counter(val raw: String, val unit: String?, val defaultEvery: Int) {
        /** Every so many months, with no counter (a piano, a boiler of one's own). */
        TIME("yearly", null, MONTHS_IN_A_YEAR),

        /** Every so many kilometres, or once a year (a trailer, a motorbike). */
        KILOMETRES("kilometres", "km", KILOMETRES_START),

        /** Every so many engine hours, or once a year (a boat, a generator). */
        ENGINE_HOURS("engineHours", "h", ENGINE_HOURS_START),
        ;

        companion object {
            fun of(raw: String?): Counter? = entries.firstOrNull { it.raw == raw }
        }
    }

    /** A regular service: what it is counted by, and every how many months, kilometres or hours (at least 1). */
    class Service(val counter: Counter, every: Int? = null) {
        /** Months for [Counter.TIME], kilometres or hours for a counter; where it starts when not said. */
        val every: Int = max(1, every ?: counter.defaultEvery)

        override fun equals(other: Any?): Boolean = other is Service && other.counter == counter && other.every == every

        override fun hashCode(): Int = counter.hashCode() * HASH + every

        override fun toString(): String = "Service(${counter.raw}, every: $every)"
    }

    /** These answers with some changed, as the iOS app's `var` copies are. */
    @Suppress("LongParameterList") // One parameter per switch.
    fun copy(
        hasDocuments: Boolean = this.hasDocuments,
        hasBills: Boolean = this.hasBills,
        service: Service? = this.service,
        belongsTo: Role? = this.belongsTo,
        grouping: BoxGrouping = this.grouping,
    ): CategorySwitches = CategorySwitches(hasDocuments, hasBills, service, belongsTo, grouping)

    override fun equals(other: Any?): Boolean =
        other is CategorySwitches && other.hasDocuments == hasDocuments && other.hasBills == hasBills &&
            other.service == service && other.belongsTo == belongsTo && other.grouping == grouping

    override fun hashCode(): Int = listOf(hasDocuments, hasBills, service, belongsTo, grouping).hashCode()

    override fun toString(): String =
        "CategorySwitches(documents: $hasDocuments, bills: $hasBills, service: $service, " +
            "belongsTo: ${belongsTo?.raw}, grouping: ${grouping.raw})"

    // Writing

    /**
     * [parts] with these answers. Only what differs from what they answer now changes. The
     * grouping isn't the definition's: the store keeps it on the category, beside it.
     */
    fun applied(to: CategoryParts, own: OwnCategories = Catalog.builtIn.ownCategories): CategoryParts {
        val current = reading(to, grouping)
        val (pockets, behavior) = pocketsAndBehavior(to, current)
        val (sections, blueprints) = service(to, current, own)
        return CategoryParts(sections, blueprints, pockets, behavior)
    }

    /** What the pockets, the part and the visits answer: only what differs from [current] changes. */
    private fun pocketsAndBehavior(to: CategoryParts, current: CategorySwitches): Pair<List<String>, Behavior> {
        var behavior = to.behavior
        var pockets = to.pockets
        if (hasDocuments != current.hasDocuments) pockets = toggled(pockets, SectionPocket.DOCUMENTS, hasDocuments)
        if (hasBills != current.hasBills) {
            pockets = toggled(pockets, SectionPocket.SUBSCRIPTIONS, hasBills)
            // A place bills and contracts are filed under, like a home. Another part it plays (one
            // imported from a newer version) is left alone.
            if (hasBills && behavior.role == null) behavior = behavior.copy(role = Role.HOME)
            if (!hasBills && behavior.role == Role.HOME) behavior = behavior.copy(role = null)
        }
        if (pockets != to.pockets) pockets = SectionPocket.orderedRaw(pockets)
        if (belongsTo != current.belongsTo) {
            // As plants: filed under a section of that part, or on its own, and under the only one by itself.
            behavior = behavior.copy(mayBelongTo = belongsTo, goesUnderTheOnlyOne = belongsTo != null)
        }
        if (service?.counter != current.service?.counter) {
            // Turned on or off, or counted another way: the visits it gets follow. How often alone
            // leaves them as they are.
            behavior = behavior.copy(visit = visit(service))
        }
        return pockets to behavior
    }

    /** The counter field and the service deadline, when the service differs from [current]'s. */
    private fun service(
        to: CategoryParts,
        current: CategorySwitches,
        own: OwnCategories,
    ): Pair<List<FieldSection>, List<ObligationBlueprint>> {
        var sections = to.sections
        var blueprints = to.blueprints
        if (service != current.service) {
            val inPlace = service?.takeIf { current.service?.counter == it.counter }?.let { kept ->
                blueprints.indexOfFirst { it.key == serviceBlueprintKey(kept.counter) }.takeIf { it >= 0 }
            }
            if (service != null && inPlace != null) {
                // Only how often: the same deadline, in place, with its new rule.
                blueprints = blueprints.toMutableList().also { it[inPlace] = serviceBlueprint(service, own) }
            } else {
                blueprints = blueprints.filterNot { isServiceBlueprint(it.key) }
                sections = sections.filterNot { it.key == COUNTER_SECTION_KEY }
                if (service != null) {
                    blueprints = blueprints + serviceBlueprint(service, own)
                    own.counterField(service.counter)?.let { field ->
                        sections = sections + FieldSection(COUNTER_SECTION_KEY, field.label, listOf(field))
                    }
                }
            }
        }
        return sections to blueprints
    }

    /** A new category of the person's own with these answers: the base pockets, then these answers applied. */
    fun parts(own: OwnCategories = Catalog.builtIn.ownCategories): CategoryParts =
        applied(CategoryParts(pockets = own.basePockets), own)

    companion object {
        /** The field section that holds the counter. Part of the `.dosar` contract. */
        const val COUNTER_SECTION_KEY = "custom.counter"

        /** Service deadlines start with this; the rest names what they count by. Part of the `.dosar` contract. */
        const val SERVICE_BLUEPRINT_PREFIX = "custom.service."

        private const val MONTHS_IN_A_YEAR = 12
        private const val KILOMETRES_START = 10_000
        private const val ENGINE_HOURS_START = 100
        private const val HASH = 31
        private const val HALF = 0.5

        /** A sensible category with no changes: it keeps documents, belongs to nothing, one box per section. */
        val DEFAULTS: CategorySwitches = CategorySwitches()

        /** The counter's field: one key per unit, so a value typed in hours never reads as kilometres. */
        fun counterFieldKey(unit: String): String = "$COUNTER_SECTION_KEY.$unit"

        fun serviceBlueprintKey(counter: Counter): String = SERVICE_BLUEPRINT_PREFIX + counter.raw

        /** Whether a deadline is one the switches make. */
        fun isServiceBlueprint(key: String): Boolean = key.startsWith(SERVICE_BLUEPRINT_PREFIX)

        // Reading

        /**
         * The switches [parts] answer, with the [grouping] kept beside them. The interval is read
         * from the service deadline's own rule, so it lives in one place. A category an earlier
         * version made with one box of the whole category's answers one box (the store passes
         * [BoxGrouping.GROUPED] for it, as `CategorySwitches(reading:)` does).
         */
        fun reading(parts: CategoryParts, grouping: BoxGrouping): CategorySwitches {
            val service = Counter.entries.firstNotNullOfOrNull { counter ->
                parts.blueprints.firstOrNull { it.key == serviceBlueprintKey(counter) }
                    ?.let { Service(counter, every(rule(it.recurrence))) }
            }
            return CategorySwitches(
                hasDocuments = SectionPocket.DOCUMENTS.raw in parts.pockets,
                hasBills = SectionPocket.SUBSCRIPTIONS.raw in parts.pockets,
                service = service,
                belongsTo = parts.behavior.mayBelongTo,
                grouping = grouping,
            )
        }

        /**
         * The visits a category of one's own gets (`CategorySwitches.visit(for:)`): none without „Are
         * revizii sau lucrări”; with it, a service where a counter is kept (kilometres, engine hours:
         * the form asks the counter and the parts, as for a car), and a job done by someone where it
         * goes by time (a piano, a boiler). The one rule: the switches write it, and the repair list
         * gives it to a category an earlier version made.
         */
        fun visit(service: Service?): VisitKind = when (service?.counter) {
            null -> VisitKind.NONE
            Counter.TIME -> VisitKind.JOB
            Counter.KILOMETRES, Counter.ENGINE_HOURS -> VisitKind.SERVICE
        }

        /**
         * What „Ține de…” offers (`CategorySwitches.belongingChoices`): every part that holds
         * sections some category of the binder plays ([played], each category's part), in the one
         * order ([Role.PARENTS]), and the one [current] says even when none plays it now. Never a
         * category's name or key.
         */
        fun belongingChoices(played: Collection<Role?>, current: Role? = null): List<Role> =
            Role.PARENTS.filter { it in played || it == current }

        /** The interval a service deadline's rule says, in its counter's unit; none when it says none. */
        fun every(rule: RecurrenceRule): Int? = when (rule) {
            // Swift's `rounded()`: to the nearest, halves away from zero; a counter's step is never below zero.
            is RecurrenceRule.Metric -> floor(rule.every + HALF).toInt()
            is RecurrenceRule.Interval -> when (rule.unit) {
                "month" -> rule.every
                "year" -> rule.every * MONTHS_IN_A_YEAR
                else -> null
            }
            else -> null
        }

        // What a service brings

        /**
         * The service deadline it suggests, like a car's "Revizie periodică" (`serviceBlueprint`): the
         * shared catalog's for its counter ([OwnCategories.service], its words, kind, completion and
         * reminders), counting by its counter or once a year, whichever comes first, or every so many
         * months for one by time; the first one after the same interval, or a year for a counter.
         */
        fun serviceBlueprint(
            service: Service,
            own: OwnCategories = Catalog.builtIn.ownCategories,
        ): ObligationBlueprint {
            val (recurrence, firstDue) = when (service.counter) {
                Counter.TIME -> {
                    val (every, unit) = interval(months = service.every)
                    RecurrenceRule.Interval(every, unit, "completion") to afterInterval(every, unit)
                }
                Counter.KILOMETRES, Counter.ENGINE_HOURS -> {
                    val unit = requireNotNull(service.counter.unit)
                    RecurrenceRule.Metric(service.every.toDouble(), unit, 1, "year") to afterInterval(1, "year")
                }
            }
            return own.service(service.counter).copy(recurrence = recurrence.toJson(), firstDue = firstDue)
        }

        /** The months of a service by time, as whole years when they are. */
        fun interval(months: Int): Pair<Int, String> =
            if (months % MONTHS_IN_A_YEAR == 0) months / MONTHS_IN_A_YEAR to "year" else months to "month"

        /**
         * A category of one's own an earlier version made with one box of its own for the whole
         * category ("O cutie pentru toate" before it was the grouping): its box becomes one per
         * section, grouped, which looks the same (`TemplateStore.takeBoxAsGrouping`). A grouping
         * already [chosen] stays. Only a box the switches wrote: a category of one's own that behaves
         * like Garanții keeps its box, and a built-in the catalog's. None when nothing changes.
         */
        fun boxAsGrouping(parts: CategoryParts, isBuiltIn: Boolean, chosen: BoxGrouping?): BoxTaken? {
            val behavior = parts.behavior
            if (isBuiltIn || behavior.box != Box.WHOLE_CATEGORY) return null
            // What the switches write, besides the box: a home's part for bills, and the visits its
            // service gives, nothing else.
            var besides = behavior.copy(box = Box.PER_SECTION)
            if (besides.role == Role.HOME) besides = besides.copy(role = null)
            val service = reading(parts, BoxGrouping.of(behavior, chosen?.raw)).service
            if (besides.visit == visit(service)) besides = besides.copy(visit = VisitKind.NONE)
            if (besides != Behavior.STANDARD) return null
            return BoxTaken(behavior.copy(box = Box.PER_SECTION), chosen ?: BoxGrouping.GROUPED)
        }
    }
}

private fun toggled(pockets: List<String>, pocket: SectionPocket, on: Boolean): List<String> =
    if (on) pockets + pocket.raw else pockets.filterNot { it == pocket.raw }

private fun rule(json: JsonElement?): RecurrenceRule = json?.let(RecurrenceRule.codec::decode) ?: RecurrenceRule.None

/** A first due day that many units after the day a deadline is made, as a blueprint's `firstDue` writes it. */
private fun afterInterval(every: Int, unit: String): JsonElement = JsonObject(
    mapOf(
        "type" to JsonPrimitive("afterInterval"),
        "every" to MachineText.number(every.toLong()),
        "unit" to JsonPrimitive(unit),
    ),
)

/** What [CategorySwitches.boxAsGrouping] makes of a category: its behaviour with a box each, and its grouping. */
data class BoxTaken(val behavior: Behavior, val grouping: BoxGrouping)

/**
 * What a category of one's own is made of besides the answers to its switches, as the iOS app
 * exports it (`shared/catalog/ownCategories.json`, `CatalogExportTests.OwnCategories`): the pockets
 * every new one starts with, and for each way a service is counted, its counter field and its
 * service deadline at the interval it starts at; and „Recuperate” ([recovered]). The words are the
 * iOS app's; Android writes none.
 */
class OwnCategories internal constructor(
    /** The pockets every new category of one's own starts with, as stored keys; the switches add theirs. */
    val basePockets: List<String>,
    private val fields: Map<CategorySwitches.Counter, FieldDefinition>,
    private val services: Map<CategorySwitches.Counter, ObligationBlueprint>,
    /** „Recuperate”, where the repair list keeps records whose section was deleted on another device. */
    val recovered: RecoveredCategory,
) {
    /** The counter the hero shows and the service counts by; none for a service by time. */
    fun counterField(counter: CategorySwitches.Counter): FieldDefinition? = fields[counter]

    /** The service deadline of [counter] as the catalog writes it, at the interval it starts at. */
    fun service(counter: CategorySwitches.Counter): ObligationBlueprint = services.getValue(counter)
}

/**
 * „Recuperate”, the category of one's own the repair list keeps records in whose section was
 * deleted on another device, as the iOS app's `LostRecordsStep` makes it: one key and one
 * section id on every device and on both apps, so two that keep records there make one.
 */
data class RecoveredCategory(
    val key: String,
    val name: String,
    val symbol: String,
    /** `SectionPocket` keys, as stored. */
    val pockets: List<String>,
    /** The id of its one section. */
    val sectionID: UUID,
)
