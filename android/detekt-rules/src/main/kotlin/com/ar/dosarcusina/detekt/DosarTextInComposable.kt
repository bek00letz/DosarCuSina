package com.ar.dosarcusina.detekt

import dev.detekt.api.Config
import dev.detekt.api.Entity
import dev.detekt.api.Finding
import dev.detekt.api.Rule
import org.jetbrains.kotlin.psi.KtStringTemplateExpression

/**
 * No words written in a composable: every word on a screen comes from the String Catalogs through
 * core's `Word` (`Word.app("…")`, by its iOS key), so both apps say the same and the catalogs list
 * every word (the iPhone app's `text-in-shaped-screen` and catalog checks). A string that writes no
 * letters (a separator, an empty value), a key handed to `Word`, an annotation's and a debug label
 * or key (`label = "…"`, `key = "…"`, `testTag("…")`) are not words on a screen.
 */
class DosarTextInComposable(config: Config) : Rule(
    config,
    "Words on a screen come from the String Catalogs through Word, never written in a composable.",
) {
    override fun visitStringTemplateExpression(expression: KtStringTemplateExpression) {
        super.visitStringTemplateExpression(expression)
        if (!expression.writesWords || expression.isInAnnotation()) return
        val function = expression.enclosingNamedFunction() ?: return
        if (!function.isAnnotated(COMPOSABLE)) return
        if (expression.enclosingCall()?.calleeName in ALLOWED_CALLS) return
        if (expression.enclosingArgument()?.getArgumentName()?.asName?.asString() in ALLOWED_ARGUMENTS) return
        report(
            Finding(
                Entity.from(expression),
                "${function.name} writes „${expression.literalText}” itself: say it with Word.app(\"<iOS key>\") " +
                    "from the String Catalog (or hand it data), never a literal in a composable.",
            ),
        )
    }

    private companion object {
        const val COMPOSABLE = "Composable"

        /** Calls whose string is a key or machine text, never words shown. */
        val ALLOWED_CALLS = setOf(
            "app", "shared", "widgets", "Word",
            "testTag", "require", "check", "error", "requireNotNull", "checkNotNull",
        )

        /** Arguments that name a thing for the code, never words shown. */
        val ALLOWED_ARGUMENTS = setOf("label", "key", "contentKey", "tag", "testTag")
    }
}
