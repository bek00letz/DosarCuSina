import Foundation
import SwiftData
import Testing
@testable import DosarCuSina

/// Files kept in a folder whose name has a space and a diacritic, as the phone's own
/// "Application Support" has a space: every step finds them where they are. Placeholder data only.
@MainActor
@Suite("Files in folders whose names have spaces")
struct FolderNamesTests {
    /// A new folder named like the phone's own, with a space and a diacritic.
    private func folder() throws -> URL {
        let folder = URL.temporaryDirectory
            .appending(path: "folders-\(UUID().uuidString)", directoryHint: .isDirectory)
            .appending(path: "Application Support Șină", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }

    private func names(in folder: URL) throws -> [String] {
        try FileManager.default.contentsOfDirectory(atPath: folder.path(percentEncoded: false))
    }

    private func remove(_ folder: URL) {
        try? FileManager.default.removeItem(at: folder.deletingLastPathComponent())
    }

    @Test func startingFreshMovesTheBinderAsideWhereverItIsKept() async throws {
        let folder = try folder()
        defer { remove(folder) }
        let url = folder.appending(path: "Dosar.store")
        do {
            let container = try PersistenceController.makeContainer(storeURL: url)
            let store = TemplateStore(context: container.mainContext)
            try store.installBuiltIns()
            let vehicle = try #require(try store.template(forKey: BuiltInTemplates.Key.vehicle))
            try store.setSensitive(vehicle, true)
        }
        let locks = SectionLocks.file(forStoreAt: url)
        #expect(FileManager.default.fileExists(atPath: locks.path(percentEncoded: false)))

        PersistenceController.moveStoreAside(at: url)
        let names = try names(in: folder)
        #expect(!FileManager.default.fileExists(atPath: url.path(percentEncoded: false)), "The binder went aside")
        #expect(names.contains { $0.hasPrefix("unreadable-") && $0.hasSuffix("Dosar.store") })
        #expect(FileManager.default.fileExists(atPath: locks.path(percentEncoded: false)), "The locks stayed")
        #expect(FileManager.default.fileExists(atPath: SectionLocks.timesFile(for: locks).path(percentEncoded: false)), "When they were chosen stayed")
    }

    @Test func fileProtectionAppliesInFoldersWhoseNamesHaveSpaces() throws {
        let folder = try folder()
        defer { remove(folder) }
        let url = folder.appending(path: "Dosar.store")
        let external = DocumentFileProtection.externalDataFolder(for: url)
        try FileManager.default.createDirectory(at: external, withIntermediateDirectories: true)
        try Data("pagina 1".utf8).write(to: external.appending(path: "0B6C6F43-0000-4000-8000-000000000001"))

        #expect(DocumentFileProtection.apply(toStoreAt: url) > 0, "The folder and the page it holds were found")
    }

    @Test func aShareKeptInAFolderWhoseNameHasSpacesIsFoundAndRemoved() throws {
        let folder = try folder()
        defer { remove(folder) }
        let inbox = ShareInbox(directory: folder.appending(path: "Primite acum", directoryHint: .isDirectory))
        let source = folder.appending(path: "Factură ENGIE.pdf")
        try Data("%PDF-1.4 placeholder".utf8).write(to: source)

        let staging = try inbox.makeStagingFolder()
        let file = try inbox.stage(copyOf: source, into: staging, index: 0)
        let item = try inbox.commit(staging: staging, payload: .pdf, files: [file], originalName: "Factură ENGIE.pdf")

        #expect(inbox.items().map(\.id) == [item.id], "The item that arrived is read back")
        #expect(inbox.waitingItems()?.map(\.id) == [item.id])
        try inbox.savePreview(InboxPreview(kind: nil, title: "Factură", categoryKey: nil, pageCount: 1), thumbnail: Data("thumbnail".utf8), for: item)
        #expect(inbox.preview(of: item)?.hasThumbnail == true)
        #expect(inbox.thumbnailURL(of: item) != nil, "Its picture is found")

        try inbox.remove(item.id)
        #expect(inbox.items().isEmpty, "It is gone once removed")
    }
}
