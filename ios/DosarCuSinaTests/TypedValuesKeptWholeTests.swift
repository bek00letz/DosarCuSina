import Foundation
import SwiftData
import Testing
@testable import DosarCuSina

/// A value whose field says what it is (a pet's microchip, whose 642 start can pass as a
/// Maestro card) is kept whole by one rule wherever a section's words go: where they are
/// stored, the binder's search, the iPhone's search and the text kept from a document
/// (`PaymentCardNumbers.KeptWhole`), while a card number beside it is still masked. What the
/// share extension writes about a shared file goes through the same card rule. Card numbers
/// are the networks' published test numbers; microchips are made up here, never written out.
@MainActor
@Suite("Typed values kept whole everywhere")
struct TypedValuesKeptWholeTests {
    static let visa = CardNumbersKeptOutTests.visa
    static let visaMasked = CardNumbersKeptOutTests.visaMasked
    /// A microchip that passes the Luhn check: alone, its digits read as a Maestro card.
    static let chip = PersonalDocumentCaptureTests.withCheckDigit("642" + String(repeating: "0", count: 8) + "123")
    /// Digits shaped the same way that no field of the section holds.
    static let otherChip = PersonalDocumentCaptureTests.withCheckDigit("642" + String(repeating: "0", count: 8) + "456")

    // MARK: The share inbox

    @Test func aSharedFilesNameKeepsNoCardNumberInTheInbox() throws {
        let folder = URL.temporaryDirectory.appending(path: "typed-values-\(UUID().uuidString)", directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: folder) }
        let inbox = ShareInbox(directory: folder.appending(path: ShareInbox.folderName))
        try FileManager.default.createDirectory(at: inbox.directory, withIntermediateDirectories: true)

        let staging = try inbox.makeStagingFolder()
        let name = try inbox.stage(data: Data("%PDF-1.4 test".utf8), fileExtension: "pdf", into: staging, index: 0)
        let item = try inbox.commit(staging: staging, payload: .pdf, files: [name], originalName: "Card \(Self.visa).pdf")
        #expect(item.originalName == "Card \(Self.visaMasked).pdf")
        let manifest = inbox.folder(for: item.id).appending(path: ShareInbox.manifestName)
        #expect(!PersonalDocumentCaptureTests.holdsTestNumber(String(decoding: try Data(contentsOf: manifest), as: UTF8.self)))
        #expect(inbox.items().first?.originalName == "Card \(Self.visaMasked).pdf")

        // An item an earlier version wrote with the whole number reads masked.
        let earlierStaging = try inbox.makeStagingFolder()
        let earlierName = try inbox.stage(data: Data("%PDF-1.4 test".utf8), fileExtension: "pdf", into: earlierStaging, index: 0)
        let earlier = try inbox.commit(staging: earlierStaging, payload: .pdf, files: [earlierName], originalName: "Card NUMAR.pdf")
        let earlierManifest = inbox.folder(for: earlier.id).appending(path: ShareInbox.manifestName)
        let written = String(decoding: try Data(contentsOf: earlierManifest), as: UTF8.self).replacingOccurrences(of: "NUMAR", with: Self.visa)
        try Data(written.utf8).write(to: earlierManifest)
        #expect(inbox.items().first { $0.id == earlier.id }?.originalName == "Card \(Self.visaMasked).pdf")
    }
}
