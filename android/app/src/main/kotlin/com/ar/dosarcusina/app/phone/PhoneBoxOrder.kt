package com.ar.dosarcusina.app.phone

import com.ar.dosarcusina.catalog.BinderBoxID
import com.ar.dosarcusina.store.templates.BoxOrder
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.distinctUntilChanged
import kotlinx.coroutines.flow.map
import kotlinx.serialization.json.JsonElement

/**
 * The person's order of the binder's boxes on this phone, as the iOS app's `BinderLayoutStore`: only
 * the order is kept, each box as the saved order writes it ([BinderBoxID.storageKey]), under the iOS
 * app's key; which boxes there are always comes from the data. A box this build can't read is left out.
 */
class PhoneBoxOrder(private val preferences: PhonePreferences) : BoxOrder {
    override val saved: List<BinderBoxID> get() = order(preferences[KEY])

    /** The order as it changes: what the grid observes. */
    val changes: Flow<List<BinderBoxID>> get() = preferences.values.map { order(it[KEY]) }.distinctUntilChanged()

    override fun save(order: List<BinderBoxID>) {
        preferences[KEY] = PhoneJson.list(order.map { it.storageKey })
    }

    /** Forgets the order: the boxes go back to theirs. */
    fun reset() {
        preferences[KEY] = null
    }

    private fun order(kept: JsonElement?): List<BinderBoxID> = PhoneJson.strings(kept).mapNotNull { BinderBoxID.of(it) }

    companion object {
        /** The iOS app's key. */
        const val KEY = "binder.boxOrder"
    }
}
