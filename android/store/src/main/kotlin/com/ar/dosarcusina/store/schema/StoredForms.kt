package com.ar.dosarcusina.store.schema

import androidx.room3.ColumnTypeConverter
import com.ar.dosarcusina.core.values.DecimalText
import com.ar.dosarcusina.core.values.MachineText
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.intOrNull
import java.math.BigDecimal
import java.time.Instant
import java.util.UUID

/**
 * How the database keeps the iOS models' kinds of values, one form each, so a value reads back
 * as it was written:
 * - an id (`UUID`) as its text;
 * - a moment (`Date`) as milliseconds since 1970 in UTC ([StoredMoment]);
 * - an amount (`Decimal`) as its machine text, never through a Double ([DecimalText]);
 * - a list of numbers or words (`[Int]`, `[String]`) as machine JSON ([MachineText]).
 *
 * A day is kept as its ISO text in a `String` column (`StoredDay`), JSON the iOS app keeps as
 * `Data` as its text in a `String` column (read and written through `KeptValues.kt`), and a
 * picture or file the iOS app keeps outside the database (`.externalStorage`) as the digest of
 * its file beside the database ([com.ar.dosarcusina.store.StoreFiles]).
 */
class StoredForms {
    @ColumnTypeConverter
    fun idText(id: UUID?): String? = id?.toString()

    @ColumnTypeConverter
    fun id(text: String?): UUID? = text?.let(UUID::fromString)

    @ColumnTypeConverter
    fun momentMillis(moment: Instant?): Long? = moment?.toEpochMilli()

    @ColumnTypeConverter
    fun moment(millis: Long?): Instant? = millis?.let(Instant::ofEpochMilli)

    @ColumnTypeConverter
    fun amountText(amount: BigDecimal?): String? = amount?.let(DecimalText::write)

    @ColumnTypeConverter
    fun amount(text: String?): BigDecimal? = text?.let(DecimalText::read)

    @ColumnTypeConverter
    fun numbersText(numbers: List<Int>): String = MachineText.json(JsonArray(numbers.map { JsonPrimitive(it) }))

    @ColumnTypeConverter
    fun numbers(text: String): List<Int> =
        (MachineText.parse(text) as? JsonArray).orEmpty().mapNotNull { (it as? JsonPrimitive)?.intOrNull }

    @ColumnTypeConverter
    fun wordsText(words: List<String>): String = MachineText.json(JsonArray(words.map { JsonPrimitive(it) }))

    @ColumnTypeConverter
    fun words(text: String): List<String> =
        (MachineText.parse(text) as? JsonArray).orEmpty()
            .mapNotNull { (it as? JsonPrimitive)?.takeIf { word -> word.isString }?.content }
}

/**
 * Moments as the database keeps them: to the millisecond, in UTC. A moment made on the phone
 * keeps more than that, so whatever writes one passes it through [kept] first, and what it
 * compares later reads back the same.
 */
object StoredMoment {
    /** [moment] as the database keeps it. */
    fun kept(moment: Instant): Instant = Instant.ofEpochMilli(moment.toEpochMilli())

    /** Now, as the database keeps it. */
    fun now(): Instant = kept(Instant.now())

    /**
     * The oldest moment, `0001-01-01T00:00:00Z`, as the SQL default of a moment's column: the
     * iOS app's `ChangeTime.unknown` (`Date.distantPast`), older than any change.
     */
    const val UNKNOWN_MILLIS = "-62135596800000"
}

/**
 * The SQL defaults of the columns that can't be empty: the iOS models' defaults, so every column
 * is optional or defaulted (the CloudKit rule the iOS store keeps) and a column a later version
 * adds needs nothing written into the rows already there.
 */
object Defaults {
    const val EMPTY = "''"
    const val FALSE = "0"
    const val TRUE = "1"
    const val ZERO = "0"
    const val CURRENCY = "'RON'"
    const val NO_WORDS = "'[]'"
}
