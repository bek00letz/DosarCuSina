package com.ar.dosarcusina.core.subscriptions

import com.ar.dosarcusina.core.values.RomanianText
import com.ar.dosarcusina.core.values.TextRules
import kotlinx.serialization.json.JsonObject

/**
 * A code an ongoing contract's papers are identified by, declared once in the iOS app (`SubscriptionCode`) and
 * read from the catalog ([SubscriptionCatalog]): the subscription's field that keeps it, what capture reads it as,
 * and how much an agreeing one says about which contract a paper belongs to. Which codes a service has is the
 * service's ([Service.codes]).
 */
data class SubscriptionCode(
    /** Its name, as the iOS case: `clientCode`, `pod`. */
    val name: String,
    val family: Family,
    /** The subscription field that keeps it (`subscription.pod`). */
    val fieldKey: String,
    /** What capture reads it as (`podCode`). */
    val captureKey: String,
    /** How strongly an agreeing code says it is the same contract. */
    val weight: Int,
    /** Names one consumption point or one line: a different one is a different contract. */
    val namesOnePoint: Boolean,
    /** A home's own fields for the same code, when homes keep it (`home.pod`). */
    val homeFieldKeys: List<String>,
    /** How a kept and a read value are compared ([normalized]). */
    val comparison: Comparison,
    /** The condition under which the subscription's edit form shows and keeps it, as a template writes it. */
    val editFormCondition: JsonObject,
) {
    /**
     * What kind of code it is: a paper read for one service under another's name keeps it as its own of the same
     * family.
     */
    enum class Family(val raw: String) {
        /** Names the place supplied: a POD, a CLC, a water or heating place code. */
        CONSUMPTION_POINT("consumptionPoint"),

        /** Names the customer: a client code, a billing account. */
        CUSTOMER("customer"),
        CONTRACT("contract"),
        LINE("line"),
    }

    /** How a code is compared. */
    enum class Comparison(val raw: String) {
        /** Without spaces, dashes, case or diacritics ([RomanianText.compact]). */
        COMPACT("compact"),

        /** A phone number in its national form: "+40 7…" and "0040 7…" are "07…". */
        NATIONAL_PHONE_NUMBER("nationalPhoneNumber"),
    }

    /** [text] as it is compared with another value of this code. */
    fun normalized(text: String): String = when (comparison) {
        Comparison.COMPACT -> RomanianText.compact(text)
        Comparison.NATIONAL_PHONE_NUMBER -> national(text)
    }

    override fun toString(): String = name

    companion object {
        private const val INTERNATIONAL_PREFIX = "0040"
        private const val COUNTRY_CODE = "40"
        private const val INTERNATIONAL_LENGTH = 11

        /** Every code, in the edit form's order. */
        val all: List<SubscriptionCode> get() = SubscriptionCatalog.builtIn.codes

        /** The code named [name] (`pod`); null for none. */
        fun named(name: String): SubscriptionCode? = all.firstOrNull { it.name == name }

        /** The code a capture field is, if it is one. */
        fun ofCaptureKey(captureKey: String): SubscriptionCode? = all.firstOrNull { it.captureKey == captureKey }

        /**
         * The codes a subscription keeps, from its values' texts by field key ([text]): what the store hands the
         * matcher.
         */
        fun kept(text: (fieldKey: String) -> String?): Map<SubscriptionCode, String> =
            all.mapNotNull { code -> text(code.fieldKey)?.let { code to it } }.toMap()

        /**
         * The fields a paper read as [service] keeps, as the iOS app's `SubscriptionCode.keeping`: the codes it has,
         * and a code read under another service's name as its own code of the same family when it read none of those
         * itself (a gas bill's "POD gaz" is its CLC; a water bill's "cod loc consum" its place code). Any other code
         * goes, so a service is never asked or given a code it doesn't have; what isn't a code stays. A paper whose
         * service isn't known keeps every code it read. Each field's capture key is [captureKey]; [rekeyed] is a
         * field kept under another code's capture key.
         */
        fun <F> keeping(
            fields: List<F>,
            service: String?,
            captureKey: (F) -> String,
            rekeyed: (F, String) -> F,
        ): List<F> {
            val declared = ServiceKind.service(service) ?: return fields
            val read = fields.mapNotNull { ofCaptureKey(captureKey(it)) }
            val kept = mutableListOf<F>()
            val given = mutableSetOf<SubscriptionCode>()
            for (field in fields) {
                val code = ofCaptureKey(captureKey(field))
                if (code == null) {
                    kept.add(field)
                } else if (code in declared.codes) {
                    kept.add(field)
                    given.add(code)
                } else {
                    val own = declared.codes.firstOrNull { it.family == code.family && it !in read && it !in given }
                    if (own != null) {
                        kept.add(rekeyed(field, own.captureKey))
                        given.add(own)
                    }
                }
            }
            return kept
        }

        /** The national form of a Romanian number: "+40 7…" and "0040 7…" become "07…". */
        fun national(text: String): String {
            val digits = TextRules.characters(text).filter(TextRules::isNumber).joinToString("")
            return when {
                digits.startsWith(INTERNATIONAL_PREFIX) -> "0" + digits.substring(INTERNATIONAL_PREFIX.length)
                digits.startsWith(COUNTRY_CODE) && TextRules.characters(digits).size == INTERNATIONAL_LENGTH ->
                    "0" + digits.substring(COUNTRY_CODE.length)
                else -> digits
            }
        }
    }
}
