package com.ar.dosarcusina.ui.ds

import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.selection.toggleable
import androidx.compose.material3.ripple
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.hapticfeedback.HapticFeedbackType
import androidx.compose.ui.platform.LocalHapticFeedback
import androidx.compose.ui.semantics.Role

/**
 * A whole-row check, at least 48 dp tall, as the iPhone app's `DSCheckRow`: checklist parts,
 * reminder choices, one pick out of several. The row is the target, never a tiny checkbox.
 * [detail] shows under the row only while it is checked, and may hold fields. [isRadio] for one
 * pick out of several (TalkBack says so).
 */
@Composable
fun DSCheckRow(
    title: String,
    isOn: Boolean,
    onToggle: (Boolean) -> Unit,
    modifier: Modifier = Modifier,
    subtitle: String? = null,
    isRadio: Boolean = false,
    detail: (@Composable () -> Unit)? = null,
) {
    val colors = DS.colors
    val haptics = LocalHapticFeedback.current
    val interaction = remember { MutableInteractionSource() }
    Column(modifier.fillMaxWidth(), verticalArrangement = Arrangement.spacedBy(DSSpace.xs)) {
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .heightIn(min = DSControl.minimumHitTarget)
                .toggleable(
                    value = isOn,
                    interactionSource = interaction,
                    indication = ripple(),
                    role = if (isRadio) Role.RadioButton else Role.Checkbox,
                ) { checked ->
                    val feedback = if (checked) HapticFeedbackType.ToggleOn else HapticFeedbackType.ToggleOff
                    haptics.performHapticFeedback(feedback)
                    onToggle(checked)
                },
            horizontalArrangement = Arrangement.spacedBy(DSSpace.s),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            val tint by dsAnimateColor(if (isOn) colors.accent else colors.tertiaryLabel)
            DSIcon(if (isOn) DSSymbol.DONE else DSSymbol.UNCHECKED, tint, size = DSIconSize.large)
            Column(Modifier.weight(1f)) {
                DSText(title, DSTextStyle.BODY)
                subtitle?.let { DSText(it, DSTextStyle.FOOTNOTE) }
            }
        }
        if (detail != null) DSAnimatedVisibility(visible = isOn, edge = DSEdge.TOP) { detail() }
    }
}
