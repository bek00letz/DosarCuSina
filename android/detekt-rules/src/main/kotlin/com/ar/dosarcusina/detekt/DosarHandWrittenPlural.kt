package com.ar.dosarcusina.detekt

import dev.detekt.api.Config
import dev.detekt.api.Entity
import dev.detekt.api.Finding
import dev.detekt.api.Rule
import org.jetbrains.kotlin.lexer.KtTokens
import org.jetbrains.kotlin.psi.KtBinaryExpression
import org.jetbrains.kotlin.psi.KtConstantExpression
import org.jetbrains.kotlin.psi.KtExpression
import org.jetbrains.kotlin.psi.KtIfExpression
import org.jetbrains.kotlin.psi.KtWhenConditionWithExpression
import org.jetbrains.kotlin.psi.KtWhenExpression

/**
 * No hand-written plural: a count compared with one or two choosing between two wordings
 * (`if (count == 1) "o zi" else "$count zile"`, or a `when` with a `1 ->` wording). Romanian has
 * three forms („o zi”, „2 zile”, „20 de zile”); a counted word is a catalog key with plural forms,
 * written with `Word.count(n)` (the iPhone app's hand-written plural check).
 */
class DosarHandWrittenPlural(config: Config) : Rule(
    config,
    "A count picks its wording from the String Catalog's plural forms, never by comparing it with one or two.",
) {
    override fun visitIfExpression(expression: KtIfExpression) {
        super.visitIfExpression(expression)
        val condition = expression.condition as? KtBinaryExpression ?: return
        if (!comparesWithACount(condition)) return
        if (containsWords(expression.then) && containsWords(expression.`else`)) report(expression)
    }

    override fun visitWhenExpression(expression: KtWhenExpression) {
        super.visitWhenExpression(expression)
        val counted = expression.entries.filter { entry ->
            entry.conditions.any { (it as? KtWhenConditionWithExpression)?.expression.isSmallCount() }
        }
        val otherwise = expression.entries.firstOrNull { it.isElse }
        val choosesWording = counted.any { containsWords(it.expression) } && containsWords(otherwise?.expression)
        if (choosesWording) report(expression)
    }

    private fun comparesWithACount(condition: KtBinaryExpression): Boolean =
        condition.operationToken in COMPARISONS && (condition.left.isSmallCount() || condition.right.isSmallCount())

    private fun KtExpression?.isSmallCount(): Boolean =
        this is KtConstantExpression && text.trimEnd('L', 'l') in SMALL_COUNTS

    private fun report(expression: KtExpression) {
        report(
            Finding(
                Entity.from(expression),
                "A hand-written plural: Romanian counts in three forms. Use the catalog's plural key with " +
                    "Word.count(n) (Word.app(\"%lld zile\", Word.count(n))), never a comparison with one or two.",
            ),
        )
    }

    private companion object {
        val SMALL_COUNTS = setOf("1", "2")
        val COMPARISONS = setOf(KtTokens.EQEQ, KtTokens.EXCLEQ, KtTokens.LT, KtTokens.GT, KtTokens.LTEQ, KtTokens.GTEQ)
    }
}
