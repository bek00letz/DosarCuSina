package com.ar.dosarcusina.ui.ds

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.widthIn
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import com.ar.dosarcusina.core.wording.Word

/**
 * A designed empty state, as the iPhone app's `DSEmptyState`: a symbol, a short title, one
 * sentence on what goes here, and the action that fills it.
 */
@Composable
fun DSEmptyState(
    title: String,
    message: String,
    modifier: Modifier = Modifier,
    symbol: DSSymbol = DSSymbol.FOLDER,
    actionTitle: String? = null,
    onAction: (() -> Unit)? = null,
) {
    CenteredState(symbol, DS.colors.accent, title, message, modifier) {
        if (actionTitle != null && onAction != null) DSPrimaryButton(actionTitle, onAction)
    }
}

/**
 * A full-area error, as the iPhone app's `DSErrorState`: what happened and what to do next, with
 * „Încearcă din nou” whenever trying again can help (docs/COPY_GUIDE.md).
 */
@Composable
fun DSErrorState(title: String, message: String, modifier: Modifier = Modifier, onRetry: (() -> Unit)? = null) {
    CenteredState(DSSymbol.WARNING, DS.colors.status.overdue, title, message, modifier) {
        if (onRetry != null) DSSecondaryButton(Word.app("Încearcă din nou").written(), onRetry)
    }
}

/**
 * The calm state a protected section shows until it is opened, as the iPhone app's
 * `DSLockedState`. Opening it asks the phone's own unlock (Phase 6); [isWorking] while it asks.
 */
@Composable
fun DSLockedState(
    title: String,
    unlockTitle: String,
    onUnlock: () -> Unit,
    modifier: Modifier = Modifier,
    message: String? = null,
    isWorking: Boolean = false,
) {
    CenteredState(DSSymbol.LOCK, DS.colors.accent, title, message, modifier) {
        DSPrimaryButton(unlockTitle, onUnlock, enabled = !isWorking)
    }
}

@Composable
private fun CenteredState(
    symbol: DSSymbol,
    tint: Color,
    title: String,
    message: String?,
    modifier: Modifier,
    action: @Composable () -> Unit,
) {
    Column(
        modifier = modifier.fillMaxWidth().padding(DSSpace.xxl),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(DSSpace.l),
    ) {
        DSIcon(symbol, tint, size = DSIconSize.hero)
        Column(
            modifier = Modifier.widthIn(max = STATE_WIDTH),
            horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.spacedBy(DSSpace.xs),
        ) {
            DSText(title, DSTextStyle.TITLE, Modifier.semantics { heading() }, textAlign = TextAlign.Center)
            message?.let {
                DSText(it, DSTextStyle.BODY, color = DS.colors.secondaryLabel, textAlign = TextAlign.Center)
            }
        }
        Column(Modifier.widthIn(max = STATE_WIDTH)) { action() }
    }
}

/** What a notice says about itself: information, a warning, an error or a success. */
enum class DSNoticeKind(val symbol: DSSymbol) {
    INFO(DSSymbol.INFO),
    WARNING(DSSymbol.WARNING),
    ERROR(DSSymbol.ERROR),
    SUCCESS(DSSymbol.DONE),
}

/**
 * An inline notice inside a screen or form, as the iPhone app's `DSNotice`: information, a
 * warning, an error or a success, with an optional action. It never blocks the screen.
 */
@Composable
fun DSNotice(
    kind: DSNoticeKind,
    title: String,
    modifier: Modifier = Modifier,
    message: String? = null,
    actionTitle: String? = null,
    onAction: (() -> Unit)? = null,
) {
    val tint = noticeTint(kind)
    Row(
        modifier = modifier
            .fillMaxWidth()
            .semantics(mergeDescendants = onAction == null) {}
            .background(tint.copy(alpha = DSTint.NOTICE), DSShapes.notice)
            .padding(DSSpace.m),
        horizontalArrangement = Arrangement.spacedBy(DSSpace.s),
    ) {
        DSIcon(kind.symbol, tint)
        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(DSSpace.xxs)) {
            DSText(title, DSTextStyle.HEADLINE)
            message?.let { DSText(it, DSTextStyle.SUBHEADLINE) }
            if (actionTitle != null && onAction != null) DSLinkButton(actionTitle, onAction)
        }
    }
}

@Composable
private fun noticeTint(kind: DSNoticeKind): Color {
    val colors = DS.colors
    return when (kind) {
        DSNoticeKind.INFO -> colors.accent
        DSNoticeKind.WARNING -> colors.status.soon
        DSNoticeKind.ERROR -> colors.status.overdue
        DSNoticeKind.SUCCESS -> colors.status.done
    }
}

private val STATE_WIDTH = 480.dp
