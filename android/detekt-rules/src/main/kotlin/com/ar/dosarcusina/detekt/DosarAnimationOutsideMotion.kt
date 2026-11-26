package com.ar.dosarcusina.detekt

import dev.detekt.api.Config
import dev.detekt.api.Entity
import dev.detekt.api.Finding
import dev.detekt.api.Rule
import org.jetbrains.kotlin.psi.KtCallExpression

/**
 * No animation outside the design system's motion: every animation is one of `DSMotion`'s springs,
 * which turn into a short fade with "remove animations" on (the iPhone app's `DS.Motion` check). A
 * spec made by hand (`tween`, `spring`, `keyframes`…) and an animation left on Compose's own default
 * (`animate…AsState` or `animateContentSize` without `animationSpec`, `AnimatedVisibility` without
 * `enter` and `exit`, `AnimatedContent` without `transitionSpec`, `Crossfade` without
 * `animationSpec`) are refused. The motion's own file (ui/ds/DSMotion.kt) makes the specs.
 */
class DosarAnimationOutsideMotion(config: Config) : Rule(
    config,
    "Animations use DSMotion's springs, which keep to the phone's remove-animations setting.",
) {
    override fun visitCallExpression(expression: KtCallExpression) {
        super.visitCallExpression(expression)
        val name = expression.calleeName ?: return
        val missing = when {
            name in SPECS -> "a spec of its own"
            leavesTheDefault(name, expression) -> "Compose's default"
            else -> return
        }
        report(
            Finding(
                Entity.from(expression),
                "$name animates with $missing: use DSMotion (motion.spec(reduceMotion), DSAnimatedVisibility, " +
                    "dsAnimateFloat, Modifier.dsAnimateContentSize), whose springs fade with remove animations on.",
            ),
        )
    }

    /** Whether the call animates and leaves out the argument that would give it a DSMotion spec. */
    private fun leavesTheDefault(name: String, call: KtCallExpression): Boolean {
        val needed = when {
            ANIMATE_AS_STATE.matches(name) || name == "animateContentSize" || name == "Crossfade" ->
                listOf("animationSpec")
            name == "AnimatedVisibility" -> listOf("enter", "exit")
            name == "AnimatedContent" -> listOf("transitionSpec")
            else -> return false
        }
        return needed.any { !call.hasNamedArgument(it) }
    }

    private companion object {
        val SPECS = setOf(
            "tween", "spring", "keyframes", "keyframesWithSpline", "snap", "repeatable", "infiniteRepeatable",
            "TweenSpec", "SpringSpec", "KeyframesSpec", "SnapSpec",
        )
        val ANIMATE_AS_STATE = Regex("animate\\w*AsState")
    }
}
