package com.ar.dosarcusina.store.obligations

import com.ar.dosarcusina.core.deadlines.defaultProfile
import com.ar.dosarcusina.core.values.ObligationKind
import com.ar.dosarcusina.archive.v3.RecurrenceRule
import com.ar.dosarcusina.archive.v3.ReminderProfile
import com.ar.dosarcusina.core.values.CalendarDay
import com.ar.dosarcusina.store.BinderView
import com.ar.dosarcusina.store.schema.Obligation
import com.ar.dosarcusina.store.schema.reminders
import java.time.ZoneId

/**
 * What a deadline of the person's own is, from two plain answers, as the iOS app's `DeadlineChoice`
 * (ios/DosarCuSina/Views/Add/DeadlineChoice.swift): how important it is gives its kind, and the kind its
 * reminders. The words of each answer are Phase 4's.
 */
object DeadlineChoice {
    /** How important a deadline of one's own is („Cât de important e”), and the kind each answer gives. */
    enum class Importance(val raw: String, val kind: ObligationKind) {
        LEGAL("legal", ObligationKind.LEGAL),
        MONEY("money", ObligationKind.PAYMENT),
        HEALTH("health", ObligationKind.HEALTH),
        REMINDER("reminder", ObligationKind.ROUTINE),
        ;

        companion object {
            /**
             * The answer a deadline's kind is, for the four kinds the answers give; null for any other (a
             * deadline from an older backup with no category's blueprint), whose kind „Editează” then leaves
             * as it is.
             */
            fun of(kind: ObligationKind): Importance? = entries.firstOrNull { it.kind == kind }
        }
    }

    /** The reminders a deadline of [importance] gets: its kind's default profile. */
    fun reminders(importance: Importance): ReminderProfile = ReminderProfile.of(importance.kind.defaultProfile)

    /**
     * A deadline's reminders once its importance moves it from kind [from] to [to]: what the person can't
     * set (how serious it is, how many days late is still calm) is the new kind's; the leads and the
     * follow-up the new kind's only while they are still the old kind's own, else the person's, as they
     * set them. The travel margin stays. The one rule, for `ObligationActions.setImportance` and for the
     * edit sheet while it is open.
     */
    fun reminders(profile: ReminderProfile, from: ObligationKind, to: ObligationKind): ReminderProfile {
        if (from == to) return profile
        val was = from.defaultProfile
        val becomes = to.defaultProfile
        val isTheKinds = profile.leadDays == was.leadDays && profile.followUpAfterLapse == was.followUpAfterLapse
        return ReminderProfile(
            leadDays = if (isTheKinds) becomes.leadDays else profile.leadDays,
            consequence = becomes.consequence.stored,
            graceDays = becomes.graceDays,
            followUpAfterLapse = if (isTheKinds) becomes.followUpAfterLapse else profile.followUpAfterLapse,
            travelMarginDays = profile.travelMarginDays,
        )
    }
}

/**
 * What „Editează” on a deadline's page edits, as one value, as the iOS app's `DeadlineEdit`
 * (ios/DosarCuSina/Services/Obligations/DeadlineEdit.swift): its name and how important it is (only a
 * deadline of the person's own, [isPersonsOwn]), its due day, how it repeats, its reminders and its
 * reminder time. The sheet keeps the one it opened with and the one the person leaves;
 * `ObligationActions.edit` saves the difference as one undoable step.
 */
data class DeadlineEdit(
    val title: String,
    /** How important it is, offered only for a deadline of the person's own whose kind is one of the answers. */
    val importance: DeadlineChoice.Importance?,
    val dueDay: CalendarDay,
    val recurrence: RecurrenceRule,
    /** Its leads and follow-up, as the person sets them; the rest of the profile as stored. */
    val reminders: ReminderProfile,
    /** Its own reminder time, null for the general one from Settings. */
    val reminderMinuteOfDay: Int?,
    /** Whether its name and importance are the person's to change. */
    val isPersonsOwn: Boolean,
    /**
     * Whether closing it replaces a document with a new one, so it closes when done, whatever a repeat
     * would say, and the new document reminds of its own.
     */
    val closesWhenDone: Boolean = false,
) {
    /** Whether the sheet offers „Cât de important e”. */
    val offersImportance: Boolean get() = importance != null && isPersonsOwn

    /**
     * Whether „Se repetă” is offered: a rule of every so many days, weeks, months or years, or none
     * (`RepeatChoice`). A rule on fixed dates, by a counter or by law is its category's, and a deadline
     * that closes when done has no repeat to choose.
     */
    val offersRepeat: Boolean
        get() = !closesWhenDone && (recurrence == RecurrenceRule.None || recurrence is RecurrenceRule.Interval)

    /** A new importance, with the reminders moved by the one rule, so the sheet shows what saving will keep. */
    fun choosing(answer: DeadlineChoice.Importance): DeadlineEdit {
        val current = importance?.takeIf { isPersonsOwn } ?: return this
        if (current == answer) return this
        return copy(importance = answer, reminders = DeadlineChoice.reminders(reminders, current.kind, answer.kind))
    }

    /** It has a name. */
    val canSave: Boolean get() = title.isNotBlank()

    /**
     * Whether, against [start] (the deadline as the sheet opened with it), this edit adds or changes what
     * reminds: its leads, its follow-up, its reminder time.
     */
    fun changesReminders(start: DeadlineEdit): Boolean =
        reminders != start.reminders || reminderMinuteOfDay != start.reminderMinuteOfDay

    companion object {
        /** The deadline as it is now in [view]: what the sheet opens with. */
        fun of(view: BinderView, obligation: Obligation, zone: ZoneId): DeadlineEdit {
            val own = obligation.isPersonsOwn
            return DeadlineEdit(
                title = obligation.title,
                importance = if (own) DeadlineChoice.Importance.of(obligation.kind) else null,
                dueDay = obligation.dueDay(zone),
                recurrence = obligation.recurrence,
                reminders = obligation.reminders,
                reminderMinuteOfDay = obligation.reminderMinuteOfDay,
                isPersonsOwn = own,
                closesWhenDone = DeadlineCategory.completionKind(view, obligation).shape.replacesDocument,
            )
        }
    }
}
