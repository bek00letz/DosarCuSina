import Foundation
import SwiftData

/// One stored property of `Model` that holds words: what a person typed or a reader read (a
/// name, a note, a section's values, its rows under Date importante, a document's text), as
/// opposed to ids, keys, hashes, content types and pictures. The unit of work masks every card
/// number in these as it saves (`FreeText`).
struct FreeTextProperty<Model: PersistentModel> {
    let name: String
    /// Whether the property holds a card number; with `write`, it is masked too.
    let mask: (_ record: Model, _ write: Bool) -> Bool

    /// Plain text, masked by the "anywhere" rule (`PaymentCardNumbers.redact`).
    static func text(_ name: String, _ keyPath: ReferenceWritableKeyPath<Model, String>) -> Self {
        Self(name: name) { record, write in
            let text = record[keyPath: keyPath]
            let masked = PaymentCardNumbers.redact(text)
            guard masked != text else { return false }
            if write { record[keyPath: keyPath] = masked }
            return true
        }
    }

    static func text(_ name: String, _ keyPath: ReferenceWritableKeyPath<Model, String?>) -> Self {
        Self(name: name) { record, write in
            guard let text = record[keyPath: keyPath] else { return false }
            let masked = PaymentCardNumbers.redact(text)
            guard masked != text else { return false }
            if write { record[keyPath: keyPath] = masked }
            return true
        }
    }

    /// A list of words (a firm's trades, free text allowed).
    static func texts(_ name: String, _ keyPath: ReferenceWritableKeyPath<Model, [String]>) -> Self {
        Self(name: name) { record, write in
            let texts = record[keyPath: keyPath]
            let masked = texts.map { PaymentCardNumbers.redact($0) }
            guard masked != texts else { return false }
            if write { record[keyPath: keyPath] = masked }
            return true
        }
    }

    /// A section's values, stored as JSON `FieldValues`, by the rule for fields
    /// (`PaymentCardNumbers.sanitizing`): a bank card's last digits cut to four, sealed codes left
    /// alone, a value its own field type tells apart from a card (an IBAN, a microchip) kept whole.
    /// What a newer build wrote inside a value is masked too, and kept (`KeptObject`).
    static func values(_ name: String, _ keyPath: ReferenceWritableKeyPath<Model, Data?>, fields: @escaping (Model) -> [FieldDefinition]) -> Self {
        Self(name: name) { record, write in
            guard let values = KeptObject.stored(in: record[keyPath: keyPath], fallback: FieldValues()) else { return false }
            let masked = PaymentCardNumbers.sanitizing(values, fields: { fields(record) })
            guard masked != values else { return false }
            if write { record[keyPath: keyPath] = KeptObject.data(masked) }
            return true
        }
    }

    /// Rows under Date importante, stored as JSON, with the rows a newer build wrote
    /// (`PaymentCardNumbers.sanitizing` for rows): a secret row's sealed code is left alone.
    static func facts(_ name: String, _ keyPath: ReferenceWritableKeyPath<Model, Data?>) -> Self {
        Self(name: name) { record, write in
            guard let data = record[keyPath: keyPath] else { return false }
            let facts = KeptList<CustomFact>.stored(in: data)
            let masked = PaymentCardNumbers.sanitizing(facts)
            guard masked != facts else { return false }
            if write { record[keyPath: keyPath] = StoredJSON.encode(masked) }
            return true
        }
    }

    /// JSON with words inside (a category of one's own: its fields' names, choices and
    /// defaults, its deadlines' titles): every string in it, sealed codes left alone. Written
    /// again only when something was masked, so the bytes of everything else never change.
    static func json(_ name: String, _ keyPath: ReferenceWritableKeyPath<Model, Data?>) -> Self {
        Self(name: name) { record, write in
            guard let data = record[keyPath: keyPath], let raw = StoredJSON.decode(JSONValue.self, from: data) else { return false }
            let masked = PaymentCardNumbers.redacting(raw)
            guard masked != raw else { return false }
            if write { record[keyPath: keyPath] = StoredJSON.encode(masked) }
            return true
        }
    }
}

/// A record whose every stored text and data property is either words (`freeText`) or never
/// a person's words (`machineText`). `FreeTextTests` checks the two lists against the schema,
/// so a new property can't be forgotten.
protocol HoldsFreeText: UndoableRecord {
    static var freeText: [FreeTextProperty<Self>] { get }
    /// Stored text and data that are never words: ids, keys, raw values of the app's own
    /// choices, hashes, content types, the app's own JSON (a rule, a framing) and pictures.
    static var machineText: Set<String> { get }
}

/// A bank card's full number is never kept in the binder, whoever wrote it and from wherever:
/// a row typed under Date importante, a note, a visit's title, a firm's address, a document's
/// text, a backup brought in. The unit of work masks every card number in the words of every
/// record it saves, just before it saves, by the one rule (`PaymentCardNumbers`): only the last
/// four digits stay ("•••• 1111"). Every save goes through the unit of work (the
/// `save-outside-unit-of-work` check), and every stored text is listed (`HoldsFreeText`), so a
/// new action or a new property can't go around it.
///
/// A secret (a PIN, a code row) is sealed before it is saved, and masked first
/// (`SecretFields.sealing`); its sealed text is never rewritten here.
enum FreeText {
    /// Masks every card number in the words of every record `context` is about to save.
    static func mask(_ context: ModelContext) {
        context.processPendingChanges()
        for model in context.insertedModelsArray + context.changedModelsArray {
            guard let record = model as? any HoldsFreeText else { continue }
            mask(record, write: true)
        }
    }

    /// The names of the properties of `record` that hold a card number; masked when `write`.
    @discardableResult
    static func mask<M: HoldsFreeText>(_ record: M, write: Bool) -> [String] {
        M.freeText.filter { $0.mask(record, write) }.map(\.name)
    }

    /// Every type of the schema that keeps words.
    static var types: [any HoldsFreeText.Type] {
        DosarSchemaV9.models.compactMap { $0 as? any HoldsFreeText.Type }
    }
}

// MARK: - The schema's words

extension DosarSchemaV9.Asset: HoldsFreeText {
    static var freeText: [FreeTextProperty<DosarSchemaV9.Asset>] {
        [
            .text("name", \.name), .text("notes", \.notes), .values("valuesData", \.valuesData, fields: \.categoryFields),
            .facts("customFactsData", \.customFactsData),
        ]
    }
    static var machineText: Set<String> { ["templateKey", "symbolOverride", "tintOverrideRaw", "photoData"] }

    /// The fields its category defines, so a value its own type tells apart from a card number
    /// stays whole (`PaymentCardNumbers.keepsWhole`). None when the category can't be found.
    /// Read only when a value would be masked, and on any thread (a backup's own context).
    fileprivate var categoryFields: [FieldDefinition] {
        guard let context = modelContext, let template = (try? TemplateStore.templatesByKey(in: context))?[templateKey] else { return [] }
        return template.definition.allFields
    }
}

extension DosarSchemaV9.Obligation: HoldsFreeText {
    static var freeText: [FreeTextProperty<DosarSchemaV9.Obligation>] {
        // A recurrence is the app's own words, but what a newer build wrote inside it may not be.
        [.text("title", \.title), .text("notes", \.notes), .text("provider", \.provider), .text("reference", \.reference),
         .json("recurrenceData", \.recurrenceData)]
    }
    static var machineText: Set<String> { ["blueprintKey", "kindRaw", "dueDayISO", "consequenceRaw", "estimatedCostCurrency", "statusRaw", "snoozedUntilISO"] }
}

extension DosarSchemaV9.HistoryEntry: HoldsFreeText {
    static var freeText: [FreeTextProperty<DosarSchemaV9.HistoryEntry>] {
        [.text("title", \.title), .text("note", \.note), .text("reference", \.reference)]
    }
    static var machineText: Set<String> { ["kindRaw", "totalCostCurrency", "cycleDueDayISO", "nextDueDayISO", "previousStatusRaw"] }
}

extension DosarSchemaV9.ServiceItem: HoldsFreeText {
    static var freeText: [FreeTextProperty<DosarSchemaV9.ServiceItem>] {
        [
            .text("name", \.name), .text("group", \.group), .text("partBrandOrCode", \.partBrandOrCode),
            .text("partSerialNumber", \.partSerialNumber), .text("batchOrTicket", \.batchOrTicket),
            .text("locationDetail", \.locationDetail), .text("notes", \.notes),
        ]
    }
    static var machineText: Set<String> { ["componentKey", "currency"] }
}

extension DosarSchemaV9.MeasurementLog: HoldsFreeText {
    static var freeText: [FreeTextProperty<DosarSchemaV9.MeasurementLog>] {
        [.text("name", \.name), .text("source", \.source), .text("notes", \.notes)]
    }
    static var machineText: Set<String> { ["kindRaw", "unit", "unitPriceCurrency"] }
}

extension DosarSchemaV9.Attachment: HoldsFreeText {
    static var freeText: [FreeTextProperty<DosarSchemaV9.Attachment>] {
        // A framing is numbers, but what a newer build wrote inside it may not be.
        [.text("title", \.title), .text("fileName", \.fileName), .text("extractedText", \.extractedText), .json("framingData", \.framingData)]
    }
    static var machineText: Set<String> {
        ["kindRaw", "contentType", "fileData", "thumbnailData", "sha256", "documentDayISO", "validUntilISO", "documentID"]
    }
}

extension DosarSchemaV9.AttachmentPage: HoldsFreeText {
    static var freeText: [FreeTextProperty<DosarSchemaV9.AttachmentPage>] { [] }
    static var machineText: Set<String> { ["imageData"] }
}

extension DosarSchemaV9.Provider: HoldsFreeText {
    static var freeText: [FreeTextProperty<DosarSchemaV9.Provider>] {
        [
            .text("name", \.name), .texts("trades", \.trades), .text("phone", \.phone), .text("email", \.email),
            .text("address", \.address), .text("notes", \.notes),
        ]
    }
    /// A tax ID is a CUI, digits only and at most ten of them (`ProviderTaxID`).
    static var machineText: Set<String> { ["contactIdentifier", "taxID"] }
}

extension DosarSchemaV9.CategoryTemplate: HoldsFreeText {
    static var freeText: [FreeTextProperty<DosarSchemaV9.CategoryTemplate>] {
        [
            .text("name", \.name), .text("summary", \.summary), .json("sectionsData", \.sectionsData),
            .json("blueprintsData", \.blueprintsData), .json("componentsData", \.componentsData),
            .json("behaviorData", \.behaviorData),
        ]
    }
    static var machineText: Set<String> { ["key", "symbol", "tintRaw", "heroStyleRaw", "pocketsRaw"] }
}
