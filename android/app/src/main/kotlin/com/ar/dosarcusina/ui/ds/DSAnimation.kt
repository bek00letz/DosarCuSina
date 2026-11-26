package com.ar.dosarcusina.ui.ds

import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.animateColorAsState
import androidx.compose.animation.animateContentSize
import androidx.compose.animation.core.animateDpAsState
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.interaction.collectIsPressedAsState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.State
import androidx.compose.runtime.getValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.unit.Dp

// The animated values and transitions screens use, each with a DSMotion kind, so every animation
// is a spring that keeps to "remove animations" (the iPhone app's `dsAnimation`).

/** A number that springs to [target] with [motion]. */
@Composable
fun dsAnimateFloat(target: Float, motion: DSMotion = DSMotion.STANDARD): State<Float> =
    animateFloatAsState(target, animationSpec = motion.spec(LocalReduceMotion.current), label = "dsFloat")

/** A length that springs to [target] with [motion]. */
@Composable
fun dsAnimateDp(target: Dp, motion: DSMotion = DSMotion.STANDARD): State<Dp> =
    animateDpAsState(target, animationSpec = motion.spec(LocalReduceMotion.current), label = "dsDp")

/** A colour that springs to [target] with [motion]. */
@Composable
fun dsAnimateColor(target: Color, motion: DSMotion = DSMotion.QUICK): State<Color> =
    animateColorAsState(target, animationSpec = motion.spec(LocalReduceMotion.current), label = "dsColor")

/** Grows and shrinks with its content, with [motion]. */
@Composable
fun Modifier.dsAnimateContentSize(motion: DSMotion = DSMotion.STANDARD): Modifier =
    animateContentSize(animationSpec = motion.spec(LocalReduceMotion.current))

/** Shows [content] while [visible], arriving from and leaving towards [edge]; a fade with "remove animations". */
@Composable
fun DSAnimatedVisibility(
    visible: Boolean,
    modifier: Modifier = Modifier,
    edge: DSEdge = DSEdge.TOP,
    motion: DSMotion = DSMotion.STANDARD,
    content: @Composable () -> Unit,
) {
    val reduceMotion = LocalReduceMotion.current
    AnimatedVisibility(
        visible = visible,
        modifier = modifier,
        enter = motion.enter(edge, reduceMotion),
        exit = motion.exit(edge, reduceMotion),
    ) { content() }
}

/**
 * The pressed state of a tappable surface that isn't a Material control (a box, a custom row): a
 * slight shrink and dim that springs back, only the dim with "remove animations", as the iPhone
 * app's `dsPressable`. Pass the same [interactionSource] to the surface's `clickable`.
 */
@Composable
fun Modifier.dsPressable(interactionSource: MutableInteractionSource, enabled: Boolean = true): Modifier {
    val pressed by interactionSource.collectIsPressedAsState()
    val reduceMotion = LocalReduceMotion.current
    val scale by dsAnimateFloat(if (pressed && !reduceMotion) PRESSED_SCALE else 1f, DSMotion.QUICK)
    val alpha by dsAnimateFloat(
        when {
            !enabled -> DSTint.DISABLED
            pressed -> DSTint.PRESSED
            else -> 1f
        },
        DSMotion.QUICK,
    )
    return graphicsLayer {
        scaleX = scale
        scaleY = scale
        this.alpha = alpha
    }
}

private const val PRESSED_SCALE = 0.97f
