package com.ar.dosarcusina.ui.ds.gallery

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.unit.Density
import com.ar.dosarcusina.ui.ds.DS
import com.ar.dosarcusina.ui.ds.DSHairline
import com.ar.dosarcusina.ui.ds.DSSpace
import com.ar.dosarcusina.ui.ds.DSText
import com.ar.dosarcusina.ui.ds.DSTextStyle
import com.ar.dosarcusina.ui.ds.DosarTheme
import com.ar.dosarcusina.ui.ds.LocalReduceMotion
import com.ar.dosarcusina.ui.ds.dsReadableWidth

/**
 * Every component of the design system, as the iPhone app's `DesignSystemGallery`: each entry
 * drawn three times, in the light theme, the dark theme and at the largest font scale, so a
 * component that breaks in one of them shows here first. A new component gets an entry
 * ([GalleryEntries]). For development: Settings opens it in a debug build.
 */
@Composable
fun DesignSystemGallery(modifier: Modifier = Modifier, entries: List<GalleryEntry> = GalleryEntries.all) {
    LazyColumn(
        modifier = modifier.background(DS.colors.background),
        verticalArrangement = Arrangement.spacedBy(DSSpace.xl),
    ) {
        items(entries, key = { it.name }) { entry -> GalleryEntryView(entry) }
    }
}

/** One component in the gallery: its name (the code's) and a sample of it. */
class GalleryEntry(val name: String, val sample: @Composable () -> Unit)

/** The three ways each entry is drawn. */
enum class GalleryVariant(val label: String, val dark: Boolean, val fontScale: Float?) {
    LIGHT(GallerySamples.LIGHT, dark = false, fontScale = null),
    DARK(GallerySamples.DARK, dark = true, fontScale = null),

    /** The largest font scale Android offers (200 %). */
    LARGEST_TEXT(GallerySamples.LARGEST_TEXT, dark = false, fontScale = LARGEST_FONT_SCALE),
}

/** The largest font scale Android's settings offer. */
const val LARGEST_FONT_SCALE: Float = 2f

@Composable
private fun GalleryEntryView(entry: GalleryEntry) {
    Column(
        Modifier.dsReadableWidth().padding(horizontal = DSSpace.m),
        verticalArrangement = Arrangement.spacedBy(DSSpace.s),
    ) {
        DSText(entry.name, DSTextStyle.SECTION_TITLE)
        GalleryVariant.entries.forEach { variant -> GalleryVariantView(variant, entry) }
        DSHairline()
    }
}

/** [entry] in [variant]'s theme and font scale. */
@Composable
fun GalleryVariantView(variant: GalleryVariant, entry: GalleryEntry) {
    val density = LocalDensity.current
    val scaled = Density(density.density, variant.fontScale ?: density.fontScale)
    DosarTheme(dark = variant.dark, highContrast = false, reduceMotion = LocalReduceMotion.current) {
        CompositionLocalProvider(LocalDensity provides scaled) {
            Column(
                Modifier.fillMaxWidth().background(DS.colors.background).padding(DSSpace.s),
                verticalArrangement = Arrangement.spacedBy(DSSpace.xs),
            ) {
                DSText(variant.label, DSTextStyle.CAPTION_EMPHASIZED)
                Box(Modifier.fillMaxWidth()) { entry.sample() }
            }
        }
    }
}
