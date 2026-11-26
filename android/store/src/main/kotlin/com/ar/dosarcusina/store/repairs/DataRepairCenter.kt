package com.ar.dosarcusina.store.repairs

import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow

/**
 * What the repair list shows, what waits as suggestions, and whether the calm prompt has something new
 * to say, as the iOS app's `DataRepairCenter`. Refreshed after launch's built-ins
 * ([com.ar.dosarcusina.store.LaunchData]) and after every import
 * ([com.ar.dosarcusina.store.RoomArchiveTarget]); the list in Settings, the prompt and Urmează's
 * "Din timp" read [state]. Nothing here changes data without the owner's tap.
 *
 * Corrections (data an earlier version saved wrongly) and suggestions ([DataRepairStep.isSuggestion]:
 * nothing wrong, something the app can now do better) are told apart once, here: corrections go to the
 * repair list and may be announced by the prompt; suggestions never are.
 */
class DataRepairCenter(private val repairs: DataRepairs) {
    /** What the screens read. */
    data class State(
        /** Every correction waiting for the owner, in registry order: the repair list. */
        val pending: List<DataRepairFinding> = emptyList(),
        /** Every suggestion waiting for the owner, in registry order: one calm note in Urmează. */
        val suggestions: List<DataRepairFinding> = emptyList(),
        /** Corrections the prompt hasn't announced yet: the prompt shows while this isn't empty. Never a suggestion. */
        val announcement: List<DataRepairFinding> = emptyList(),
    )

    /** One group of the list: findings of one kind together, in registry order. */
    data class Group(val group: DataRepairGroup, val findings: List<DataRepairFinding>)

    private val mutex = Any()
    private val current = MutableStateFlow(State())

    /** What the list, the prompt and the suggestions' note show now. */
    val state: StateFlow<State> = current.asStateFlow()

    val pending: List<DataRepairFinding> get() = current.value.pending
    val suggestions: List<DataRepairFinding> get() = current.value.suggestions
    val announcement: List<DataRepairFinding> get() = current.value.announcement

    /**
     * Runs detection (and the steps that run by themselves). [announce] lets the prompt speak about
     * corrections it hasn't announced before; the list never announces.
     */
    fun refresh(announce: Boolean) = synchronized(mutex) {
        val found = repairs.detect()
        val (suggested, corrections) = found.partition(DataRepairs::isSuggestion)
        val announcement = if (announce) {
            repairs.ledger.unannounced(corrections).ifEmpty { current.value.announcement }
        } else {
            repairs.ledger.markAnnounced(corrections)
            emptyList()
        }
        current.value = State(corrections, suggested, announcement)
    }

    /** The owner opened the list: nothing pending is news any more. */
    fun seen() = synchronized(mutex) {
        repairs.ledger.markAnnounced(current.value.pending)
        current.value = current.value.copy(announcement = emptyList())
    }

    /** The prompt was shown and put away: its findings stay in the list. */
    fun announcementShown() = synchronized(mutex) {
        current.value = current.value.copy(announcement = emptyList())
    }

    /** Makes the changes the owner approved, then looks again. */
    fun apply(findings: List<DataRepairFinding>) = synchronized(mutex) {
        repairs.apply(findings)
        refresh(announce = false)
    }

    /** "Lasă așa", then looks again. */
    fun dismiss(findings: List<DataRepairFinding>) = synchronized(mutex) {
        repairs.dismiss(findings)
        refresh(announce = false)
    }

    /** The groups of the repair list. */
    val groups: List<Group> get() = groups(pending)

    /** The groups of the suggestions' page, the same way. */
    val suggestionGroups: List<Group> get() = groups(suggestions)

    /** What the suggestions are about, for their note: each kind once, in registry order. */
    val suggestionTopics: List<DataRepairGroup> get() = suggestionGroups.map { it.group }

    private fun groups(findings: List<DataRepairFinding>): List<Group> =
        findings.groupBy { DataRepairs.step(it.step).group }.map { (group, found) -> Group(group, found) }
}
