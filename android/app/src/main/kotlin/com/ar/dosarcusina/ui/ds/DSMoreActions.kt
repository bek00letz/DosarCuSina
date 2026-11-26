package com.ar.dosarcusina.ui.ds

import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.sizeIn
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.IconButton
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import com.ar.dosarcusina.core.wording.Word

/** One of a page's extra actions: its words, its symbol and what it does. [id] is stable within the page. */
data class DSMoreAction(
    val id: String,
    val title: String,
    val symbol: DSSymbol,
    val role: DSButtonRole = DSButtonRole.NORMAL,
    val onClick: () -> Unit,
)

/**
 * The one rule for a page's extra actions, as the iPhone app's `DSMoreActionsLayout`: none shows
 * nothing, one shows as itself with its own words, two or more share „Mai multe”. A menu never
 * hides a single item.
 */
enum class DSMoreActionsLayout {
    NOTHING,
    DIRECT,
    MENU,
    ;

    companion object {
        fun of(count: Int): DSMoreActionsLayout = when {
            count < 1 -> NOTHING
            count == 1 -> DIRECT
            else -> MENU
        }
    }
}

/** A page's extra actions in its top bar, by [DSMoreActionsLayout]. */
@Composable
fun DSMoreActionsToolbar(actions: List<DSMoreAction>) {
    when (DSMoreActionsLayout.of(actions.size)) {
        DSMoreActionsLayout.NOTHING -> Unit
        DSMoreActionsLayout.DIRECT -> {
            val only = actions.first()
            TextButton(onClick = only.onClick, modifier = Modifier.sizeIn(minHeight = DSControl.minimumHitTarget)) {
                DSText(only.title, DSTextStyle.BODY, color = inkOf(only.role))
            }
        }
        DSMoreActionsLayout.MENU -> MoreMenu(actions)
    }
}

@Composable
private fun MoreMenu(actions: List<DSMoreAction>) {
    var isOpen by remember { mutableStateOf(false) }
    val more = Word.app("Mai multe").written()
    Box {
        IconButton(onClick = { isOpen = true }, modifier = Modifier.semantics { contentDescription = more }) {
            DSIcon(DSSymbol.MORE, DS.colors.accent)
        }
        DropdownMenu(expanded = isOpen, onDismissRequest = { isOpen = false }) {
            actions.forEach { item ->
                val ink = if (item.role == DSButtonRole.DESTRUCTIVE) DS.colors.statusText.overdue else DS.colors.label
                DropdownMenuItem(
                    text = { DSText(item.title, DSTextStyle.BODY, color = ink) },
                    leadingIcon = { DSIcon(item.symbol, ink) },
                    onClick = {
                        isOpen = false
                        item.onClick()
                    },
                )
            }
        }
    }
}

@Composable
private fun inkOf(role: DSButtonRole) =
    if (role == DSButtonRole.DESTRUCTIVE) DS.colors.statusText.overdue else DS.colors.accent
