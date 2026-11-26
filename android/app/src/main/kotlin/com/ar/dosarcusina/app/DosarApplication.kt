package com.ar.dosarcusina.app

import android.app.Application
import android.content.Context
import com.ar.dosarcusina.app.graph.AppGraph
import com.ar.dosarcusina.app.graph.AppPlaces
import com.ar.dosarcusina.app.graph.PhoneDatabases
import com.ar.dosarcusina.app.graph.PhoneLog
import com.ar.dosarcusina.app.locale.AppLocale
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.SupervisorJob
import java.util.Locale
import java.util.concurrent.Executors

/**
 * The app as it starts: in Romanian ([AppLocale]), with its one [graph], which opens the binder away
 * from the main thread at once. Screens reach the graph through [appGraph].
 */
class DosarApplication : Application() {
    /** Everything the screens stand on, made once. */
    lateinit var graph: AppGraph
        private set

    /** The app's own work, for as long as it runs. */
    private val scope = CoroutineScope(SupervisorJob())

    override fun onCreate() {
        super.onCreate()
        Locale.setDefault(AppLocale.locale)
        AppLocale.tellTheSystem(this)
        graph = AppGraph(
            places = AppPlaces.under(files = filesDir, cache = cacheDir),
            databases = PhoneDatabases(this),
            log = PhoneLog(),
            preferencesWriter = Executors.newSingleThreadExecutor(::preferencesThread),
        )
        graph.start(scope)
    }

    private fun preferencesThread(work: Runnable) = Thread(work, "Preferences").apply { isDaemon = true }
}

/** The app's one graph, from any of its contexts: an activity's, a screen's (`LocalContext.current`). */
val Context.appGraph: AppGraph get() = (applicationContext as DosarApplication).graph
