package com.ar.dosarcusina.store

import java.lang.ref.PhantomReference
import java.lang.ref.ReferenceQueue
import java.util.Collections
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.atomic.AtomicBoolean

/**
 * Runs an action once, when asked or once what it belongs to is gone, whichever comes first: the job
 * of `java.lang.ref.Cleaner`, which Android has only from Android 13, while the app runs from
 * Android 11. One daemon thread waits for what is gone, as `Cleaner`'s does.
 */
internal object WhenGone {
    private val queue = ReferenceQueue<Any>()

    /** Every action not run yet, so each stays reachable until its owner goes. */
    private val waiting: MutableSet<Cleanup> = Collections.newSetFromMap(ConcurrentHashMap())

    init {
        Thread(::watch, "WhenGone").apply {
            isDaemon = true
            start()
        }
    }

    /** One action, run at most once. */
    class Cleanup internal constructor(owner: Any, private val action: Runnable) :
        PhantomReference<Any>(owner, queue) {
        private val done = AtomicBoolean(false)

        /** Runs the action now, unless it already ran. */
        fun clean() {
            if (!done.compareAndSet(false, true)) return
            waiting.remove(this)
            action.run()
        }
    }

    /** [action] runs when [owner] is gone, or when its [Cleanup.clean] is called, once. */
    fun register(owner: Any, action: Runnable): Cleanup {
        val cleanup = Cleanup(owner, action)
        waiting.add(cleanup)
        return cleanup
    }

    private fun watch() {
        try {
            while (true) (queue.remove() as? Cleanup)?.clean()
        } catch (_: InterruptedException) {
            // The process is ending.
        }
    }
}
