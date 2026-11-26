package com.ar.dosarcusina.store.repairs

import com.ar.dosarcusina.archive.v3.FieldValue
import com.ar.dosarcusina.archive.v3.FieldValues
import com.ar.dosarcusina.core.values.KeptObject
import com.ar.dosarcusina.store.TestBinderStore
import com.ar.dosarcusina.store.bucharest
import com.ar.dosarcusina.store.schema.Asset
import com.ar.dosarcusina.store.schema.BinderDatabase
import com.ar.dosarcusina.store.schema.keptValues
import com.ar.dosarcusina.store.schema.withKeptValues
import kotlinx.coroutines.runBlocking
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertTrue

/** A repair list over [binder] with a ledger of its own, as the iOS tests' `repairs(_:)`. */
fun repairs(binder: TestBinderStore, ledger: DataRepairLedger = DataRepairLedger(file = null)): DataRepairs =
    DataRepairs(binder.unit, ledger, zone = { bucharest })

/**
 * Applies [step]'s findings, then checks a second detection finds none and a second apply of the same
 * findings changes nothing (the iOS tests' `applyTwice`). Gives what was found.
 */
fun applyTwice(binder: TestBinderStore, step: DataRepairStepId, check: () -> Unit): List<DataRepairFinding> {
    val list = repairs(binder)
    val found = list.detect().filter { it.step == step }
    assertTrue(found.isNotEmpty(), "$step finds its fixture")
    list.apply(found)
    check()
    val again = list.detect().filter { it.step == step }
    assertEquals(emptyList<DataRepairFinding>(), again, "$step finds nothing once applied")
    val before = binder.database()
    list.apply(found)
    check()
    assertEquals(before, binder.database(), "Applying again changes nothing")
    return found
}

/** Writes straight into the database, around the unit of work, as an earlier version saved it. */
fun <T> TestBinderStore.earlier(write: suspend (BinderDatabase) -> T): T = runBlocking { write(store.database) }

/** [this] section with [values] laid over its own. */
fun Asset.with(vararg values: Pair<String, FieldValue>): Asset {
    var kept: FieldValues = keptValues.value
    for ((key, value) in values) kept = kept.with(key, value)
    return withKeptValues(KeptObject.made(kept, FieldValues.codec))
}
