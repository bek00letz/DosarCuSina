package com.ar.dosarcusina.app.graph

import com.ar.dosarcusina.store.BinderStore
import java.io.File

/**
 * Where the app keeps what it keeps, in its own storage: one place for each, decided here once.
 *
 * - [binder]: the binder's store (its database, the files it names, this phone's lock choices and the
 *   repair list's ledger beside the database), in the app's files, which a move to a new phone brings
 *   along and Android's cloud backup never takes (`res/xml/data_extraction_rules.xml`).
 * - [preferences]: this phone's own small things ([com.ar.dosarcusina.app.phone.PhonePreferences]),
 *   apart from the store, so starting the binder again leaves them.
 * - [undo]: the pictures an undoable step took, kept only while its "Anulează" can bring them back, in
 *   the app's cache, which the phone may empty and a move never brings.
 */
data class AppPlaces(val binder: File, val preferences: File, val undo: File) {
    /** The binder's database file, which the lock choices and the repair ledger sit beside. */
    val database: File get() = File(binder, BinderStore.DATABASE_NAME)

    companion object {
        /** The places under the app's files folder ([files]) and cache folder ([cache]). */
        fun under(files: File, cache: File): AppPlaces = AppPlaces(
            binder = File(files, "binder"),
            preferences = File(files, "preferences.json"),
            undo = File(cache, "Anulare"),
        )
    }
}
