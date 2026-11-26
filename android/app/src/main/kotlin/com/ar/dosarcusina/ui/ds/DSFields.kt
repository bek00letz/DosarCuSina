package com.ar.dosarcusina.ui.ds

import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material3.IconButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.OutlinedTextFieldDefaults
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.focus.FocusRequester
import androidx.compose.ui.focus.onFocusChanged
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.input.KeyboardCapitalization
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.input.PasswordVisualTransformation
import androidx.compose.ui.text.input.VisualTransformation
import com.ar.dosarcusina.core.wording.Word

// The fields, one per kind of value, as the iPhone app's DS…Field controls: Android's own outlined
// field, its label above the value, the problem or a footnote under it, a focus ring in the accent,
// at least 56 dp tall and growing with the text. A field's problem shows once the person leaves it,
// or at once after a refused save (DSRevealsValidation), which can take the person to it.

/** A field for words: a name, a note, a plate. [singleLine] false for a note that grows. */
@Composable
fun DSTextField(
    title: String,
    value: String,
    onValueChange: (String) -> Unit,
    modifier: Modifier = Modifier,
    validation: DSValidation = DSValidation.Valid,
    footnote: String? = null,
    placeholder: String? = null,
    singleLine: Boolean = true,
    keyboard: KeyboardOptions = KeyboardOptions(capitalization = KeyboardCapitalization.Sentences),
) {
    DSOutlinedField(
        FieldLook(title, validation, footnote, placeholder),
        value,
        onValueChange,
        modifier,
        singleLine = singleLine,
        keyboard = keyboard,
    )
}

/**
 * A field for a secret such as an API key or a PIN code, as the iPhone app's `DSSecureField`:
 * hidden while typing unless the person shows it, never corrected or suggested.
 */
@Composable
fun DSSecretField(
    title: String,
    value: String,
    onValueChange: (String) -> Unit,
    modifier: Modifier = Modifier,
    validation: DSValidation = DSValidation.Valid,
    footnote: String? = null,
) {
    var isShown by rememberSaveable { mutableStateOf(false) }
    val toggle = Word.app(if (isShown) "Ascunde" else "Arată").written()
    DSOutlinedField(
        FieldLook(title, validation, footnote, placeholder = null),
        value,
        onValueChange,
        modifier,
        singleLine = true,
        keyboard = KeyboardOptions(keyboardType = KeyboardType.Password, autoCorrectEnabled = false),
        transformation = if (isShown) VisualTransformation.None else PasswordVisualTransformation(),
        trailing = {
            IconButton(
                onClick = { isShown = !isShown },
                modifier = Modifier.semantics { contentDescription = toggle },
            ) {
                DSIcon(if (isShown) DSSymbol.HIDE else DSSymbol.SHOW, DS.colors.secondaryLabel)
            }
        },
    )
}

/** What a field says around its value. */
internal data class FieldLook(
    val title: String,
    val validation: DSValidation,
    val footnote: String?,
    val placeholder: String?,
)

/** The outlined field every DS text field draws, with its problem's visibility and the reveal's target. */
@Composable
internal fun DSOutlinedField(
    look: FieldLook,
    value: String,
    onValueChange: (String) -> Unit,
    modifier: Modifier,
    singleLine: Boolean,
    keyboard: KeyboardOptions,
    transformation: VisualTransformation = VisualTransformation.None,
    readOnly: Boolean = false,
    interactionSource: MutableInteractionSource? = null,
    trailing: (@Composable () -> Unit)? = null,
) {
    val colors = DS.colors
    var hadFocus by remember { mutableStateOf(false) }
    var hasLeft by rememberSaveable { mutableStateOf(false) }
    val shown = DSValidationVisibility.shown(look.validation, hasLeft, LocalRevealsValidation.current)
    val focus = remember { FocusRequester() }
    OutlinedTextField(
        value = value,
        onValueChange = onValueChange,
        modifier = modifier
            .fillMaxWidth()
            .heightIn(min = DSControl.minimumHitTarget)
            .onFocusChanged { state ->
                if (hadFocus && !state.isFocused) hasLeft = true
                hadFocus = state.isFocused
            }
            .dsValidationTarget((shown as? DSValidation.Invalid)?.message, focus),
        label = { DSText(look.title, DSTextStyle.SUBHEADLINE, color = null) },
        placeholder = look.placeholder?.let { { DSText(it, DSTextStyle.BODY, color = colors.tertiaryLabel) } },
        supportingText = (shown.message ?: look.footnote)?.let { line -> { FieldMessage(line, shown) } },
        isError = shown is DSValidation.Invalid,
        singleLine = singleLine,
        readOnly = readOnly,
        keyboardOptions = keyboard,
        visualTransformation = transformation,
        trailingIcon = trailing,
        interactionSource = interactionSource,
        shape = DSShapes.control,
        colors = OutlinedTextFieldDefaults.colors(
            focusedBorderColor = colors.accent,
            unfocusedBorderColor = colors.separator,
            errorBorderColor = colors.status.overdue,
            cursorColor = colors.accent,
            focusedLabelColor = colors.accent,
        ),
    )
}

/** The line under a field: its problem with a symbol, or its footnote. */
@Composable
private fun FieldMessage(line: String, shown: DSValidation) {
    val colors = DS.colors
    val ink = when (shown) {
        is DSValidation.Invalid -> colors.statusText.overdue
        is DSValidation.Warning -> colors.statusText.soon
        DSValidation.Valid -> colors.secondaryLabel
    }
    DSText(line, DSTextStyle.FOOTNOTE, color = ink)
}
