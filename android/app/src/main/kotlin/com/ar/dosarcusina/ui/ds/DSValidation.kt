package com.ar.dosarcusina.ui.ds

import androidx.compose.foundation.relocation.BringIntoViewRequester
import androidx.compose.foundation.relocation.bringIntoViewRequester
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.Immutable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.remember
import androidx.compose.runtime.staticCompositionLocalOf
import androidx.compose.ui.Modifier
import androidx.compose.ui.focus.FocusRequester
import androidx.compose.ui.focus.focusRequester
import androidx.compose.ui.hapticfeedback.HapticFeedbackType
import androidx.compose.ui.layout.onGloballyPositioned
import androidx.compose.ui.layout.positionInRoot
import androidx.compose.ui.platform.LocalHapticFeedback
import androidx.compose.ui.semantics.error
import androidx.compose.ui.semantics.semantics
import com.ar.dosarcusina.core.wording.Word
import java.util.UUID

/**
 * The outcome of checking a field's value, as the iPhone app's `DSValidation`. Messages say what
 * is wrong and how to fix it („Seria de șasiu are 17 caractere. Ai scris 15.”).
 */
@Immutable
sealed interface DSValidation {
    data object Valid : DSValidation

    /** Blocks saving: drawn in the overdue colour, with an error haptic. */
    data class Invalid(val message: String) : DSValidation

    /** Worth knowing, never blocks saving („Pașaportul expiră în mai puțin de 6 luni.”). */
    data class Warning(val message: String) : DSValidation

    val message: String?
        get() = when (this) {
            Valid -> null
            is Invalid -> message
            is Warning -> message
        }

    companion object {
        /** What every required field says when left empty. */
        val requiredMissing: DSValidation
            get() = Invalid(Word.app("Completează acest câmp.").written())
    }
}

/**
 * A form's request to show every field's problem: its save refused for a missing or wrong value,
 * as the iPhone app's `DSValidationReveal`. Each refusal is another attempt, so the form goes to
 * its first problem every time, not only the first.
 */
@Immutable
data class DSValidationReveal(val attempt: Int = 0) {
    val isOn: Boolean get() = attempt > 0

    /** A save was refused: show every problem and go to the first. */
    fun revealed(): DSValidationReveal = copy(attempt = attempt + 1)
}

/**
 * Decides when a field's problem shows, as the iPhone app's `DSValidationVisibility`: not while the
 * person is still typing for the first time, only once they leave the field or after a refused save.
 */
object DSValidationVisibility {
    fun shown(validation: DSValidation, hasLeftField: Boolean, reveal: Boolean): DSValidation =
        if (hasLeftField || reveal) validation else DSValidation.Valid
}

/** Whether the form around has had a save refused: every field shows its problem then. */
val LocalRevealsValidation = staticCompositionLocalOf { false }

/** The problems of one form, and how high each sits, so a refused save goes to the one nearest the top. */
class DSValidationTargets {
    private class Target(
        var message: String?,
        var top: Float,
        val requester: BringIntoViewRequester,
        val focus: FocusRequester,
    )

    private val targets = mutableMapOf<String, Target>()

    internal fun register(id: String, requester: BringIntoViewRequester, focus: FocusRequester) {
        targets[id] = Target(null, Float.MAX_VALUE, requester, focus)
    }

    internal fun set(id: String, message: String?) {
        targets[id]?.message = message
    }

    internal fun place(id: String, top: Float) {
        targets[id]?.top = top
    }

    internal fun remove(id: String) {
        targets.remove(id)
    }

    /** Takes the person to the problem highest on the screen: brought into view, focused. */
    internal suspend fun goToFirst() {
        val first = targets.values.filter { it.message != null }.minByOrNull { it.top } ?: return
        first.requester.bringIntoView()
        runCatching { first.focus.requestFocus() }
    }
}

private val LocalValidationTargets = staticCompositionLocalOf<DSValidationTargets?> { null }

/**
 * The one way a form shows its problems after a refused save, as the iPhone app's
 * `dsRevealsValidation`: every field shows its own, the form scrolls to the first (the one highest
 * on the screen) and focus moves there, so TalkBack says what is wrong. Wrap the form's scrolling
 * content; the DS fields take part by themselves, anything else that states a problem with
 * [dsValidationTarget].
 */
@Composable
fun DSRevealsValidation(reveal: DSValidationReveal, content: @Composable () -> Unit) {
    val targets = remember { DSValidationTargets() }
    val haptics = LocalHapticFeedback.current
    LaunchedEffect(reveal.attempt) {
        if (!reveal.isOn) return@LaunchedEffect
        haptics.performHapticFeedback(HapticFeedbackType.Reject)
        targets.goToFirst()
    }
    CompositionLocalProvider(
        LocalRevealsValidation provides reveal.isOn,
        LocalValidationTargets provides targets,
        content = content,
    )
}

/**
 * Takes part in a refused save's reveal: while [message] is set, this is a problem the form can
 * scroll to and move focus to, and TalkBack reads it as an error. [focus] is the field's own, when
 * it takes focus.
 */
@Composable
fun Modifier.dsValidationTarget(message: String?, focus: FocusRequester = remember { FocusRequester() }): Modifier {
    val targets = LocalValidationTargets.current ?: return this
    val id = remember { UUID.randomUUID().toString() }
    val requester = remember { BringIntoViewRequester() }
    DisposableEffect(targets) {
        targets.register(id, requester, focus)
        onDispose { targets.remove(id) }
    }
    LaunchedEffect(message) { targets.set(id, message) }
    return this
        .bringIntoViewRequester(requester)
        .focusRequester(focus)
        .onGloballyPositioned { targets.place(id, it.positionInRoot().y) }
        .then(if (message != null) Modifier.semantics { error(message) } else Modifier)
}
