package com.ar.dosarcusina.app.locale

import android.app.LocaleManager
import android.content.Context
import android.content.res.Configuration
import android.os.Build
import android.os.LocaleList
import java.util.Locale

/**
 * The app writes Romanian on every phone, whatever language the phone is set to, as the iOS app's
 * `Locale.dosarDefault`: its own words are Romanian already (the default resources), and this makes
 * what Android writes for it Romanian too (a date picker's months, the screen reader's voice, line
 * breaks). The app's one language is declared in `res/xml/locales_config.xml`, so the phone's
 * settings offer no other.
 *
 * Android 13 and later keep an app's language themselves: the app asks once ([tellTheSystem]) and the
 * phone applies it everywhere. Before that, each activity, which is what draws, is given the language
 * in its `attachBaseContext` ([wrap]), and the app's default locale is the app's from its start. (The
 * application's own context is left as the phone made it: wrapping it can change what
 * `applicationContext` is.)
 */
object AppLocale {
    /** The app's one language, as a language tag. */
    const val TAG = "ro"

    /** The app's one language. */
    val locale: Locale = Locale.forLanguageTag(TAG)

    /** Whether the languages the phone keeps for the app (their tags, in order) are the app's alone. */
    fun isApplied(tags: String): Boolean = tags == TAG

    /** [base] with the app's language: for `attachBaseContext`. */
    fun wrap(base: Context): Context {
        Locale.setDefault(locale)
        val configuration = Configuration(base.resources.configuration)
        configuration.setLocales(LocaleList(locale))
        return base.createConfigurationContext(configuration)
    }

    /** Asks the phone to keep the app's language, from Android 13, unless it already does. */
    fun tellTheSystem(context: Context) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU) return
        val manager = context.getSystemService(LocaleManager::class.java) ?: return
        if (!isApplied(manager.applicationLocales.toLanguageTags())) {
            manager.applicationLocales = LocaleList.forLanguageTags(TAG)
        }
    }
}
