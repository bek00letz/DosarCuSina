package com.ar.dosarcusina.store.examples

import com.ar.dosarcusina.core.wording.Word
import com.ar.dosarcusina.store.UndoReceipt
import com.ar.dosarcusina.store.schema.Asset

/**
 * Removing the examples, the same step wherever it is offered: on the binder, where the examples
 * are, and in Setări › Exemple, as the iOS app's `ExampleRemoval`
 * (ios/DosarCuSina/Views/Dosar/ExampleRemoval.swift). One undoable step
 * ([ExampleDataService.removeExamples]); the toast takes it back, so it asks nothing first.
 */
object ExampleRemoval {
    /** Whether the binder offers „Șterge exemplele”: while any example is in it. */
    fun isOffered(assets: List<Asset>): Boolean = assets.any { it.isExample }

    /** Removes every example; the toast says so, and „Anulează” brings every one back. */
    fun remove(examples: ExampleDataService): Removed {
        val removed = examples.removeExamples()
        return Removed(removed.receipt, removed.value)
    }

    /** What removing did: the receipt that takes it back, and the sections kept as the person's. */
    class Removed(val receipt: UndoReceipt, val kept: List<String>) {
        /** The toast's words: what the person added to an example stays theirs, and it says that too. */
        val toast: Word
            get() = if (kept.isEmpty()) {
                Word.app("Am șters exemplele.")
            } else {
                Word.app("Am șters exemplele. Ce ai pus tu în ele a rămas al tău.")
            }
    }
}
