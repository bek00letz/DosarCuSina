package com.ar.dosarcusina.store.repairs

/**
 * A step of the iOS registry whose rule needs what this app doesn't have yet (a later phase's
 * engines and actions, or the categories of one's own): it holds its place, its id, its group and
 * how it runs, and finds nothing until it is ported. Never half a rule: a step either finds and
 * applies what the iOS step does, or waits here, saying on what ([waitsFor]).
 */
class WaitingStep internal constructor(
    override val id: DataRepairStepId,
    override val group: DataRepairGroup,
    /** What its port needs first, for whoever ports it. */
    val waitsFor: String,
    override val runsByItself: Boolean = false,
    override val isSuggestion: Boolean = false,
    override val applyVerb: ApplyVerb = ApplyVerb.CORRECT,
) : DataRepairStep

/** The steps that wait, each as the iOS app declares it. */
object WaitingSteps {
    private const val CAPTURE_REPAIRS = "CaptureRepairs and the document and visit actions (Phase 3)"
    private const val READINGS = "ReadingSeries and HouseholdMutations' readings (Phase 3)"
    private const val POLICIES = "the policy facts (BlueprintFacts, DeadlineFacts) and ObligationActions (Phase 3)"
    private const val PAPERS = "PaperIdentity and the history actions (Phase 3)"
    private const val OWN_CATEGORIES = "CategorySwitches and TemplateStore's categories of one's own"

    val staleDocumentLinks = WaitingStep(
        DataRepairStepId.STALE_DOCUMENT_LINKS, DataRepairGroup.MOVED_DOCUMENTS, CAPTURE_REPAIRS,
    )
    val visitsWithoutInvoice = WaitingStep(
        DataRepairStepId.VISITS_WITHOUT_INVOICE, DataRepairGroup.VISITS_WITHOUT_INVOICE, CAPTURE_REPAIRS,
    )
    val duplicateProviders = WaitingStep(
        DataRepairStepId.DUPLICATE_PROVIDERS, DataRepairGroup.FIRMS_KEPT_TWICE,
        "CaptureRepairs' firms and ProviderActions (Phase 3)",
    )
    val doubleCompletions = WaitingStep(
        DataRepairStepId.DOUBLE_COMPLETIONS, DataRepairGroup.DEADLINES_CLOSED_TWICE,
        "LikelyDoubleCompletions, RecurrenceEngine and ObligationActions (Phase 3)",
    )
    val counterOutliers = WaitingStep(DataRepairStepId.COUNTER_OUTLIERS, DataRepairGroup.COUNTERS, READINGS)
    val estimatedVisitReadings = WaitingStep(
        DataRepairStepId.ESTIMATED_VISIT_READINGS, DataRepairGroup.ESTIMATES_KEPT_AS_READINGS, READINGS,
    )
    val heroFromReadings = WaitingStep(DataRepairStepId.HERO_FROM_READINGS, DataRepairGroup.COUNTERS, READINGS)
    val cascoInRcaFields = WaitingStep(DataRepairStepId.CASCO_IN_RCA_FIELDS, DataRepairGroup.CASCO_IN_RCA, POLICIES)
    val homePolicyWithoutDeadline = WaitingStep(
        DataRepairStepId.HOME_POLICY_WITHOUT_DEADLINE, DataRepairGroup.POLICIES_WITHOUT_DEADLINE, POLICIES,
    )
    val travelCutoff = WaitingStep(
        DataRepairStepId.TRAVEL_CUTOFF, DataRepairGroup.PASSPORTS_AND_TRAVEL,
        "DeadlineReminders, ReminderProfile's urgency rule and DocumentType.travelMargins (Phase 3)",
    )
    val homePolicySets = WaitingStep(DataRepairStepId.HOME_POLICY_SETS, DataRepairGroup.HOME_POLICIES, POLICIES)
    val policyNumberParts = WaitingStep(
        DataRepairStepId.POLICY_NUMBER_PARTS, DataRepairGroup.POLICY_NUMBERS,
        "CompositeValue and capture's policy reader (Phase 3)",
    )
    val billNumbers = WaitingStep(
        DataRepairStepId.BILL_NUMBERS, DataRepairGroup.BILL_NUMBERS,
        "capture's bill reader (BillReader, Phase 3)", runsByItself = true,
    )
    val sameBillTwice = WaitingStep(DataRepairStepId.SAME_BILL_TWICE, DataRepairGroup.BILLS_LOGGED_TWICE, PAPERS)
    val sameVisitTwice = WaitingStep(DataRepairStepId.SAME_VISIT_TWICE, DataRepairGroup.VISITS_LOGGED_TWICE, PAPERS)
    val estimatedBillReadings = WaitingStep(
        DataRepairStepId.ESTIMATED_BILL_READINGS, DataRepairGroup.ESTIMATED_INDEXES,
        "ReadingSeries and capture's bill reading cues (Phase 3)",
    )
    val sectionsIntoTheirHome = WaitingStep(
        DataRepairStepId.SECTIONS_INTO_THEIR_HOME, DataRepairGroup.BELONGS_TO_ANOTHER_SECTION,
        "AssetActions.automaticParent and AssetActions.move (Phase 3)",
        isSuggestion = true, applyVerb = ApplyVerb.MOVE,
    )
    val ownCategoryBoxes = WaitingStep(
        DataRepairStepId.OWN_CATEGORY_BOXES, DataRepairGroup.OWN_CATEGORY_BOXES,
        "$OWN_CATEGORIES (TemplateStore.takeBoxAsGrouping)", runsByItself = true,
    )
    val ownCategoryVisits = WaitingStep(
        DataRepairStepId.OWN_CATEGORY_VISITS, DataRepairGroup.OWN_CATEGORY_VISITS,
        "$OWN_CATEGORIES (CategorySwitches.visit(for:))", runsByItself = true,
    )
    val serviceNotes = WaitingStep(
        DataRepairStepId.SERVICE_NOTES, DataRepairGroup.SERVICES,
        "$OWN_CATEGORIES (CategorySwitches.isServiceBlueprint)",
    )
    val renewalRepeats = WaitingStep(
        DataRepairStepId.RENEWAL_REPEATS, DataRepairGroup.RENEWED_DOCUMENTS,
        "CompletionKind and CompletionShape.replacesDocument (Phase 3)",
    )
    val subscriptionCodes = WaitingStep(
        DataRepairStepId.SUBSCRIPTION_CODES, DataRepairGroup.SUBSCRIPTION_CODES,
        "ServiceKind, SubscriptionCode and ContractReader (Phase 3)",
    )
    val citizenships = WaitingStep(
        DataRepairStepId.CITIZENSHIPS, DataRepairGroup.CITIZENSHIPS,
        "Citizenship (reading one off a document, keeping them on the person; Phase 3)",
    )
    val labourParts = WaitingStep(
        DataRepairStepId.LABOUR_PARTS, DataRepairGroup.LABOUR,
        "LabourLine and CaptureLexicon.labourWords (Phase 3)",
    )
    val lostRecords = WaitingStep(
        DataRepairStepId.LOST_RECORDS, DataRepairGroup.LOST_RECORDS,
        "TemplateStore.createCustom (the categories of one's own) and AssetActions.create (Phase 3)",
        applyVerb = ApplyVerb.KEEP,
    )
}
