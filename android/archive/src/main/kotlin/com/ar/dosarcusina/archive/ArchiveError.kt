package com.ar.dosarcusina.archive

/**
 * What can go wrong with a backup as a whole, the iOS app's `ArchiveError`
 * (ios/DosarCuSina/Services/Archive/DossierArchiveService.swift), case for case. A path or a
 * title stays on the error for tests and the log; the words the person reads come from the
 * shared catalog by its kind, and never name a path inside the archive.
 */
sealed class ArchiveError : Exception() {
    data object NotADossier : ArchiveError()
    data class UnsupportedVersion(val version: Int) : ArchiveError()
    data class MissingFile(val path: String) : ArchiveError()
    data class ChecksumMismatch(val path: String) : ArchiveError()
    data class UnlistedFile(val path: String) : ArchiveError()
    data class UnreadableFile(val path: String) : ArchiveError()
    data class BrokenReference(val path: String) : ArchiveError()

    /** The archive is protected with a password and none was given. */
    data object NeedsPassword : ArchiveError()

    /** The password given doesn't open the archive. */
    data object WrongPassword : ArchiveError()

    /** A protected archive was given an empty password: nothing was typed. */
    data object NoPasswordTyped : ArchiveError()

    /** A document, by its title, is bigger than one file of a backup may be. */
    data class DocumentTooLarge(val title: String) : ArchiveError()

    /** A section's photo, by the section's name, is bigger than one file of a backup may be. */
    data class PhotoTooLarge(val name: String) : ArchiveError()
}

/**
 * The one way an archive's own bytes are opened, the iOS app's `DossierArchiveReader.opened`:
 * a protected one with its password, a plain one as it is.
 */
object ArchiveOpening {
    /**
     * Hands [body] the archive's plain bytes, opened with [password] when it is protected. A
     * protected archive's failures, anywhere in [body] too, come out as the archive's own: a
     * wrong password as [ArchiveError.WrongPassword], a header that isn't one as
     * [ArchiveError.NotADossier].
     */
    fun <T> opened(source: ArchiveByteSource, password: String?, body: (ArchiveByteSource) -> T): T {
        var plain = source
        if (ArchiveEncryption.isEncrypted(source)) {
            ensure(password != null) { ArchiveError.NeedsPassword }
            // No archive is protected with an empty password (`MINIMUM_PASSWORD_LENGTH`): nothing
            // was typed, which says nothing about the file.
            ensure(!password.isNullOrEmpty()) { ArchiveError.NoPasswordTyped }
            plain = inArchiveWords { ArchiveEncryption.DecryptingSource(source, password.orEmpty()) }
        }
        return inArchiveWords { body(plain) }
    }

    /** A protected archive's failures, anywhere in it, as the archive's own. */
    @Suppress("SwallowedException")
    private fun <T> inArchiveWords(body: () -> T): T = try {
        body()
    } catch (error: ArchiveEncryption.Failure.WrongPassword) {
        throw ArchiveError.WrongPassword
    } catch (error: ArchiveEncryption.Failure.Damaged) {
        throw ArchiveError.NotADossier
    }
}
