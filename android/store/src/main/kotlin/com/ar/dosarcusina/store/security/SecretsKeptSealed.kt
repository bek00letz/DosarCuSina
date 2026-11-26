package com.ar.dosarcusina.store.security

import com.ar.dosarcusina.archive.binder.BuiltIns
import com.ar.dosarcusina.archive.v3.FieldDefinition
import com.ar.dosarcusina.store.Step
import com.ar.dosarcusina.store.Tables
import com.ar.dosarcusina.store.schema.keptFacts
import com.ar.dosarcusina.store.schema.keptSections
import com.ar.dosarcusina.store.schema.keptValues

/**
 * The store's own guard that the database holds only sealed secrets: every section a step makes or
 * writes again is read for a secret in plain (a field its category marks secret, a secret row under
 * Date importante), and the save is refused when there is one ([SecretFieldError.NotSealed]). Every
 * action seals first ([SecretFields.sealing]); this is what stops a step that didn't. The iOS app
 * keeps the same rule by sealing in `AssetActions`, its one way to write a section's values.
 */
internal object SecretsKeptSealed {
    /** Throws [SecretFieldError.NotSealed] when a section [step] saves keeps a secret in plain. */
    fun check(step: Step, builtIns: BuiltIns) {
        val saved = step.changes(Tables.assets).saved
        if (saved.isEmpty()) return
        val categories = LinkedHashMap<String, List<FieldDefinition>>()
        for (template in step.all(Tables.templates)) {
            categories.putIfAbsent(template.key, template.keptSections.items.flatMap { it.fields })
        }
        for (asset in saved) {
            val fields = categories[asset.templateKey]
                ?: builtIns.definition(asset.templateKey)?.sections?.flatMap { it.fields }.orEmpty()
            val plain = SecretFields.holdsUnsealed(asset.keptValues.value, fields) ||
                SecretFields.holdsUnsealed(asset.keptFacts.items)
            if (plain) throw SecretFieldError.NotSealed()
        }
    }
}
