package com.ar.dosarcusina.catalog

import com.ar.dosarcusina.archive.v3.FieldValue
import com.ar.dosarcusina.archive.v3.FieldValues
import com.ar.dosarcusina.archive.v3.ObligationBlueprint
import com.ar.dosarcusina.archive.v3.RecurrenceRule
import com.ar.dosarcusina.archive.v3.ReminderProfile
import com.ar.dosarcusina.core.deadlines.CompletionKind
import com.ar.dosarcusina.core.deadlines.ObligationKind
import com.ar.dosarcusina.core.urgency.Consequence
import com.ar.dosarcusina.core.values.CalendarDay
import com.ar.dosarcusina.core.values.Money
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive

// A category's usual deadline as the rules read it, over the archive's stored form
// (`ObligationBlueprint`, ios/DosarCuSina/Models/Obligations/ObligationTypes.swift and
// DueDayValidity.swift): its kind, how it completes, how it repeats, the reminders it gives a
// section's values, whether it is worth making on a day, and the facts it names.

/** What kind of duty it is; a kind a newer build wrote reads as the loudest. */
val ObligationBlueprint.obligationKind: ObligationKind get() = ObligationKind.stored(kind)

/**
 * What closing it asks: what it states, else (a blueprint written before blueprints stated one, or a
 * kind a newer build wrote) what a deadline of one's own of its kind asks ([CompletionKind.own]).
 */
val ObligationBlueprint.completionKind: CompletionKind
    get() = CompletionKind.stored(completion) ?: CompletionKind.own(obligationKind)

/** How it repeats; none when it doesn't say. */
val ObligationBlueprint.recurrenceRule: RecurrenceRule
    get() = recurrence?.let(RecurrenceRule.codec::decode) ?: RecurrenceRule.None

/** How it reminds by default: what it says, else its kind's own ([ObligationKind.defaultProfile]). */
val ObligationBlueprint.defaultReminders: ReminderProfile
    get() = reminders?.let(ReminderProfile.codec::decode) ?: ReminderProfile.of(obligationKind.defaultProfile)

/**
 * How it reminds for a section with [values], taking its variants into account: a passport three
 * months before its travel cut-off, an identity card 90 and 30 days before it expires
 * (`reminders(for:)`). A variant this build can't read reminds as the blueprint does.
 */
fun ObligationBlueprint.remindersFor(values: FieldValues): ReminderProfile {
    val variants = reminderVariants as? JsonObject ?: return defaultReminders
    val field = (variants["field"] as? JsonPrimitive)?.takeIf { it.isString }?.content ?: return defaultReminders
    val value = (values[field] as? FieldValue.Text)?.value ?: return defaultReminders
    val profile = (variants["variants"] as? JsonObject)?.get(value) ?: return defaultReminders
    return ReminderProfile.codec.decode(profile) ?: defaultReminders
}

/** Its day comes from a field of the section (a document's expiry), not from itself. */
val ObligationBlueprint.isFieldDriven: Boolean get() = drivingField != null

/** The field it takes its day from, when it is field-driven. */
val ObligationBlueprint.drivingField: String?
    get() {
        val rule = firstDue as? JsonObject ?: return null
        if ((rule["type"] as? JsonPrimitive)?.content != "field") return null
        return (rule["field"] as? JsonPrimitive)?.takeIf { it.isString }?.content
    }

/**
 * Whether a deadline from this blueprint is worth making on [day]: a day still ahead, or one that
 * passed for something that must be renewed by law (an identity card that expired still needs
 * renewing). A warranty, a minimum period, a bill, a bank card or a cazier that passed is only
 * history. What the law asks is the profile the section's [values] give ([remindersFor]: a
 * document's type). Capture's filing plan and a section's edits both ask this.
 */
fun ObligationBlueprint.isWorthScheduling(
    day: CalendarDay,
    today: CalendarDay,
    values: FieldValues = FieldValues(),
): Boolean {
    if (day >= today) return true
    return obligationKind == ObligationKind.RENEWAL &&
        Consequence.stored(remindersFor(values).consequence) == Consequence.LEGAL
}

/** The section's fields that hold its facts (a policy's insurer, number and claims phone); none when it names none. */
val ObligationBlueprint.factFields: BlueprintFacts? get() = facts?.let(BlueprintFacts::read)

/**
 * A fact a deadline needs at hand, by what it is for, not by how its field is called, as the iOS app's
 * `BlueprintFactRole`. [raw] is part of the `.dosar` contract.
 */
enum class BlueprintFactRole(val raw: String) {
    /** Who issued the policy. */
    INSURER("insurer"),
    POLICY_NUMBER("policyNumber"),

    /** The line to call for a claim or assistance. */
    CLAIMS_PHONE("claimsPhone"),

    /** Who the policy insures, as a household member's name. */
    POLICYHOLDER("policyholder"),

    /** The sum the policy insures for (suma asigurată), as money. */
    INSURED_SUM("insuredSum"),
    ;

    /**
     * Whether the fact describes one policy paper and no other: its number and the sum it insures for.
     * A newer policy that doesn't print it leaves it empty, so the earlier policy's never passes for the
     * newer one's. Who issued it, its claims line and who it insures carry over a renewal.
     */
    val belongsToThePolicy: Boolean get() = this == POLICY_NUMBER || this == INSURED_SUM
}

/**
 * Which of the section's fields hold the facts one deadline needs, as the iOS app's `BlueprintFacts`: a
 * car's CASCO keeps its own insurer, policy number, claims phone and insured sum, apart from its RCA.
 * Every reader of a deadline's facts goes through these roles, never by guessing from field names.
 */
data class BlueprintFacts(val fields: Map<BlueprintFactRole, String>) {
    /** The field that holds [role], if the deadline names one. */
    fun field(role: BlueprintFactRole): String? = fields[role]

    companion object {
        /** The facts a blueprint names, as stored (`{"insurer": "vehicle.insurer", …}`); none when unreadable. */
        fun read(json: JsonElement): BlueprintFacts? {
            val record = json as? JsonObject ?: return null
            val fields = LinkedHashMap<BlueprintFactRole, String>()
            for (role in BlueprintFactRole.entries) {
                val value = record[role.raw] ?: continue
                val text = (value as? JsonPrimitive)?.takeIf { it.isString }?.content
                if (text != null) fields[role] = text else if (value !is JsonNull) return null
            }
            return BlueprintFacts(fields)
        }
    }
}

/**
 * The facts a deadline's page puts at hand, as the iOS app's `DeadlineFacts`
 * (ios/DosarCuSina/Services/Obligations/DeadlineFacts.swift): its own insurer, policy number, claims
 * phone and insured sum, read through its blueprint's fact roles. A car's CASCO page shows the CASCO
 * policy, never the RCA's, and a deadline whose blueprint names no facts shows none but its own
 * reference.
 */
data class DeadlineFacts(
    val insurer: String? = null,
    val policyNumber: String? = null,
    val claimsPhone: String? = null,
    /** Who the policy insures, as a household member's name. */
    val policyholder: String? = null,
    /** The sum the policy insures for (a home's PAD and optional policy, a car's CASCO). */
    val insuredSum: Money? = null,
) {
    companion object {
        /**
         * The facts of the deadline made from [blueprintKey], read from the section's [values] with the
         * roles of its category's [blueprints]. The deadline's own [reference] (a policy number typed on
         * it) wins over the section's field.
         */
        fun of(
            blueprintKey: String?,
            blueprints: List<ObligationBlueprint>,
            values: FieldValues,
            reference: String?,
        ): DeadlineFacts {
            val facts = blueprintKey?.let { key -> blueprints.firstOrNull { it.key == key } }?.factFields
            fun value(role: BlueprintFactRole): String? =
                facts?.field(role)?.let { (values[it] as? FieldValue.Text)?.value }?.takeIf { it.isNotEmpty() }
            val own = reference?.takeIf { it.isNotBlank() }
            val sum = facts?.field(BlueprintFactRole.INSURED_SUM)?.let { (values[it] as? FieldValue.Amount)?.value }
                ?.takeIf { it.amount.signum() > 0 }
            return DeadlineFacts(
                insurer = value(BlueprintFactRole.INSURER),
                policyNumber = own ?: value(BlueprintFactRole.POLICY_NUMBER),
                claimsPhone = value(BlueprintFactRole.CLAIMS_PHONE),
                policyholder = value(BlueprintFactRole.POLICYHOLDER),
                insuredSum = sum,
            )
        }
    }
}
