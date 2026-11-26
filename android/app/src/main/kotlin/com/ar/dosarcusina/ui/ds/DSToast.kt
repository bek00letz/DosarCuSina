package com.ar.dosarcusina.ui.ds

import androidx.compose.runtime.Stable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.compose.runtime.staticCompositionLocalOf
import com.ar.dosarcusina.core.wording.Word
import java.util.UUID

/**
 * What „Anulează” takes back: the receipt of the step just taken (the store's `UndoReceipt`, which
 * `UnitOfWork.performUndoable` makes). The toast shows its button only while [canUndo].
 */
interface DSUndo {
    val canUndo: Boolean

    /** Takes the step back; throws when it can't (something changed it since), and the toast says so. */
    fun undo()
}

/** How a toast looks: what just happened. */
enum class DSToastTone(val symbol: DSSymbol) {
    DONE(DSSymbol.DONE),
    DELETED(DSSymbol.TRASH),
    FAILURE(DSSymbol.OVERDUE),
}

/**
 * A short-lived confirmation with an optional „Anulează”, floating above the content, as the
 * iPhone app's `DSToast`: preferred over „Are you sure?” for anything that can be taken back.
 * [title] is what just happened („ITP: gata”), [undo] what its button takes back, [offer] a small
 * next step beside it („Adaugă o notă”). [whenGone] runs once when it leaves without its button
 * used. TalkBack reads it, and it stays twice as long while TalkBack is on.
 */
data class DSToast(
    val title: String,
    val tone: DSToastTone = DSToastTone.DONE,
    val undo: DSUndo? = null,
    val afterUndo: (() -> Unit)? = null,
    val offer: Offer? = null,
    val whenGone: (() -> Unit)? = null,
    val durationMillis: Long = STANDARD_MILLIS,
    val id: String = UUID.randomUUID().toString(),
) {
    /** A next step a toast offers: its words and what it does. Using it closes the toast. */
    data class Offer(val title: String, val onClick: () -> Unit)

    /** Whether the toast shows „Anulează”. */
    val offersUndo: Boolean get() = undo?.canUndo == true

    companion object {
        const val STANDARD_MILLIS: Long = 5_000

        /** A deletion's toast, and one that offers a next step: long enough to read and choose. */
        const val LONGER_MILLIS: Long = 8_000

        /** A saved change the person can take back. */
        fun undo(title: String, receipt: DSUndo, afterUndo: (() -> Unit)? = null): DSToast =
            DSToast(title, undo = receipt, afterUndo = afterUndo)

        /** Something deleted, with „Anulează” to bring it back whole. */
        fun undoDeletion(title: String, receipt: DSUndo): DSToast =
            DSToast(title, tone = DSToastTone.DELETED, undo = receipt, durationMillis = LONGER_MILLIS)

        /** A failed save or undo, said in plain words with what to do next ([message], the caller's). */
        fun failure(message: String): DSToast = DSToast(message, tone = DSToastTone.FAILURE)

        /** The words of an undo that didn't work. */
        internal val undoFailed: String
            get() = Word.app("Nu am putut salva. Încearcă din nou; dacă tot nu merge, repornește aplicația.").written()
    }
}

/**
 * Where a toast that must outlive its screen is shown, as the iPhone app's `DSToastCenter`: the
 * shell's, above the navigation bar on whichever tab is open. Deleting a section closes its page,
 * but its „Anulează” stays. Screens reach it with [LocalToastCenter]. Only the newest toast shows.
 */
@Stable
class DSToastCenter {
    var toast: DSToast? by mutableStateOf(null)
        private set

    /** Shows [next] in place of whatever shows; the one before is told it left unused. */
    fun show(next: DSToast) {
        toast?.takeIf { it.id != next.id }?.whenGone?.invoke()
        toast = next
    }

    /** The toast leaves: its time passed, it was swiped away, or its button was used ([used]). */
    fun dismiss(id: String, used: Boolean = false) {
        val current = toast?.takeIf { it.id == id } ?: return
        if (!used) current.whenGone?.invoke()
        toast = null
    }

    /** Its „Anulează”: the receipt takes the step back, or a failure says why in its place. */
    fun takeBack(shown: DSToast) {
        val receipt = shown.undo ?: return
        runCatching { receipt.undo() }
            .onSuccess {
                dismiss(shown.id, used = true)
                shown.afterUndo?.invoke()
            }
            .onFailure { show(DSToast.failure(DSToast.undoFailed)) }
    }

    /** Its offered next step: the toast closes and the step runs. */
    fun take(shown: DSToast) {
        val offer = shown.offer ?: return
        dismiss(shown.id, used = true)
        offer.onClick()
    }
}

/** The shell's toast center; null outside the shell (the gallery shows its own). */
val LocalToastCenter = staticCompositionLocalOf<DSToastCenter?> { null }
