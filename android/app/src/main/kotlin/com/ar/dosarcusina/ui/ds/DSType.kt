package com.ar.dosarcusina.ui.ds

import androidx.compose.material3.Typography
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.em

/**
 * The type scale, as the iPhone app's `DSTextStyle`: each style is one of Material's, in sp, so
 * every one follows the phone's font size up to its largest scale; never a size of a screen's
 * own. Large sizes get slightly tighter tracking, like a large title's.
 */
enum class DSTextStyle {
    /** Hero numbers and the largest headlines inside content (not the top bar's title). */
    DISPLAY,

    /** A screen-level headline inside content. */
    TITLE,

    /** Card and section titles. */
    SECTION_TITLE,

    /** Row titles and emphasized labels. */
    HEADLINE,

    /** Default reading text. */
    BODY,

    /** Secondary lines under a title. */
    SUBHEADLINE,

    /** Supporting notes, field hints. */
    FOOTNOTE,

    /** Badges, metadata. */
    CAPTION,

    /** Small emphasized labels such as field captions. */
    CAPTION_EMPHASIZED,
    ;

    /** Drawn in the secondary label colour unless a screen says otherwise. */
    val isSecondary: Boolean get() = this in SECONDARY

    /** The style, from [typography], with its weight and tracking; [numeric] for tabular digits. */
    fun style(typography: Typography, numeric: Boolean = false): TextStyle {
        val base = when (this) {
            DISPLAY -> typography.headlineLarge.copy(fontWeight = FontWeight.Bold, letterSpacing = DISPLAY_TRACKING.em)
            TITLE -> typography.headlineSmall.copy(fontWeight = FontWeight.Bold, letterSpacing = TITLE_TRACKING.em)
            SECTION_TITLE -> typography.titleLarge.copy(fontWeight = FontWeight.SemiBold)
            HEADLINE -> typography.titleMedium.copy(fontWeight = FontWeight.SemiBold)
            BODY -> typography.bodyLarge
            SUBHEADLINE -> typography.bodyMedium
            FOOTNOTE -> typography.bodySmall
            CAPTION -> typography.labelMedium
            CAPTION_EMPHASIZED -> typography.labelMedium.copy(fontWeight = FontWeight.SemiBold)
        }
        return if (numeric) base.copy(fontFeatureSettings = TABULAR_FIGURES) else base
    }

    companion object {
        /** OpenType's tabular figures: digits of one width, so columns line up and numbers don't jitter. */
        const val TABULAR_FIGURES: String = "tnum"
        private const val DISPLAY_TRACKING = -0.02f
        private const val TITLE_TRACKING = -0.01f
        private val SECONDARY = setOf(SUBHEADLINE, FOOTNOTE, CAPTION, CAPTION_EMPHASIZED)
    }
}
