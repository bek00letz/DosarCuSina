import Foundation

/// The pictures and files one step took from the binder (a deleted document's pages, a
/// deleted section's photos, a photo it replaced), kept on disk only while the step's undo
/// receipt can bring them back. So "Anulează" works for a step of any size, and a receipt
/// never holds pictures in memory: what a record still has, it knows only by digest.
///
/// One folder per receipt, inside this run's folder in the app's temporary folder. Each file
/// is named by its digest, written with complete protection (unreadable while the phone is
/// locked) and read back only while its bytes still match the digest. The folder goes as soon
/// as the receipt goes (its toast left, or the step was taken back); what an earlier run left
/// (the app stopped while a toast showed) goes when the app next starts (`removeLeftovers`).
final class UndoFiles {
    /// Where every receipt keeps what its step took.
    static var root: URL {
        FileManager.default.temporaryDirectory.appending(path: "Anulare", directoryHint: .isDirectory)
    }

    /// This run's folder under `root`: removing an earlier run's leftovers never touches it.
    static let run = UUID().uuidString

    let folder: URL
    /// What it keeps, by digest.
    private(set) var kept: Set<FileDigest> = []

    init(root: URL = UndoFiles.root) {
        folder = root.appending(path: Self.run, directoryHint: .isDirectory).appending(path: UUID().uuidString, directoryHint: .isDirectory)
    }

    deinit {
        try? FileManager.default.removeItem(at: folder)
    }

    /// Keeps `data`, known by `digest`; the same bytes are kept once.
    func keep(_ data: Data, as digest: FileDigest) throws {
        guard !kept.contains(digest) else { return }
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try data.write(to: url(of: digest), options: Self.writing)
        kept.insert(digest)
    }

    /// Lets go of everything but `digests`.
    func keepOnly(_ digests: Set<FileDigest>) {
        for digest in kept.subtracting(digests) {
            try? FileManager.default.removeItem(at: url(of: digest))
        }
        kept.formIntersection(digests)
    }

    /// The bytes of every one of `digests`, each exactly as it was kept; nil when one is missing
    /// or no longer matches its digest.
    func bytes(of digests: Set<FileDigest>) -> [FileDigest: Data]? {
        var found: [FileDigest: Data] = [:]
        for digest in digests {
            guard kept.contains(digest), let data = try? Data(contentsOf: url(of: digest)), FileDigest(data) == digest else { return nil }
            found[digest] = data
        }
        return found
    }

    /// Removes what earlier runs kept: their receipts are gone with them.
    static func removeLeftovers(root: URL = root) {
        let fileManager = FileManager.default
        guard let folders = try? fileManager.contentsOfDirectory(at: root, includingPropertiesForKeys: nil) else { return }
        for folder in folders where folder.lastPathComponent != run {
            try? fileManager.removeItem(at: folder)
        }
    }

    private func url(of digest: FileDigest) -> URL {
        folder.appending(path: digest.name)
    }

    private static var writing: Data.WritingOptions {
        #if os(iOS)
        [.atomic, .completeFileProtection]
        #else
        [.atomic]
        #endif
    }
}
