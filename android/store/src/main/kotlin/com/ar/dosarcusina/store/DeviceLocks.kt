package com.ar.dosarcusina.store

/**
 * Which categories are locked on this phone, kept beside the store and never in it: the iOS
 * app's `SectionLocks`, whose port (with when each choice was made, and failing closed when its
 * file can't be read) comes with the locks. What the archive's target reads and writes.
 */
interface DeviceLocks {
    /** Every category key this phone has a choice for, and whether it is locked. */
    fun read(): Map<String, Boolean>

    /** Keeps [locks] as this phone's choices, whole; throws when it can't. */
    fun write(locks: Map<String, Boolean>)
}
