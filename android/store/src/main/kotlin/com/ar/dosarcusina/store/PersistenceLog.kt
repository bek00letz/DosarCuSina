package com.ar.dosarcusina.store

/**
 * The persistence log: where a step that saves on its own, with no one to tell (launch's steps,
 * a receipt's files), says it failed, as the iOS app's `PersistenceLog`
 * (ios/DosarCuSina/Services/Persistence/PersistenceLog.swift). It names the step and the kind of
 * error only, never a value of the household's: an [Entry] has no room for one. The app writes it
 * to the phone's log; the tests keep what was written.
 */
fun interface PersistenceLog {
    fun write(entry: Entry)

    /** One line: how bad, which step, and the kind of error (its type's name). */
    data class Entry(val level: Level, val step: String, val kind: String)

    enum class Level {
        /** A step failed and was taken back; it is tried again when it next runs. */
        ERROR,

        /** The code broke one of the store's rules (a question asked after its unit wrote). */
        FAULT,
    }

    /** Logs that [step] failed with [error]: its kind, never its message, which may hold a value. */
    fun failed(step: String, error: Throwable) = write(Entry(Level.ERROR, step, kindOf(error)))

    /** Runs [work], and logs it when it fails instead of throwing. Returns whether it succeeded. */
    fun attempt(step: String, work: () -> Unit): Boolean = try {
        work()
        true
    } catch (
        // Every failure of a step that saves on its own is logged and the next step still runs.
        @Suppress("TooGenericExceptionCaught") error: Exception,
    ) {
        failed(step, error)
        false
    }

    companion object {
        /** The kind of [error], as the log names it. */
        fun kindOf(error: Throwable): String = error::class.qualifiedName ?: error::class.java.name
    }
}
