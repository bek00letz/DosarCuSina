package com.ar.dosarcusina.archive

import com.ar.dosarcusina.archive.v3.CustomFact
import com.ar.dosarcusina.archive.v3.FieldDefinition
import com.ar.dosarcusina.archive.v3.FieldValue
import com.ar.dosarcusina.archive.v3.FieldValues
import com.ar.dosarcusina.core.text.SealedText
import com.ar.dosarcusina.core.values.JsonTrees
import com.ar.dosarcusina.core.values.KeptList
import com.ar.dosarcusina.core.values.KeptObject
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive

/**
 * What an archive may carry of a secret, as the iOS app's `SecretFields`
 * (ios/DosarCuSina/Services/Security/SecretFields.swift): nothing. A secret field's value (an
 * identity card's PIN) and a secret row under Date importante (an alarm code) are kept only on
 * the phone, sealed. A sealed value is known by its own form, whatever its field says, so
 * nothing sealed is written or read anywhere; and an import keeps the phone's own secrets for
 * the same records, in both modes. Sealing itself comes with the locks (Phase 6).
 */
// Each rule of the iOS app's SecretFields, side by side.
@Suppress("TooManyFunctions")
object SecretRules {
    /** Marks sealed text, with the format's version ([SealedText.PREFIX], the one place it is written). */
    const val SEALED_PREFIX = SealedText.PREFIX

    fun isSealed(text: String): Boolean = SealedText.isSealed(text)

    /** Whether a value is a sealed secret, by its own form. */
    fun isSealed(value: FieldValue): Boolean = when (value) {
        is FieldValue.Text -> isSealed(value.value)
        is FieldValue.Choices -> value.value.any(::isSealed)
        else -> false
    }

    /** A part this build doesn't read, or null when it says it is secret or anything in it is sealed. */
    private fun withoutSecrets(raw: JsonElement): JsonElement? {
        val saysSecret = ((raw as? JsonObject)?.get("isSecret") as? JsonPrimitive)?.let {
            !it.isString && it.content == "true"
        } ?: false
        return if (saysSecret || JsonTrees.containsString(raw, ::isSealed)) null else raw
    }

    /** A part this build doesn't read, when it says it is secret or anything in it is sealed. */
    private fun sealedPart(raw: JsonElement): JsonElement? = if (withoutSecrets(raw) == null) raw else null

    /** The values without any secret: every sealed value, and every value of a field the category marks secret. */
    fun stripping(values: FieldValues, fields: List<FieldDefinition>?): FieldValues {
        var result = values.mappingUnreadable { if (JsonTrees.containsString(it, ::isSealed)) null else it }
        for ((key, value) in values.storage) if (isSealed(value)) result = result.with(key, null)
        for (field in fields.orEmpty()) if (field.isSecret) result = result.with(field.key, null)
        return result
    }

    /** The same for values as stored: what a newer build wrote inside them goes too when anything in it is sealed. */
    fun stripping(values: KeptObject<FieldValues>, fields: List<FieldDefinition>?): KeptObject<FieldValues> =
        values.replacingValue(stripping(values.value, fields)).mappingKept(::withoutSecrets)

    /**
     * Only the sealed values, by their own form: those this build reads, and those it can't with anything sealed in
     * them.
     */
    fun sealedValues(values: FieldValues): FieldValues {
        var result = values.mappingUnreadable(::sealedPart)
        for ((key, value) in values.storage) if (!isSealed(value)) result = result.with(key, null)
        return result
    }

    /**
     * Incoming values (an archive's, which never carries secrets) with the secrets this phone
     * keeps for the same record. A kept secret stays only while its field still applies (a PIN
     * goes when the card became a passport).
     */
    fun keepingLocalSecrets(incoming: FieldValues, existing: FieldValues, fields: List<FieldDefinition>?): FieldValues {
        var result = stripping(incoming, fields)
        val sealed = sealedValues(existing)
        for ((key, value) in sealed.storage) {
            val field = fields?.firstOrNull { it.key == key }
            if (field != null && !field.applies(result)) continue
            result = result.with(key, value)
        }
        // A sealed value this build can't read stays too, unless the archive gives its field a value.
        return result.addingUnreadable(sealed)
    }

    fun keepingLocalSecrets(
        incoming: KeptObject<FieldValues>,
        existing: FieldValues,
        fields: List<FieldDefinition>?,
    ): KeptObject<FieldValues> {
        val stripped = stripping(incoming, fields)
        return stripped.replacingValue(keepingLocalSecrets(stripped.value, existing, fields))
    }

    /** The rows without the secret ones, read or not, for anything that leaves the binder. */
    fun strippingFacts(facts: KeptList<CustomFact>): KeptList<CustomFact> =
        facts.replacingItems(facts.items.filter { !it.isSecret }).mappingKept(::withoutSecrets)

    /** The phone's secret rows of a record, as stored, read or not: what a restore keeps of the phone's own. */
    fun secretFacts(facts: KeptList<CustomFact>): KeptList<CustomFact> =
        facts.filtered({ it.isSecret }, { sealedPart(it) != null })

    /**
     * Rows as an archive carries them (none secret) with every secret row this phone keeps for
     * the same record, each as it is stored here. A row from the archive with the same id gives way.
     */
    fun keepingLocalSecretFacts(incoming: KeptList<CustomFact>, existing: KeptList<CustomFact>): KeptList<CustomFact> =
        strippingFacts(incoming).replacingEntries(secretFacts(existing))
}
