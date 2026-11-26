package com.ar.dosarcusina.core.reminders

import com.ar.dosarcusina.core.reminders.ReminderPlanner.IDENTIFIER_PREFIX
import com.ar.dosarcusina.core.reminders.ReminderPlanner.LAPSE_SUFFIX
import com.ar.dosarcusina.core.urgency.ReminderLead
import com.ar.dosarcusina.core.values.CalendarDay
import com.ar.dosarcusina.core.values.TextRules
import java.util.UUID
import kotlin.math.abs

/**
 * A reminder's identifier, made and read back, as the iOS app's `ReminderPlanner.identifier`,
 * `obligationId(fromIdentifier:)` and `cycle(fromIdentifier:deliveredOn:)`.
 */
object ReminderIdentifiers {
    /** The prefix of a lead's suffix: `d` before the due day. */
    const val DUE_LEAD: String = "d"

    /** The prefix of a lead's suffix before a travel cut-off: never read back as a due day. */
    const val TRAVEL_LEAD: String = "t"

    /** The identifier of a reminder of [obligationId]: `obligation.<id>.<suffix>`. */
    fun make(obligationId: UUID, suffix: String): String = "$IDENTIFIER_PREFIX$obligationId.$suffix"

    /** The deadline a reminder's identifier belongs to; null for one that names none. */
    fun obligationId(identifier: String): UUID? {
        if (!identifier.startsWith(IDENTIFIER_PREFIX)) return null
        val first = identifier.removePrefix(IDENTIFIER_PREFIX).split('.').firstOrNull { it.isNotEmpty() } ?: return null
        return Uuids.parse(first)
    }

    /**
     * The cycle a reminder delivered on [deliveredOn] was about, for reminders scheduled before
     * they carried it: a lead's `d<n>` is about the day `n` days later, the follow-up about the
     * day before. Null when it can't be told (a snooze, a travel lead), so a button on it
     * changes nothing.
     */
    fun cycle(identifier: String, deliveredOn: CalendarDay): CalendarDay? {
        if (obligationId(identifier) == null) return null
        val suffix = identifier.split('.').lastOrNull { it.isNotEmpty() } ?: return null
        if (suffix == LAPSE_SUFFIX) return deliveredOn.addingDays(-1)
        if (!suffix.startsWith(DUE_LEAD)) return null
        // A lead's days the app writes are at most a hundred years; nothing it reads is further.
        val days = TextRules.swiftInt(suffix.drop(1))?.takeIf { abs(it) <= ReminderLead.LONGEST_DAYS } ?: return null
        return deliveredOn.addingDays(days.toInt())
    }
}

/** A UUID read as the iPhone reads one: 8-4-4-4-12 hexadecimal digits, in either case. */
internal object Uuids {
    private val SHAPE = Regex("[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}")

    fun parse(text: String): UUID? = if (SHAPE.matches(text)) UUID.fromString(text) else null
}
