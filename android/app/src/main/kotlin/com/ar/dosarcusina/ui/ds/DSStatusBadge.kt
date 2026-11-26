package com.ar.dosarcusina.ui.ds

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Shape
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import com.ar.dosarcusina.core.urgency.AttentionUrgency
import com.ar.dosarcusina.core.urgency.UrgencyTone
import com.ar.dosarcusina.core.values.CalendarDay
import com.ar.dosarcusina.core.values.DosarCalendar
import com.ar.dosarcusina.core.wording.DurationWording
import com.ar.dosarcusina.core.wording.WhenWording
import com.ar.dosarcusina.core.wording.Word

/**
 * A compact status capsule, as the iPhone app's `DSStatusBadge`: a coloured symbol and short
 * words on a soft tint of the status colour, the words in the status's accessible text colour,
 * digits tabular. It wraps instead of being cut off; a badge of one line is a capsule.
 */
@Composable
fun DSStatusBadge(status: DSStatus, text: String, modifier: Modifier = Modifier) {
    val colors = DS.colors
    Row(
        modifier = modifier
            .semantics(mergeDescendants = true) {}
            .background(colors.status.of(status).copy(alpha = DSTint.FILL), badgeShape())
            .padding(horizontal = DSSpace.xs, vertical = DSSpace.xxs),
        horizontalArrangement = Arrangement.spacedBy(DSSpace.xxs),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        DSIcon(status.symbol, colors.status.of(status), size = DSIconSize.small)
        DSText(
            text,
            DSTextStyle.CAPTION,
            color = colors.statusText.of(status),
            numeric = true,
            fontWeight = FontWeight.SemiBold,
            maxLines = BADGE_LINES,
        )
    }
}

/** A badge that only names its status („Întârziat”, „Rezolvat”). */
@Composable
fun DSStatusBadge(status: DSStatus, modifier: Modifier = Modifier) {
    DSStatusBadge(status, status.title.written(), modifier)
}

/** A badge for a due day, drawn from its urgency: „În 5 zile”, „Azi”, „Depășit de 3 zile”. */
@Composable
fun DSDueBadge(
    urgency: AttentionUrgency,
    daysRemaining: Int,
    modifier: Modifier = Modifier,
    today: CalendarDay = DosarCalendar.today(),
) {
    DSStatusBadge(DSStatus.of(urgency.tone), DSDueText.due(urgency, daysRemaining, today), modifier)
}

/** A badge for an expiry, drawn from its urgency: „Valabil” while nothing is needed yet, then how far it is. */
@Composable
fun DSExpiryBadge(
    urgency: AttentionUrgency,
    daysRemaining: Int,
    modifier: Modifier = Modifier,
    today: CalendarDay = DosarCalendar.today(),
) {
    val status = if (urgency.tone == UrgencyTone.CALM) DSStatus.DONE else DSStatus.of(urgency.tone)
    DSStatusBadge(status, DSDueText.expiry(urgency, daysRemaining, today), modifier)
}

/** „Expirat”, whatever its date says: a document replaced by a new one. */
@Composable
fun DSReplacedBadge(modifier: Modifier = Modifier) {
    DSStatusBadge(DSStatus.OVERDUE, Word.app("Expirat").written(), modifier)
}

/** A small coloured dot, for dense lists where a badge would be noise; TalkBack reads its status. */
@Composable
fun DSStatusDot(status: DSStatus, modifier: Modifier = Modifier) {
    val title = status.title.written()
    Box(
        modifier
            .size(decorationSize(DOT))
            .background(DS.colors.status.of(status), CircleShape)
            .semantics { contentDescription = title },
    )
}

/** A badge's words for a due day or an expiry, from its urgency (the iPhone app's `DSDueText`). */
object DSDueText {
    /** „Azi”, „Mâine”, „În 5 zile”, „Întârziat cu 2 zile”, „Depășit de 3 zile”. */
    fun due(urgency: AttentionUrgency, daysRemaining: Int, today: CalendarDay): String =
        WhenWording.standalone(urgency, daysRemaining, today)

    /**
     * „Valabil” until it needs the person, then „Expiră în 20 de zile”, „Expiră mâine”, „Expiră azi”,
     * „Expirat de 3 zile”.
     */
    fun expiry(urgency: AttentionUrgency, daysRemaining: Int, today: CalendarDay): String {
        if (urgency.tone == UrgencyTone.CALM) return Word.app("Valabil").written()
        val distance = DurationWording.distance(daysRemaining, today)
        return when (urgency) {
            AttentionUrgency.OVERDUE, AttentionUrgency.WITHIN_GRACE ->
                Word.app("Expirat de %@", Word.text(distance)).written()
            AttentionUrgency.TODAY -> Word.app("Expiră azi").written()
            AttentionUrgency.SOON, AttentionUrgency.UPCOMING, AttentionUrgency.LATER ->
                expiresIn(daysRemaining, distance)
        }
    }

    private fun expiresIn(daysRemaining: Int, distance: String): String {
        if (daysRemaining == 1) return Word.app("Expiră mâine").written()
        return Word.app("Expiră %@", Word.text(DurationWording.inside(distance))).written()
    }
}

/**
 * The badge's corners grow with the text, so one line is always a capsule and a badge that wraps
 * at the largest sizes becomes a rounded rectangle, never a tall pill.
 */
@Composable
private fun badgeShape(): Shape = DSContinuousShape(BADGE_RADIUS * LocalDensity.current.fontScale)

private const val BADGE_LINES = 3
private val BADGE_RADIUS = 12.dp
private val DOT = 8.dp
