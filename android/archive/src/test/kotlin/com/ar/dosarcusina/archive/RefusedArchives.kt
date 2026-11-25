package com.ar.dosarcusina.archive

import java.util.zip.CRC32
import java.util.zip.Deflater

/**
 * Small archives both apps refuse, each with the kind of error it is refused with, built byte by
 * byte here (not with the app's writer, which never makes one). Each case is one the iOS tests
 * already cover, or the rule behind one; they are written to shared/test-vectors/archive/refused/
 * with the write switch, and both apps' tests read them from there.
 */
object RefusedArchives {
    /** One case: its file's name, the iOS app's name for the error, what the archive does, its bytes. */
    class Case(val file: String, val kind: String, val behaviour: String, val bytes: ByteArray)

    fun all(): List<Case> = listOf(
        Case("not-a-zip.bin", "invalidZipArchive", "is shorter than any zip", ByteArray(10)),
        Case(
            "no-end-record.bin", "endOfCentralDirectoryNotFound", "has no end of central directory record",
            ByteArray(100) { 0x20 },
        ),
        Case(
            "overlapping-entries.zip",
            "overlappingEntries",
            "has two files whose directory records start at the same bytes",
            zip(stored("a.bin", ByteArray(100) { 1 }), stored("b.bin", ByteArray(100) { 2 }).copy(directoryOffset = 0)),
        ),
        Case("runs-into-directory.zip", "overlappingEntries", "has a file whose stated size runs into the directory",
            zip(stored("a.txt", "Dosar".encodeToByteArray()).copy(compressedSize = 50, size = 50))),
        Case("changed-byte.zip", "crcMismatch", "has a stored file with one byte changed after its checksum was taken",
            zip(stored("a.bin", ByteArray(64) { it.toByte() }).let { it.copy(payload = it.payload.flipped(10)) })),
        Case("leaves-the-archive.zip", "unsafeEntryPath", "names a file outside the archive (../x.txt)",
            zip(stored("../x.txt", "x".encodeToByteArray()))),
        Case("same-file-twice.zip", "duplicateEntry", "holds the same name twice",
            zip(stored("a.txt", "a".encodeToByteArray()), stored("a.txt", "b".encodeToByteArray()))),
        Case("same-name-two-spellings.zip", "duplicateEntry",
            "holds one name twice, its letter ș written as one character and as s with a comma below",
            zip(stored("acte/ș.txt", "a".encodeToByteArray()), stored("acte/ș.txt", "b".encodeToByteArray()))),
        Case("marked-zip64.zip", "sizeLimitExceeded", "says it holds 65 535 files, which marks a ZIP64 archive",
            zip(stored("a.txt", "a".encodeToByteArray()), entryCount = 0xFFFF)),
        Case("file-too-large.zip", "sizeLimitExceeded", "says one file is 129 MiB once read back",
            zip(stored("a.txt", "a".encodeToByteArray()), claim("big.bin", METHOD_STORE, 129L shl 20, 129L shl 20))),
        Case("grows-too-much.zip", "sizeLimitExceeded", "says a 1 KiB compressed file unpacks to 10 MiB",
            zip(stored("a.txt", "a".encodeToByteArray()), claim("big.bin", METHOD_DEFLATE, 1_024, 10L shl 20))),
        Case("unpacks-too-large.zip", "unpacksTooLarge", "says its files together unpack to more than 8 GiB",
            zip(stored("a.txt", "a".encodeToByteArray()),
                *Array(65) { claim("f$it.bin", METHOD_DEFLATE, 1L shl 20, 128L shl 20) })),
        Case("stored-sizes-differ.zip", "fileCorrupted", "has a stored file whose two sizes differ",
            zip(stored("a.txt", "Dosar".encodeToByteArray()).copy(size = 6))),
        Case("cut-short.zip", "fileCorrupted", "has a compressed file cut off halfway",
            zip(deflated("a.txt", TEXT).halved())),
        Case("longer-than-it-says.zip", "sizeLimitExceeded", "has a compressed file that unpacks to more than it says",
            zip(deflated("a.txt", TEXT).copy(size = TEXT.size - 1L))),
        Case("unknown-compression.zip", "unsupportedCompressionMethod", "has a file compressed another way (method 12)",
            zip(stored("a.txt", "Dosar".encodeToByteArray()).copy(method = 12))),
        Case("no-local-header.zip", "invalidZipArchive", "has a file whose own header isn't where the directory says",
            zip(stored("a.txt", "Dosar".encodeToByteArray()).copy(localSignature = 0))),
    )

    private val TEXT = "Dosar cu Șină. ".repeat(200).encodeToByteArray()
    private const val METHOD_STORE = 0
    private const val METHOD_DEFLATE = 8

    /** A file as it is written: what its own header and its directory record say. */
    data class Raw(
        val name: String,
        val payload: ByteArray,
        val method: Int,
        val crc: Long,
        val compressedSize: Long,
        val size: Long,
        /** Where the directory says the file starts; by default where it was written. */
        val directoryOffset: Long? = null,
        /** Only in the directory: nothing of it is written before it. */
        val claimOnly: Boolean = false,
        val localSignature: Long = DosarZipEngine.LOCAL_SIGNATURE,
    )

    private fun stored(name: String, data: ByteArray) =
        Raw(name, data, METHOD_STORE, crc(data), data.size.toLong(), data.size.toLong())

    /** The file with only the first half of its data, its own header and its directory record saying so. */
    private fun Raw.halved() = copy(payload = payload.copyOf(payload.size / 2), compressedSize = payload.size / 2L)

    private fun deflated(name: String, data: ByteArray): Raw {
        val deflater = Deflater(Deflater.DEFAULT_COMPRESSION, true)
        deflater.setInput(data)
        deflater.finish()
        val buffer = ByteArray(data.size + 64)
        val written = deflater.deflate(buffer)
        check(deflater.finished())
        deflater.end()
        return Raw(name, buffer.copyOf(written), METHOD_DEFLATE, crc(data), written.toLong(), data.size.toLong())
    }

    private fun claim(name: String, method: Int, compressedSize: Long, size: Long) =
        Raw(name, ByteArray(0), method, 0, compressedSize, size, directoryOffset = 0, claimOnly = true)

    private fun crc(data: ByteArray) = CRC32().apply { update(data) }.value

    private fun ByteArray.flipped(at: Int) = copyOf().also { it[at] = (it[at].toInt() xor 0xFF).toByte() }

    /** A zip of [entries], laid out as the app's writer lays one out unless an entry says otherwise. */
    fun zip(vararg entries: Raw, entryCount: Int = entries.size): ByteArray {
        val out = LittleEndianWriter(1_024)
        var offset = 0L
        val offsets = entries.map { entry ->
            if (entry.claimOnly) return@map entry.directoryOffset ?: 0L
            val name = entry.name.encodeToByteArray()
            val start = offset
            out.u32(entry.localSignature)
            out.u16(20)
            out.u16(0x0800)
            out.u16(entry.method)
            out.u16(0)
            out.u16(0x21)
            out.u32(entry.crc)
            out.u32(entry.compressedSize)
            out.u32(entry.size)
            out.u16(name.size)
            out.u16(0)
            out.bytes(name)
            out.bytes(entry.payload)
            offset += 30 + name.size + entry.payload.size
            entry.directoryOffset ?: start
        }
        val directoryStart = offset
        var directorySize = 0L
        entries.zip(offsets).forEach { (entry, start) ->
            val name = entry.name.encodeToByteArray()
            out.u32(DosarZipEngine.DIRECTORY_SIGNATURE)
            out.u16(0x0314)
            out.u16(20)
            out.u16(0x0800)
            out.u16(entry.method)
            out.u16(0)
            out.u16(0x21)
            out.u32(entry.crc)
            out.u32(entry.compressedSize)
            out.u32(entry.size)
            out.u16(name.size)
            out.u16(0)
            out.u16(0)
            out.u16(0)
            out.u16(0)
            out.u32(0x81A4_0000L)
            out.u32(start)
            out.bytes(name)
            directorySize += 46 + name.size
        }
        out.u32(DosarZipEngine.END_SIGNATURE)
        out.u16(0)
        out.u16(0)
        out.u16(entryCount)
        out.u16(entryCount)
        out.u32(directorySize)
        out.u32(directoryStart)
        out.u16(0)
        return out.toByteArray()
    }
}
