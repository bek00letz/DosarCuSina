package com.ar.dosarcusina.ui.ds

import androidx.compose.foundation.clickable
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.interaction.PressInteraction
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.hapticfeedback.HapticFeedbackType
import androidx.compose.ui.platform.LocalHapticFeedback
import androidx.compose.ui.semantics.selected
import androidx.compose.ui.semantics.semantics
import com.ar.dosarcusina.core.values.RomanianText
import com.ar.dosarcusina.core.wording.Word
import com.ar.dosarcusina.ui.shell.DSSheet

/**
 * One option out of several, as the iPhone app's `DSChoiceField`: a menu up to [MENU_LIMIT]
 * options, and beyond it a searchable list in a sheet ([DSChoiceList]: a country). [allowsNone]
 * for an optional field, which offers „Niciuna” first.
 */
@Composable
fun <T> DSChoiceField(
    title: String,
    options: List<T>,
    optionTitle: (T) -> String,
    selection: T?,
    onChoose: (T?) -> Unit,
    modifier: Modifier = Modifier,
    validation: DSValidation = DSValidation.Valid,
    footnote: String? = null,
    allowsNone: Boolean = false,
) {
    var isChoosing by remember { mutableStateOf(false) }
    val haptics = LocalHapticFeedback.current
    val choose: (T?) -> Unit = { option ->
        isChoosing = false
        haptics.performHapticFeedback(HapticFeedbackType.SegmentTick)
        onChoose(option)
    }
    val interaction = remember { MutableInteractionSource() }
    LaunchedEffect(interaction) {
        interaction.interactions.collect { if (it is PressInteraction.Release) isChoosing = true }
    }
    Box(modifier) {
        DSOutlinedField(
            FieldLook(title, validation, footnote, placeholder = Word.app("Alege").written()),
            value = selection?.let(optionTitle).orEmpty(),
            onValueChange = {},
            modifier = Modifier,
            singleLine = true,
            keyboard = KeyboardOptions.Default,
            readOnly = true,
            interactionSource = interaction,
            trailing = { DSIcon(DSSymbol.CHEVRON, DS.colors.tertiaryLabel, size = DSIconSize.small) },
        )
        if (options.size <= MENU_LIMIT) {
            DropdownMenu(expanded = isChoosing, onDismissRequest = { isChoosing = false }) {
                if (allowsNone) MenuOption(Word.app("Niciuna").written(), selection == null) { choose(null) }
                options.forEach { option -> MenuOption(optionTitle(option), option == selection) { choose(option) } }
            }
        } else {
            DSSheet(visible = isChoosing, onDismissRequest = { isChoosing = false }) {
                DSChoiceList(title, options, optionTitle, selection, choose, allowsNone = allowsNone)
            }
        }
    }
}

@Composable
private fun MenuOption(title: String, isSelected: Boolean, onClick: () -> Unit) {
    DropdownMenuItem(
        text = { DSText(title, DSTextStyle.BODY) },
        onClick = onClick,
        modifier = Modifier.semantics { selected = isSelected },
        trailingIcon = if (isSelected) ({ DSIcon(DSSymbol.DONE, DS.colors.accent) }) else null,
    )
}

/**
 * Pick one option from a long list, with search, as the iPhone app's `DSChoiceList`: what a long
 * choice field opens, and the question a screen asks on its own. Search folds diacritics and case
 * ([RomanianText.fold]), so „romania” finds „România”. The whole row is the target.
 */
@Composable
fun <T> DSChoiceList(
    title: String,
    options: List<T>,
    optionTitle: (T) -> String,
    selection: T?,
    onChoose: (T?) -> Unit,
    modifier: Modifier = Modifier,
    message: String? = null,
    allowsNone: Boolean = false,
) {
    var query by rememberSaveable { mutableStateOf("") }
    val needle = RomanianText.fold(query.trim())
    val matches = if (needle.isEmpty()) {
        options
    } else {
        options.filter { RomanianText.fold(optionTitle(it)).contains(needle) }
    }
    Column(
        modifier.fillMaxWidth().padding(horizontal = DSSpace.m),
        verticalArrangement = Arrangement.spacedBy(DSSpace.s),
    ) {
        DSText(title, DSTextStyle.HEADLINE)
        message?.takeIf { query.isEmpty() }?.let { DSText(it, DSTextStyle.SUBHEADLINE) }
        DSTextField(Word.app("Caută").written(), query, { query = it })
        LazyColumn {
            if (allowsNone && query.isEmpty()) {
                item { ListOption(Word.app("Niciuna").written(), selection == null) { onChoose(null) } }
            }
            items(matches) { option -> ListOption(optionTitle(option), option == selection) { onChoose(option) } }
        }
    }
}

@Composable
private fun ListOption(title: String, isSelected: Boolean, onClick: () -> Unit) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .heightIn(min = DSControl.minimumHitTarget)
            .clickable(onClick = onClick)
            .semantics(mergeDescendants = true) { selected = isSelected },
        horizontalArrangement = Arrangement.spacedBy(DSSpace.s),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        DSText(title, DSTextStyle.BODY, Modifier.weight(1f))
        if (isSelected) DSIcon(DSSymbol.DONE, DS.colors.accent)
    }
}

/** A choice field is a menu up to this many options, and a searchable list beyond. */
const val MENU_LIMIT: Int = 24
