package com.ar.dosarcusina.ui.ds

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.gestures.Orientation
import androidx.compose.foundation.gestures.draggable
import androidx.compose.foundation.gestures.rememberDraggableState
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxScope
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableFloatStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.shadow
import androidx.compose.ui.hapticfeedback.HapticFeedbackType
import androidx.compose.ui.layout.Layout
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.LocalHapticFeedback
import androidx.compose.ui.semantics.CustomAccessibilityAction
import androidx.compose.ui.semantics.LiveRegionMode
import androidx.compose.ui.semantics.customActions
import androidx.compose.ui.semantics.liveRegion
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.IntOffset
import androidx.compose.ui.unit.dp
import com.ar.dosarcusina.core.wording.Word
import kotlinx.coroutines.delay
import kotlin.math.roundToInt

/**
 * Draws [center]'s toast floating at the bottom of [BoxScope], [bottomInset] above the edge (the
 * navigation bar), arriving with the emphasized spring (a fade with "remove animations"). It goes
 * by itself after its time (twice as long with TalkBack on), on a swipe down, or when its button
 * is used; TalkBack reads it as it arrives.
 */
@Composable
fun BoxScope.DSToastHost(center: DSToastCenter, modifier: Modifier = Modifier, talkBackOn: Boolean = false) {
    val toast = center.toast
    val haptics = LocalHapticFeedback.current
    LaunchedEffect(toast?.id) {
        val shown = toast ?: return@LaunchedEffect
        val feedback = if (shown.tone == DSToastTone.FAILURE) HapticFeedbackType.Reject else HapticFeedbackType.Confirm
        haptics.performHapticFeedback(feedback)
        delay(if (talkBackOn) shown.durationMillis * 2 else shown.durationMillis)
        center.dismiss(shown.id)
    }
    // The last toast stays drawn while it leaves.
    val last = remember { LastShown() }
    if (toast != null) last.toast = toast
    DSAnimatedVisibility(
        visible = toast != null,
        modifier = modifier.align(Alignment.BottomCenter),
        edge = DSEdge.BOTTOM,
        motion = DSMotion.EMPHASIZED,
    ) {
        last.toast?.let { ToastBar(it, center) }
    }
}

/** The toast drawn last, kept while it animates away. */
private class LastShown {
    var toast: DSToast? = null
}

@Composable
private fun ToastBar(toast: DSToast, center: DSToastCenter) {
    val colors = DS.colors
    var drag by remember(toast.id) { mutableFloatStateOf(0f) }
    val dismissAt = with(LocalDensity.current) { SWIPE_TO_DISMISS.toPx() }
    val settled by dsAnimateFloat(drag.coerceAtLeast(0f), DSMotion.QUICK)
    val close = Word.app("Închide").written()
    Box(
        Modifier
            .padding(horizontal = DSSpace.m, vertical = DSSpace.xs)
            .dsReadableWidth()
            .offset { IntOffset(0, settled.roundToInt()) }
            .draggable(
                orientation = Orientation.Vertical,
                state = rememberDraggableState { delta -> drag += delta },
                onDragStopped = { if (drag > dismissAt) center.dismiss(toast.id) else drag = 0f },
            )
            .shadow(TOAST_ELEVATION, DSShapes.floatingBar)
            .background(colors.surfaceRaised, DSShapes.floatingBar)
            .dsHairlineBorder(DSShapes.floatingBar)
            .heightIn(min = DSControl.floatingBar)
            .semantics {
                liveRegion = LiveRegionMode.Polite
                customActions = listOf(
                    CustomAccessibilityAction(close) {
                        center.dismiss(toast.id)
                        true
                    },
                )
            }
            .padding(start = DSSpace.m, end = DSSpace.xs, top = DSSpace.xxs, bottom = DSSpace.xxs),
    ) {
        WordsBesideAction(
            words = { ToastWords(toast) },
            action = { ToastButtons(toast, center) },
        )
    }
}

@Composable
private fun ToastWords(toast: DSToast) {
    val colors = DS.colors
    val tint = when (toast.tone) {
        DSToastTone.DONE -> colors.status.done
        DSToastTone.DELETED -> colors.secondaryLabel
        DSToastTone.FAILURE -> colors.status.overdue
    }
    Row(
        modifier = Modifier.padding(vertical = DSSpace.xs),
        horizontalArrangement = Arrangement.spacedBy(DSSpace.s),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        DSIcon(toast.tone.symbol, tint)
        DSText(toast.title, DSTextStyle.SUBHEADLINE, color = colors.label)
    }
}

@Composable
private fun ToastButtons(toast: DSToast, center: DSToastCenter) {
    Row {
        toast.offer?.let { offer -> ToastButton(offer.title) { center.take(toast) } }
        if (toast.offersUndo) ToastButton(Word.app("Anulează").written()) { center.takeBack(toast) }
    }
}

@Composable
private fun ToastButton(title: String, onClick: () -> Unit) {
    TextButton(onClick = onClick, modifier = Modifier.heightIn(min = DSControl.minimumHitTarget)) {
        DSText(title, DSTextStyle.SUBHEADLINE, color = DS.colors.accent, fontWeight = FontWeight.SemiBold)
    }
}

/**
 * The toast's words and its buttons, as the iPhone app's `WordsBesideAction`: side by side while
 * the buttons take no more than half the width, the words wrapping beside them; otherwise the
 * words across the whole width and the buttons under them at the end. It decides by measuring,
 * never by the font size.
 */
@Composable
private fun WordsBesideAction(words: @Composable () -> Unit, action: @Composable () -> Unit) {
    Layout(contents = listOf(words, action), modifier = Modifier.fillMaxWidth()) { parts, constraints ->
        val (wordsPart, actionPart) = parts
        val width = constraints.maxWidth
        val gap = DSSpace.s.roundToPx()
        val buttons = actionPart.map { it.measure(constraints.copy(minWidth = 0, minHeight = 0)) }
        val buttonWidth = buttons.sumOf { it.width }
        val beside = ToastArrangement.fitsBeside(buttonWidth, width, gap)
        val wordsWidth = if (beside) (width - buttonWidth - gap).coerceAtLeast(0) else width
        val text = wordsPart.map { it.measure(constraints.copy(minWidth = 0, minHeight = 0, maxWidth = wordsWidth)) }
        val textHeight = text.maxOfOrNull { it.height } ?: 0
        val buttonHeight = buttons.maxOfOrNull { it.height } ?: 0
        val height = if (beside) maxOf(textHeight, buttonHeight) else textHeight + buttonHeight
        layout(width, height) {
            text.forEach { it.placeRelative(0, if (beside) (height - it.height) / 2 else 0) }
            var x = width - buttonWidth
            buttons.forEach {
                it.placeRelative(x, if (beside) (height - it.height) / 2 else textHeight)
                x += it.width
            }
        }
    }
}

/** The decision behind the toast's layout, apart from Compose so it is tested. */
object ToastArrangement {
    /** Whether buttons [buttonWidth] wide leave the words at least as much of [width] as they take. */
    fun fitsBeside(buttonWidth: Int, width: Int, gap: Int): Boolean =
        buttonWidth == 0 || buttonWidth <= (width - gap) / 2
}

private val SWIPE_TO_DISMISS = 30.dp
private val TOAST_ELEVATION = 6.dp
