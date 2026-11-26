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
    private const val POLICIES = "capture's reading of a policy's cover (InsuranceCover.read, capture, Phase 5)"

    val cascoInRcaFields = WaitingStep(DataRepairStepId.CASCO_IN_RCA_FIELDS, DataRepairGroup.CASCO_IN_RCA, POLICIES)
    val homePolicyWithoutDeadline = WaitingStep(
        DataRepairStepId.HOME_POLICY_WITHOUT_DEADLINE, DataRepairGroup.POLICIES_WITHOUT_DEADLINE,
        "capture's reading of a policy's cover and its end (InsuranceCover.read and CaptureAnalyzer, Phase 5)",
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
    val sameBillTwice = WaitingStep(
        DataRepairStepId.SAME_BILL_TWICE, DataRepairGroup.BILLS_LOGGED_TWICE,
        "a bill as capture files it (CaptureFiler.logBill and finishBill: the meter reading its paper records " +
            "and its „Factura de plătit”, which the join keeps once; capture, Phase 5)",
    )
    val estimatedBillReadings = WaitingStep(
        DataRepairStepId.ESTIMATED_BILL_READINGS, DataRepairGroup.ESTIMATED_INDEXES,
        "capture's bill reader (BillReader: the bill's layout, its meter index and how it says the index " +
            "was taken) and SubscriptionMeter.number (capture, Phase 5)",
    )
    val subscriptionCodes = WaitingStep(
        DataRepairStepId.SUBSCRIPTION_CODES, DataRepairGroup.SUBSCRIPTION_CODES,
        "ServiceKind, SubscriptionCode and ContractReader (Phase 3)",
    )
    val citizenships = WaitingStep(
        DataRepairStepId.CITIZENSHIPS, DataRepairGroup.CITIZENSHIPS,
        "Citizenship (reading one off a document, keeping them on the person; Phase 3)",
    )
}
