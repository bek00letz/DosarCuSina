package com.ar.dosarcusina.detekt

import dev.detekt.api.Config
import dev.detekt.api.Rule
import dev.detekt.test.lint
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Test
import org.junit.jupiter.params.ParameterizedTest
import org.junit.jupiter.params.provider.MethodSource

/**
 * Every rule against its fixtures (src/test/resources/fixtures/<rule>/): the failing one finds
 * exactly what it was written to show, the passing one nothing, as
 * `scripts/architecture-check.sh --self-test` checks the iPhone app's rules.
 */
class DosarRulesTest {
    @ParameterizedTest
    @MethodSource("rules")
    fun `the failing fixture is refused`(rule: Rule) {
        val findings = rule.lint(fixture(rule, "fails"), compile = false)
        assertEquals(FAILURES.getValue(rule.ruleName.value), findings.size, findings.joinToString("\n") { it.message })
    }

    @ParameterizedTest
    @MethodSource("rules")
    fun `the passing fixture is let through`(rule: Rule) {
        val findings = rule.lint(fixture(rule, "passes"), compile = false)
        assertEquals(emptyList<String>(), findings.map { it.message })
    }

    @Test
    fun `the rule set holds every rule, each with its fixtures`() {
        val names = DosarRuleSetProvider().instance().rules.keys.map { it.value }.toSet()
        assertEquals(FAILURES.keys, names)
    }

    private fun fixture(rule: Rule, kind: String): String {
        val path = "/fixtures/${rule.ruleName.value}/$kind.kt"
        val stream = requireNotNull(javaClass.getResourceAsStream(path)) { "$path is missing" }
        return stream.use { it.readBytes().decodeToString() }
    }

    companion object {
        /** How many findings each failing fixture was written to show. */
        private val FAILURES = mapOf(
            "DosarHandWrittenPlural" to 2,
            "DosarTextInComposable" to 2,
            "DosarSheetOutsideRouter" to 2,
            "DosarAnimationOutsideMotion" to 4,
            "DosarBareProgress" to 1,
        )

        @JvmStatic
        fun rules(): List<Rule> = DosarRuleSetProvider().instance().rules.values.map { it(Config.empty) }
    }
}
