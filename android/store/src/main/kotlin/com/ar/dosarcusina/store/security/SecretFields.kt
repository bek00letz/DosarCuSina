package com.ar.dosarcusina.store.security

import com.ar.dosarcusina.archive.SecretRules
import com.ar.dosarcusina.archive.v3.CustomFact
import com.ar.dosarcusina.archive.v3.FieldDefinition
import com.ar.dosarcusina.archive.v3.FieldValue
import com.ar.dosarcusina.archive.v3.FieldValues
import com.ar.dosarcusina.core.text.PaymentCardNumbers
import com.ar.dosarcusina.core.text.SealedText
import com.ar.dosarcusina.core.values.KeptList
import com.ar.dosarcusina.core.values.KeptObject

/**
 * Seals and opens a secret (an identity card's PIN, an alarm code), as the iOS app's `SecretSealer`
 * (ios/DosarCuSina/Services/Security/SecretFields.swift): sealed text starts with
 * [SealedText.PREFIX], and the binder keeps only sealed text. The phone's own implementation, over
 * a key in Android's Keystore that never leaves the phone, comes with the locks (Phase 6); until
 * then nothing can be sealed ([NOT_YET]), so no secret is ever saved in plain.
 */
interface SecretSealer {
    /** [plain] sealed: [SealedText.PREFIX] and what only this phone's keys open. */
    fun seal(plain: String): String

    /** What [sealed] holds; throws [SecretFieldError] when no key here opens it. */
    fun open(sealed: String): String

    companion object {
        /**
         * The sealer while this build has no key to seal with (the Keystore comes in Phase 6): it
         * refuses, so a step that would keep a secret saves nothing rather than keep it in plain.
         */
        val NOT_YET: SecretSealer = object : SecretSealer {
            override fun seal(plain: String): String = throw SecretFieldError.KeyUnavailable()

            override fun open(sealed: String): String = throw SecretFieldError.Unreadable()
        }
    }
}

/** Why a secret couldn't be kept or opened, as kinds: the screens word them. */
sealed class SecretFieldError(message: String) : Exception(message) {
    /** The phone's key store refused to keep or give the key. */
    class KeyUnavailable : SecretFieldError("The phone couldn't keep the code safely")

    /** The sealed value can't be opened with any key this phone has. */
    class Unreadable : SecretFieldError("No key on this phone opens the code")

    /**
     * A step would save a secret in plain: a field the category marks secret, or a secret row under
     * Date importante, holding text that isn't sealed. Nothing of the step is kept; every action
     * seals first ([SecretFields.sealing]).
     */
    class NotSealed : SecretFieldError("A secret would be saved without being sealed")
}

/**
 * The rules for secret fields, as the iOS app's `SecretFields`: kept sealed, and never carried out of
 * the binder. Sealing is here ([sealing], [sealingFacts]); what leaves the binder (search, a backup,
 * a notification) goes without them through the one set of rules the archive follows ([stripping],
 * [strippingFacts], which are `SecretRules`').
 */
object SecretFields {
    /** The secret fields among [fields]. */
    fun fields(fields: List<FieldDefinition>): List<FieldDefinition> = fields.filter { it.isSecret }

    /**
     * [values] with every secret typed in plain sealed; values already sealed pass through. A card
     * number is masked before sealing (a sealed value is never rewritten once kept, so this is where
     * it is kept out), and a secret left empty keeps no value.
     */
    fun sealing(values: FieldValues, fields: List<FieldDefinition>, sealer: SecretSealer): FieldValues {
        var result = values
        for (field in fields(fields)) {
            val text = values[field.key]?.textValue ?: continue
            if (SealedText.isSealed(text)) continue
            val plain = PaymentCardNumbers.redact(text.trim())
            result = result.with(field.key, if (plain.isEmpty()) null else FieldValue.Text(sealer.seal(plain)))
        }
        return result
    }

    /**
     * [facts] with every secret row typed in plain sealed (and marked sensitive); rows already sealed
     * pass through, a secret row left empty keeps no value. A card number is masked before sealing.
     */
    fun sealingFacts(facts: List<CustomFact>, sealer: SecretSealer): List<CustomFact> = facts.map { fact ->
        if (!fact.isSecret || SealedText.isSealed(fact.value)) return@map fact
        val plain = PaymentCardNumbers.redact(fact.value.trim())
        fact.copy(isSensitive = true, value = if (plain.isEmpty()) "" else sealer.seal(plain))
    }

    /** Whether [values] keep, in a field [fields] mark secret, text that isn't sealed. */
    fun holdsUnsealed(values: FieldValues, fields: List<FieldDefinition>): Boolean =
        fields(fields).any { field ->
            when (val value = values[field.key]) {
                is FieldValue.Text -> value.value.isNotEmpty() && !SealedText.isSealed(value.value)
                is FieldValue.Choices -> value.value.any { it.isNotEmpty() && !SealedText.isSealed(it) }
                else -> false
            }
        }

    /** Whether [facts] keep a secret row whose value isn't sealed. */
    fun holdsUnsealed(facts: List<CustomFact>): Boolean =
        facts.any { it.isSecret && it.value.isNotEmpty() && !SealedText.isSealed(it.value) }

    /** The values without any secret, for anything that leaves the binder (`SecretRules.stripping`). */
    fun stripping(values: KeptObject<FieldValues>, fields: List<FieldDefinition>?): KeptObject<FieldValues> =
        SecretRules.stripping(values, fields)

    /** The rows without the secret ones, for anything that leaves the binder (`SecretRules.strippingFacts`). */
    fun strippingFacts(facts: KeptList<CustomFact>): KeptList<CustomFact> = SecretRules.strippingFacts(facts)
}
