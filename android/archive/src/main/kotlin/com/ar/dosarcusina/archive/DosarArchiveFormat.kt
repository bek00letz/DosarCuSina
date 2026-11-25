package com.ar.dosarcusina.archive

/** The `.dosar` format this build reads and writes (shared/schemas/dosar-v3.md). */
object DosarArchiveFormat {
    /** The manifest's `schemaVersion`; a higher one is refused with a request to update the app. */
    const val SCHEMA_VERSION: Int = 3

    /** A backup file's extension. */
    const val FILE_EXTENSION: String = "dosar"
}
