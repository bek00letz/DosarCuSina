import CoreGraphics
import Foundation
import SwiftData
import Testing
@testable import DosarCuSina

/// One page per document: the picture first, its values with "Copiază", and "Editează",
/// which corrects the values, adds the back and reads the document again, all through the
/// actions and as one step "Anulează" takes back.
@Suite("A document's page")
@MainActor
struct DocumentPageTests {

    // MARK: Setup

    private struct Household {
        let context: ModelContext
        let person: Asset
        let documents: CategoryTemplate
    }

    private func household() throws -> Household {
        let context = try makeContext()
        let store = TemplateStore(context: context)
        let member = try #require(try store.template(forKey: BuiltInTemplates.Key.member))
        let documents = try #require(try store.template(forKey: BuiltInTemplates.Key.documents))
        let person = try AssetActions(context: context).create(name: "Exemplu Ion", template: member, values: FieldValues())
        return Household(context: context, person: person, documents: documents)
    }

    private func document(_ type: String, named name: String, values extra: [String: FieldValue] = [:], in household: Household) throws -> Asset {
        var values = FieldValues()
        values[DocumentType.typeFieldKey] = .text(type)
        for (key, value) in extra { values[key] = value }
        return try AssetActions(context: household.context).create(name: name, template: household.documents, values: values, parent: household.person)
    }

    /// A photo filed on `document`, as capture would file it.
    private func picture(on document: Asset, pages: Int = 1, seed: UInt8 = 1, in context: ModelContext) async throws -> DosarCuSina.Attachment {
        let store = CaptureDocumentStore()
        let images = (0..<pages).map { CaptureDocumentStoreTests.page(width: 900, height: 568, seed: seed &+ UInt8($0)) }
        let stored = try await store.store(.init(pages: images, kind: .passport))
        return try await AttachmentActions(context: context).fileForTest(stored.ref, from: store, title: document.name, asset: document)
    }

    private var definition: TemplateDefinition { BuiltInTemplates.documents }

    // MARK: Where a document opens

    @Test("A personal document opens as its document page; every other section keeps its section page")
    func personalDocumentsOpenAsDocumentPages() {
        #expect(DocumentPageLayout.isOn)
        #expect(DocumentPageLayout.opensAsDocumentPage(role: .personalDocument))
        for role: CategoryBehavior.Role? in [nil, .holder, .subscription, .home] {
            #expect(!DocumentPageLayout.opensAsDocumentPage(role: role))
        }
        #expect(BuiltInTemplates.documents.behavior.role == .personalDocument)
    }

    @Test("The document's own picture is its newest current one; older and archived pictures are listed under it")
    func theCurrentPicture() async throws {
        let household = try household()
        let card = try document(DocumentType.idCard, named: "Carte de identitate – Exemplu Ion", in: household)
        #expect(DocumentPageFacts.currentPicture(of: card) == nil, "No picture yet: the page asks for one")

        let old = try await picture(on: card, seed: 1, in: household.context)
        old.createdAt = Date(timeIntervalSince1970: 1_700_000_000)
        let new = try await picture(on: card, seed: 9, in: household.context)
        #expect(DocumentPageFacts.currentPicture(of: card)?.id == new.id)
        #expect(DocumentPageFacts.olderPictures(of: card).map(\.id) == [old.id])
        #expect(DocumentPageFacts.isCurrentPicture(new, ofPersonalDocument: card))
        #expect(!DocumentPageFacts.isCurrentPicture(old, ofPersonalDocument: card), "An older picture opens a page of its own")

        _ = try AttachmentActions(context: household.context).setArchived(new, true)
        #expect(DocumentPageFacts.currentPicture(of: card)?.id == old.id)
    }

    // MARK: What the page shows

    @Test("Values are listed in the template's order, secrets and fields that don't apply left out; typed values copy, choices don't")
    func valueRows() throws {
        var values = FieldValues()
        values[DocumentType.typeFieldKey] = .text(DocumentType.idCard)
        values[DocumentType.variantFieldKey] = .text(DocumentType.Variant.idCardElectronic)
        values[DocumentFields.number] = .text("XX000000")
        values[DocumentFields.personalNumber] = .text("1800101990006")
        values[DocumentFields.issueDate] = .date(CalendarDay(year: 2024, month: 3, day: 14))
        values[DocumentFields.expiry] = .date(CalendarDay(year: 2034, month: 3, day: 14))
        values["document.pinAuthentication"] = .text("sealed")
        // A cazier's result doesn't apply to an identity card.
        values[DocumentFields.recordResult] = .text("Nu figurează")

        let rows = DocumentPageFacts.rows(values, definition: definition)
        let keys = rows.map(\.key)
        #expect(keys == [DocumentType.typeFieldKey, DocumentType.variantFieldKey, DocumentFields.number, DocumentFields.personalNumber,
                         DocumentFields.issueDate, DocumentFields.expiry])
        #expect(!keys.contains("document.pinAuthentication"), "A PIN has its own row, behind Face ID")
        #expect(!keys.contains(DocumentFields.recordResult))

        let copies = Dictionary(uniqueKeysWithValues: rows.map { ($0.key, $0.copies) })
        #expect(copies[DocumentFields.number] == true)
        #expect(copies[DocumentFields.personalNumber] == true)
        #expect(copies[DocumentFields.issueDate] == true)
        #expect(copies[DocumentFields.expiry] == true)
        #expect(copies[DocumentType.typeFieldKey] == false)
        #expect(copies[DocumentType.variantFieldKey] == false)
        #expect(rows.filter(\.isExpiry).map(\.key) == [DocumentFields.expiry], "Only the expiry shows its urgency")
        #expect(rows.first { $0.key == DocumentFields.personalNumber }?.text == "1800101990006")
    }

    @Test("A copy from a personal document or a locked category stays on this phone; any other is an ordinary copy")
    func copyKind() {
        #expect(DocumentPageFacts.copyKind(isPersonalDocument: true, isLockedCategory: false) == .personal)
        #expect(DocumentPageFacts.copyKind(isPersonalDocument: false, isLockedCategory: true) == .personal)
        #expect(DocumentPageFacts.copyKind(isPersonalDocument: false, isLockedCategory: false) == .ordinary)
        for type in [FieldType.text, .date, .expiryDate, .number] { #expect(DocumentPageFacts.copiesValue(of: type)) }
        for type in [FieldType.choice, .multiChoice, .toggle, .secret] { #expect(!DocumentPageFacts.copiesValue(of: type)) }
    }

    @Test("A card's two sides are named; longer documents' pages are counted")
    func pageNames() {
        #expect(DocumentPageFacts.pageNames(count: 2) == ["Fața", "Spatele"])
        #expect(DocumentPageFacts.pageNames(count: 1) == nil)
        #expect(DocumentPageFacts.pageNames(count: 3) == nil)
    }

    @Test("The back can be added to a two-sided document kept as one photo, never to a bank card, a passport or a PDF")
    func whenTheBackCanBeAdded() async throws {
        let household = try household()
        let card = try document(DocumentType.idCard, named: "Carte de identitate – Exemplu Ion", in: household)
        #expect(!DocumentPageFacts.canAddBack(card.values, picture: nil))
        let front = try await picture(on: card, in: household.context)
        #expect(DocumentPageFacts.canAddBack(card.values, picture: front))

        var bankCard = FieldValues()
        bankCard[DocumentType.typeFieldKey] = .text(DocumentType.bankCard)
        #expect(!DocumentPageFacts.canAddBack(bankCard, picture: front), "A card's back shows its security code")
        var passport = FieldValues()
        passport[DocumentType.typeFieldKey] = .text(DocumentType.passport)
        #expect(!DocumentPageFacts.canAddBack(passport, picture: front))
        #expect(DocumentPageFacts.canAddBack(FieldValues(), picture: front), "No type yet counts as Alt document")

        let licence = try document(DocumentType.drivingLicence, named: "Permis de conducere – Exemplu Ion", in: household)
        let both = try await picture(on: licence, pages: 2, in: household.context)
        #expect(!DocumentPageFacts.canAddBack(licence.values, picture: both), "It has its back already")

        let pdf = try AttachmentActions(context: household.context).file(
            DocumentDraft(fileName: "Act.pdf", kind: .identity, contentType: "com.adobe.pdf", originalData: Data("%PDF-1.4".utf8)), asset: card)
        #expect(!DocumentPageFacts.canAddBack(card.values, picture: pdf))
    }

    @Test("A bank card's picture is never shown in a list; other documents' are")
    func picturesInLists() {
        var values = FieldValues()
        values[DocumentType.typeFieldKey] = .text(DocumentType.bankCard)
        #expect(!DocumentPageFacts.showsPicture(in: values))
        values[DocumentType.typeFieldKey] = .text(DocumentType.idCard)
        #expect(DocumentPageFacts.showsPicture(in: values))
    }

    @Test("A person's page lists every one of their documents, then a few papers; other pages list three")
    func aPersonListsTheirDocuments() {
        #expect(DocumentsPocket.shownCount(personal: 6, papers: 0, isHolder: true) == 6)
        #expect(DocumentsPocket.shownCount(personal: 5, papers: 7, isHolder: true) == 8)
        #expect(DocumentsPocket.shownCount(personal: 0, papers: 7, isHolder: false) == 3)
        #expect(DocumentsPocket.shownCount(personal: 1, papers: 1, isHolder: false) == 2)
        #expect(BuiltInTemplates.member.pockets.contains(.documents))
        #expect(BuiltInTemplates.member.behavior.role == .holder)
    }

    // MARK: Naming

    @Test("A name that is still the type's own follows a corrected type; a name of one's own never changes")
    func retyping() {
        #expect(DocumentNaming.retyped("Alt document – Exemplu Ion", from: "Alt document", to: "Pașaport") == "Pașaport – Exemplu Ion")
        #expect(DocumentNaming.retyped("alt document", from: "Alt document", to: "Pașaport") == "Pașaport")
        #expect(DocumentNaming.retyped("Buletinul vechi", from: "Carte de identitate", to: "Pașaport") == nil)
        #expect(DocumentNaming.retyped("Pașaport – Exemplu Ion", from: "Pașaport", to: "Pașaport") == nil)
        #expect(DocumentNaming.retyped("Carte de identitate – Exemplu Ion Mihai", from: "Carte de identitate", to: "Permis de conducere")
                == "Permis de conducere – Exemplu Ion Mihai", "The holder's name stays as it was written")
    }

    // MARK: Editing through the actions

    @Test("Adding the back keeps the front as it was, shows the back as capture prepared it, and keeps the fingerprint")
    func addingPages() async throws {
        let household = try household()
        let card = try document(DocumentType.idCard, named: "Carte de identitate – Exemplu Ion", in: household)
        let front = try await picture(on: card, in: household.context)
        let frontData = front.orderedPages.first?.imageData
        let fingerprint = front.sha256
        let bytes = front.byteCount
        let back = Data([0x01, 0x02, 0x03])
        let turned = PageFraming.plain.turned()

        try AttachmentActions(context: household.context).addPages(AddedPages(images: [back], framing: [turned]), to: front)
        #expect(front.orderedPages.map(\.imageData) == [frontData, back])
        #expect(front.framing[page: 1] == turned)
        #expect(front.sha256 == fingerprint)
        #expect(front.byteCount == bytes + back.count)
    }

    @Test("A document kept as a PDF takes no pages")
    func noPagesForAPDF() throws {
        let household = try household()
        let card = try document(DocumentType.idCard, named: "Carte de identitate – Exemplu Ion", in: household)
        let pdf = try AttachmentActions(context: household.context).file(
            DocumentDraft(fileName: "Act.pdf", kind: .identity, contentType: "com.adobe.pdf", originalData: Data("%PDF-1.4".utf8)), asset: card)
        #expect(throws: AddedPages.Refusal.keptWhole) {
            try AttachmentActions(context: household.context).addPages(AddedPages(images: [Data([1])], framing: []), to: pdf)
        }
    }

    @Test("A bank card's picture takes no back, from any screen, nor does a document made a bank card in the same edit")
    func noBackForABankCard() async throws {
        let household = try household()
        let card = try document(DocumentType.bankCard, named: "Card bancar", in: household)
        let front = try await picture(on: card, in: household.context)
        #expect(throws: AddedPages.Refusal.noBackSide) {
            try AttachmentActions(context: household.context).addPages(AddedPages(images: [Data([1])], framing: [.plain]), to: front)
        }
        #expect(front.orderedPages.count == 1)

        let other = try document(DocumentType.other, named: "Alt document", in: household)
        let otherFront = try await picture(on: other, in: household.context)
        var values = other.values
        values[DocumentType.typeFieldKey] = .text(DocumentType.bankCard)
        let edit = AssetActions.DocumentEdit(name: other.name, values: values, notes: nil,
                                             addedPages: AddedPages(images: [Data([1])], framing: [.plain]))
        #expect(throws: AddedPages.Refusal.noBackSide) {
            try AssetActions(context: household.context).editDocument(other, edit, picture: otherFront)
        }
        #expect(otherFront.orderedPages.count == 1)
    }

    @Test("Editează saves the values, the back and the text read as one step, and Anulează takes all of it back")
    func editingIsOneUndoableStep() async throws {
        let household = try household()
        let card = try document(DocumentType.other, named: "Alt document – Exemplu Ion", values: [DocumentFields.number: .text("XX000000")], in: household)
        let front = try await picture(on: card, in: household.context)
        let before = card.values

        var values = card.values
        values[DocumentType.typeFieldKey] = .text(DocumentType.idCard)
        values[DocumentFields.number] = .text("XX000001")
        let edit = AssetActions.DocumentEdit(name: card.name, values: values, notes: nil,
                                             addedPages: AddedPages(images: [Data([0x09])], framing: [.plain]),
                                             readText: "CARTE DE IDENTITATE 4111 1111 1111 1111")
        let saved = try AssetActions(context: household.context).editDocument(card, edit, picture: front)
        #expect(card.values[DocumentFields.number]?.textValue == "XX000001")
        #expect(card.name == "Carte de identitate – Exemplu Ion", "The name follows the corrected type")
        #expect(front.orderedPages.count == 2)
        #expect(front.extractedText?.contains("4111 1111 1111 1111") == false, "No card number is kept in a document's text")

        #expect(saved.receipt.canUndo)
        try saved.receipt.undo()
        #expect(card.values == before)
        #expect(card.name == "Alt document – Exemplu Ion")
        #expect(front.orderedPages.count == 1, "The back added in the step goes with it")
        #expect(try household.context.fetchCount(FetchDescriptor<AttachmentPage>()) == 1)
    }

    @Test("A name the person changes in the same edit is theirs, even when the type changes")
    func ownNameStays() throws {
        let household = try household()
        let card = try document(DocumentType.other, named: "Alt document – Exemplu Ion", in: household)
        var values = card.values
        values[DocumentType.typeFieldKey] = .text(DocumentType.passport)
        _ = try AssetActions(context: household.context).editDocument(
            card, AssetActions.DocumentEdit(name: "Pașaportul nou", values: values, notes: nil), picture: nil)
        #expect(card.name == "Pașaportul nou")
    }

    @Test("Adding the back to an example asks first, and changes nothing until the person keeps it")
    func backOnAnExampleAsks() async throws {
        let household = try household()
        let card = try document(DocumentType.idCard, named: "Carte de identitate – Exemplu Ion", in: household)
        let front = try await picture(on: card, in: household.context)
        card.isExample = true
        household.person.isExample = true
        let edit = AssetActions.DocumentEdit(name: card.name, values: card.values, notes: nil,
                                             addedPages: AddedPages(images: [Data([0x09])], framing: [.plain]))
        #expect(throws: ExampleSectionQuestion.self) {
            try AssetActions(context: household.context).editDocument(card, edit, picture: front)
        }
        #expect(front.orderedPages.count == 1)
    }

    // MARK: Reading again

    private func engine(store: CaptureDocumentStore) -> CaptureEngine {
        CaptureEngine(analyzer: CaptureAnalyzer(), recognizer: CaptureEngineTests.FixedRecognizer(text: CaptureEngineTests.passportText),
                      normalizer: nil, onDeviceModel: nil, cloudModel: nil, store: store)
    }

    private let today = Date(timeIntervalSince1970: 1_793_577_600)

    @Test("Citește din nou reads the kept picture with the engine and puts what it read into the form, saying what changed")
    func readingAgain() async throws {
        let household = try household()
        let passport = try document(DocumentType.passport, named: "Pașaport – Exemplu Ion", values: [DocumentFields.number: .text("X0000000")], in: household)
        let photo = try await picture(on: passport, in: household.context)
        let store = CaptureDocumentStore()
        let reading = DocumentReading(context: household.context, engine: engine(store: store), store: store, referenceDate: today)

        let outcome = try await reading.read(passport, picture: photo, into: passport.values, definition: definition)
        #expect(outcome.values[DocumentFields.expiry]?.dateValue == CalendarDay(year: 2031, month: 4, day: 15))
        #expect(outcome.values[DocumentType.typeFieldKey]?.textValue == DocumentType.passport, "The type stays the person's")
        #expect(outcome.changes.contains { $0.key == DocumentFields.expiry && $0.before == nil })
        #expect(outcome.changes.allSatisfy { outcome.values[$0.key] == $0.after })
        #expect(outcome.addedPages == nil, "Nothing is added by reading again")
        #expect(outcome.readText?.isEmpty == false)
        #expect(passport.values[DocumentFields.expiry] == nil, "Nothing is saved until Gata")
    }

    @Test("Adding the back reads front and back as one document; only the back is new")
    func addingTheBackReadsBoth() async throws {
        let household = try household()
        let passport = try document(DocumentType.passport, named: "Pașaport – Exemplu Ion", in: household)
        let photo = try await picture(on: passport, in: household.context)
        let store = CaptureDocumentStore()
        let reading = DocumentReading(context: household.context, engine: engine(store: store), store: store, referenceDate: today)
        let back = CaptureImage(image: CaptureDocumentStoreTests.page(width: 900, height: 568, seed: 40))

        let outcome = try await reading.read(passport, picture: photo, adding: [back], into: passport.values, definition: definition)
        let added = try #require(outcome.addedPages)
        #expect(added.images.count == 1)
        #expect(added.framing.count == 1)
        #expect(outcome.values[DocumentFields.expiry] != nil)
        #expect(photo.orderedPages.count == 1, "The page waits in the form until Gata")
    }

    @Test("What was read keeps the type the person chose, unless it is Alt document")
    func readingKeepsTheType() {
        var form = FieldValues()
        form[DocumentType.typeFieldKey] = .text(DocumentType.idCard)
        var read = FieldValues()
        read[DocumentType.typeFieldKey] = .text(DocumentType.passport)
        read[DocumentType.variantFieldKey] = .text(DocumentType.Variant.passportElectronic)
        read[DocumentFields.number] = .text("X0000000")
        let kept = DocumentReading.keepingType(of: form, in: read)
        #expect(kept[DocumentType.typeFieldKey] == nil)
        #expect(kept[DocumentType.variantFieldKey] == nil)
        #expect(kept[DocumentFields.number] != nil)

        form[DocumentType.typeFieldKey] = .text(DocumentType.other)
        #expect(DocumentReading.keepingType(of: form, in: read)[DocumentType.typeFieldKey]?.textValue == DocumentType.passport)
        #expect(DocumentReading.kind(for: form) == nil)
        form[DocumentType.typeFieldKey] = .text(DocumentType.passport)
        #expect(DocumentReading.kind(for: form) == .passport)
    }

    @Test("A value read that only differs in how it is written doesn't change what the person typed")
    func mergingKeepsTheWayItIsWritten() {
        var current = FieldValues()
        current[VehicleFields.plate] = .text("B-123-ABC")
        var read = FieldValues()
        read[VehicleFields.plate] = .text("B 123 ABC")
        read[DocumentFields.number] = .text("X0000000")
        let merged = CaptureFiler.merging(read, into: current)
        #expect(merged[VehicleFields.plate]?.textValue == "B-123-ABC")
        #expect(merged[DocumentFields.number]?.textValue == "X0000000")
    }

    @Test("The note after reading names the values it changed")
    func changedLine() {
        let changes = [
            DocumentReading.Change(key: DocumentFields.personalNumber, label: "CNP", before: nil, after: .text("1800101990006")),
            DocumentReading.Change(key: DocumentFields.expiry, label: "Valabil până la", before: nil, after: .date(CalendarDay(year: 2031, month: 4, day: 15))),
        ]
        let line = DocumentEditSheet.changedLine(changes)
        #expect(line.contains("CNP"))
        #expect(line.contains("Valabil până la"))
    }
}
