package com.ar.dosarcusina.app.graph

import android.util.Log
import com.ar.dosarcusina.store.PersistenceLog

/**
 * The persistence log on the phone: each entry is one line of the phone's log (`android.util.Log`),
 * written from the entry alone, which has room for its level, its step and the kind of error and
 * nothing else, so no value of the household's ever reaches it.
 */
class PhoneLog(
    /** Where a line goes: the phone's log, or a test's list. */
    private val sink: (String) -> Unit = { Log.e(TAG, it) },
) : PersistenceLog {
    override fun write(entry: PersistenceLog.Entry) = sink(line(entry))

    companion object {
        /** The tag the app's lines carry in the phone's log. */
        const val TAG = "DosarCuSina"

        /** One entry as a line: „ERROR Installing the built-in categories: java.io.IOException”. */
        fun line(entry: PersistenceLog.Entry): String = "${entry.level.name} ${entry.step}: ${entry.kind}"
    }
}
