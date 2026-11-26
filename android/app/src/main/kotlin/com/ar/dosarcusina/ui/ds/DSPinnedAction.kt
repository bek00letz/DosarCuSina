package com.ar.dosarcusina.ui.ds

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.WindowInsetsSides
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.ime
import androidx.compose.foundation.layout.navigationBars
import androidx.compose.foundation.layout.only
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.union
import androidx.compose.foundation.layout.windowInsetsPadding
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.layout.onSizeChanged
import androidx.compose.ui.platform.LocalDensity

/**
 * A screen or sheet with its main action pinned to the bottom edge, as the iPhone app's
 * `dsPinnedAction`: it shows whatever the sheet's height and the font size, above the navigation
 * bar and the keyboard, and the content scrolls under it; never at the end of scrolling content.
 * What goes with the action is in the same bar, in one order: [note] above it (why it can't be
 * pressed yet, why the last save didn't work), the [action], then [secondary] actions under it.
 * The one bottom bar: never one drawn by hand.
 *
 * [content] is given the padding that keeps its last row clear of the bar.
 */
@Composable
fun DSPinnedActionScaffold(
    action: @Composable () -> Unit,
    modifier: Modifier = Modifier,
    note: (@Composable () -> Unit)? = null,
    secondary: (@Composable () -> Unit)? = null,
    content: @Composable (PaddingValues) -> Unit,
) {
    var barHeight by remember { mutableIntStateOf(0) }
    val density = LocalDensity.current
    Box(modifier.fillMaxSize()) {
        content(PaddingValues(bottom = with(density) { barHeight.toDp() }))
        Column(
            modifier = Modifier
                .align(Alignment.BottomCenter)
                .fillMaxWidth()
                .background(DS.colors.surface)
                .onSizeChanged { barHeight = it.height },
        ) {
            DSHairline()
            Column(
                modifier = Modifier
                    .windowInsetsPadding(AboveBarsAndKeyboard)
                    .dsReadableWidth()
                    .padding(horizontal = DSSpace.m, vertical = DSSpace.s),
                verticalArrangement = Arrangement.spacedBy(DSSpace.s),
            ) {
                note?.invoke()
                action()
                secondary?.invoke()
            }
        }
    }
}

/** The bar keeps clear of the navigation bar, and rises above the keyboard while one is up. */
private val AboveBarsAndKeyboard: WindowInsets
    @Composable get() = WindowInsets.navigationBars.union(WindowInsets.ime).only(WindowInsetsSides.Bottom)
