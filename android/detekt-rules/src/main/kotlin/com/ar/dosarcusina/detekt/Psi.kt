package com.ar.dosarcusina.detekt

import com.intellij.psi.PsiElement
import org.jetbrains.kotlin.psi.KtAnnotated
import org.jetbrains.kotlin.psi.KtAnnotationEntry
import org.jetbrains.kotlin.psi.KtCallExpression
import org.jetbrains.kotlin.psi.KtFunction
import org.jetbrains.kotlin.psi.KtLiteralStringTemplateEntry
import org.jetbrains.kotlin.psi.KtNamedFunction
import org.jetbrains.kotlin.psi.KtStringTemplateExpression
import org.jetbrains.kotlin.psi.KtValueArgument

// What the rules read of the code, by its shape alone (no type resolution), so they run fast on
// every module.

/** The name a call is made by: `Text` for `Text(…)`, `app` for `Word.app(…)`. */
internal val KtCallExpression.calleeName: String?
    get() = calleeExpression?.text

/** Whether the call names [name] for an argument: `animationSpec = …`. */
internal fun KtCallExpression.hasNamedArgument(name: String): Boolean =
    valueArguments.any { it.getArgumentName()?.asName?.asString() == name }

/** Whether this declaration carries an annotation named [name] (`@Composable`). */
internal fun KtAnnotated.isAnnotated(name: String): Boolean =
    annotationEntries.any { it.shortName?.asString() == name }

/** The function this element is written in, the nearest named one. */
internal fun PsiElement.enclosingNamedFunction(): KtNamedFunction? {
    var current = parent
    while (current != null) {
        if (current is KtNamedFunction) return current
        current = current.parent
    }
    return null
}

/** The nearest call this element is an argument of, inside its own function. */
internal fun PsiElement.enclosingCall(): KtCallExpression? {
    var current = parent
    while (current != null && current !is KtFunction) {
        if (current is KtCallExpression) return current
        current = current.parent
    }
    return null
}

/** The argument this element is the value of, when it is one directly or through an `if`. */
internal fun PsiElement.enclosingArgument(): KtValueArgument? {
    var current = parent
    while (current != null && current !is KtCallExpression && current !is KtFunction) {
        if (current is KtValueArgument) return current
        current = current.parent
    }
    return null
}

/** Whether this element is written inside an annotation (`@Suppress("…")`). */
internal fun PsiElement.isInAnnotation(): Boolean {
    var current = parent
    while (current != null) {
        if (current is KtAnnotationEntry) return true
        current = current.parent
    }
    return false
}

/** The words a string template writes as they are, its `$…` parts left out. */
internal val KtStringTemplateExpression.literalText: String
    get() = entries.filterIsInstance<KtLiteralStringTemplateEntry>().joinToString("") { it.text }

/** Whether a string template writes a word: any letter, in any script. */
internal val KtStringTemplateExpression.writesWords: Boolean
    get() = literalText.any { it.isLetter() }

/** Whether [element] holds, anywhere inside, a string template that writes words. */
internal fun containsWords(element: PsiElement?): Boolean {
    if (element == null) return false
    if (element is KtStringTemplateExpression) return element.writesWords
    return element.children.any { containsWords(it) }
}
