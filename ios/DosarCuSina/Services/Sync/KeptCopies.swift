import Foundation
import SwiftData

/// Copies of the binder kept on this phone before it syncs with another iCloud account than
/// the one it synced with (`PersistenceController.syncWithThisAccount`): that account's binder
/// comes down in its place, so what was on the phone is first written as a backup (`.dosar`,
/// through `DossierArchiveService`, without a password, like any backup kept on the phone).
/// Settings offers it until the person brings it in ("Adaugă" in the backup screen) or deletes it.
@MainActor
enum KeptCopies {
    /// Beside the store, on this phone only: never in iCloud's database or in a backup of the binder.
    static var folder: URL {
        URL.applicationSupportDirectory.appending(path: "Kept before account change", directoryHint: .isDirectory)
    }

    /// Writes a copy of `container`'s binder and returns where it is.
    static func keep(container: ModelContainer, in folder: URL = folder) async throws -> URL {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return try await DossierArchiveService(container: container).export(to: folder)
    }

    /// The copies kept, the newest first.
    static func all(in folder: URL = folder) -> [URL] {
        let keys: [URLResourceKey] = [.contentModificationDateKey]
        let files = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: keys)) ?? []
        func modified(_ url: URL) -> Date { (try? url.resourceValues(forKeys: Set(keys)).contentModificationDate) ?? .distantPast }
        return files.filter { $0.pathExtension.lowercased() == "dosar" }.sorted { modified($0) > modified($1) }
    }

    /// Deletes a kept copy, once the person said so.
    @discardableResult
    static func remove(_ url: URL) -> Bool {
        (try? FileManager.default.removeItem(at: url)) != nil
    }
}
