package com.ar.dosarcusina.store.repairs

import com.ar.dosarcusina.archive.binder.BuiltIns
import com.ar.dosarcusina.catalog.Catalog
import com.ar.dosarcusina.core.values.DosarCalendar
import com.ar.dosarcusina.store.BinderSnapshot
import com.ar.dosarcusina.store.BinderView
import com.ar.dosarcusina.store.ChangeOrigin
import com.ar.dosarcusina.store.DeviceLocks
import com.ar.dosarcusina.store.Step
import com.ar.dosarcusina.store.UnitOfWork
import kotlinx.coroutines.runBlocking
import java.time.Instant
import java.time.ZoneId

/**
 * The repair list: data an earlier version saved wrongly, found by an ordered registry of steps and
 * changed only with the owner's OK, as the iOS app's `DataRepairs`
 * (ios/DosarCuSina/Services/Repairs/DataRepairs.swift). The binder comes to this phone from the
 * person's iOS backups, so the same repairs run here, in the same order, under the same ids: else the
 * two apps would hold different binders.
 *
 * - Every step is idempotent and has a stored id ([DataRepairStepId]); its findings carry ids built
 *   from it, so a dismissal is remembered ([DataRepairLedger]) and an applied repair isn't found again.
 * - [detect] runs after the built-in categories are installed at launch and after every import.
 *   Steps that only change how a value is stored, never what it says ([DataRepairStep.runsByItself]),
 *   run then; every other step only lists what it would change.
 * - [apply] changes what the owner approved, in one unit of work.
 * - Both are the app's own steps ([ChangeOrigin.APP]), the owner's OK included: what a repair changes
 *   keeps its change time, so a copy changed by the person on another phone still comes in with
 *   "Adaugă", and the list finds the repair again after that import.
 *
 * A finding carries kinds and data only ([DataRepairSubject], [DataRepairGroup], [ApplyVerb]), never a
 * sentence: what the list says is the app's to word, from its strings, as the iOS app's String Catalog
 * words it.
 */
class DataRepairs(
    private val unit: UnitOfWork,
    /** What the owner chose to leave as it is, and what the calm prompt already announced. */
    val ledger: DataRepairLedger,
    /** The app's own categories, for a section whose category's record isn't here (`BuiltInTemplates.definition`). */
    private val builtIns: BuiltIns = Catalog.builtIn,
    /** The time zone the app counts days in (`Calendar.dosar`). */
    private val zone: () -> ZoneId = DosarCalendar::zone,
) {
    /**
     * Runs the steps that change nothing anyone sees, in one app-made unit, then lists what waits for
     * the owner, leaving out what they chose to leave as it is.
     */
    fun detect(): List<DataRepairFinding> {
        val context = context()
        unit.perform(ChangeOrigin.APP) { step ->
            for (repair in steps) if (repair.runsByItself) repair.runByItself(step, context)
        }
        val view = runBlocking { BinderSnapshot.read(unit.store.database) }
        val scan = DataRepairScan(view, context)
        val found = steps.filterNot { it.runsByItself }.flatMap { it.findings(scan) }
        val dismissed = ledger.dismissed
        return found.filter { it.id !in dismissed }
    }

    /** Makes the approved changes, in one app-made step: all of them, or none. */
    fun apply(findings: List<DataRepairFinding>) {
        // A finding that only says what to do changes nothing.
        val fixable = findings.filter { it.isFixable }
        if (fixable.isEmpty()) return
        val byStep = fixable.groupBy { it.step }
        val context = context()
        unit.perform(ChangeOrigin.APP) { step ->
            for (repair in steps) {
                val mine = byStep[repair.id] ?: continue
                repair.apply(mine, step, context)
            }
        }
    }

    /** "Lasă așa": remembered, so the finding isn't offered again. */
    fun dismiss(findings: List<DataRepairFinding>) {
        ledger.dismiss(findings.map { it.id })
    }

    private fun context() = DataRepairContext(zone(), unit.clock(), builtIns, unit.locks)

    companion object {
        /**
         * The registry, in the order the steps run: the iOS app's `DataRepairs.steps`, step for step
         * (`DataRepairRegistryTest` reads that list and fails when this one differs). A new repair is a
         * new step at the end; one whose rule needs what this app doesn't have yet waits ([WaitingStep]).
         */
        val steps: List<DataRepairStep> = listOf(
            ChoiceKeysStep,
            FirstVersionDeadlinesStep,
            WaitingSteps.staleDocumentLinks,
            WaitingSteps.visitsWithoutInvoice,
            WaitingSteps.duplicateProviders,
            DoubleCompletionsStep,
            CounterOutliersStep,
            EstimatedVisitReadingsStep,
            HeroFromReadingsStep,
            WaitingSteps.cascoInRcaFields,
            WaitingSteps.homePolicyWithoutDeadline,
            TravelCutoffStep,
            WaitingSteps.homePolicySets,
            UnitKeysStep,
            WaitingSteps.policyNumberParts,
            WaitingSteps.billNumbers,
            WaitingSteps.sameBillTwice,
            CardNumbersStep,
            WaitingSteps.sameVisitTwice,
            DayYearsStep,
            WaitingSteps.estimatedBillReadings,
            WaitingSteps.sectionsIntoTheirHome,
            OwnCategoryBoxesStep,
            OwnCategoryVisitsStep,
            ServiceNotesStep,
            RenewalRepeatsStep,
            WaitingSteps.subscriptionCodes,
            WaitingSteps.citizenships,
            PersonalLessonLabelsStep,
            WaitingSteps.labourParts,
            WaitingSteps.lostRecords,
        )

        private val byId: Map<DataRepairStepId, DataRepairStep> = steps.associateBy { it.id }

        /** The step with [id]: every id has one. */
        fun step(id: DataRepairStepId): DataRepairStep = byId.getValue(id)

        /**
         * Whether a finding is a suggestion (its step's [DataRepairStep.isSuggestion]): the one rule that
         * keeps suggestions out of the repair list and its prompt.
         */
        fun isSuggestion(finding: DataRepairFinding): Boolean = step(finding.step).isSuggestion
    }
}

/**
 * The stored ids of the registry's steps, as the iOS app's `DataRepairStepID`: never renamed, since
 * dismissals are kept by them, and the same on both apps.
 */
enum class DataRepairStepId(val raw: String) {
    CHOICE_KEYS("choice-keys"),
    FIRST_VERSION_DEADLINES("first-version-deadlines"),
    STALE_DOCUMENT_LINKS("stale-document-links"),
    VISITS_WITHOUT_INVOICE("visits-without-invoice"),
    DUPLICATE_PROVIDERS("duplicate-providers"),
    DOUBLE_COMPLETIONS("double-completions"),
    COUNTER_OUTLIERS("counter-outliers"),
    ESTIMATED_VISIT_READINGS("estimated-visit-readings"),
    HERO_FROM_READINGS("hero-from-readings"),
    CASCO_IN_RCA_FIELDS("casco-in-rca-fields"),
    HOME_POLICY_WITHOUT_DEADLINE("home-policy-without-deadline"),
    TRAVEL_CUTOFF("travel-cutoff"),
    HOME_POLICY_SETS("home-policy-sets"),
    UNIT_KEYS("unit-keys"),
    POLICY_NUMBER_PARTS("policy-number-parts"),
    BILL_NUMBERS("bill-numbers"),
    SAME_BILL_TWICE("same-bill-twice"),
    CARD_NUMBERS("card-numbers"),
    SAME_VISIT_TWICE("same-visit-twice"),
    DAY_YEARS("day-years"),
    ESTIMATED_BILL_READINGS("estimated-bill-readings"),
    SECTIONS_INTO_THEIR_HOME("sections-into-their-home"),
    OWN_CATEGORY_BOXES("own-category-boxes"),
    OWN_CATEGORY_VISITS("own-category-visits"),
    SERVICE_NOTES("service-notes"),
    RENEWAL_REPEATS("renewal-repeats"),
    SUBSCRIPTION_CODES("subscription-codes"),
    CITIZENSHIPS("citizenships"),
    PERSONAL_LESSON_LABELS("personal-lesson-labels"),
    LABOUR_PARTS("labour-parts"),
    LOST_RECORDS("lost-records"),
}

/**
 * What a group of findings is called in the list, one per title the iOS app gives its steps (two
 * steps can share one: the counters' and the hero value's). The app words each from its strings.
 */
enum class DataRepairGroup {
    /** Choice values from older builds, kept as their display text. */
    CHOICE_KEYS,

    /** Deadlines imported from a first-version backup. */
    OLD_BACKUP_DEADLINES,

    /** Documents moved with their old links. */
    MOVED_DOCUMENTS,

    /** Visits saved without their invoice. */
    VISITS_WITHOUT_INVOICE,

    /** The same firm kept twice. */
    FIRMS_KEPT_TWICE,

    /** Deadlines an old reminder may have closed twice. */
    DEADLINES_CLOSED_TWICE,

    /** Counter readings that look wrong, and the hero value worked out from them. */
    COUNTERS,

    /** Visit readings that were the form's estimate. */
    ESTIMATES_KEPT_AS_READINGS,

    /** CASCO facts kept in a car's RCA fields. */
    CASCO_IN_RCA,

    /** Home policies kept without their deadline. */
    POLICIES_WITHOUT_DEADLINE,

    /** Passports get the day they stop being good for travel. */
    PASSPORTS_AND_TRAVEL,

    /** A home's shared policy facts split into PAD and the optional policy. */
    HOME_POLICIES,

    /** Units stored by their label in older builds. */
    UNITS,

    /** Policy numbers kept with only their series. */
    POLICY_NUMBERS,

    /** Invoice numbers kept in a bill's note by older builds. */
    BILL_NUMBERS,

    /** The same bill logged twice in Istoric. */
    BILLS_LOGGED_TWICE,

    /** Whole bank card numbers kept in rows, notes or titles by older builds. */
    CARD_NUMBERS,

    /** The same visit's invoice logged twice in Istoric. */
    VISITS_LOGGED_TWICE,

    /** Kept days that can't be: another calendar's year, or a day its month doesn't have. */
    IMPOSSIBLE_DAYS,

    /** Meter indexes a bill estimated, kept as if read. */
    ESTIMATED_INDEXES,

    /** Sections that can be filed under the household's only home, car or person. */
    BELONGS_TO_ANOTHER_SECTION,

    /** A category of one's own whose one box becomes its grouping. */
    OWN_CATEGORY_BOXES,

    /** A category of one's own gets the visits its switch gives. */
    OWN_CATEGORY_VISITS,

    /** Service deadlines of a category of one's own that keep their rule as a note. */
    SERVICES,

    /** Deadlines that close when a document is replaced, kept repeating by an earlier version. */
    RENEWED_DOCUMENTS,

    /** A subscription's code kept under another code's name. */
    SUBSCRIPTION_CODES,

    /** A person's second citizenship, which an earlier version didn't keep. */
    CITIZENSHIPS,

    /** Labels capture learned that hold a name, an address or a plate of the household. */
    LEARNED_LABELS,

    /** Labour lines an earlier version kept as parts of a visit. */
    LABOUR,

    /** Records whose section was deleted on another device. */
    LOST_RECORDS,
}

/** What applying one finding says on its button, as the iOS steps' `applyTitle`. */
enum class ApplyVerb {
    /** "Corectează": every correction's. */
    CORRECT,

    /** "Mută": a suggestion that files a section under the household's home. */
    MOVE,

    /** "Uită eticheta": forget a label capture learned. */
    FORGET_LABEL,

    /** "Păstrează": keep a record whose section was deleted on another device. */
    KEEP,
}

/** One thing a repair would change, with what applying it needs and what the list says of it. */
data class DataRepairFinding(
    /** `<step>:<record>:<value>`: the same finding keeps its id; a new value makes a new one. */
    val id: String,
    val step: DataRepairStepId,
    /** What it is about: what applying it needs, and the data the app words it from. */
    val subject: DataRepairSubject,
    /**
     * The repair can make the change. When false the finding only says what the person can do (check
     * a day on the paper), and "Am înțeles" puts it away.
     */
    val isFixable: Boolean = true,
) {
    companion object {
        /** A finding's id from its step and parts, as the iOS app builds them (ids in capitals). */
        fun id(step: DataRepairStepId, vararg parts: String): String = (listOf(step.raw) + parts).joinToString(":")
    }
}

/** A step of the registry, as the iOS app's `DataRepairStep`. */
interface DataRepairStep {
    val id: DataRepairStepId

    /** What a group of its findings is called in the list. */
    val group: DataRepairGroup

    /**
     * Its findings are suggestions, not corrections: nothing was saved wrongly, the app can now do
     * better with what is there. A suggestion is never in the repair list and never announced by its
     * prompt; it waits as one calm note (`AttentionModel.suggestionNote`).
     */
    val isSuggestion: Boolean get() = false

    /** What applying one of its findings says on its button. */
    val applyVerb: ApplyVerb get() = ApplyVerb.CORRECT

    /** Changes only how something is stored, never what it says: runs without asking. */
    val runsByItself: Boolean get() = false

    /** Makes the change that runs without asking, in [step]; how many records changed. */
    fun runByItself(step: Step, context: DataRepairContext): Int = 0

    /** What it would change, in the binder as [scan] reads it. */
    fun findings(scan: DataRepairScan): List<DataRepairFinding> = emptyList()

    /**
     * Applies approved findings in [step], which the registry's unit saves. Checks each one again
     * first, so a finding that no longer holds changes nothing.
     */
    fun apply(findings: List<DataRepairFinding>, step: Step, context: DataRepairContext) = Unit
}

/** What every step reads beside the binder: the app's days, its clock, its catalog and this phone's locks. */
class DataRepairContext(
    val zone: ZoneId,
    val now: Instant,
    val builtIns: BuiltIns,
    val locks: DeviceLocks,
)

/**
 * What one detection pass reads, and what it knows so far, so a later step doesn't offer a second
 * repair for what an earlier one already covers (a reading corrected doesn't also fix its hero value).
 */
class DataRepairScan(
    /** The binder as stored, read in one transaction. */
    val view: BinderView,
    val context: DataRepairContext,
) {
    /** Readings an earlier step already offers to correct, by id. */
    val flaggedReadings: MutableSet<String> = mutableSetOf()

    /** Sections an earlier step already offers to correct, by id. */
    val flaggedAssets: MutableSet<String> = mutableSetOf()
}
