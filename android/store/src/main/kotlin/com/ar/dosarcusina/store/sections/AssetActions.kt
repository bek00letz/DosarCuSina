package com.ar.dosarcusina.store.sections

import com.ar.dosarcusina.archive.v3.CustomFact
import com.ar.dosarcusina.archive.v3.FieldDefinition
import com.ar.dosarcusina.archive.v3.FieldValue
import com.ar.dosarcusina.archive.v3.FieldValues
import com.ar.dosarcusina.archive.v3.ObligationBlueprint
import com.ar.dosarcusina.archive.v3.StoredFile
import com.ar.dosarcusina.catalog.BlueprintRules
import com.ar.dosarcusina.catalog.Catalog
import com.ar.dosarcusina.catalog.CategoryParts
import com.ar.dosarcusina.catalog.DocumentNaming
import com.ar.dosarcusina.catalog.FieldRules
import com.ar.dosarcusina.catalog.PlannedObligation
import com.ar.dosarcusina.catalog.RecurrenceEngine
import com.ar.dosarcusina.catalog.Role
import com.ar.dosarcusina.catalog.SubscriptionFields
import com.ar.dosarcusina.catalog.drivingField
import com.ar.dosarcusina.catalog.isWorthScheduling
import com.ar.dosarcusina.catalog.recurrenceRule
import com.ar.dosarcusina.core.readings.LowerReadingAnswer
import com.ar.dosarcusina.core.readings.MeasurementKind
import com.ar.dosarcusina.core.readings.ReadingSource
import com.ar.dosarcusina.core.readiness.DocumentTypes
import com.ar.dosarcusina.core.readiness.TravelData
import com.ar.dosarcusina.core.subscriptions.BillReminders
import com.ar.dosarcusina.core.values.CalendarDay
import com.ar.dosarcusina.core.values.DosarCalendar
import com.ar.dosarcusina.core.values.JsonCodec
import com.ar.dosarcusina.core.values.MeasurementUnit
import com.ar.dosarcusina.core.values.ObligationStatus
import com.ar.dosarcusina.core.values.StoredDay
import com.ar.dosarcusina.core.values.ThreeWay
import com.ar.dosarcusina.store.BinderSnapshot
import com.ar.dosarcusina.store.BinderView
import com.ar.dosarcusina.store.Step
import com.ar.dosarcusina.store.Tables
import com.ar.dosarcusina.store.UndoReceipt
import com.ar.dosarcusina.store.Undoable
import com.ar.dosarcusina.store.UnitOfWork
import com.ar.dosarcusina.store.examples.ExampleOwnership
import com.ar.dosarcusina.store.obligations.DeadlineMutations
import com.ar.dosarcusina.store.obligations.DeadlineReminders
import com.ar.dosarcusina.store.obligations.ObligationActions
import com.ar.dosarcusina.store.readings.HeroMetric
import com.ar.dosarcusina.store.readings.HouseholdReadings
import com.ar.dosarcusina.store.readings.PlannedSectionReading
import com.ar.dosarcusina.store.schema.Asset
import com.ar.dosarcusina.store.schema.CategoryTemplate
import com.ar.dosarcusina.store.schema.MeasurementLog
import com.ar.dosarcusina.store.schema.StoredMoment
import com.ar.dosarcusina.store.schema.dueDay
import com.ar.dosarcusina.store.schema.keptBlueprints
import com.ar.dosarcusina.store.schema.keptFacts
import com.ar.dosarcusina.store.schema.keptSections
import com.ar.dosarcusina.store.schema.keptValues
import com.ar.dosarcusina.store.schema.withKeptFacts
import com.ar.dosarcusina.store.schema.withKeptValues
import com.ar.dosarcusina.store.security.SecretFields
import com.ar.dosarcusina.store.security.SecretSealer
import com.ar.dosarcusina.store.templates.HouseholdDeadlines
import com.ar.dosarcusina.store.templates.template
import kotlinx.coroutines.runBlocking
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonElement
import java.time.Instant
import java.time.ZoneId
import java.util.UUID

/** Why a section action was refused, as kinds: the screens word them. */
sealed class AssetActionError(message: String) : Exception(message) {
    /** Something can't be filed under itself, nor under anything filed under it. */
    class WouldCreateLoop : AssetActionError("A section can't go under one that is already under it")

    /** The place chosen to move something to is gone. */
    class MissingDestination : AssetActionError("The place chosen isn't in the binder any more")

    /** A new person was asked for without a name. */
    class MissingName : AssetActionError("A new person needs a name")
}

/**
 * What an edit of a section started from: its name, values and notes as the form read them when it
 * opened, as the iOS app's `SectionEditStart`. Saving writes only what changed from these
 * ([AssetActions.update]).
 */
data class SectionEditStart(val name: String, val values: FieldValues, val notes: String?) {
    /** The edit's values laid over the values stored now: every field the edit changed, every other as stored. */
    fun laying(edited: FieldValues, stored: FieldValues): FieldValues =
        ThreeWay.laying(edited, stored, values, FieldValues.codec)

    companion object {
        /** What a form opened on [asset] starts from. */
        fun of(asset: Asset): SectionEditStart = SectionEditStart(asset.name, asset.keptValues.value, asset.notes)
    }
}

/** A parent made with a section: a new person and their first document, a new home and its first subscription. */
data class NewParent(val name: String, val template: CategoryTemplate, val values: FieldValues = FieldValues())

/** Where a moved section goes ("Mută la…"). */
sealed interface MoveTarget {
    /** An existing section of the parent's kind, by its id. */
    data class ToSection(val id: UUID) : MoveTarget

    /** A new person with this name, made in the same step (documents only). */
    data class NewMember(val name: String) : MoveTarget

    /** Filed under nothing: a subscription or a plant taken out of its home, into its own box. */
    data object Standalone : MoveTarget
}

/** What happens to the sections filed under one that is deleted; the screen asks. */
enum class ChildrenOnDelete {
    /** They stay, standing on their own. */
    KEEP,

    /** They go too, and whatever is filed under them. */
    DELETE,
}

/** What saving an edit changed beyond the values, for the screen to say. */
data class EditOutcome(
    /** The subscription's bill reminder followed its direct debit, with the receipt that takes back the whole edit. */
    val billReminder: Undoable<BillReminders.Change>? = null,
)

/** "Editează" on a personal document's page: the values the person corrected, as one undoable step. */
data class DocumentEdit(
    val name: String,
    val values: FieldValues,
    val notes: String?,
    /** What the form started from; only what changed from it is written. None: the document as stored now. */
    val startedFrom: SectionEditStart? = null,
)

/**
 * Everything a person does to a section: making one (with its deadlines and its parent), editing
 * it, measuring it, moving it and deleting it, as the iOS app's `AssetActions`
 * (ios/DosarCuSina/Services/Obligations/AssetActions.swift, AssetActions+Move.swift,
 * +Document.swift and +Photo.swift). Each is one step of the unit of work, which joins a step it
 * runs inside.
 *
 * - **Every question comes first**, before the unit opens: something of the person's in an example
 *   ([ExampleOwnership.requireReal]), a lower counter ([HouseholdReadings.askAboutReading]).
 * - **Secrets are sealed** before they are saved ([SecretFields.sealing], with [sealer]); the store
 *   refuses a secret in plain.
 * - **A form saves only what was changed in it** ([SectionEditStart], [ThreeWay]).
 * - **The household's own deadlines follow** a section made or deleted ([HouseholdDeadlines]).
 */
// The iOS type's surface, one function per job.
@Suppress("TooManyFunctions")
class AssetActions(
    private val unit: UnitOfWork,
    /** Seals secret fields (PIN codes) before they are saved. */
    private val sealer: SecretSealer = SecretSealer.NOT_YET,
    /** The moment a reading is recorded at when nothing else says, and every step's clock. */
    private val now: () -> Instant = unit.clock,
    /** The time zone the app counts days in (`Calendar.dosar`). */
    private val zone: () -> ZoneId = DosarCalendar::zone,
    /** The app's own categories: a section's definition when its category's record isn't here. */
    private val catalog: Catalog = Catalog.builtIn,
    /** What a personal document can be: its types, their variants and the names they give. */
    private val documentTypes: DocumentTypes = TravelData.builtIn.documents,
) {
    // Planning

    /** The deadlines a new section of [template] starts with, for [values], with their first days worked out. */
    fun plannedObligations(template: CategoryTemplate, values: FieldValues): List<PlannedObligation> =
        plannedObligations(
            CategoryParts(sections = template.keptSections.items, blueprints = template.keptBlueprints.items),
            values,
        )

    /** The same for a category not saved yet: one of the person's own, while they describe it. */
    fun plannedObligations(parts: CategoryParts, values: FieldValues): List<PlannedObligation> =
        BlueprintRules.planned(
            parts.sections.flatMap { it.fields }, parts.blueprints, values, today(), documentTypes,
        )

    // Making

    /**
     * Makes the section and the selected deadlines in one step, and its hero value as its first
     * reading. With [newParent], the parent is made in the same step, so a failure leaves neither.
     * The household's own deadlines follow (a tenancy brings the rental income declaration).
     */
    @Suppress("LongParameterList") // The iOS action's own questions.
    fun create(
        name: String,
        template: CategoryTemplate,
        values: FieldValues,
        notes: String? = null,
        obligations: List<PlannedObligation> = emptyList(),
        parent: Asset? = null,
        newParent: NewParent? = null,
        isExample: Boolean = false,
    ): Asset {
        // Something of the person's never lands inside an example without asking.
        val view = snapshot()
        ExampleOwnership.requireReal(view, parent?.let { view.row(Tables.assets, it.pk) }, catalog, isExample)
        val prepared = prepare(values, fields(template))
        val parentValues = newParent?.let { prepare(it.values, fields(it.template)) }
        val made = Making(name, template, prepared, notes, obligations, isExample)
        return unit.perform(now = now()) { step ->
            val holder = newParent?.let {
                val holderValues = requireNotNull(parentValues)
                make(step, Making(it.name, it.template, holderValues, null, emptyList(), isExample), parent = null)
            }
            make(step, made, holder?.pk ?: parent?.pk)
        }
    }

    /** Makes [section] in [step] under the section in row [parent]: the one way, [SectionMaking.make]. */
    private fun make(step: Step, section: Making, parent: Long?): Asset =
        SectionMaking.make(step, section, parent, StoredMoment.kept(now()), zone(), catalog)

    // Editing

    /**
     * Saves an edit. Deadlines first due by a field (a document's renewal by its expiry) move with it,
     * a field that drives a deadline the section hasn't got makes it, and their reminders follow a
     * changed value they read ([DeadlineReminders.follow]). A changed hero value (the kilometres) is a
     * new reading, dated [readingDate] or now; a lower counter asks until [lowerReading] answers it. A
     * subscription whose direct debit changed pauses or resumes its bill reminder ([BillReminders]).
     *
     * Only what the edit changed from [startedFrom] (else the section as stored now) is written
     * ([ThreeWay]): a name, a note or a field it left as it read them keeps what is stored now.
     */
    @Suppress("LongParameterList") // The iOS action's own questions.
    fun update(
        asset: Asset,
        name: String,
        values: FieldValues,
        notes: String?,
        startedFrom: SectionEditStart? = null,
        readingSource: ReadingSource = ReadingSource.PERSON,
        readingDate: Instant? = null,
        lowerReading: LowerReadingAnswer? = null,
    ): EditOutcome {
        val view = snapshot()
        val edit = edit(view, current(view, asset), Typed(name, values, notes, startedFrom), readingSource, readingDate)
        // Every question first, before anything is written (`StepQuestion`).
        HouseholdReadings.askAboutReading(view, edit.reading, lowerReading)
        return unit.perform(now = now()) { step -> write(step, edit, lowerReading) }
    }

    /**
     * Asks what saving [values] on [asset] with [update] would ask (a lower counter), changing
     * nothing: for a screen that saves the edit with other changes in one step.
     */
    fun askFirst(
        asset: Asset,
        values: FieldValues,
        startedFrom: SectionEditStart? = null,
        lowerReading: LowerReadingAnswer?,
    ) {
        val view = snapshot()
        val section = current(view, asset)
        val start = startedFrom ?: SectionEditStart.of(section)
        val edit = edit(view, section, Typed(section.name, values, section.notes, start), ReadingSource.PERSON, null)
        HouseholdReadings.askAboutReading(view, edit.reading, lowerReading)
    }

    /**
     * Saves a personal document's edit in one undoable step, through [update] (sealing, deadlines,
     * reminders). A name that is still the type's own follows a corrected type
     * ([DocumentNaming.retyped]); a name the person changed in the same
     * edit is theirs. Its back and reading it again are capture's (Phase 5).
     */
    fun editDocument(document: Asset, edit: DocumentEdit): Undoable<EditOutcome> = unit.performUndoable(now()) { _ ->
        val stored = current(snapshot(), document)
        val start = edit.startedFrom ?: SectionEditStart.of(stored)
        var name = edit.name
        if (name == start.name) {
            val oldName = documentName(start.values)
            val newName = documentName(edit.values)
            if (newName != null) {
                DocumentNaming.retyped(start.name, oldName, newName)?.let { name = it }
            }
        }
        update(stored, name, edit.values, edit.notes, start)
    }

    /**
     * Replaces the free rows under Date importante. A secret row (a code) is sealed before it is
     * saved; a card number in any row is kept as its last four digits (`FreeText`). Only what the
     * edit changed from [startedFrom] (else the rows stored now) is written, row by row ([ThreeWay]).
     */
    fun setCustomFacts(asset: Asset, facts: List<CustomFact>, startedFrom: List<CustomFact>? = null): UndoReceipt {
        val stored = current(snapshot(), asset).keptFacts.items
        val laid = ThreeWay.laying(facts, stored, startedFrom ?: stored, FactsCodec)
        val kept = laid.filter { it.label.isNotBlank() || it.value.isNotBlank() }
        val sealed = SecretFields.sealingFacts(kept, sealer)
        return unit.performUndoable(now()) { step ->
            val row = fresh(step, asset)
            step.update(row.withKeptFacts(row.keptFacts.replacingItems(sealed)))
        }.receipt
    }

    /** Sets or removes the section's photo (a pet, the car, a box on the binder), kept beside the database. */
    fun setPhoto(asset: Asset, photo: StoredFile?) = unit.perform(now = now()) { step ->
        val digest = photo?.let(step::keep)
        step.update(fresh(step, asset).copy(photoData = digest))
    }

    /**
     * What a personal document with [values] is called by its type and variant ("Carte de
     * identitate", "Cazier judiciar"), when it has a type this build knows.
     */
    fun documentName(values: FieldValues): String? = documentTypes.nameFromFields(
        values[documentTypes.typeField]?.textValue, values[documentTypes.variantField]?.textValue,
    )

    // Measuring

    /**
     * Records a counter reading on its own (the kilometres read today) in the unit of the section's
     * hero field, through the one path: an estimate is never stored, a lower counter asks first, and
     * the hero value follows the readings. Gives the reading kept, or none for an estimate.
     */
    fun recordReading(
        asset: Asset,
        value: Double,
        source: ReadingSource,
        at: Instant? = null,
        lowerReading: LowerReadingAnswer? = null,
    ): MeasurementLog? {
        val view = snapshot()
        val section = current(view, asset)
        val unitOfField = HeroMetric.unit(HeroMetric.categoryFields(view, section))
        // Every question first, before anything is written (`StepQuestion`).
        val isExample = ExampleOwnership.requireReal(view, section, catalog)
        val planned = HouseholdReadings.plan(view, section.pk, value, at ?: now(), source, unitOfField)
        HouseholdReadings.askAboutReading(view, planned, lowerReading)
        if (!planned.reading.isStored) return null
        return unit.perform(now = now()) { step ->
            HouseholdReadings.recordReading(step, planned, lowerReading, isExample)
        }
    }

    /**
     * Records a measured value of any kind (a meter index, a weight, a lab value) through the one
     * reading path. Counter readings also update the hero value. [asExample] only for the example loader.
     */
    @Suppress("LongParameterList") // The iOS action's parts, each with its default.
    fun recordMeasurement(
        asset: Asset,
        kind: MeasurementKind,
        value: Double,
        unit: MeasurementUnit? = null,
        name: String = "",
        at: Instant? = null,
        asExample: Boolean = false,
        lowerReading: LowerReadingAnswer? = null,
    ): MeasurementLog {
        val view = snapshot()
        val section = current(view, asset)
        val isExample = ExampleOwnership.requireReal(view, section, catalog, creatingExample = asExample)
        val planned = HouseholdReadings.plan(
            view, section.pk, value, at ?: now(), ReadingSource.PERSON, unit, kind = kind, name = name,
        )
        HouseholdReadings.askAboutReading(view, planned, lowerReading)
        return this.unit.perform(now = now()) { step ->
            // Only an estimate gives none, and this records what was measured.
            requireNotNull(HouseholdReadings.recordReading(step, planned, lowerReading, isExample)) {
                "A measured value is a number"
            }
        }
    }

    /**
     * "Nu e contor nou": the reading the person once said started a new counter doesn't. The
     * readings in its unit count as one counter again, and the hero value follows them. One
     * undoable step; nothing is deleted.
     */
    fun notANewCounter(start: MeasurementLog): UndoReceipt = unit.performUndoable(now = now()) { step ->
        val log = requireNotNull(step.row(Tables.readings, start.pk)) { "The reading is gone" }
        step.update(log.copy(startsCounter = false))
        log.asset?.let { HeroMetric.sync(step, it) }
    }.receipt

    // Moving

    /** Files [child] under [parent], or makes it stand on its own with none; never under itself. */
    fun setParent(child: Asset, parent: Asset?) = unit.perform(now = now()) { step ->
        setParent(step, fresh(step, child), parent?.let { fresh(step, it) })
    }

    /**
     * Files [child] under [target] in one step, renamed to [renamingTo] when given. For a new person,
     * the person and the move are kept together or not at all. The receipt takes the move back: the
     * old place and name return, and a person made for it goes again.
     */
    fun move(child: Asset, target: MoveTarget, renamingTo: String? = null): UndoReceipt =
        unit.performUndoable(now()) { step ->
            val parent: Asset? = when (target) {
                MoveTarget.Standalone -> null
                is MoveTarget.ToSection -> step.all(Tables.assets).firstOrNull { it.id == target.id }
                    ?: throw AssetActionError.MissingDestination()
                is MoveTarget.NewMember -> newMember(step, target.name, fresh(step, child).isExample)
            }
            setParent(step, fresh(step, child), parent)
            val newName = renamingTo?.trim()?.takeIf { it.isNotEmpty() }
            val row = fresh(step, child)
            if (newName != null && newName != row.name) {
                val typed = Typed(newName, row.keptValues.value, row.notes, SectionEditStart.of(row))
                write(step, edit(step, row, typed, ReadingSource.PERSON, null), lowerReading = null)
            }
        }.receipt

    // Deleting

    /**
     * Deletes the section with its deadlines, history, readings and documents (their pages too),
     * and, with [ChildrenOnDelete.DELETE], everything filed under it; what stays stands on its own.
     * A household deadline only it needed goes too. One undoable step: the receipt brings all of it
     * back with every link.
     */
    fun delete(asset: Asset, children: ChildrenOnDelete = ChildrenOnDelete.KEEP): UndoReceipt =
        unit.performUndoable(now()) { step ->
            val moment = StoredMoment.kept(now())
            if (children == ChildrenOnDelete.DELETE) {
                for (child in SectionPlaces.descendants(step, fresh(step, asset))) {
                    step.row(Tables.assets, child.pk)?.let(step::delete)
                }
            }
            step.delete(fresh(step, asset))
            HouseholdDeadlines(catalog.household, zone()).reconcile(step, CalendarDay.of(moment, zone()), moment)
        }.receipt

    // Inside

    /** What a form typed: its name, values and notes, and what it started from. */
    private class Typed(val name: String, val values: FieldValues, val notes: String?, val start: SectionEditStart?)

    /** An edit worked out before its step: what is written, and the reading it records. */
    private class Edit(
        val asset: Long,
        val name: String,
        val values: FieldValues,
        val notes: String?,
        val previous: FieldValues,
        val template: CategoryTemplate?,
        val reading: PlannedSectionReading?,
    )

    /** [typed] laid over [section] as [view] has it, with the rules and the seal applied: what saving writes. */
    private fun edit(view: BinderView, section: Asset, typed: Typed, source: ReadingSource, date: Instant?): Edit {
        val opened = typed.start ?: SectionEditStart.of(section)
        val stored = section.keptValues.value
        val laid = opened.laying(typed.values, stored)
        val template = SectionPlaces.categories(view)[section.templateKey]
        val definition = template?.let { fields(it) }
        val values = definition?.let {
            val ruled = FieldRules.applying(FieldRules.normalizingChoices(laid, it), it, stored, documentTypes)
            SecretFields.sealing(ruled, it, sealer)
        } ?: laid
        val hero = definition?.let { HeroMetric.value(values, it) }
        val before = definition?.let { HeroMetric.value(stored, it) }
        val reading = if (hero == null || hero == before) {
            null
        } else {
            HouseholdReadings.plan(view, section.pk, hero, date ?: now(), source, HeroMetric.unit(definition))
        }
        return Edit(
            asset = section.pk,
            name = ThreeWay.value(typed.name, section.name, opened.name),
            values = values,
            notes = ThreeWay.value(typed.notes, section.notes, opened.notes),
            previous = stored,
            template = template,
            reading = reading,
        )
    }

    private fun write(step: Step, edit: Edit, lowerReading: LowerReadingAnswer?): EditOutcome {
        val row = requireNotNull(step.row(Tables.assets, edit.asset)) { "No section in row ${edit.asset}" }
        val values = row.keptValues.replacingValue(edit.values)
        step.update(row.copy(name = edit.name, notes = edit.notes).withKeptValues(values))
        val template = edit.template
        if (template != null) {
            val blueprints = template.keptBlueprints.items
            // A value the deadlines' reminders read changed: they remind as it asks, unless the person set them.
            DeadlineReminders.follow(step, fresh(step, edit.asset), blueprints, edit.previous)
            moveDueDays(step, edit, blueprints)
            makeDrivenDeadlines(step, edit, blueprints)
            edit.reading?.let { HouseholdReadings.recordReading(step, it, lowerReading) }
        }
        // A subscription's direct debit changed: its bill reminder pauses or comes back.
        return EditOutcome(billReminder = followBills(step, edit))
    }

    /** Deadlines first due by a field that changed, and that don't repeat, move with it. */
    private fun moveDueDays(step: Step, edit: Edit, blueprints: List<ObligationBlueprint>) {
        val byKey = blueprints.associateByFirst()
        val active = obligations(step, edit.asset).filter {
            ObligationStatus.stored(it.statusRaw) == ObligationStatus.ACTIVE
        }
        for (obligation in active) {
            val blueprint = obligation.blueprintKey?.let(byKey::get)?.takeUnless { it.recurrenceRule.repeats }
            val due = blueprint?.let { movedDay(edit, it) } ?: continue
            step.update(obligation.copy(dueDayISO = StoredDay.text(due)))
        }
    }

    /**
     * The day a deadline from [blueprint] moves to, when the edit changed the field it is first due by
     * ([drivingField]) to a day: that day by its rule ([RecurrenceEngine.firstDue], with its offset).
     */
    private fun movedDay(edit: Edit, blueprint: ObligationBlueprint): CalendarDay? {
        val field = blueprint.drivingField ?: return null
        if (edit.previous[field] == edit.values[field]) return null
        val today = CalendarDay.of(StoredMoment.kept(now()), zone())
        return RecurrenceEngine.firstDue(blueprint, edit.values, today)
    }

    /**
     * A field that drives a deadline gets a value and the section has none from it: the deadline is
     * made, as adding the section would have (a policy's end typed in later).
     */
    private fun makeDrivenDeadlines(step: Step, edit: Edit, blueprints: List<ObligationBlueprint>) {
        val moment = StoredMoment.kept(now())
        val today = CalendarDay.of(moment, zone())
        val running = setOf(ObligationStatus.ACTIVE, ObligationStatus.PAUSED)
        val kept = obligations(step, edit.asset).filter { ObligationStatus.stored(it.statusRaw) in running }
            .mapNotNull { it.blueprintKey }.toSet()
        for (blueprint in blueprints.filter { it.key !in kept && drives(edit, it) }) {
            val day = RecurrenceEngine.firstDue(blueprint, edit.values, today)
                ?.takeIf { blueprint.isWorthScheduling(it, today, edit.values) } ?: continue
            DeadlineMutations.makeObligation(step, blueprint, fresh(step, edit.asset), day, today, moment, catalog)
        }
    }

    /** Whether the edit gave [blueprint]'s field a day it didn't have, for a deadline that applies. */
    private fun drives(edit: Edit, blueprint: ObligationBlueprint): Boolean {
        val field = blueprint.drivingField ?: return false
        val changed = edit.previous[field] != edit.values[field]
        return changed && edit.values[field] is FieldValue.Day && BlueprintRules.applies(blueprint, edit.values)
    }

    private fun followBills(step: Step, edit: Edit): Undoable<BillReminders.Change>? {
        val bills = obligations(step, edit.asset).filter { it.blueprintKey == SubscriptionFields.BILL_BLUEPRINT }
        val today = CalendarDay.of(StoredMoment.kept(now()), zone())
        val deadlines = bills.map { bill ->
            BillReminders.BillDeadline(
                bill.id, ObligationStatus.stored(bill.statusRaw), bill.dueDay ?: CalendarDay.of(bill.createdAt, zone()),
            )
        }
        val before = paysByDirectDebit(edit.previous)
        val followed = BillReminders.follow(before, paysByDirectDebit(edit.values), deadlines, today) ?: return null
        val actions = ObligationActions(unit, now)
        var receipt: UndoReceipt? = null
        for (bill in bills.filter { it.id in followed.deadlines }) {
            receipt = when (followed.change) {
                BillReminders.Change.PAUSED -> actions.pause(bill)
                BillReminders.Change.RESUMED -> actions.resume(bill)
            }
        }
        return receipt?.let { Undoable(followed.change, it) }
    }

    private fun paysByDirectDebit(values: FieldValues): Boolean =
        (values[SubscriptionFields.DIRECT_DEBIT] as? FieldValue.Toggle)?.value ?: false

    private fun setParent(step: Step, child: Asset, parent: Asset?) {
        if (parent != null && !SectionPlaces.canFile(step, child, parent)) throw AssetActionError.WouldCreateLoop()
        step.update(child.copy(parent = parent?.pk))
    }

    /** A new person for a move: named, of the category that plays a holder's part, made in [step]. */
    private fun newMember(step: Step, name: String, isExample: Boolean): Asset {
        val trimmed = name.trim()
        if (trimmed.isEmpty()) throw AssetActionError.MissingName()
        val holder = SectionPlaces.categories(step).values.toList().template(withRole = Role.HOLDER)
            ?: throw AssetActionError.MissingDestination()
        val values = prepare(FieldValues(), fields(holder))
        return make(step, Making(trimmed, holder, values, null, emptyList(), isExample), parent = null)
    }

    /** [values] as saving a new section keeps them: choices as keys, the rules applied, secrets sealed. */
    private fun prepare(values: FieldValues, fields: List<FieldDefinition>): FieldValues {
        val keys = FieldRules.normalizingChoices(values, fields)
        val ruled = FieldRules.applying(keys, fields, previous = null, documentTypes = documentTypes)
        return SecretFields.sealing(ruled, fields, sealer)
    }

    private fun fields(template: CategoryTemplate): List<FieldDefinition> =
        template.keptSections.items.flatMap { it.fields }

    private fun obligations(step: Step, asset: Long) =
        step.pointingAt(Tables.obligations, "asset", asset).mapNotNull { step.row(Tables.obligations, it) }

    private fun List<ObligationBlueprint>.associateByFirst(): Map<String, ObligationBlueprint> {
        val byKey = LinkedHashMap<String, ObligationBlueprint>()
        for (blueprint in this) byKey.putIfAbsent(blueprint.key, blueprint)
        return byKey
    }

    private fun today(): CalendarDay = CalendarDay.of(now(), zone())

    private fun snapshot(): BinderView = runBlocking { BinderSnapshot.read(unit.store.database) }

    private fun current(view: BinderView, asset: Asset): Asset =
        requireNotNull(view.row(Tables.assets, asset.pk)) { "No section in row ${asset.pk}" }

    private fun fresh(step: Step, asset: Asset): Asset = fresh(step, asset.pk)

    private fun fresh(step: Step, row: Long): Asset =
        step.row(Tables.assets, row) ?: throw NoSuchElementException("The section isn't in the binder")

    /** A section's rows under Date importante, as a whole, for laying an edit over them row by row. */
    private object FactsCodec : JsonCodec<List<CustomFact>> {
        override fun decode(json: JsonElement): List<CustomFact>? {
            val rows = json as? JsonArray ?: return null
            val facts = rows.map(CustomFact.codec::decode)
            return if (facts.any { it == null }) null else facts.filterNotNull()
        }

        override fun encode(value: List<CustomFact>): JsonElement = JsonArray(value.map(CustomFact.codec::encode))
    }
}
