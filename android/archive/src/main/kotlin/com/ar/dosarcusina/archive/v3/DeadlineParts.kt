package com.ar.dosarcusina.archive.v3

import com.ar.dosarcusina.core.values.JsonCodec
import com.ar.dosarcusina.core.values.MachineText
import com.ar.dosarcusina.core.values.MeasurementUnit
import com.ar.dosarcusina.core.values.MonthDay
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonPrimitive
import kotlin.math.abs

/**
 * When a deadline reminds, as the iOS app's `ReminderProfile`: `{"leadDays": [30, 7, 0],
 * "consequence": "legal", "graceDays": 0, "followUpAfterLapse": true}`, with `travelMarginDays`
 * only when it isn't 0. Every length is held to what the app counts with (none below zero, a
 * hundred years at most); a consequence a newer build wrote is kept as written.
 */
class ReminderProfile(
    leadDays: List<Int>,
    val consequence: String,
    graceDays: Int = 0,
    followUpAfterLapse: Boolean? = null,
    travelMarginDays: Int = 0,
) {
    /** Days before the due day, largest first, each once. */
    val leadDays: List<Int> = leadDays.map { bounded(abs(it.toLong())) }.distinct().sortedDescending()
    val graceDays: Int = bounded(graceDays.toLong())
    val followUpAfterLapse: Boolean = followUpAfterLapse ?: defaultFollowUp(consequence)
    val travelMarginDays: Int = bounded(travelMarginDays.toLong())

    fun toJson(): JsonElement = jsonObject {
        put("leadDays", JsonArray(leadDays.map { MachineText.number(it.toLong()) }))
        put("consequence", consequence)
        put("graceDays", graceDays)
        put("followUpAfterLapse", followUpAfterLapse)
        if (travelMarginDays > 0) put("travelMarginDays", travelMarginDays)
    }

    override fun equals(other: Any?): Boolean =
        other is ReminderProfile && other.leadDays == leadDays && other.consequence == consequence &&
            other.graceDays == graceDays && other.followUpAfterLapse == followUpAfterLapse &&
            other.travelMarginDays == travelMarginDays

    override fun hashCode(): Int = leadDays.hashCode() * 31 + consequence.hashCode()

    override fun toString(): String = toJson().toString()

    companion object {
        /** A hundred years: the longest length the app counts with (`ReminderLead.longestDays`). */
        const val LONGEST_DAYS = 36_500

        /** What a profile reminds with when it doesn't say (`leadDays` missing). */
        private val DEFAULT_LEADS = listOf(7, 0)

        fun bounded(days: Long): Int = days.coerceIn(0, LONGEST_DAYS.toLong()).toInt()

        /** Legal and financial consequences follow up the day after a lapse unless told otherwise. */
        fun defaultFollowUp(consequence: String): Boolean = consequence == "legal" || consequence == "financial"

        val codec: JsonCodec<ReminderProfile> = codec(
            read = { record ->
                ReminderProfile(
                    leadDays = record.element("leadDays")?.let { JsonRecord.list(it).map(JsonRecord::int) }
                        ?: DEFAULT_LEADS,
                    // A consequence that isn't given is the loudest (`Consequence(stored:)`).
                    consequence = record.stringOrNull("consequence") ?: "legal",
                    graceDays = record.intOrNull("graceDays") ?: 0,
                    followUpAfterLapse = record.boolOrNull("followUpAfterLapse"),
                    travelMarginDays = record.intOrNull("travelMarginDays") ?: 0,
                )
            },
            write = ReminderProfile::toJson,
        )
    }
}

/**
 * How a deadline repeats, as the iOS app's `RecurrenceRule` (shared/schemas/dosar-v3.md,
 * "Recurrence"). A rule this build can't read (a type, unit, anchor or legal rule from a newer
 * build) is [Unreadable], kept as written: it behaves as one-off.
 */
sealed interface RecurrenceRule {
    data object None : RecurrenceRule

    data class Interval(val every: Int, val unit: String, val anchor: String) : RecurrenceRule

    data class FixedDates(val dates: List<MonthDay>) : RecurrenceRule

    data class Metric(
        val every: Double,
        val unit: String,
        val fallbackEvery: Int?,
        val fallbackUnit: String?,
    ) : RecurrenceRule

    data class Legal(val rule: String) : RecurrenceRule

    data class Unreadable(val raw: JsonElement) : RecurrenceRule

    fun toJson(): JsonElement = when (this) {
        None -> jsonObject { put("type", "none") }
        is Interval -> jsonObject {
            put("type", "interval")
            put("every", every)
            put("unit", unit)
            put("anchor", anchor)
        }
        is FixedDates -> jsonObject {
            put("type", "fixedDates")
            putStrings("dates", dates.sorted().map(MonthDay::isoString))
        }
        is Metric -> jsonObject {
            put("type", "metric")
            put("every", every)
            put("unit", unit)
            if (fallbackEvery != null) {
                put("fallbackEvery", fallbackEvery)
                put("fallbackUnit", fallbackUnit)
            }
        }
        is Legal -> jsonObject {
            put("type", "legal")
            put("rule", rule)
        }
        is Unreadable -> raw
    }

    companion object {
        val UNITS = setOf("day", "week", "month", "year")
        val ANCHORS = setOf("dueDate", "completion")
        val LEGAL_RULES = setOf("vehicleITP")

        /** The most a counter's step can be (ten million): a step from outside is held to it. */
        const val LONGEST_METRIC_STEP = 10_000_000.0

        /** Reads every rule; one this build can't read is kept as [Unreadable]. */
        val codec: JsonCodec<RecurrenceRule> = object : JsonCodec<RecurrenceRule> {
            override fun decode(json: JsonElement): RecurrenceRule = try {
                read(JsonRecord.of(json)) ?: Unreadable(json)
            } catch (_: UnreadableRecord) {
                Unreadable(json)
            }

            override fun encode(value: RecurrenceRule): JsonElement = value.toJson()
        }

        private fun read(record: JsonRecord): RecurrenceRule? = when (record.string("type")) {
            "none" -> None
            "interval" -> {
                val unit = record.string("unit")
                val anchor = record.stringOrNull("anchor") ?: "dueDate"
                if (unit in UNITS && anchor in ANCHORS) Interval(record.int("every"), unit, anchor) else null
            }
            "fixedDates" -> FixedDates(record.list("dates").map {
                MonthDay.parse(JsonRecord.text(it)) ?: throw UnreadableRecord()
            })
            "metric" -> metric(record)
            "legal" -> record.string("rule").takeIf { it in LEGAL_RULES }?.let(::Legal)
            else -> null
        }

        private fun metric(record: JsonRecord): RecurrenceRule? {
            val fallbackEvery = record.intOrNull("fallbackEvery")
            val fallbackUnit = record.stringOrNull("fallbackUnit")
            if (fallbackEvery != null && fallbackUnit !in UNITS) return null
            val every = record.double("every").coerceIn(0.0, LONGEST_METRIC_STEP)
            val unit = MeasurementUnit.storedKey(record.string("unit"))
            return Metric(every, unit, fallbackEvery, fallbackUnit.takeIf { fallbackEvery != null })
        }
    }
}

/**
 * How a document's pages are shown (`framing`), as the iOS app's `DocumentFraming`:
 * `{"version": 1, "pages": [...]}`, one entry per page, each optional. The page files stay as
 * taken; this only says how to draw them.
 */
data class DocumentFraming(val version: Int = CURRENT_VERSION, val pages: List<PageFraming> = emptyList()) {
    /** Every page shown as it came: nothing to keep. */
    val isPlain: Boolean get() = pages.all(PageFraming::isPlain)

    companion object {
        const val CURRENT_VERSION = 1

        val codec: JsonCodec<DocumentFraming> = codec(
            read = { record ->
                DocumentFraming(
                    record.intOrNull("version") ?: CURRENT_VERSION,
                    record.element("pages")?.let { JsonRecord.list(it).map(PageFraming::read) }.orEmpty(),
                )
            },
            write = { framing ->
                jsonObject {
                    put("version", framing.version)
                    put("pages", JsonArray(framing.pages.map(PageFraming::toJson)))
                }
            },
        )
    }
}

/** One page's framing: the document's corners in the photo, the app's guesses and the person's choice. */
data class PageFraming(
    val crop: List<Pair<Double, Double>>? = null,
    val prefersWholePhoto: Boolean = false,
    val quarterTurns: Int = 0,
    val choiceQuarterTurns: Int? = null,
    val choiceShowsWholePhoto: Boolean? = null,
) {
    val isPlain: Boolean
        get() = crop == null && !prefersWholePhoto && quarterTurns == 0 && choiceQuarterTurns == null
            && choiceShowsWholePhoto == null

    fun toJson(): JsonElement = jsonObject {
        put("crop", crop?.let { corners -> JsonArray(corners.map(::point)) })
        put("prefersWholePhoto", prefersWholePhoto)
        put("quarterTurns", quarterTurns)
        if (choiceQuarterTurns != null || choiceShowsWholePhoto != null) {
            put("choice", jsonObject {
                put("quarterTurns", choiceQuarterTurns)
                put("showsWholePhoto", choiceShowsWholePhoto)
            })
        }
    }

    companion object {
        private const val CORNERS = 4
        private const val TURNS = 4

        private fun point(corner: Pair<Double, Double>): JsonElement = jsonObject {
            put("x", corner.first)
            put("y", corner.second)
        }

        /** A page as stored; keys it doesn't know, or none, read as the plain page. */
        fun read(json: JsonElement): PageFraming {
            val record = JsonRecord.of(json)
            val corners = record.element("crop")?.let { list ->
                JsonRecord.list(list).map { point -> JsonRecord.of(point).let { it.double("x") to it.double("y") } }
            }
            val choice = record.objOrNull("choice")?.let(::JsonRecord)
            return PageFraming(
                crop = corners?.takeIf { it.size == CORNERS },
                prefersWholePhoto = record.boolOrNull("prefersWholePhoto") ?: false,
                quarterTurns = ((record.intOrNull("quarterTurns") ?: 0) % TURNS + TURNS) % TURNS,
                choiceQuarterTurns = choice?.intOrNull("quarterTurns"),
                choiceShowsWholePhoto = choice?.boolOrNull("showsWholePhoto"),
            )
        }
    }
}

/** Identifiers as the archive writes them: UUIDs, read in any case and written in lowercase. */
object Ids {
    private val SHAPE = Regex("[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}")

    /** The UUID [text] is, in the one form Swift's `UUID(uuidString:)` takes; null otherwise. */
    fun parse(text: String): java.util.UUID? = if (SHAPE.matches(text)) java.util.UUID.fromString(text) else null

    fun text(id: java.util.UUID): String = id.toString()

    fun json(id: java.util.UUID?): JsonPrimitive? = id?.let { JsonPrimitive(text(it)) }
}
