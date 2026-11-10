import Foundation
import Testing
@testable import DosarCuSina

/// A manifest an earlier version wrote keeps the shared file's name whole. The app writes it
/// again masked the first time it reads the inbox, once; looking without reading (the share
/// extension, the coordinator) changes nothing. Only the published test number is used.
@Suite("Shared-file names from before masking")
struct InboxOlderNamesTests {
    static let card = "4111 1111 1111 1111"

    private func olderItem(in inbox: ShareInbox) throws -> (InboxItem, URL) {
        let staging = try inbox.makeStagingFolder()
        let name = try inbox.stage(data: Data("%PDF-1.4 test".utf8), fileExtension: "pdf", into: staging, index: 0)
        let item = try inbox.commit(staging: staging, payload: .pdf, files: [name], originalName: "Extras NUMAR.pdf", receivedAt: Date(timeIntervalSince1970: 1_800_000_000))
        let manifest = inbox.folder(for: item.id).appending(path: ShareInbox.manifestName)
        // As an earlier version wrote it: version 1, the whole number in the name.
        var json = String(decoding: try Data(contentsOf: manifest), as: UTF8.self).replacingOccurrences(of: "NUMAR", with: Self.card)
        json = json.replacingOccurrences(of: "\"version\":2", with: "\"version\":1")
        try Data(json.utf8).write(to: manifest)
        return (item, manifest)
    }

    @Test func theAppWritesAnOlderNameAgainMaskedOnce() throws {
        let folder = URL.temporaryDirectory.appending(path: "older-names-\(UUID().uuidString)", directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: folder) }
        let inbox = ShareInbox(directory: folder.appending(path: ShareInbox.folderName))
        try FileManager.default.createDirectory(at: inbox.directory, withIntermediateDirectories: true)
        let (item, manifest) = try olderItem(in: inbox)
        let masked = "Extras \(PaymentCardNumbers.redact(Self.card)).pdf"
        #expect(masked != "Extras \(Self.card).pdf")

        // Only looking leaves the file as it is.
        #expect(inbox.waitingItems().first?.originalName == masked)
        #expect(String(decoding: try Data(contentsOf: manifest), as: UTF8.self).contains(Self.card))

        // Reading the inbox writes it again, masked, keeping the rest.
        let read = inbox.contents()
        #expect(read.items.map(\.id) == [item.id])
        let written = try Data(contentsOf: manifest)
        let text = String(decoding: written, as: UTF8.self)
        #expect(!text.contains(Self.card))
        #expect(text.contains(masked))
        let reread = try MachineText.jsonDecoder().decode(InboxItem.self, from: written)
        #expect(reread.version == 1, "Its version stays as it was")
        #expect(reread.files == item.files)
        #expect(reread.receivedAt == item.receivedAt)

        // Once: the next read changes nothing.
        let modified = try FileManager.default.attributesOfItem(atPath: manifest.path())[.modificationDate] as? Date
        _ = inbox.contents()
        #expect(try Data(contentsOf: manifest) == written)
        #expect(try FileManager.default.attributesOfItem(atPath: manifest.path())[.modificationDate] as? Date == modified)
    }

    @Test func aNameWithNothingToMaskIsNeverWrittenAgain() throws {
        let folder = URL.temporaryDirectory.appending(path: "older-names-\(UUID().uuidString)", directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: folder) }
        let inbox = ShareInbox(directory: folder.appending(path: ShareInbox.folderName))
        try FileManager.default.createDirectory(at: inbox.directory, withIntermediateDirectories: true)
        let staging = try inbox.makeStagingFolder()
        let name = try inbox.stage(data: Data("%PDF-1.4 test".utf8), fileExtension: "pdf", into: staging, index: 0)
        let item = try inbox.commit(staging: staging, payload: .pdf, files: [name], originalName: "Factura.pdf")
        let manifest = inbox.folder(for: item.id).appending(path: ShareInbox.manifestName)
        let before = try Data(contentsOf: manifest)
        _ = inbox.contents()
        #expect(try Data(contentsOf: manifest) == before)
    }
}
