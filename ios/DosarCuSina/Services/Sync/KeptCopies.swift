import Foundation
import SwiftData

/// Copies of the binder kept on this phone before something replaces it (`Reason`): syncing
/// with another iCloud account than the one it synced with (`PersistenceController.syncWithThisAccount`),
/// whose binder comes down in its place, and „Înlocuiește tot” with a backup (`BackupFlow`),
/// which deletes on every device the binder syncs to. What was there is first written as a
/// backup (`.dosar`, through `DossierArchiveService`, without a password, like any backup kept on
/// the phone). Settings offers each, saying why it was kept, until the person brings it in
/// ("Adaugă" in the backup screen) or deletes it.
///
/// Every copy is a file of its own, never written over another: two account changes on one day
/// keep two copies (`name(for:in:)`). The newest `mostKept` of each reason stay, by one order
/// (`all(in:)`): a copy past them goes as a new one is kept.
@MainActor
enum KeptCopies {
    /// Why a copy was kept, each in a folder of its own beside the store.
    enum Reason: CaseIterable {
        case accountChange
        case replacingAll

        var folder: URL {
            switch self {
            case .accountChange: URL.applicationSupportDirectory.appending(path: "Kept before account change", directoryHint: .isDirectory)
            case .replacingAll: URL.applicationSupportDirectory.appending(path: "Kept before replacing", directoryHint: .isDirectory)
            }
        }
    }

    /// How many copies stay on the phone: each is the whole binder, documents included, and
    /// the newest are the ones worth bringing back.
    static let mostKept = 3

    /// Beside the store, on this phone only: never in iCloud's database or in a backup of the binder.
    static var folder: URL { Reason.accountChange.folder }

    /// Writes a copy kept for `reason` (`keep(container:in:now:)`).
    static func keep(container: ModelContainer, for reason: Reason, now: Date = Date()) async throws -> URL {
        try await keep(container: container, in: reason.folder, now: now)
    }

    /// Every copy kept, whatever the reason, the newest first.
    static func everyKept(in folders: [URL] = Reason.allCases.map(\.folder)) -> [URL] {
        folders.flatMap { all(in: $0) }.sorted { (keptAt($0) ?? .distantPast) > (keptAt($1) ?? .distantPast) }
    }

    /// Why `copy` was kept, by the folder it is in.
    static func reason(of copy: URL) -> Reason {
        Reason.allCases.first { $0.folder.standardizedFileURL.path == copy.deletingLastPathComponent().standardizedFileURL.path } ?? .accountChange
    }

    /// Writes a copy of `container`'s binder and returns where it is. It is written in a folder
    /// of its own first, so a copy that didn't finish is never among the kept ones, then given a
    /// name no other kept copy has; the oldest go past `mostKept`.
    static func keep(container: ModelContainer, in folder: URL = folder, now: Date = Date()) async throws -> URL {
        let files = FileManager.default
        try files.createDirectory(at: folder, withIntermediateDirectories: true)
        let writing = folder.appending(path: ".writing-\(UUID().uuidString)", directoryHint: .isDirectory)
        try files.createDirectory(at: writing, withIntermediateDirectories: true)
        defer { try? files.removeItem(at: writing) }
        let written = try await DossierArchiveService(container: container).export(to: writing, exportedAt: now)
        let kept = name(for: written, in: folder)
        try files.moveItem(at: written, to: kept)
        try? files.setAttributes([.modificationDate: now], ofItemAtPath: kept.path(percentEncoded: false))
        for old in all(in: folder).dropFirst(mostKept) { remove(old) }
        return kept
    }

    /// Where a copy written as `written` is kept in `folder`: its own name, else the same name
    /// with the first number after it that no kept copy has („… 2”, „… 3”).
    static func name(for written: URL, in folder: URL) -> URL {
        let base = written.deletingPathExtension().lastPathComponent
        let taken = Set(all(in: folder).map(\.lastPathComponent))
        var candidate = "\(base).dosar"
        var number = 2
        while taken.contains(candidate) {
            candidate = "\(base) \(number).dosar"
            number += 1
        }
        return folder.appending(path: candidate)
    }

    /// The copies kept, the newest first: by when each was kept, and for two kept in the same
    /// moment by the number in its name.
    static func all(in folder: URL = folder) -> [URL] {
        let keys: [URLResourceKey] = [.contentModificationDateKey]
        let files = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: keys, options: .skipsHiddenFiles)) ?? []
        return files.filter { $0.pathExtension.lowercased() == "dosar" }.sorted { lhs, rhs in
            let left = keptAt(lhs) ?? .distantPast, right = keptAt(rhs) ?? .distantPast
            if left != right { return left > right }
            // By the name before its extension, so „… 2” comes after the name it numbers.
            let leftName = lhs.deletingPathExtension().lastPathComponent, rightName = rhs.deletingPathExtension().lastPathComponent
            return leftName.compare(rightName, options: .numeric) == .orderedDescending
        }
    }

    /// When a copy was kept.
    static func keptAt(_ url: URL) -> Date? {
        try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
    }

    /// Deletes a kept copy, once the person said so.
    @discardableResult
    static func remove(_ url: URL) -> Bool {
        (try? FileManager.default.removeItem(at: url)) != nil
    }
}
