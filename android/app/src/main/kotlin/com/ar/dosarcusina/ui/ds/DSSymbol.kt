package com.ar.dosarcusina.ui.ds

import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.rounded.ArrowBack
import androidx.compose.material.icons.automirrored.rounded.KeyboardArrowRight
import androidx.compose.material.icons.rounded.Add
import androidx.compose.material.icons.rounded.AddCircle
import androidx.compose.material.icons.rounded.CalendarToday
import androidx.compose.material.icons.rounded.CheckCircle
import androidx.compose.material.icons.rounded.Close
import androidx.compose.material.icons.rounded.Delete
import androidx.compose.material.icons.rounded.Description
import androidx.compose.material.icons.rounded.Error
import androidx.compose.material.icons.rounded.FolderOpen
import androidx.compose.material.icons.rounded.GridView
import androidx.compose.material.icons.rounded.Info
import androidx.compose.material.icons.rounded.Lock
import androidx.compose.material.icons.rounded.MoreVert
import androidx.compose.material.icons.rounded.People
import androidx.compose.material.icons.rounded.RadioButtonUnchecked
import androidx.compose.material.icons.rounded.Report
import androidx.compose.material.icons.rounded.Schedule
import androidx.compose.material.icons.rounded.Search
import androidx.compose.material.icons.rounded.Settings
import androidx.compose.material.icons.rounded.Visibility
import androidx.compose.material.icons.rounded.VisibilityOff
import androidx.compose.material.icons.rounded.Warning
import androidx.compose.ui.graphics.vector.ImageVector

/**
 * The symbols the app draws, each named for what it means and matched to the iPhone app's SF
 * Symbol ([systemName]) with Material's rounded icon of the same weight. Screens draw a [DSSymbol],
 * never an icon of their own, so one meaning has one picture everywhere. A category's symbol from
 * the catalog (an SF Symbol's name) is found with [of].
 */
enum class DSSymbol(val systemName: String, val vector: ImageVector) {
    OVERDUE("exclamationmark.circle.fill", Icons.Rounded.Error),
    SOON("clock.fill", Icons.Rounded.Schedule),
    CALENDAR("calendar", Icons.Rounded.CalendarToday),
    DONE("checkmark.circle.fill", Icons.Rounded.CheckCircle),
    UNCHECKED("circle", Icons.Rounded.RadioButtonUnchecked),
    WARNING("exclamationmark.triangle.fill", Icons.Rounded.Warning),
    INFO("info.circle.fill", Icons.Rounded.Info),
    ERROR("xmark.octagon.fill", Icons.Rounded.Report),
    LOCK("lock.fill", Icons.Rounded.Lock),
    ADD("plus", Icons.Rounded.Add),
    CHEVRON("chevron.forward", Icons.AutoMirrored.Rounded.KeyboardArrowRight),
    BACK("chevron.backward", Icons.AutoMirrored.Rounded.ArrowBack),
    MORE("ellipsis.circle", Icons.Rounded.MoreVert),
    CLOSE("xmark", Icons.Rounded.Close),
    TRASH("trash.fill", Icons.Rounded.Delete),
    SEARCH("magnifyingglass", Icons.Rounded.Search),
    BINDER("square.grid.2x2.fill", Icons.Rounded.GridView),
    ADD_CIRCLE("plus.circle.fill", Icons.Rounded.AddCircle),
    SETTINGS("gearshape.fill", Icons.Rounded.Settings),
    PEOPLE("person.2.fill", Icons.Rounded.People),
    SHOW("eye", Icons.Rounded.Visibility),
    HIDE("eye.slash", Icons.Rounded.VisibilityOff),
    DOCUMENT("doc.text.fill", Icons.Rounded.Description),
    FOLDER("folder", Icons.Rounded.FolderOpen),
    ;

    companion object {
        private val bySystemName = entries.associateBy { it.systemName }

        /**
         * The symbol for an SF Symbol's name, as the catalog stores a category's: the one matched to
         * it, else [FOLDER]. A category's symbols are added here as their screens come.
         */
        fun of(systemName: String?): DSSymbol = systemName?.let(bySystemName::get) ?: FOLDER
    }
}
