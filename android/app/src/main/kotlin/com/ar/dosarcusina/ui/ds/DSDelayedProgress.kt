package com.ar.dosarcusina.ui.ds

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.size
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.unit.dp
import com.ar.dosarcusina.core.wording.Word
import kotlinx.coroutines.delay

/**
 * A progress indicator that stays invisible for a short delay, so fast work never flashes one,
 * as the iPhone app's `DSDelayedProgress`. Its room is always kept, so nothing jumps when it
 * shows; it fades in with the standard motion. The one progress indicator of the app (the
 * `DosarBareProgress` detekt rule): [label] is the words under it, null when a title nearby
 * already says what is happening.
 */
@Composable
fun DSDelayedProgress(
    modifier: Modifier = Modifier,
    label: String? = Word.app("Se încarcă…").written(),
    delayMillis: Long = DSMotion.PROGRESS_DELAY_MILLIS,
) {
    var isVisible by rememberSaveable { mutableStateOf(false) }
    LaunchedEffect(Unit) {
        delay(delayMillis)
        isVisible = true
    }
    val shown by dsAnimateFloat(if (isVisible) 1f else 0f)
    val spoken = label ?: Word.app("Se încarcă…").written()
    // Hidden from TalkBack until it shows.
    val heard = if (isVisible) Modifier.semantics { contentDescription = spoken } else Modifier.clearAndSetSemantics {}
    Column(
        modifier = modifier
            .alpha(shown)
            .then(heard),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(DSSpace.xs),
    ) {
        CircularProgressIndicator(modifier = Modifier.size(INDICATOR), color = DS.colors.secondaryLabel)
        label?.let { DSText(it, DSTextStyle.FOOTNOTE) }
    }
}

private val INDICATOR = 28.dp
