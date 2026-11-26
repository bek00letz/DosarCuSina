package com.ar.dosarcusina.archive

import com.ar.dosarcusina.archive.binder.ArchiveTarget
import com.ar.dosarcusina.archive.binder.Binder
import com.ar.dosarcusina.archive.binder.BuiltIns
import com.ar.dosarcusina.archive.binder.Removed
import com.ar.dosarcusina.archive.v3.DossierPackage
import com.ar.dosarcusina.core.values.DosarCalendar
import java.io.File
import java.time.Clock
import java.time.ZoneId
import java.util.UUID

/**
 * Brings a `.dosar` archive into the binder, as the iOS app's `DossierArchiveService`: read and
 * checked a piece at a time ([DossierArchiveReader]), decided without the store
 * ([DossierImporter]), then written by the store in one step, everything or nothing
 * ([ArchiveTarget.apply]). Nothing here knows about Android: Phase 2's Room store is a target.
 */
class DossierArchiveService(
    private val target: ArchiveTarget,
    /** The app's own categories (`com.ar.dosarcusina.catalog.Catalog.builtIn`). */
    private val builtIns: BuiltIns,
    private val clock: Clock = Clock.systemUTC(),
    /** The time zone days are counted in; the phone's, read each time ([DosarCalendar.zone]). */
    private val zone: () -> ZoneId = DosarCalendar::zone,
) {
    /** What an archive holds, once every file in it is checked; none of its files is kept. */
    fun inspect(source: ArchiveByteSource, password: String? = null): ArchiveSummary =
        DossierArchiveReader.summary(source, builtIns, password)

    /**
     * Reads an archive and writes it into the binder. Its documents' files pass through a folder
     * of their own in [staging], removed when done, whatever happens.
     */
    fun importArchive(
        source: ArchiveByteSource,
        password: String? = null,
        mode: ArchiveImportMode,
        staging: File,
    ): ArchiveImportResult {
        val folder = File(staging, "import-${UUID.randomUUID()}.files")
        try {
            return importPackage(DossierArchiveReader.read(source, builtIns, password, folder), mode)
        } finally {
            folder.deleteRecursively()
        }
    }

    /**
     * Writes the binder to [file] (which must not exist yet), sealed with [password] when there
     * is one; on any failure nothing is left there. [appVersion] is the app's, for the manifest.
     */
    fun export(file: File, password: String? = null, appVersion: String) {
        DossierArchiveWriter(appVersion, clock.instant(), zone()).write(target.snapshot(), file, password)
    }

    /** Writes an already read package into the binder, in one step. */
    fun importPackage(pack: DossierPackage, mode: ArchiveImportMode): ArchiveImportResult {
        val plan = DossierImporter(pack, target.snapshot(), mode, clock.instant(), zone(), builtIns).run()
        target.apply(plan.changes)
        return plan.result
    }
}

/** Links to records an import takes out: none any more, so nothing points at a record that isn't there. */
internal object Links {
    fun without(written: Binder, removed: Removed): Binder {
        fun UUID?.kept(out: Set<UUID>): UUID? = this?.takeUnless { it in out }
        return written.copy(
            assets = written.assets.map { it.copy(parentId = it.parentId.kept(removed.assets)) },
            obligations = written.obligations.map { it.copy(assetId = it.assetId.kept(removed.assets)) },
            historyEntries = written.historyEntries.map {
                it.copy(
                    assetId = it.assetId.kept(removed.assets), obligationId = it.obligationId.kept(removed.obligations),
                    providerIds = it.providerIds.filter { id -> id !in removed.providers },
                )
            },
            serviceItems = written.serviceItems.map {
                it.copy(
                    entryId = it.entryId.kept(removed.historyEntries),
                    supplierId = it.supplierId.kept(removed.providers),
                )
            },
            providers =
                written.providers.map { it.copy(assetIds = it.assetIds.filter { id -> id !in removed.assets }) },
            measurements = written.measurements.map { it.copy(assetId = it.assetId.kept(removed.assets)) },
            attachments = written.attachments.map {
                it.copy(
                    assetId = it.assetId.kept(removed.assets), obligationId = it.obligationId.kept(removed.obligations),
                    historyEntryId = it.historyEntryId.kept(removed.historyEntries),
                    serviceItemId = it.serviceItemId.kept(removed.serviceItems),
                    measurementId = it.measurementId.kept(removed.measurements),
                    providerId = it.providerId.kept(removed.providers),
                    supersededById = it.supersededById.kept(removed.attachments),
                )
            },
        )
    }
}
