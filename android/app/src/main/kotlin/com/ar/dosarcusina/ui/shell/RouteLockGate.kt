package com.ar.dosarcusina.ui.shell

import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.staticCompositionLocalOf

/**
 * The seam the section locks plug into (Phase 6 brings the phone's own unlock): whether a lock
 * keeps what it guards closed right now, and what it shows in its place. The one answer for every
 * route, sheet and screen, as the iPhone app's `RouteLockGate` with `BiometricVaultManager`. An
 * implementation reads snapshot state, so a lock that opens or comes back is followed at once.
 */
interface LockGate {
    /**
     * Whether [lock] keeps its content closed now: a [RouteLock.Section] while its category is
     * locked and the session closed (a section whose category isn't known counts as locked), a
     * [RouteLock.UnknownSection] while anything of the binder is. Never asked for
     * [RouteLock.Open] or [RouteLock.DrawnByItsScreen].
     */
    fun isClosed(lock: RouteLock): Boolean

    /**
     * What a closed lock shows: the calm locked state ([com.ar.dosarcusina.ui.ds.DSLockedState])
     * naming nothing of what it guards but the section's own name. In a sheet, it keeps a way to
     * close it ([onClose]).
     */
    @Composable
    fun Locked(lock: RouteLock, inSheet: Boolean, onClose: () -> Unit)
}

/** The app's lock gate, provided by [AppShell]: there is no default, so nothing is drawn unguarded. */
val LocalLockGate = staticCompositionLocalOf<LockGate> { error("No LockGate: AppShell provides the app's") }

/**
 * The lock a screen's own sheets and dialogs are drawn behind ([DSSheet]): the section the screen
 * shows, set by its gate or by a screen that draws its own locked state ([ScreenLock]). A sheet
 * of a locked screen lives inside its gate: when the lock comes back while it is up, it shows the
 * locked state with „Închide”, and nothing it held is saved.
 */
val LocalScreenLock = staticCompositionLocalOf<RouteLock> { RouteLock.Open }

/**
 * Draws a route's screen or a sheet behind the lock it declares ([RouteLock]), wherever it was
 * opened from, as the iPhone app's `RouteLockGate`. Over a sheet, the locked state keeps a way to
 * close it.
 */
@Composable
fun RouteLockGate(
    lock: RouteLock,
    inSheet: Boolean = false,
    onClose: () -> Unit = {},
    content: @Composable () -> Unit,
) {
    val guards = lock is RouteLock.Section || lock is RouteLock.UnknownSection
    val gate = LocalLockGate.current
    if (guards && gate.isClosed(lock)) {
        gate.Locked(lock, inSheet, onClose)
    } else {
        ScreenLock(if (guards) lock else LocalScreenLock.current, content)
    }
}

/**
 * Declares the lock this screen's own sheets are drawn behind, for a screen that decides a
 * section's lock itself and draws its own locked state (a deadline's page), as the iPhone app's
 * `.screenLock(_:)`.
 */
@Composable
fun ScreenLock(lock: RouteLock, content: @Composable () -> Unit) {
    CompositionLocalProvider(LocalScreenLock provides lock, content = content)
}
