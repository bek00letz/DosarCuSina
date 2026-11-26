package com.ar.dosarcusina.store.locks

/**
 * The person's answer that a lock may be turned off: their fingerprint, face or screen lock, asked
 * just now. The iOS app's `LockLowering` (ios/DosarCuSina/Services/Security/BiometricVaultManager.swift).
 *
 * Only a [Confirmation] makes one, and only once it has asked the person and they confirmed; every
 * way of turning a lock off takes one ([CategoryLocks.setLock], [CategoryLocks.keepLocksAsTheyAre],
 * and the app lock when it comes) or throws [Needed], so no lock goes off without asking. Turning a
 * lock on needs none.
 */
class LockLowering private constructor() {
    /** A lock was about to be turned off without asking first; nothing changed. */
    class Needed : IllegalStateException("A lock stays on until the person confirms it may go off")

    /**
     * How the person is asked whether a lock may go off: every time, whether or not anything is
     * unlocked just now. The app asks with the system's prompt (`BiometricPrompt`, with the screen
     * lock as the other way in); the tests confirm or refuse themselves.
     */
    abstract class Confirmation {
        /** Asks the person now, for [reason]; whether they confirmed. Cancelling or failing is a no. */
        protected abstract suspend fun confirmed(reason: String): Boolean

        /** The person's answer, asked now, for [reason]: a lowering when they confirmed, else none. */
        suspend fun confirmLowering(reason: String): LockLowering? = if (confirmed(reason)) LockLowering() else null
    }
}
