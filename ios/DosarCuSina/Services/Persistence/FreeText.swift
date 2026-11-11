import Foundation
import SwiftData

/// One stored property of `Model` that holds words: what a person typed or a reader read (a
/// name, a note, a section's values, its rows under Date importante, a document's text), as
/// opposed to ids, keys, hashes, content types and pictures. The unit of work masks every card
/// number in these as it saves (`FreeText`).
struct FreeTextProperty<Model: HoldsFreeText> {
    let name: String
    /// Whether the property holds a card number; with `write`, it is masked too.
    let mask: (_ record: Model, _ write: Bool) -> Bool

    /// Plain text, masked by the "anywhere" rule (`PaymentCardNumbers.redact`); what the
    /// record's section keeps whole stays (`HoldsFreeText.keptWhole`).
    static func text(_ name: String, _ keyPath: ReferenceWritableKeyPath<Model, String>) -> Self {
        Self(name: name) { record, write in
            guard let masked = Self.masked(record[keyPath: keyPath], in: record) else { return false }
            if write { record[keyPath: keyPath] = masked }
            return true
        }
    }

    static func text(_ name: String, _ keyPath: ReferenceWritableKeyPath<Model, String?>) -> Self {
        Self(name: name) { record, write in
            guard let text = record[keyPath: keyPath], let masked = Self.masked(text, in: record) else { return false }
            if write { record[keyPath: keyPath] = masked }
            return true
        }
    }

    /// A list of words (a firm's trades, free text allowed).
    static func texts(_ name: String, _ keyPath: ReferenceWritableKeyPath<Model, [String]>) -> Self {
        Self(name: name) { record, write in
            let texts = record[keyPath: keyPath]
            let masked = texts.map { Self.masked($0, in: record) ?? $0 }
            guard masked != texts else { return false }
            if write { record[keyPath: keyPath] = masked }
            return true
        }
    }

    /// The text with its card numbers masked, or nil when it holds none. What the record's section
    /// keeps whole is read only when something would be masked.
    private static func masked(_ text: String, in record: Model) -> String? {
        guard PaymentCardNumbers.redact(text) != text else { return nil }
        let masked = PaymentCardNumbers.redact(text, keeping: record.keptWhole)
        return masked == text ? nil : masked
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
    /// (`PaymentCardNumbers.sanitizing` for rows): a secret row's sealed code is left alone, and
    /// what the record's section keeps whole stays.
    static func facts(_ name: String, _ keyPath: ReferenceWritableKeyPath<Model, Data?>) -> Self {
        Self(name: name) { record, write in
            guard let data = record[keyPath: keyPath] else { return false }
            let facts = KeptList<CustomFact>.stored(in: data)
            guard PaymentCardNumbers.sanitizing(facts) != facts else { return false }
            let masked = PaymentCardNumbers.sanitizing(facts, keeping: record.keptWhole)
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
    /// What its words keep whole: the digits its section's own typed values hold, such as a pet's
    /// microchip (`PaymentCardNumbers.KeptWhole`), so a note, a visit or a document's text that
    /// repeats the microchip keeps it as its field does. Nothing for a record of no section (a
    /// firm, a category). Read only when something would be masked.
    var keptWhole: PaymentCardNumbers.KeptWhole { get }
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
        DosarSchemaV13.models.compactMap { $0 as? any HoldsFreeText.Type }
    }
}

// MARK: - The schema's words

extension DosarSchemaV13.Asset: HoldsFreeText {
    static var freeText: [FreeTextProperty<DosarSchemaV13.Asset>] {
        [
            .text("name", \.name), .text("notes", \.notes), .values("valuesData", \.valuesData, fields: \.categoryFields),
            .facts("customFactsData", \.customFactsData),
        ]
    }
    static var machineText: Set<String> { ["templateKey", "symbolOverride", "tintOverrideRaw", "photoData"] }

    var keptWhole: PaymentCardNumbers.KeptWhole {
        PaymentCardNumbers.KeptWhole(values, fields: categoryFields)
    }

    /// The fields its category defines, so a value its own type tells apart from a card number
    /// stays whole (`PaymentCardNumbers.keepsWhole`). None when the category can't be found.
    /// Read only when a value would be masked, and on any thread (a backup's own context).
    fileprivate var categoryFields: [FieldDefinition] {
        guard let context = modelContext, let template = (try? TemplateStore.templatesByKey(in: context))?[templateKey] else { return [] }
        return template.definition.allFields
    }
}

extension DosarSchemaV13.Obligation: HoldsFreeText {
    static var freeText: [FreeTextProperty<DosarSchemaV13.Obligation>] {
        // A recurrence is the app's own words, but what a newer build wrote inside it may not be.
        [.text("title", \.title), .text("notes", \.notes), .text("provider", \.provider), .text("reference", \.reference),
         .json("recurrenceData", \.recurrenceData), .json("remindersData", \.remindersData)]
    }
    static var machineText: Set<String> { ["blueprintKey", "kindRaw", "dueDayISO", "consequenceRaw", "estimatedCostCurrency", "statusRaw", "snoozedUntilISO"] }
    var keptWhole: PaymentCardNumbers.KeptWhole { asset?.keptWhole ?? .nothing }

}

extension DosarSchemaV13.HistoryEntry: HoldsFreeText {
    static var freeText: [FreeTextProperty<DosarSchemaV13.HistoryEntry>] {
        [.text("title", \.title), .text("note", \.note), .text("reference", \.reference)]
    }
    static var machineText: Set<String> { ["kindRaw", "totalCostCurrency", "cycleDueDayISO", "nextDueDayISO", "previousStatusRaw"] }
    var keptWhole: PaymentCardNumbers.KeptWhole { asset?.keptWhole ?? .nothing }

}

extension DosarSchemaV13.ServiceItem: HoldsFreeText {
    static var freeText: [FreeTextProperty<DosarSchemaV13.ServiceItem>] {
        [
            .text("name", \.name), .text("group", \.group), .text("partBrandOrCode", \.partBrandOrCode),
            .text("partSerialNumber", \.partSerialNumber), .text("batchOrTicket", \.batchOrTicket),
            .text("locationDetail", \.locationDetail), .text("notes", \.notes),
        ]
    }
    static var machineText: Set<String> { ["componentKey", "currency"] }
    var keptWhole: PaymentCardNumbers.KeptWhole { entry?.asset?.keptWhole ?? .nothing }

}

extension DosarSchemaV13.MeasurementLog: HoldsFreeText {
    static var freeText: [FreeTextProperty<DosarSchemaV13.MeasurementLog>] {
        [.text("name", \.name), .text("source", \.source), .text("notes", \.notes)]
    }
    static var machineText: Set<String> { ["kindRaw", "unit", "unitPriceCurrency"] }
    var keptWhole: PaymentCardNumbers.KeptWhole { asset?.keptWhole ?? .nothing }

}

extension DosarSchemaV13.Attachment: HoldsFreeText {
    static var freeText: [FreeTextProperty<DosarSchemaV13.Attachment>] {
        // A framing is numbers, but what a newer build wrote inside it may not be.
        [.text("title", \.title), .text("fileName", \.fileName), .text("extractedText", \.extractedText), .json("framingData", \.framingData)]
    }
    static var machineText: Set<String> {
        ["kindRaw", "contentType", "fileData", "thumbnailData", "sha256", "documentDayISO", "validUntilISO", "documentID"]
    }
    var keptWhole: PaymentCardNumbers.KeptWhole { SearchIndexBuilder.section(of: self)?.keptWhole ?? .nothing }

}

extension DosarSchemaV13.AttachmentPage: HoldsFreeText {
    static var freeText: [FreeTextProperty<DosarSchemaV13.AttachmentPage>] { [] }
    static var machineText: Set<String> { ["imageData"] }
    var keptWhole: PaymentCardNumbers.KeptWhole { .nothing }

}

extension DosarSchemaV13.Provider: HoldsFreeText {
    static var freeText: [FreeTextProperty<DosarSchemaV13.Provider>] {
        [
            .text("name", \.name), .texts("trades", \.trades), .text("phone", \.phone), .text("email", \.email),
            .text("address", \.address), .text("notes", \.notes),
        ]
    }
    /// A tax ID is a CUI, digits only and at most ten of them (`ProviderTaxID`).
    static var machineText: Set<String> { ["contactIdentifier", "taxID"] }
    var keptWhole: PaymentCardNumbers.KeptWhole { .nothing }

}

extension DosarSchemaV13.CategoryTemplate: HoldsFreeText {
    static var freeText: [FreeTextProperty<DosarSchemaV13.CategoryTemplate>] {
        [
            .text("name", \.name), .text("summary", \.summary), .json("sectionsData", \.sectionsData),
            .json("blueprintsData", \.blueprintsData), .json("componentsData", \.componentsData),
            .json("behaviorData", \.behaviorData),
        ]
    }
    static var machineText: Set<String> { ["key", "symbol", "tintRaw", "heroStyleRaw", "pocketsRaw"] }
    var keptWhole: PaymentCardNumbers.KeptWhole { .nothing }

}
