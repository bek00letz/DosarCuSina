package com.ar.dosarcusina.store.examples

import com.ar.dosarcusina.catalog.Catalog
import com.ar.dosarcusina.catalog.ExampleHousehold
import com.ar.dosarcusina.core.values.CalendarDay
import com.ar.dosarcusina.core.values.DosarCalendar
import com.ar.dosarcusina.store.LaunchData
import com.ar.dosarcusina.store.Step
import com.ar.dosarcusina.store.Tables
import com.ar.dosarcusina.store.Undoable
import com.ar.dosarcusina.store.UnitOfWork
import com.ar.dosarcusina.store.history.HistoryActions
import com.ar.dosarcusina.store.history.HistoryWording
import com.ar.dosarcusina.store.obligations.ObligationActions
import com.ar.dosarcusina.store.providers.ProviderActions
import com.ar.dosarcusina.store.schema.Asset
import com.ar.dosarcusina.store.sections.AssetActions
import com.ar.dosarcusina.store.templates.HouseholdDeadlines
import com.ar.dosarcusina.store.view
import java.time.Instant
import java.time.ZoneId
import java.util.UUID

/**
 * "Explore with examples": a small household that shows every part of the app, as the iOS app's
 * `ExampleDataService` (ios/DosarCuSina/Services/Examples/ExampleDataService.swift). The household is
 * the one the iOS app declares ([ExampleHousehold], exported to shared/catalog/examples/), made
 * through the actions only. Everything it makes is marked as an example: no sync carries it to
 * another device (Android has none), and nothing outside the app shows it (reminders, the badge and
 * widgets read the deadlines through `DeadlineSnapshot.forOutside`, search outside the app asks
 * `SearchPrivacy.mayShowOutside`). It goes away with [removeExamples].
 */
class ExampleDataService(
    private val unit: UnitOfWork,
    /** Launch's steps: the built-in categories are installed the one way, before the household is made. */
    private val launch: LaunchData,
    /** The words a record's title is written with when nothing names it (the household names every one). */
    private val wording: HistoryWording,
    private val household: ExampleHousehold = ExampleHousehold.builtIn,
    /** Every step's clock, and the moment the household's days and moments are counted from. */
    private val now: () -> Instant = unit.clock,
    /** The time zone the app counts days in (`Calendar.dosar`). */
    private val zone: () -> ZoneId = DosarCalendar::zone,
) {
    /** Whether any example is in the binder. */
    fun hasExamples(): Boolean = unit.view().all(Tables.assets).any { it.isExample }

    /**
     * Adds the example household, in one save: a failure part-way leaves no half household behind.
     * Does nothing if examples are already there.
     */
    fun loadExamples() {
        if (hasExamples()) return
        val moment = now()
        launch.installBuiltIns(moment)
        val actions = ExampleActions(
            AssetActions(unit, now = { moment }, zone = zone),
            ObligationActions(unit, now = { moment }, zone = zone),
            HistoryActions(unit, wording, now = { moment }),
            ProviderActions(unit, now = { moment }),
        )
        unit.perform(now = moment) { step -> ExampleLoader(actions, step, moment, zone()).load(household) }
    }

    /**
     * Deletes every example in one undoable step. Only examples go: anything of the person's is never
     * touched. Gives the names of the example sections kept because something of the person's sits in
     * them (from before the app asked): they become the person's, with everything under them and the
     * people who worked on them, so the screen can say so. The receipt brings every example back with
     * its links, and the kept ones become examples again.
     */
    fun removeExamples(): Undoable<List<String>> = unit.performUndoable(now()) { step ->
        val kept = keepTheOnesHoldingSomethingReal(step)
        for (row in step.all(Tables.assets).filter { it.isExample }.map { it.pk }) {
            step.row(Tables.assets, row)?.let(step::delete)
        }
        // Example records that don't hang off a section; people who worked on a kept one were kept with it.
        step.all(Tables.providers).filter { it.isExample }.forEach(step::delete)
        step.all(Tables.obligations).filter { it.isExample && it.asset == null }.forEach(step::delete)
        HouseholdDeadlines(Catalog.builtIn.household, zone()).reconcile(step, CalendarDay.of(now(), zone()), now())
        kept
    }

    /**
     * "Da" to „Păstrezi … ca al tău?” ([ExampleSectionQuestion]): the whole example the section sits
     * in, and everything in it, become the person's. Removing the examples never touches them again.
     */
    fun adopt(sectionId: UUID) {
        val view = unit.view()
        val section = view.all(Tables.assets).firstOrNull { it.id == sectionId } ?: return
        val root = ExampleOwnership.exampleSection(view, section) ?: section
        unit.perform(now = now()) { step -> step.row(Tables.assets, root.pk)?.let { ExampleTree.makeReal(step, it) } }
    }

    /** Each example from its top that holds something of the person's becomes theirs; their names. */
    private fun keepTheOnesHoldingSomethingReal(step: Step): List<String> {
        val kept = ArrayList<String>()
        for (row in step.all(Tables.assets).filter { it.isExample }.map { it.pk }) {
            // Read again: keeping one above it may have made it the person's already.
            val asset = step.row(Tables.assets, row)?.takeIf { isTopHoldingSomethingReal(step, it) } ?: continue
            kept += asset.name
            ExampleTree.makeReal(step, asset)
        }
        return kept
    }

    /** An example not filed under another example, with something of the person's in it or under it. */
    private fun isTopHoldingSomethingReal(step: Step, asset: Asset): Boolean {
        val parentIsExample = asset.parent?.let { step.row(Tables.assets, it) }?.isExample == true
        return asset.isExample && !parentIsExample && ExampleTree.holdsSomethingReal(step, asset)
    }
}
