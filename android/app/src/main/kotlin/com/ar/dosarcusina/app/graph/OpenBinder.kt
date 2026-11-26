package com.ar.dosarcusina.app.graph

import com.ar.dosarcusina.store.BinderStore
import com.ar.dosarcusina.store.LaunchData
import com.ar.dosarcusina.store.RoomArchiveTarget
import com.ar.dosarcusina.store.UnitOfWork
import com.ar.dosarcusina.store.history.HistoryActions
import com.ar.dosarcusina.store.history.HistoryWording
import com.ar.dosarcusina.store.locks.CategoryLocks
import com.ar.dosarcusina.store.obligations.ObligationActions
import com.ar.dosarcusina.store.providers.ProviderActions
import com.ar.dosarcusina.store.repairs.DataRepairCenter
import com.ar.dosarcusina.store.sections.AssetActions
import com.ar.dosarcusina.store.templates.TemplateStore

/**
 * The binder once it is open, and everything that changes it: the one way screens reach the
 * household's data. Each action saves through the one unit of work ([unit]), so a screen never
 * writes a record itself, and each is made once here, by hand, from the same store, locks and words.
 */
class OpenBinder(
    val store: BinderStore,
    /** The one way the binder saves; its undo receipts take a step back. */
    val unit: UnitOfWork,
    /** This phone's locks, the one way a category is locked or opened. */
    val locks: CategoryLocks,
    /** The repair list, the calm prompt and the suggestions' note read its state. */
    val repairs: DataRepairCenter,
    wording: HistoryWording,
) {
    val templates = TemplateStore(unit, locks)
    val obligations = ObligationActions(unit)
    val assets = AssetActions(unit)
    val history = HistoryActions(unit, wording)
    val providers = ProviderActions(unit)

    /** Where a backup is brought in, with the repair list it looks at again. */
    val archive = RoomArchiveTarget(unit, repairs)

    /** What the app does to the binder at every start. */
    val launch = LaunchData(unit, repairs)
}
