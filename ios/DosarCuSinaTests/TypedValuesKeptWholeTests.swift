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

    static func masked(_ digits: String) -> String {
        "\(PaymentCardNumbers.mask) \(digits.suffix(4))"
    }

    /// A pet with the microchip in its field and a card number in its notes, and a section
    /// with no microchip field.
    private func household() throws -> (context: ModelContext, pet: Asset, other: Asset) {
        let context = try makeContext()
        let actions = AssetActions(context: context, calendar: .bucharest, now: { noon("2026-11-10") }, sealer: .ephemeral())
        let store = TemplateStore(context: context)
        let pets = try #require(try store.template(forKey: BuiltInTemplates.Key.pet))
        let pet = try actions.create(name: "Motănelul din exemplu", template: pets,
                                     values: FieldValues([PetFields.microchip: .text(Self.chip)]), notes: "Card \(Self.visa)")
        let others = try #require(try store.template(forKey: BuiltInTemplates.Key.other))
        let other = try actions.create(name: "Barca de pe lac", template: others, values: FieldValues())
        return (context, pet, other)
    }

    private func file(_ title: String, text: String, in section: Asset, _ context: ModelContext) throws -> DosarCuSina.Attachment {
        try AttachmentActions(context: context, calendar: .bucharest)
            .file(DocumentDraft(title: title, fileName: "carnet.pdf", kind: .other, extractedText: text), asset: section)
    }

    // MARK: The document's kept text

    @Test func aDocumentsTextKeepsItsSectionsMicrochipWholeAndMasksACard() throws {
        let (context, pet, other) = try household()
        let text = "Microcip \(Self.chip)\nPlată cu cardul \(Self.visa)\nAlt cip \(Self.otherChip)"
        let kept = try file("Carnet de sănătate", text: text, in: pet, context)
        let elsewhere = try file("Carnet de sănătate", text: text, in: other, context)

        let saved = ModelContext(context.container)
        let stored = try #require(try saved.fetch(FetchDescriptor<DosarCuSina.Attachment>()).first { $0.id == kept.id })
        #expect(stored.extractedText == "Microcip \(Self.chip)\nPlată cu cardul \(Self.visaMasked)\nAlt cip \(Self.masked(Self.otherChip))")
        // A section with no microchip field: nothing says what the digits are.
        let alone = try #require(try saved.fetch(FetchDescriptor<DosarCuSina.Attachment>()).first { $0.id == elsewhere.id })
        #expect(alone.extractedText == "Microcip \(Self.masked(Self.chip))\nPlată cu cardul \(Self.visaMasked)\nAlt cip \(Self.masked(Self.otherChip))")
        #expect(FreeText.mask(stored, write: false).isEmpty, "A later save leaves it as it is")
    }

    @Test func captureKeepsAMicrochipItReadWholeInTheTextItKeeps() {
        let text = "Microcip \(Self.chip)\nPlată cu cardul \(Self.visa)"
        let field = CaptureField(key: .microchip, value: .text(Self.chip), confidence: 0.9, sourceText: "Microcip \(Self.chip)", tier: .heuristic)
        func read(_ kind: CaptureDocumentKind, fields: [CaptureField]) -> CaptureResult {
            CaptureResult(kind: kind, kindConfidence: 0.9, fields: fields, suggestions: [], reminder: nil,
                          recognizedText: text, barcodes: [], document: nil, notices: []).withoutCardNumbers()
        }
        let vet = read(.veterinaryRecord, fields: [field])
        #expect(vet.recognizedText == "Microcip \(Self.chip)\nPlată cu cardul \(Self.visaMasked)")
        #expect(vet.field(.microchip)?.value.text == Self.chip)
        #expect(vet.field(.microchip)?.sourceText == "Microcip \(Self.chip)")
        // Nothing read as a microchip: the same digits are masked.
        #expect(read(.veterinaryRecord, fields: []).recognizedText == "Microcip \(Self.masked(Self.chip))\nPlată cu cardul \(Self.visaMasked)")
        // On a bank card nothing is kept whole.
        #expect(!read(.bankCard, fields: [field]).recognizedText.contains(Self.chip))
    }

    // MARK: Search

    @Test func theIndexKeepsATypedMicrochipWholeAndACardOut() throws {
        let (context, pet, _) = try household()
        let document = try file("Carnet de sănătate", text: "Microcip \(Self.chip)\nPlată cu cardul \(Self.visa)", in: pet, context)

        let index = try SearchIndexBuilder(context: context).build()
        let found = Set(index.search(Self.chip).map(\.document.route))
        #expect(found.contains(.asset(pet.id)), "Found by its microchip field")
        #expect(found.contains(.document(document.id)), "Found by the text read off its document")
        #expect(index.search("4111111111111111").isEmpty)
        #expect(index.search("1111").isEmpty)
        for entry in index.documents {
            for field in entry.fields {
                #expect(!PersonalDocumentCaptureTests.holdsTestNumber(field.text), "\(entry.id)")
            }
        }
        // The same rule as the save: what a section's own typed value holds, and nothing else.
        let kept = SearchIndexBuilder.keptWhole(by: pet, try TemplateStore.templatesByKey(in: context))
        #expect(SearchPrivacy.redacting("Cip \(Self.chip)", keeping: kept) == "Cip \(Self.chip)")
        #expect(SearchPrivacy.redacting("Cip \(Self.otherChip)", keeping: kept) == "Cip ")
        #expect(SearchPrivacy.redacting("Cip \(Self.chip)") == "Cip ", "Without the section, the digits are a card's")
    }

    @Test func theIPhonesSearchShowsATypedMicrochipAsTheAppKeepsIt() throws {
        let (context, pet, other) = try household()
        let kept = try file("Carnet microcip \(Self.chip)", text: "", in: pet, context)
        let masked = try file("Carnet microcip \(Self.chip)", text: "", in: other, context)

        let entries = try SpotlightCatalog.entries(obligations: [], in: context)
        #expect(entries.first { $0.route == .document(kept.id) }?.title == "Carnet microcip \(Self.chip)")
        #expect(entries.first { $0.route == .document(masked.id) }?.title == "Carnet microcip", "Masked where it is kept, left out outside")
        for entry in entries {
            #expect(!PersonalDocumentCaptureTests.holdsTestNumber(entry.title))
        }
    }

    // MARK: A field's note

    @Test func aMicrochipFieldSaysNothingAboutACard() {
        #expect(DSValidation.keepingCardNumberOut(of: Self.chip, as: .microchip) == nil)
        #expect(DSValidation.keepingCardNumberOut(of: Self.chip) != nil, "A plain field can't tell it from a card")
        #expect(DSValidation.keepingCardNumberOut(of: Self.visa, as: .microchip) != nil, "Sixteen digits aren't a microchip")
    }

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
