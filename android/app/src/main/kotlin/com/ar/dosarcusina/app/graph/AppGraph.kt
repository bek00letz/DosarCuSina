package com.ar.dosarcusina.app.graph

import com.ar.dosarcusina.app.phone.PhoneBoxOrder
import com.ar.dosarcusina.app.phone.PhonePreferences
import com.ar.dosarcusina.app.phone.PhoneRecentSearches
import com.ar.dosarcusina.app.phone.PhoneTrips
import com.ar.dosarcusina.app.wording.AppHistoryWording
import com.ar.dosarcusina.catalog.Catalog
import com.ar.dosarcusina.core.readiness.TripPlans
import com.ar.dosarcusina.store.BinderStore
import com.ar.dosarcusina.store.ChangeOrigin
import com.ar.dosarcusina.store.DatabaseBuilders
import com.ar.dosarcusina.store.PersistenceLog
import com.ar.dosarcusina.store.Tables
import com.ar.dosarcusina.store.UndoFiles
import com.ar.dosarcusina.store.UnitOfWork
import com.ar.dosarcusina.store.history.HistoryWording
import com.ar.dosarcusina.store.locks.CategoryLocks
import com.ar.dosarcusina.store.repairs.DataRepairCenter
import com.ar.dosarcusina.store.repairs.DataRepairLedger
import com.ar.dosarcusina.store.repairs.DataRepairs
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.launch
import java.time.Instant
import java.util.concurrent.Executor
import kotlin.coroutines.CoroutineContext

/** Where the binder stands as the app starts: what a screen shows before it can read anything. */
sealed interface BinderState {
    /** Opening, and doing what the app does at every start: a screen waits, without a flash. */
    data object Opening : BinderState

    /** Open and ready. */
    class Ready(val binder: OpenBinder) : BinderState

    /** It couldn't be opened; [kind] names the kind of error, never a value. */
    data class CouldNotOpen(val kind: String) : BinderState
}

/**
 * Everything the screens stand on, made once when the app starts and handed to them by hand: the
 * binder ([binder], once open), this phone's own small things ([boxOrder], [trips],
 * [recentSearches]) and the words the store writes with ([wording]). No framework: each piece is
 * made here from the ones before it, so there is one of each and one way to reach it.
 *
 * Making the graph does no reading or writing. [start] opens the binder away from the main thread
 * and runs what the app does at every start ([com.ar.dosarcusina.store.LaunchData]), and [binder]
 * says when it is ready.
 */
class AppGraph(
    val places: AppPlaces,
    /** Room's builder for the database: the phone's in the app. */
    private val databases: DatabaseBuilders,
    /** Where a step that fails with no one to tell is logged: the phone's log in the app. */
    val log: PersistenceLog,
    /** Where this phone's preferences are written, one at a time. */
    preferencesWriter: Executor,
    /** The moment a step saves when it has no clock of its own. */
    private val clock: () -> Instant = Instant::now,
) {
    /** This phone's own small things, in one file. */
    val preferences = PhonePreferences(places.preferences, preferencesWriter, log)

    /** The person's order of the binder's boxes, on this phone. */
    val boxOrder = PhoneBoxOrder(preferences)

    /** The trips, on this phone only. */
    val trips = TripPlans(PhoneTrips(preferences))

    /** The last few searches, on this phone only. */
    val recentSearches = PhoneRecentSearches(preferences)

    /** The words a record of history is titled with. */
    val wording: HistoryWording = AppHistoryWording

    private val state = MutableStateFlow<BinderState>(BinderState.Opening)
    private var started: Job? = null

    /** Where the binder stands: what screens observe. */
    val binder: StateFlow<BinderState> = state.asStateFlow()

    /** Opens the binder in [scope] on [context] (never the main thread), once; later calls give the same work. */
    fun start(scope: CoroutineScope, context: CoroutineContext = Dispatchers.IO): Job = synchronized(this) {
        started ?: scope.launch(context) { state.value = open() }.also { started = it }
    }

    /** The binder once it is open; none when it couldn't be. */
    suspend fun ready(): OpenBinder? = when (val opened = binder.first { it !is BinderState.Opening }) {
        is BinderState.Ready -> opened.binder
        else -> null
    }

    /**
     * What [start] does, on the thread that calls it: what an earlier run left for undo goes, this
     * phone's preferences are read, the store opens with its unit of work, locks and repair list, and
     * the app's start-up steps run, each logged if it fails while the next still runs.
     */
    internal fun open(): BinderState {
        UndoFiles.removeLeftovers(places.undo)
        preferences.load()
        return try {
            val binder = assemble(BinderStore.open(places.binder, databases))
            reads(binder)
            binder.launch.prepare(clock())
            BinderState.Ready(binder)
        } catch (
            // Whatever stops the store opening is shown as one state, and logged by its kind.
            @Suppress("TooGenericExceptionCaught") error: Exception,
        ) {
            log.failed(OPENING, error)
            BinderState.CouldNotOpen(PersistenceLog.kindOf(error))
        }
    }

    /** Reads the binder once, which opens the database and brings it to the current version; closes it if it can't. */
    private fun reads(binder: OpenBinder) {
        runCatching { binder.unit.perform(ChangeOrigin.APP) { it.all(Tables.templates).size } }
            .onFailure { binder.store.close() }
            .getOrThrow()
    }

    private fun assemble(store: BinderStore): OpenBinder {
        val locks = CategoryLocks(store.locks, Catalog.builtIn)
        val unit = UnitOfWork(store, locks, log, clock, places.undo)
        val repairs = DataRepairCenter(DataRepairs(unit, DataRepairLedger.forStore(places.database)))
        return OpenBinder(store, unit, locks, repairs, wording)
    }

    private companion object {
        const val OPENING = "Opening the binder"
    }
}
