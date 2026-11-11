import Foundation
import SwiftData
import Testing
@testable import DosarCuSina

/// A bank card's full number is never kept, from any path: a row typed under Date importante,
/// a section's notes and values, a visit and its line items, a reading, a deadline, a firm, a
/// document, a category of one's own, a backup brought in. The unit of work masks it as it
/// saves (`FreeText`); a secret is masked before it is sealed; what an earlier version kept is
/// offered in the repair list. Card numbers are the networks' published test numbers only.
@MainActor
@Suite("Card numbers kept out of every record")
struct CardNumbersKeptOutTests {
    static let visa = "4111 1111 1111 1111"
    static let mastercard = "5555555555554444"
    static let visaMasked = "\(PaymentCardNumbers.mask) 1111"
    static let mastercardMasked = "\(PaymentCardNumbers.mask) 4444"

    /// Whether `text` still holds either test number, however it is spaced.
    static func holdsNumber(_ text: String?) -> Bool {
        guard let text else { return false }
        let digits = text.filter { $0.isNumber || $0 == "•" }
        return digits.contains("4111111111111111") || digits.contains("5555555555554444")
    }

    private static func raw(_ data: Data?) -> String {
        data.flatMap { String(data: $0, encoding: .utf8) } ?? ""
    }

    // MARK: Every stored text is listed

    @Test func everyStoredTextOfEveryModelIsWordsOrNeverWords() throws {
        let schema = Schema(versionedSchema: DosarSchemaV14.self)
        #expect(FreeText.types.count == DosarSchemaV14.models.count, "Every model says which of its texts are words")
        let textTypes: Set<String> = ["String", "Optional<String>", "Data", "Optional<Data>", "Array<String>"]
        for entity in schema.entities {
            let type = try #require(FreeText.types.first { String(describing: $0) == entity.name }, "\(entity.name) lists its words")
            let (words, machine) = Self.lists(type)
            #expect(words.isDisjoint(with: machine), "\(entity.name): a property is words or not, never both")
            let texts = Set(entity.attributes.filter { textTypes.contains(String(describing: $0.valueType)) }.map(\.name))
            #expect(words.union(machine) == texts, "\(entity.name): every stored text and data property is listed once")
        }
    }

    private static func lists<M: HoldsFreeText>(_ type: M.Type) -> (Set<String>, Set<String>) {
        (Set(M.freeText.map(\.name)), M.machineText)
    }

    // MARK: A row typed under Date importante

    @Test func aRowTypedUnderDateImportanteKeepsOnlyTheLastFourDigits() throws {
        let context = try makeContext()
        let actions = AssetActions(context: context, calendar: .bucharest, now: { noon("2026-11-10") }, sealer: .ephemeral())
        let home = try actions.create(name: "Casa din exemplu", template: try #require(try TemplateStore(context: context).template(forKey: BuiltInTemplates.Key.other)), values: FieldValues())
        let receipt = try actions.setCustomFacts(home, [
            CustomFact(label: "Card de rezervă \(Self.visa)", value: Self.visa),
            CustomFact(label: "Contract apă", value: "EXM 0000001"),
        ])

        let stored = try #require(Asset.find(home.recordKey, in: ModelContext(context.container)))
        #expect(stored.customFacts.map(\.label) == ["Card de rezervă \(Self.visaMasked)", "Contract apă"], "The label is masked too")
        #expect(stored.customFacts.map(\.value) == [Self.visaMasked, "EXM 0000001"], "Only the last four digits stay; the rest is as typed")
        #expect(!Self.holdsNumber(Self.raw(stored.customFactsData)), "Not even the stored JSON holds it")

        try receipt.undo()
        #expect(ModelContext(context.container).fetchAll(Asset.self).first { $0.id == home.id }?.customFacts.isEmpty == true,
                "Undo takes the rows back as before")
    }

    @Test func aSecretRowIsSealedWithTheCardNumberMaskedFirst() throws {
        let context = try makeContext()
        let sealer = SecretSealer.ephemeral()
        let actions = AssetActions(context: context, calendar: .bucharest, now: { noon("2026-11-10") }, sealer: sealer)
        let home = try actions.create(name: "Casa din exemplu", template: try #require(try TemplateStore(context: context).template(forKey: BuiltInTemplates.Key.other)), values: FieldValues())
        try actions.setCustomFacts(home, [CustomFact(label: "Cod alarmă", value: "Card \(Self.mastercard)", isSecret: true)])

        let fact = try #require(home.customFacts.first)
        #expect(SecretSealer.isSealed(fact.value), "A secret row is kept sealed")
        #expect(try sealer.open(fact.value) == "Card \(Self.mastercardMasked)", "What is sealed has no card number in it")
    }

    // MARK: A section's fields and notes

    @Test func aSectionsNameNotesAndFieldsKeepNoCardNumber() throws {
        let context = try makeContext()
        let store = TemplateStore(context: context)
        let actions = AssetActions(context: context, calendar: .bucharest, now: { noon("2026-11-10") }, sealer: .ephemeral())
        let documents = try #require(try store.template(forKey: BuiltInTemplates.Key.documents))
        let card = try actions.create(name: "Card Visa \(Self.visa)", template: documents, values: FieldValues([
            DocumentType.typeFieldKey: .text(DocumentType.bankCard),
            DocumentFields.cardLastFour: .text(Self.visa),
        ]), notes: "Rezervă: \(Self.mastercard)")

        #expect(card.name == "Card Visa \(Self.visaMasked)")
        #expect(card.notes == "Rezervă: \(Self.mastercardMasked)")
        #expect(card.values[DocumentFields.cardLastFour]?.textValue == "1111", "The last digits field keeps only the last four")

        let lake = try store.createCustom(name: "Bărci", symbol: "sailboat.fill", tint: .teal, sections: [
            FieldSection(key: "boat.main", title: "Barcă", fields: [FieldDefinition(key: "boat.code", label: "Cod", type: .text)]),
        ])
        let boat = try actions.create(name: "Barca de pe lac", template: lake, values: FieldValues())
        try actions.update(boat, name: boat.name, values: FieldValues(["boat.code": .text("Plătit cu \(Self.visa)")]), notes: "Card \(Self.mastercard)")
        let stored = try #require(Asset.find(boat.recordKey, in: ModelContext(context.container)))
        #expect(stored.values["boat.code"]?.textValue == "Plătit cu \(Self.visaMasked)")
        #expect(stored.notes == "Card \(Self.mastercardMasked)")
    }

    // MARK: Every other record's words, from any path

    @Test func everyRecordsWordsAreMaskedWhereverTheyAreWritten() throws {
        let context = try makeContext()
        let number = Self.visa
        let lake = CategoryTemplate(definition: TemplateDefinition(
            key: TemplateDefinition.newCustomKey(), name: "Bărci \(number)", summary: "Card \(number)", symbol: "sailboat.fill", tint: .teal,
            sections: [FieldSection(key: "boat.main", title: "Barcă", fields: [
                FieldDefinition(key: "boat.code", label: "Cod \(number)", type: .text),
            ])],
            blueprints: [ObligationBlueprint(key: "boat.engine", title: "Service \(number)", kind: .maintenance, recurrence: .interval(.years(1), anchor: .dueDate))]
        ), isBuiltIn: false, homeOrder: 50)
        context.insert(lake)
        let boat = Asset(name: "Barca de pe lac", templateKey: lake.key)
        context.insert(boat)
        let deadline = Obligation(title: "Service \(number)", kind: .maintenance, dueDay: CalendarDay("2026-12-01"))
        deadline.notes = number
        deadline.provider = "Service \(number)"
        deadline.reference = number
        context.insert(deadline)
        deadline.asset = boat
        let visit = HistoryEntry(kind: .repair, title: "Rotor \(number)", occurredAt: noon("2026-11-01"))
        visit.note = number
        visit.reference = number
        context.insert(visit)
        visit.asset = boat
        let item = ServiceItem(name: "Rotor \(number)")
        item.group = number
        item.partBrandOrCode = number
        item.partSerialNumber = number
        item.batchOrTicket = number
        item.locationDetail = number
        item.notes = number
        context.insert(item)
        item.entry = visit
        let reading = MeasurementLog(kind: .engineHours, name: "Ore \(number)", value: 210, recordedAt: noon("2026-11-01"))
        reading.source = number
        reading.notes = number
        context.insert(reading)
        reading.asset = boat
        let firm = Provider(name: "Service \(number)")
        firm.trades = [ProviderTrade.mechanic.rawValue, "Bărci \(number)"]
        firm.phone = number
        firm.email = number
        firm.address = number
        firm.notes = number
        context.insert(firm)
        let paper = DosarCuSina.Attachment(fileName: "card \(number).pdf", contentType: "com.adobe.pdf", data: Data("%PDF".utf8), kind: .other)
        paper.title = "Card \(number)"
        paper.extractedText = "Titular EXEMPLU\nCard \(number)"
        context.insert(paper)
        paper.asset = boat
        try UnitOfWork.save(context)

        // Read from the store: what is really kept.
        let saved = ModelContext(context.container)
        for type in FreeText.types {
            for (record, holding) in try Self.holding(type, in: saved) {
                Issue.record("\(record) still keeps a card number in \(holding)")
            }
        }
        let storedLake = try #require(CategoryTemplate.find(lake.key, in: saved))
        #expect(storedLake.name == "Bărci \(Self.visaMasked)")
        #expect(storedLake.sections.first?.fields.first?.label == "Cod \(Self.visaMasked)", "A category still reads after its words are masked")
        #expect(storedLake.blueprints.first?.title == "Service \(Self.visaMasked)")
        #expect(try #require(DosarCuSina.Attachment.find(paper.recordKey, in: saved)).fileName == "card \(Self.visaMasked).pdf")
        #expect(try #require(Provider.find(firm.recordKey, in: saved)).trades == [ProviderTrade.mechanic.rawValue, "Bărci \(Self.visaMasked)"])
    }

    @Test func aVisitAndItsLineItemsThroughTheirActionKeepNoCardNumber() throws {
        let context = try makeContext()
        let actions = AssetActions(context: context, calendar: .bucharest, now: { noon("2026-11-10") }, sealer: .ephemeral())
        let car = try actions.create(name: "VW Golf 2018", template: try #require(try TemplateStore(context: context).template(forKey: BuiltInTemplates.Key.vehicle)), values: FieldValues())
        let entry = try HistoryActions(context: context, now: { noon("2026-11-10") }).record(
            on: car, kind: .repair, title: "Plăcuțe frână", note: "Plătit cu \(Self.visa)",
            items: [LineItemDraft(name: "Plăcuțe", partSerialNumber: Self.mastercard, notes: "Card \(Self.visa)")]
        )
        let saved = ModelContext(context.container)
        let stored = try #require(HistoryEntry.find(entry.recordKey, in: saved))
        #expect(stored.note == "Plătit cu \(Self.visaMasked)")
        let item = try #require(stored.items?.first)
        #expect(item.partSerialNumber == Self.mastercardMasked)
        #expect(item.notes == "Card \(Self.visaMasked)")
    }

    @Test func wordsWithoutACardNumberAreKeptExactlyAsWritten() throws {
        let context = try makeContext()
        // A CNP, an IBAN, a phone number, an IMEI-like run that fails the check digit, a plate.
        let texts = ["1800101990006", "RO49 AAAA 1B31 0075 9384 0000", "0700 000 000", "B-123-ABC", "123456789012345"]
        let firm = Provider(name: "ENGIE Romania S.A.")
        firm.notes = texts.joined(separator: "\n")
        context.insert(firm)
        try UnitOfWork.save(context)
        #expect(try #require(Provider.find(firm.recordKey, in: ModelContext(context.container))).notes == texts.joined(separator: "\n"))
        #expect(FreeText.mask(firm, write: false).isEmpty)
    }

    @Test func ibansAndAPetsMicrochipAreKeptWholeWhereverTheyAreTyped() throws {
        let context = try makeContext()
        let store = TemplateStore(context: context)
        let actions = AssetActions(context: context, calendar: .bucharest, now: { noon("2026-11-10") }, sealer: .ephemeral())
        // The example IBANs, in one piece and in groups, in a firm's notes and a row.
        let ibans = PersonalDocumentCaptureTests.exampleIBANs.flatMap { [$0, FieldFormatter.groupIBAN($0)] }
        let firm = Provider(name: "ENGIE Romania S.A.")
        firm.notes = ibans.joined(separator: "\n")
        context.insert(firm)
        try UnitOfWork.save(context)
        #expect(try #require(Provider.find(firm.recordKey, in: ModelContext(context.container))).notes == ibans.joined(separator: "\n"))

        // A Romanian pet's microchip whose digits would pass as a Maestro card: whole in its own
        // field, and in the section's notes, where its field says what those digits are. Other
        // digits shaped the same way, and a card number, are still masked there.
        let chip = PersonalDocumentCaptureTests.withCheckDigit("642" + String(repeating: "0", count: 8) + "123")
        let other = PersonalDocumentCaptureTests.withCheckDigit("642" + String(repeating: "0", count: 8) + "456")
        let pets = try #require(try store.template(forKey: BuiltInTemplates.Key.pet))
        let pet = try actions.create(name: "Motănelul din exemplu", template: pets, values: FieldValues([PetFields.microchip: .text(chip)]),
                                     notes: "Cip \(chip)\nAlt cip \(other)\nCard \(Self.visa)")
        let stored = try #require(Asset.find(pet.recordKey, in: ModelContext(context.container)))
        #expect(stored.values[PetFields.microchip]?.textValue == chip)
        #expect(stored.notes == "Cip \(chip)\nAlt cip \(PaymentCardNumbers.mask) \(other.suffix(4))\nCard \(Self.visaMasked)")

        // An IBAN field of one's own whose account is the test card number: it passes its own check.
        let iban = PersonalDocumentCaptureTests.iban(country: "RO", account: "AAAA" + Self.visa.filter(\.isNumber))
        let rent = try store.createCustom(name: "Chirie", symbol: "house.fill", tint: .teal, sections: [
            FieldSection(key: "rent.main", title: "Chirie", fields: [FieldDefinition(key: "rent.iban", label: "IBAN", type: .iban)]),
        ])
        let flat = try actions.create(name: "Apartament", template: rent, values: FieldValues(["rent.iban": .text(FieldFormatter.groupIBAN(iban))]))
        let kept = try #require(Asset.find(flat.recordKey, in: ModelContext(context.container)))
        #expect(kept.values["rent.iban"]?.textValue.map { FieldFormatter.normalize($0, as: .iban) } == iban)
        #expect(FreeText.mask(kept, write: false).isEmpty)
    }

    // MARK: A backup brought in

    @Test func aBackupFromBeforeBringsNoCardNumberIn() throws {
        // A phone from before kept a card number in a section's notes and a row: saved
        // around the unit of work, as an earlier version could.
        let old = try makeContext()
        let boat = Asset(name: "Barca de pe lac", templateKey: BuiltInTemplates.Key.other, notes: "Card \(Self.visa)")
        boat.customFacts = [CustomFact(label: "Card", value: Self.mastercard)]
        old.insert(boat)
        let visit = HistoryEntry(kind: .note, title: "Plată \(Self.visa)", occurredAt: noon("2026-11-01"))
        old.insert(visit)
        visit.asset = boat
        try old.save()
        let backup = try DossierArchiveService(container: old.container, calendar: .bucharest).exportData(exportedAt: noon("2026-11-10"))

        let phone = try makeInMemoryContainer()
        try DossierArchiveService(container: phone, calendar: .bucharest).importArchive(backup, mode: .replace)
        let context = ModelContext(phone)
        let stored = try #require(Asset.find(boat.recordKey, in: context))
        #expect(stored.notes == "Card \(Self.visaMasked)")
        #expect(stored.customFacts.map(\.value) == [Self.mastercardMasked])
        #expect(try #require(HistoryEntry.find(visit.recordKey, in: context)).title == "Plată \(Self.visaMasked)")
    }

    // MARK: Kept by an earlier version: the repair list

    private func repairs(_ context: ModelContext) -> DataRepairs {
        DataRepairs(context: context, calendar: .bucharest,
                    ledger: DataRepairLedger(defaults: UserDefaults(suiteName: "card-numbers-\(UUID().uuidString)")!))
    }

    @Test func numbersAnEarlierVersionKeptAreOfferedAndMaskedOnlyWithTheOwnersOK() throws {
        let context = try makeContext()
        let boat = Asset(name: "Barca de pe lac", templateKey: BuiltInTemplates.Key.other)
        boat.customFacts = [CustomFact(label: "Card", value: Self.visa)]
        context.insert(boat)
        let visit = HistoryEntry(kind: .note, title: "Plată", occurredAt: noon("2026-11-01"))
        visit.note = "Card \(Self.mastercard)"
        context.insert(visit)
        visit.asset = boat
        let clean = Asset(name: "VW Golf 2018", templateKey: BuiltInTemplates.Key.other, notes: "B-123-ABC")
        context.insert(clean)
        // Saved as an earlier version did, around the unit of work.
        try context.save()

        let found = try repairs(context).detect().filter { $0.step == .cardNumbers }
        #expect(found.count == 2, "The section with the row and the visit, nothing else")
        #expect(found.map(\.message).sorted() == [
            "La Barca de pe lac, „Plată” păstrează un număr de card întreg. Păstrez doar ultimele patru cifre?",
            "„Barca de pe lac” păstrează un număr de card întreg. Păstrez doar ultimele patru cifre?",
        ].sorted())
        for finding in found {
            #expect(!Self.holdsNumber(finding.message) && !Self.holdsNumber(finding.id), "The list never shows or stores the number")
        }
        #expect(boat.customFacts.first?.value == Self.visa, "Nothing changes before the owner says so")

        try repairs(context).apply(found)
        let saved = ModelContext(context.container)
        #expect(try #require(Asset.find(boat.recordKey, in: saved)).customFacts.first?.value == Self.visaMasked)
        #expect(try #require(HistoryEntry.find(visit.recordKey, in: saved)).note == "Card \(Self.mastercardMasked)")
        #expect(try repairs(context).detect().filter { $0.step == .cardNumbers }.isEmpty, "A second pass finds nothing")
    }

    @Test func aNameThatHoldsTheNumberIsShownMasked() throws {
        let context = try makeContext()
        let card = Asset(name: "Card \(Self.visa)", templateKey: BuiltInTemplates.Key.other)
        context.insert(card)
        try context.save()
        let finding = try #require(try repairs(context).detect().first { $0.step == .cardNumbers })
        #expect(finding.message == "„Card \(Self.visaMasked)” păstrează un număr de card întreg. Păstrez doar ultimele patru cifre?")
    }

    // MARK: What the field says while typing

    @Test func aFieldSaysOnlyTheLastFourDigitsAreKept() {
        let note = DSValidation.keepingCardNumberOut(of: "Card \(Self.visa)")
        #expect(note?.isWarning == true, "A note, never a block")
        for text in ["1800101990006", "RO49 AAAA 1B31 0075 9384 0000", "0700 000 000", "Cod alarmă", ""] {
            #expect(DSValidation.keepingCardNumberOut(of: text) == nil, "\(text)")
        }
        #expect(DSValidation.requiredMissing.notingCardNumber(in: Self.visa).isInvalid, "A field's own problem comes first")
        #expect(DSValidation.valid.notingCardNumber(in: Self.mastercard).isWarning)
    }

    // MARK: Helpers

    /// Every record of `type` in `context` whose words hold a card number, with where.
    private static func holding<M: HoldsFreeText>(_ type: M.Type, in context: ModelContext) throws -> [(String, [String])] {
        try context.fetch(FetchDescriptor<M>()).compactMap { record in
            let names = FreeText.mask(record, write: false)
            return names.isEmpty ? nil : ("\(M.self) \(record.recordKey)", names)
        }
    }
}

private extension ModelContext {
    func fetchAll<M: PersistentModel>(_ type: M.Type) -> [M] {
        (try? fetch(FetchDescriptor<M>())) ?? []
    }
}
