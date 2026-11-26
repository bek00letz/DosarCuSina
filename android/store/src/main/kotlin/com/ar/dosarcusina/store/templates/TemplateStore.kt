package com.ar.dosarcusina.store.templates

import androidx.room3.withReadTransaction
import com.ar.dosarcusina.archive.CategoryOrder
import com.ar.dosarcusina.archive.v3.FieldSection
import com.ar.dosarcusina.archive.v3.ObligationBlueprint
import com.ar.dosarcusina.archive.v3.RecurrenceRule
import com.ar.dosarcusina.catalog.BinderBoxID
import com.ar.dosarcusina.catalog.BinderLayout
import com.ar.dosarcusina.catalog.Box
import com.ar.dosarcusina.catalog.BoxGrouping
import com.ar.dosarcusina.catalog.Catalog
import com.ar.dosarcusina.catalog.CategoryParts
import com.ar.dosarcusina.catalog.CategorySwitches
import com.ar.dosarcusina.catalog.Role
import com.ar.dosarcusina.catalog.SectionPocket
import com.ar.dosarcusina.core.values.ObligationStatus
import com.ar.dosarcusina.store.BinderView
import com.ar.dosarcusina.store.ChangeOrigin
import com.ar.dosarcusina.store.Step
import com.ar.dosarcusina.store.Tables
import com.ar.dosarcusina.store.UndoReceipt
import com.ar.dosarcusina.store.UnitOfWork
import com.ar.dosarcusina.store.locks.CategoryLocks
import com.ar.dosarcusina.store.locks.LockLowering
import com.ar.dosarcusina.store.obligations.ObligationActions
import com.ar.dosarcusina.store.obligations.status
import com.ar.dosarcusina.store.schema.CategoryTemplate
import com.ar.dosarcusina.store.schema.Obligation
import com.ar.dosarcusina.store.schema.StoredMoment
import com.ar.dosarcusina.store.schema.keptRecurrence
import java.time.Instant
import java.util.UUID
import kotlinx.coroutines.runBlocking

/** Why a category action was refused, as kinds: the screens word them (Phase 4). */
sealed class TemplateStoreError(message: String) : Exception(message) {
    /** The category still has sections; move or delete them first. */
    class InUse(val assetCount: Int) : TemplateStoreError("The category still has sections")

    /** A built-in category can't be deleted, only hidden from the binder. */
    class BuiltInCannotBeDeleted : TemplateStoreError("A built-in category can't be deleted")

    /** What a built-in category does is the app's; only categories of one's own have switches. */
    class BuiltInBehaviourIsFixed : TemplateStoreError("A built-in category's behaviour is the catalog's")

    /** The category isn't in the binder any more. */
    class NotFound : TemplateStoreError("The category isn't in the binder")
}

/**
 * The person's order of the binder's boxes, kept on this phone and never in the binder (the iOS
 * app's `BinderLayoutStore`): only the order is kept, which boxes there are always comes from the
 * data. The screens keep it (Phase 4); a category's grouping keeps it around itself
 * ([TemplateStore.setGrouping], [TemplateStore.editCustom]).
 */
interface BoxOrder {
    /** The person's order, empty while they haven't arranged the boxes. */
    val saved: List<BinderBoxID>

    /** Keeps [order] as the person's. */
    fun save(order: List<BinderBoxID>)

    /**
     * The order kept around a category whose grouping just changed (`BinderLayoutStore.keepOrder`):
     * [members] are its sections' boxes as they were before, in the order they showed.
     */
    fun keepAround(key: String, members: List<BinderBoxID>, grouped: Boolean) {
        if (saved.isEmpty()) return
        save(BinderLayout.regrouped(saved, key, members, grouped))
    }
}

/**
 * The single place that orders, shows, groups, locks, creates, changes and deletes categories, as
 * the iOS app's `TemplateStore` (ios/DosarCuSina/Services/Templates/TemplateStore.swift), and finds
 * one by the part it plays (`CategoryRoles`). Installing the built-ins is launch's
 * (`LaunchData.installBuiltIns`, by `BuiltInInstall`). Every change is one step of the unit of
 * work, the person's own; editing and deleting a category of one's own are undoable, with their
 * receipt. A category is named by its row: each action reads it again inside its step.
 */
// The iOS type's surface, one function per job.
@Suppress("TooManyFunctions")
class TemplateStore(
    private val unit: UnitOfWork,
    /** This phone's locks, the one way a category is locked or opened. */
    private val locks: CategoryLocks,
    private val catalog: Catalog = Catalog.builtIn,
    /** A new category of one's own's key (`TemplateDefinition.newCustomKey`). */
    private val newKey: () -> String = { CUSTOM_KEY_PREFIX + UUID.randomUUID().toString().lowercase() },
) {
    /**
     * The deadlines a change of switches touches ([effects]): the service deadlines a switch turns
     * off (still running), the ones it turns back on (paused), and the running ones whose interval
     * it changes. Nothing changes until the person says so ([editCustom] with `changingDeadlines`).
     */
    data class SwitchEffects(
        val pausing: List<Obligation> = emptyList(),
        val resuming: List<Obligation> = emptyList(),
        val retiming: List<Obligation> = emptyList(),
    ) {
        val isEmpty: Boolean get() = pausing.isEmpty() && resuming.isEmpty() && retiming.isEmpty()
    }

    // Reading

    /** Every category in the binder's order: its place, then when it was made. */
    fun all(): List<CategoryTemplate> = ordered(stored())

    /** Every category in the binder's order, as [view] (a step) sees it. */
    fun all(view: BinderView): List<CategoryTemplate> = ordered(view.all(Tables.templates))

    /** The category [key], the first in the binder's order when copies haven't been joined yet. */
    fun template(key: String): CategoryTemplate? = all().firstOrNull { it.key == key }

    /** Each category by key, for looking up many sections at once; the first in the binder's order wins. */
    fun templatesByKey(): Map<String, CategoryTemplate> = all().byKey()

    /** The category that plays [role], a built-in first (`template(withRole:)`). */
    fun template(withRole: Role): CategoryTemplate? = all().template(withRole)

    /** The keys of every category that plays [role], built-in or the person's own. */
    fun keys(playing: Role): Set<String> = all().keys(playing)

    /**
     * What a change of [switches] would do to the deadlines of [template]'s sections, asked before
     * the change ([SwitchEffects]).
     */
    fun effects(switches: CategorySwitches, template: CategoryTemplate): SwitchEffects =
        unit.perform(ChangeOrigin.APP) { step -> effects(switches, fresh(step, template), step) }

    // The person's choices for any category

    /** Moves the categories at [from] (places in [all]) to before the one at [to], as a list's move reports it. */
    fun move(from: Set<Int>, to: Int) = unit.perform { step ->
        val ordered = all(step).toMutableList()
        val moving = from.sorted().map { ordered[it] }
        for (index in from.sortedDescending()) ordered.removeAt(index)
        ordered.addAll(to - from.count { it < to }, moving)
        ordered.forEachIndexed { index, template ->
            if (template.homeOrder != index) step.update(template.copy(homeOrder = index))
        }
    }

    /** Shows the category on the binder or hides it. */
    fun setOnHome(template: CategoryTemplate, isOnHome: Boolean) = unit.perform { step ->
        step.update(fresh(step, template).copy(isOnHome = isOnHome))
    }

    /**
     * One box on the binder for the category's sections ("Mașini"), or one each: the person's
     * choice, kept on the category so it travels like its place (one of a built-in's own choices),
     * even when it is what the catalog says. A category whose box isn't one per section has no such
     * choice, and nothing changes. With [order], this phone's order of the boxes is kept around it,
     * the one box standing where the first of its sections stood, once the choice is saved.
     */
    fun setGrouping(template: CategoryTemplate, grouping: BoxGrouping, order: BoxOrder? = null) = unit.perform { step ->
        val row = fresh(step, template)
        val chosen = row.choosingGrouping(grouping) ?: return@perform
        val members = members(step, row.key)
        step.update(chosen)
        keepOrder(order, row, chosen, members)
    }

    /**
     * Locks or opens a category on this phone ([CategoryLocks.setLock]): locking it locks it on every
     * phone, saved on its record; opening it opens it on this phone only, and takes the person's
     * confirmation first, every time ([lowering]), or throws [LockLowering.Needed]. Locking needs none.
     */
    fun setSensitive(template: CategoryTemplate, isSensitive: Boolean, lowering: LockLowering? = null) =
        unit.perform { step ->
            step.update(locks.setLock(fresh(step, template), isSensitive, lowering, StoredMoment.kept(unit.clock())))
        }

    /**
     * Ends the wait after this phone's locks couldn't be read: every category keeps the lock it shows
     * now, as this phone's choice ([CategoryLocks.keepLocksAsTheyAre]), which takes the person's confirmation.
     */
    fun keepLocksAsTheyAre(lowering: LockLowering?) =
        locks.keepLocksAsTheyAre(all(), lowering, StoredMoment.kept(unit.clock()))

    // Categories of one's own

    /**
     * Makes a category of the person's own from the few plain questions it answers ([switches]): its
     * pockets, what its sections belong to, a counter and a service deadline, and one box for its
     * sections or one each (its grouping). It goes last on the binder, with the lock [isSensitive]
     * says, kept as this phone's choice before it is saved.
     */
    fun createCustom(
        name: String,
        symbol: String,
        switches: CategorySwitches,
        tint: String = DEFAULT_TINT,
        isSensitive: Boolean = false,
    ): CategoryTemplate = unit.perform { step ->
        val made = make(step, newKey(), name, symbol, tint, switches.parts(catalog.ownCategories), isSensitive)
        val grouped = made.takeIf { it.grouping != switches.grouping }?.choosingGrouping(switches.grouping)
        grouped?.also(step::update) ?: made
    }

    /**
     * Makes a category of the person's own from a name, a symbol and the pockets it shows, with no
     * fields of its own ("Altceva…", „Recuperate”): facts go in Date importante as free rows.
     */
    @Suppress("LongParameterList") // The iOS action's own questions.
    fun createCustom(
        name: String,
        symbol: String,
        pockets: List<SectionPocket>,
        tint: String = DEFAULT_TINT,
        isSensitive: Boolean = false,
        key: String = newKey(),
    ): CategoryTemplate = unit.perform { step ->
        val parts = CategoryParts(pockets = SectionPocket.ordered(pockets).map { it.raw })
        make(step, key, name, symbol, tint, parts, isSensitive)
    }

    /** Makes a category of the person's own with fields and deadlines of its own and the standard pockets. */
    @Suppress("LongParameterList") // The iOS action's own questions.
    fun createCustom(
        name: String,
        symbol: String,
        tint: String,
        sections: List<FieldSection>,
        blueprints: List<ObligationBlueprint> = emptyList(),
        isSensitive: Boolean = false,
        key: String = newKey(),
    ): CategoryTemplate = unit.perform { step ->
        make(step, key, name, symbol, tint, CategoryParts(sections = sections, blueprints = blueprints), isSensitive)
    }

    /**
     * Renames a category of the person's own and changes its symbol and switches, as one step the
     * toast can take back. Nothing filed is deleted: a pocket turned off only hides, and comes back
     * with what it had. With [changingDeadlines], in the same step, the service deadlines a switch
     * turned off are paused, the paused ones it turned back on run again, and running ones (and
     * those resumed) count by the new interval from their next cycle; their due day stays
     * ([effects]). Its grouping is the one a box's menu sets ([setGrouping]), and [order] is kept
     * around it. A section filed under one that no longer plays the part the category belongs to
     * stands on its own again, in its category's box, so nothing is left where no page lists it.
     */
    @Suppress("LongParameterList") // The iOS action's own questions, and the phone's order.
    fun editCustom(
        template: CategoryTemplate,
        name: String,
        symbol: String,
        switches: CategorySwitches,
        changingDeadlines: Boolean,
        order: BoxOrder? = null,
    ): UndoReceipt = unit.performUndoable { step ->
        val row = fresh(step, template)
        if (row.isBuiltIn) throw TemplateStoreError.BuiltInBehaviourIsFixed()
        val effects = if (changingDeadlines) effects(switches, row, step) else SwitchEffects()
        val members = members(step, row.key)
        val parts = switches.applied(row.parts, catalog.ownCategories)
        val edited = boxes(switches.grouping, row.withParts(parts).copy(name = name, symbol = symbol))
        step.update(edited)
        standOnTheirOwnWhereNoLongerBelonging(step, edited)
        val rules = serviceRules(parts)
        val actions = ObligationActions(unit)
        effects.pausing.forEach(actions::pause)
        effects.resuming.forEach(actions::resume)
        for (obligation in effects.resuming + effects.retiming) {
            val rule = obligation.blueprintKey?.let(rules::get)
            val now = step.row(Tables.obligations, obligation.pk)
            if (rule != null && now != null && now.keptRecurrence.value != rule) actions.setRecurrence(now, rule)
        }
        keepOrder(order, row, edited, members)
    }.receipt

    /**
     * Deletes a category of the person's own that holds no section. Undoable: the receipt brings it
     * back as it was, its place on the binder included. Its lock on this phone stays, so nothing
     * opens if it comes back.
     */
    fun delete(template: CategoryTemplate): UndoReceipt = unit.performUndoable { step ->
        val row = fresh(step, template)
        if (row.isBuiltIn) throw TemplateStoreError.BuiltInCannotBeDeleted()
        val count = step.all(Tables.assets).count { it.templateKey == row.key }
        if (count > 0) throw TemplateStoreError.InUse(count)
        step.delete(row)
    }.receipt

    /**
     * A category of one's own an earlier version made with one box of its own for the whole category
     * (`TemplateStore.takeBoxAsGrouping`): its box becomes one per section, grouped, which looks the
     * same ([CategorySwitches.boxAsGrouping]). The row to save, or none when nothing changes; it saves
     * nothing itself. Run by the repair list (`OwnCategoryBoxesStep`) and by [editCustom].
     */
    fun takeBoxAsGrouping(template: CategoryTemplate): CategoryTemplate? = template.takingBoxAsGrouping()

    // Inside

    @Suppress("LongParameterList") // What a new category is made of.
    private fun make(
        step: Step,
        key: String,
        name: String,
        symbol: String,
        tint: String,
        parts: CategoryParts,
        isSensitive: Boolean,
    ): CategoryTemplate = makeCustom(step, key, name, symbol, tint, parts, isSensitive, unit.clock())

    private fun effects(switches: CategorySwitches, template: CategoryTemplate, view: BinderView): SwitchEffects {
        val before = template.parts.blueprints.map { it.key }.filter(CategorySwitches::isServiceBlueprint).toSet()
        val rules = serviceRules(switches.applied(template.parts, catalog.ownCategories))
        val sections = view.all(Tables.assets).filter { it.templateKey == template.key }.sortedBy { it.name }
        val obligations = view.all(Tables.obligations)
        val pausing = ArrayList<Obligation>()
        val resuming = ArrayList<Obligation>()
        val retiming = ArrayList<Obligation>()
        for (obligation in sections.flatMap { section -> obligations.filter { it.asset == section.pk } }) {
            val key = obligation.blueprintKey?.takeIf(CategorySwitches::isServiceBlueprint) ?: continue
            val rule = rules[key]
            val status = obligation.status
            when {
                status == ObligationStatus.ACTIVE && key in before && rule == null -> pausing += obligation
                status == ObligationStatus.PAUSED && rule != null && key !in before -> resuming += obligation
                status == ObligationStatus.ACTIVE && rule != null && obligation.keptRecurrence.value != rule ->
                    retiming += obligation
            }
        }
        return SwitchEffects(pausing, resuming, retiming)
    }

    /** Each service deadline's rule, by key. */
    private fun serviceRules(parts: CategoryParts): Map<String, RecurrenceRule> =
        parts.blueprints.filter { CategorySwitches.isServiceBlueprint(it.key) }
            .associateBy({ it.key }, { it.recurrence?.let(RecurrenceRule.codec::decode) ?: RecurrenceRule.None })

    /**
     * One box or one each, as a category of one's own's switch answers it: its grouping. A box of the
     * whole category's that [takeBoxAsGrouping] leaves (one that behaves like Garanții) stays while one
     * box is asked, and becomes one per section when a box each is.
     */
    private fun boxes(grouping: BoxGrouping, template: CategoryTemplate): CategoryTemplate {
        var row = takeBoxAsGrouping(template) ?: template
        if (row.behavior.box == Box.WHOLE_CATEGORY) {
            if (grouping != BoxGrouping.SEPARATE) return row
            row = row.withBehavior(row.behavior.copy(box = Box.PER_SECTION))
        }
        return row.takeIf { it.grouping != grouping }?.choosingGrouping(grouping) ?: row
    }

    /** The sections of [template] filed under one that doesn't play the part it may belong to, on their own again. */
    private fun standOnTheirOwnWhereNoLongerBelonging(step: Step, template: CategoryTemplate) {
        val parents = template.behavior.mayBelongTo?.let { all(step).keys(it) }.orEmpty()
        for (section in step.all(Tables.assets).filter { it.templateKey == template.key }) {
            val parent = section.parent?.let { step.row(Tables.assets, it) } ?: continue
            if (parent.templateKey !in parents) step.update(section.copy(parent = null))
        }
    }

    /** The boxes the category's sections have when each has its own, as they stand before the step changes them. */
    private fun members(view: BinderView, key: String): List<BinderBoxID> = BinderLayout.sectionBoxes(
        key,
        view.all(Tables.assets).map { asset ->
            BinderLayout.SectionInfo(asset.id, asset.templateKey, asset.parent == null, asset.createdAt)
        },
    )

    /** Keeps [order] around a category whose grouping the step changed, once the step is saved. */
    private fun keepOrder(
        order: BoxOrder?,
        before: CategoryTemplate,
        after: CategoryTemplate,
        members: List<BinderBoxID>,
    ) {
        if (order == null || before.groupsSections == after.groupsSections) return
        unit.afterCommit { order.keepAround(after.key, members, after.groupsSections) }
    }

    private fun fresh(step: Step, template: CategoryTemplate): CategoryTemplate =
        step.row(Tables.templates, template.pk) ?: throw TemplateStoreError.NotFound()

    private fun stored(): List<CategoryTemplate> = runBlocking {
        unit.store.database.withReadTransaction { Tables.templates.readAll(unit.store.database) }
    }

    private fun ordered(templates: List<CategoryTemplate>): List<CategoryTemplate> =
        templates.sortedWith(compareBy({ it.homeOrder }, { it.createdAt }))

    companion object {
        /**
         * Makes a category of the person's own in [step] at [now], last on the binder, with the lock
         * [isSensitive] says (kept as this phone's choice before the step saves): the one way one is
         * made, for every `createCustom` and the repair list's „Recuperate”.
         */
        @Suppress("LongParameterList") // What a new category is made of.
        internal fun makeCustom(
            step: Step,
            key: String,
            name: String,
            symbol: String,
            tint: String,
            parts: CategoryParts,
            isSensitive: Boolean,
            now: Instant,
        ): CategoryTemplate {
            val made = StoredMoment.kept(now)
            val order = CategoryOrder.after(step.all(Tables.templates).map { it.homeOrder })
            val blank = CategoryTemplate(
                key = key, name = name, symbol = symbol, tintRaw = tint, isBuiltIn = false, homeOrder = order,
                createdAt = made, updatedAt = made,
            )
            val template = step.insert(blank.withParts(parts))
            step.lockMadeWith(template, isSensitive)
            return template
        }

        /** What every category of one's own's key starts with (`TemplateDefinition.customKeyPrefix`). */
        const val CUSTOM_KEY_PREFIX = "custom."

        /** The tint a category of one's own starts with (`TemplateTint.gray`). */
        const val DEFAULT_TINT = "gray"
    }
}
