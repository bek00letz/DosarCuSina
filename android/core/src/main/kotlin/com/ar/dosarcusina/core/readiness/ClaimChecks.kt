package com.ar.dosarcusina.core.readiness

import com.ar.dosarcusina.core.readiness.BinderReading.Companion.isSpaces
import com.ar.dosarcusina.core.readiness.BinderReading.Companion.notInBinder
import com.ar.dosarcusina.core.readiness.BinderReading.Companion.openDeadline
import com.ar.dosarcusina.core.readiness.BinderReading.Companion.openSection
import com.ar.dosarcusina.core.readiness.BinderReading.Companion.reminder
import com.ar.dosarcusina.core.urgency.DueDayValidity
import com.ar.dosarcusina.core.values.CalendarDay

/**
 * „Ai avut o daună”: the right policy's number and phone, what to photograph, the papers, as the
 * iOS engine's claim.
 */
internal class ClaimChecks(private val reading: BinderReading, private val policyholders: PolicyholderClasses) {
    private val keys get() = reading.keys

    /** When a policy is the one to call, by its deadline. A policy of the person's own has none. */
    private fun whenToUse(blueprintKey: String): ReadinessWords? = when (blueprintKey) {
        keys.vehicleRCA -> ReadinessPhrase.WhenRCA()
        keys.vehicleCASCO -> ReadinessPhrase.WhenCASCO()
        keys.homePAD -> ReadinessPhrase.WhenPAD()
        keys.homeInsurance -> ReadinessPhrase.WhenHomeInsurance()
        else -> null
    }

    /**
     * The policies a claim on [asset] can go to: those the binder follows or knows a fact of, or
     * every policy of its category when it knows none. Each reads its own facts.
     */
    private fun policies(asset: ReadinessAsset, assets: List<ReadinessAsset>): List<ReadinessPolicy> {
        val all = asset.facts.map { entry ->
            fun value(role: String): String? =
                entry.fields[role]?.let { asset.values.text(it) }?.takeUnless { isSpaces(it) }
            val deadline = asset.obligations[entry.blueprintKey]
            ReadinessPolicy(
                blueprintKey = entry.blueprintKey,
                title = entry.title,
                whenToUse = whenToUse(entry.blueprintKey),
                insurer = value(keys.insurer),
                policyNumber = deadline?.reference?.takeUnless { isSpaces(it) } ?: value(keys.policyNumber),
                claimsPhone = value(keys.claimsPhone),
                deadlineID = deadline?.id,
                validUntil = deadline?.due,
                policyholderClass = policyholders.of(value(keys.policyholder), assets),
            )
        }
        val known = all.filter {
            it.deadlineID != null || it.insurer != null || it.policyNumber != null || it.claimsPhone != null
        }
        return known.ifEmpty { all }
    }

    /** The policy a claim is about: the one asked for, else the first followed, else the first known. */
    private fun policy(options: List<ReadinessPolicy>, blueprintKey: String?): ReadinessPolicy? =
        blueprintKey?.let { key -> options.firstOrNull { it.blueprintKey == key } }
            ?: options.firstOrNull { it.deadlineID != null }
            ?: options.firstOrNull()

    fun checklist(
        asset: ReadinessAsset,
        blueprintKey: String?,
        today: CalendarDay,
        assets: List<ReadinessAsset>,
    ): ReadinessChecklist {
        val options = policies(asset, assets)
        val policy = policy(options, blueprintKey)
        val hasPolicy = keys.policy in asset.documentKinds
        val document = ReadinessItem(
            "claim.policyDocument",
            if (hasPolicy) ReadinessStatus.OK else ReadinessStatus.MISSING,
            ReadinessNeed.OPTIONAL,
            ReadinessPhrase.PolicyDocumentTitle(),
            if (hasPolicy) ReadinessPhrase.PolicyFiled() else ReadinessPhrase.PolicyPhotoMissing(),
            if (hasPolicy) openSection(asset.id) else ReadinessAction.AddDocument(asset.id),
        )
        val policyItems = policy?.let { policyChecks(it, asset, today) }.orEmpty() + document
        val (photos, papers) = if (reading.isVehicle(asset)) carReminders() else homeReminders()
        val groups = listOf(
            ReadinessGroup("claim.policy", ReadinessPhrase.ClaimPolicyGroup(), "doc.text.fill", policyItems),
            ReadinessGroup("claim.photos", ReadinessPhrase.ClaimPhotosGroup(), "camera.fill", photos),
            ReadinessGroup("claim.papers", ReadinessPhrase.ClaimPapersGroup(), "folder.fill", papers),
        )
        return ReadinessChecklist(groups, policy, options)
    }

    private fun policyChecks(policy: ReadinessPolicy, asset: ReadinessAsset, today: CalendarDay): List<ReadinessItem> {
        val number = ReadinessItem(
            "claim.policyNumber", ReadinessStatus.MISSING, title = ReadinessPhrase.PolicyNumberTitle(),
            detail = ReadinessPhrase.PolicyNumberMissing(), action = ReadinessAction.EditSection(asset.id),
        ).takeIf { policy.policyNumber == null }
        val phone = ReadinessItem(
            "claim.phone", ReadinessStatus.MISSING, title = ReadinessPhrase.ClaimsPhoneTitle(),
            detail = ReadinessPhrase.ClaimsPhoneMissing(), action = ReadinessAction.EditSection(asset.id),
        ).takeIf { policy.claimsPhone == null }
        val id = policy.deadlineID
        val until = policy.validUntil
        val validity = if (id != null && until != null) {
            val valid = DueDayValidity.isValid(until, today)
            ReadinessItem(
                "claim.validity",
                if (valid) ReadinessStatus.OK else ReadinessStatus.PROBLEM,
                title = ReadinessPhrase.PolicyValidityTitle(),
                detail = if (valid) ReadinessPhrase.ValidUntilFeminine(until) else ReadinessPhrase.PolicyExpired(until),
                action = openDeadline(id),
            )
        } else {
            notInBinder(
                "claim.validity",
                ReadinessPhrase.PolicyValidityTitle(),
                ReadinessPhrase.PolicyValidityUnknown(),
                asset,
                policy.blueprintKey,
            )
        }
        return listOfNotNull(number, phone, validity)
    }

    private fun carReminders(): Pair<List<ReadinessItem>, List<ReadinessItem>> = listOf(
        reminder("claim.photo.cars", ReadinessPhrase.PhotoCarsTitle, ReadinessPhrase.PhotoCarsDetail),
        reminder("claim.photo.damage", ReadinessPhrase.PhotoDamageTitle, ReadinessPhrase.PhotoDamageDetail),
        reminder("claim.photo.place", ReadinessPhrase.PhotoPlaceTitle, ReadinessPhrase.PhotoPlaceDetail),
        reminder(
            "claim.photo.otherDriver", ReadinessPhrase.PhotoOtherDriverTitle, ReadinessPhrase.PhotoOtherDriverDetail,
        ),
        reminder("claim.photo.report", ReadinessPhrase.PhotoReportTitle, ReadinessPhrase.PhotoReportDetail),
    ) to listOf(
        reminder("claim.paper.driver", ReadinessPhrase.PaperDriverTitle, ReadinessPhrase.PaperDriverDetail),
        reminder("claim.paper.car", ReadinessPhrase.PaperCarTitle, ReadinessPhrase.PaperCarDetail),
        reminder("claim.paper.report", ReadinessPhrase.PaperReportTitle, ReadinessPhrase.PaperReportDetail),
    )

    private fun homeReminders(): Pair<List<ReadinessItem>, List<ReadinessItem>> = listOf(
        reminder("claim.photo.rooms", ReadinessPhrase.PhotoRoomsTitle, ReadinessPhrase.PhotoRoomsDetail),
        reminder("claim.photo.source", ReadinessPhrase.PhotoSourceTitle, ReadinessPhrase.PhotoSourceDetail),
        reminder("claim.photo.goods", ReadinessPhrase.PhotoGoodsTitle, ReadinessPhrase.PhotoGoodsDetail),
    ) to listOf(
        reminder("claim.paper.id", ReadinessPhrase.PaperIDTitle, ReadinessPhrase.PaperIDDetail),
        reminder("claim.paper.deed", ReadinessPhrase.PaperDeedTitle, ReadinessPhrase.PaperDeedDetail),
        reminder(
            "claim.paper.report", ReadinessPhrase.PaperOfficialReportTitle, ReadinessPhrase.PaperOfficialReportDetail,
        ),
    )
}
