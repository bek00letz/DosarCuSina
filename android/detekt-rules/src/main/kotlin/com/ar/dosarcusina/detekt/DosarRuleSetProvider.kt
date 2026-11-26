package com.ar.dosarcusina.detekt

import dev.detekt.api.RuleSet
import dev.detekt.api.RuleSetId
import dev.detekt.api.RuleSetProvider

/**
 * The app's rules, checked rather than remembered, as scripts/architecture-check.sh checks the
 * iPhone app's: each names the file, the rule and what to use instead. Configured in
 * android/config/detekt/detekt.yml under `dosar`, where a rule's `excludes` names the one file
 * that is the path it guards (the design system's motion, the router's sheets).
 */
class DosarRuleSetProvider : RuleSetProvider {
    override val ruleSetId: RuleSetId = RuleSetId(ID)

    override fun instance(): RuleSet = RuleSet(
        ruleSetId,
        listOf(
            ::DosarHandWrittenPlural,
            ::DosarTextInComposable,
            ::DosarSheetOutsideRouter,
            ::DosarAnimationOutsideMotion,
            ::DosarBareProgress,
        ),
    )

    companion object {
        const val ID: String = "dosar"
    }
}
