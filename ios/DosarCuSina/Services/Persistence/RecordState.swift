import Foundation
import SwiftData

/// Which record: its type and its id (a category's key).
public struct RecordRef: Hashable, Sendable, CustomStringConvertible {
    public let type: String
    public let key: String

    init<M: UndoableRecord>(_ record: M) {
        type = M.recordType
        key = record.recordKey
    }

    public var description: String { "\(type) \(key)" }
}

/// Finds the record a ref names, for writing relationships back.
public typealias RecordResolver = (RecordRef) -> (any PersistentModel)?

/// One stored property's value: an attribute as it is stored, or a relationship as the
/// records it points to.
public enum StoredValue: Hashable {
    case attribute(AnyHashable)
    case one(RecordRef?)
    case many(Set<RecordRef>)
}

/// Every stored property of one record, as plain values. An undo receipt keeps these
/// for the records a step changed or deleted, and puts them back; tests compare them to
/// check that undo restores exactly the state before.
public struct RecordState: Hashable {
    public let ref: RecordRef
    public let values: [String: StoredValue]

    /// The state of `model`, or nil for a type that can't be recorded (none in the schema).
    static func capture(any model: any PersistentModel) -> RecordState? {
        guard let record = model as? any UndoableRecord else { return nil }
        return capture(record)
    }

    static func capture<M: UndoableRecord>(_ record: M) -> RecordState {
        RecordState(ref: RecordRef(record), values: Dictionary(uniqueKeysWithValues: M.storedProperties.map { ($0.name, $0.read(record)) }))
    }
}

/// One stored property of `Model`: how to read it into a `StoredValue` and write it back.
/// A relationship is written with the records `resolve` finds for its refs.
public struct StoredProperty<Model: PersistentModel> {
    let name: String
    let read: (Model) -> StoredValue
    let write: (Model, StoredValue, RecordResolver) -> Void

    static func attribute<Value: Hashable>(_ name: String, _ keyPath: ReferenceWritableKeyPath<Model, Value>) -> Self {
        Self(name: name, read: { .attribute(AnyHashable($0[keyPath: keyPath])) }) { model, value, _ in
            guard case .attribute(let stored) = value, let typed = stored.base as? Value else {
                assertionFailure("\(name) holds a value of another type")
                return
            }
            model[keyPath: keyPath] = typed
        }
    }

    static func toOne<Target: UndoableRecord>(_ name: String, _ keyPath: ReferenceWritableKeyPath<Model, Target?>) -> Self {
        Self(name: name, read: { model in
            .one(model[keyPath: keyPath].flatMap { $0.isDeleted ? nil : RecordRef($0) })
        }) { model, value, resolve in
            guard case .one(let ref) = value else { return assertionFailure("\(name) is a relationship to one record") }
            model[keyPath: keyPath] = ref.flatMap { resolve($0) as? Target }
        }
    }

    static func toMany<Target: UndoableRecord>(_ name: String, _ keyPath: ReferenceWritableKeyPath<Model, [Target]?>) -> Self {
        Self(name: name, read: { model in
            .many(Set((model[keyPath: keyPath] ?? []).filter { !$0.isDeleted }.map { RecordRef($0) }))
        }) { model, value, resolve in
            guard case .many(let refs) = value else { return assertionFailure("\(name) is a relationship to many records") }
            model[keyPath: keyPath] = refs.compactMap { resolve($0) as? Target }
        }
    }
}

/// A model whose every stored property is listed, so a step that changed it can be
/// taken back exactly. Every model of the schema is one (`UndoReceiptTests` checks
/// the list against the schema, so a new property can't be forgotten).
public protocol UndoableRecord: PersistentModel {
    /// Every stored attribute and relationship, by its name in the schema.
    static var storedProperties: [StoredProperty<Self>] { get }
    /// What identifies the record across contexts: its id.
    var recordKey: String { get }
    /// An empty record, to bring back one a step deleted; every property is then written.
    static func blank() -> Self
    static func find(_ key: String, in context: ModelContext) -> Self?
}

extension UndoableRecord {
    static var recordType: String { String(describing: Self.self) }

    /// Writes `state` onto this record, only where it differs.
    func restore(_ state: RecordState, resolve: RecordResolver) {
        for property in Self.storedProperties {
            guard let value = state.values[property.name], property.read(self) != value else { continue }
            property.write(self, value, resolve)
        }
    }
}

/// Every recorded type of the schema, by name.
enum UndoableRecords {
    static var types: [String: any UndoableRecord.Type] {
        Dictionary(uniqueKeysWithValues: DosarSchemaV6.models.compactMap { $0 as? any UndoableRecord.Type }.map { ($0.recordType, $0) })
    }

    /// The record `ref` names, if it exists in `context`.
    static func find(_ ref: RecordRef, in context: ModelContext) -> (any UndoableRecord)? {
        guard let type = types[ref.type] else { return nil }
        return find(type, key: ref.key, in: context)
    }

    private static func find<M: UndoableRecord>(_ type: M.Type, key: String, in context: ModelContext) -> (any UndoableRecord)? {
        M.find(key, in: context).flatMap { $0.isDeleted ? nil : $0 }
    }

    /// A new, empty record of `ref`'s type, inserted into `context`.
    static func insertBlank(_ ref: RecordRef, in context: ModelContext) -> (any UndoableRecord)? {
        guard let type = types[ref.type] else { return nil }
        return insertBlank(type, in: context)
    }

    private static func insertBlank<M: UndoableRecord>(_ type: M.Type, in context: ModelContext) -> any UndoableRecord {
        let record = M.blank()
        context.insert(record)
        return record
    }

    /// Writes `state` onto `record`, whatever its type.
    static func restore(_ record: any UndoableRecord, to state: RecordState, resolve: RecordResolver) {
        record.restore(state, resolve: resolve)
    }
}

// MARK: - Finding a record by its id

private extension ModelContext {
    func first<M: PersistentModel>(_ predicate: Predicate<M>) -> M? {
        var descriptor = FetchDescriptor<M>(predicate: predicate)
        descriptor.fetchLimit = 1
        return (try? fetch(descriptor))?.first
    }
}

// MARK: - The schema's records

extension DosarSchemaV6.Asset: UndoableRecord {
    public static var storedProperties: [StoredProperty<DosarSchemaV6.Asset>] {
        [
            .attribute("id", \.id), .attribute("name", \.name), .attribute("templateKey", \.templateKey),
            .attribute("symbolOverride", \.symbolOverride), .attribute("tintOverrideRaw", \.tintOverrideRaw),
            .attribute("notes", \.notes), .attribute("photoData", \.photoData), .attribute("valuesData", \.valuesData),
            .attribute("customFactsData", \.customFactsData), .attribute("isExample", \.isExample),
            .attribute("createdAt", \.createdAt), .attribute("updatedAt", \.updatedAt),
            .toMany("obligations", \.obligations), .toMany("attachments", \.attachments), .toMany("history", \.history),
            .toMany("measurements", \.measurements), .toMany("providers", \.providers),
            .toOne("parent", \.parent), .toMany("children", \.children),
        ]
    }
    public var recordKey: String { id.uuidString }
    public static func blank() -> Self { Self(name: "", templateKey: "") }
    public static func find(_ key: String, in context: ModelContext) -> Self? {
        guard let id = UUID(uuidString: key) else { return nil }
        return context.first(#Predicate<DosarSchemaV6.Asset> { $0.id == id }) as? Self
    }
}

extension DosarSchemaV6.Obligation: UndoableRecord {
    public static var storedProperties: [StoredProperty<DosarSchemaV6.Obligation>] {
        [
            .attribute("id", \.id), .attribute("title", \.title), .attribute("notes", \.notes),
            .attribute("blueprintKey", \.blueprintKey), .attribute("kindRaw", \.kindRaw), .attribute("dueDate", \.dueDate),
            .attribute("dueMetric", \.dueMetric), .attribute("reminderLeadDays", \.reminderLeadDays),
            .attribute("consequenceRaw", \.consequenceRaw), .attribute("graceDays", \.graceDays),
            .attribute("followUpAfterLapse", \.followUpAfterLapse), .attribute("travelMarginDays", \.travelMarginDays),
            .attribute("remindersCustomized", \.remindersCustomized),
            .attribute("reminderMinuteOfDay", \.reminderMinuteOfDay),
            .attribute("recurrenceData", \.recurrenceData), .attribute("estimatedCostAmount", \.estimatedCostAmount),
            .attribute("estimatedCostCurrency", \.estimatedCostCurrency), .attribute("provider", \.provider),
            .attribute("reference", \.reference), .attribute("statusRaw", \.statusRaw), .attribute("snoozedUntil", \.snoozedUntil),
            .attribute("isExample", \.isExample), .attribute("createdAt", \.createdAt), .attribute("updatedAt", \.updatedAt),
            .toOne("asset", \.asset), .toMany("historyEntries", \.historyEntries), .toMany("attachments", \.attachments),
        ]
    }
    public var recordKey: String { id.uuidString }
    public static func blank() -> Self { Self(title: "", kind: .routine, dueDay: CalendarDay(Date())) }
    public static func find(_ key: String, in context: ModelContext) -> Self? {
        guard let id = UUID(uuidString: key) else { return nil }
        return context.first(#Predicate<DosarSchemaV6.Obligation> { $0.id == id }) as? Self
    }
}

extension DosarSchemaV6.HistoryEntry: UndoableRecord {
    public static var storedProperties: [StoredProperty<DosarSchemaV6.HistoryEntry>] {
        [
            .attribute("id", \.id), .attribute("kindRaw", \.kindRaw), .attribute("title", \.title),
            .attribute("occurredAt", \.occurredAt), .attribute("metricReading", \.metricReading),
            .attribute("totalCostAmount", \.totalCostAmount), .attribute("totalCostCurrency", \.totalCostCurrency),
            .attribute("note", \.note), .attribute("rating", \.rating), .attribute("isExample", \.isExample),
            .attribute("cycleDueDate", \.cycleDueDate), .attribute("nextDueDate", \.nextDueDate),
            .attribute("previousStatusRaw", \.previousStatusRaw), .attribute("previousDueMetric", \.previousDueMetric),
            .toOne("asset", \.asset), .toOne("obligation", \.obligation), .toMany("providers", \.providers),
            .toMany("items", \.items), .toMany("attachments", \.attachments),
        ]
    }
    public var recordKey: String { id.uuidString }
    public static func blank() -> Self { Self(kind: .note, title: "", occurredAt: Date()) }
    public static func find(_ key: String, in context: ModelContext) -> Self? {
        guard let id = UUID(uuidString: key) else { return nil }
        return context.first(#Predicate<DosarSchemaV6.HistoryEntry> { $0.id == id }) as? Self
    }
}

extension DosarSchemaV6.ServiceItem: UndoableRecord {
    public static var storedProperties: [StoredProperty<DosarSchemaV6.ServiceItem>] {
        [
            .attribute("id", \.id), .attribute("name", \.name), .attribute("componentKey", \.componentKey),
            .attribute("group", \.group), .attribute("partBrandOrCode", \.partBrandOrCode),
            .attribute("partSerialNumber", \.partSerialNumber), .attribute("costAmount", \.costAmount),
            .attribute("laborCostAmount", \.laborCostAmount), .attribute("partsCostAmount", \.partsCostAmount),
            .attribute("currency", \.currency), .toOne("supplier", \.supplier), .attribute("batchOrTicket", \.batchOrTicket),
            .attribute("locationDetail", \.locationDetail), .attribute("daysInService", \.daysInService),
            .attribute("warrantyMonths", \.warrantyMonths), .attribute("notes", \.notes), .attribute("isExample", \.isExample),
            .toOne("entry", \.entry), .toMany("attachments", \.attachments),
        ]
    }
    public var recordKey: String { id.uuidString }
    public static func blank() -> Self { Self(name: "") }
    public static func find(_ key: String, in context: ModelContext) -> Self? {
        guard let id = UUID(uuidString: key) else { return nil }
        return context.first(#Predicate<DosarSchemaV6.ServiceItem> { $0.id == id }) as? Self
    }
}

extension DosarSchemaV6.MeasurementLog: UndoableRecord {
    public static var storedProperties: [StoredProperty<DosarSchemaV6.MeasurementLog>] {
        [
            .attribute("id", \.id), .attribute("kindRaw", \.kindRaw), .attribute("name", \.name), .attribute("value", \.value),
            .attribute("secondaryValue", \.secondaryValue), .attribute("unit", \.unit), .attribute("recordedAt", \.recordedAt),
            .attribute("unitPriceAmount", \.unitPriceAmount), .attribute("unitPriceCurrency", \.unitPriceCurrency),
            .attribute("isSelfRead", \.isSelfRead), .attribute("referenceMin", \.referenceMin),
            .attribute("referenceMax", \.referenceMax), .attribute("source", \.source), .attribute("notes", \.notes),
            .attribute("isExample", \.isExample), .toOne("asset", \.asset), .toMany("attachments", \.attachments),
        ]
    }
    public var recordKey: String { id.uuidString }
    public static func blank() -> Self { Self(kind: .custom, name: "", value: 0) }
    public static func find(_ key: String, in context: ModelContext) -> Self? {
        guard let id = UUID(uuidString: key) else { return nil }
        return context.first(#Predicate<DosarSchemaV6.MeasurementLog> { $0.id == id }) as? Self
    }
}

extension DosarSchemaV6.Attachment: UndoableRecord {
    public static var storedProperties: [StoredProperty<DosarSchemaV6.Attachment>] {
        [
            .attribute("id", \.id), .attribute("title", \.title), .attribute("fileName", \.fileName),
            .attribute("kindRaw", \.kindRaw), .attribute("contentType", \.contentType), .attribute("fileData", \.fileData),
            .attribute("thumbnailData", \.thumbnailData), .attribute("byteCount", \.byteCount), .attribute("sha256", \.sha256),
            .attribute("extractedText", \.extractedText), .attribute("documentDate", \.documentDate),
            .attribute("validUntil", \.validUntil), .attribute("documentID", \.documentID), .attribute("isArchived", \.isArchived),
            .attribute("compactedAt", \.compactedAt), .attribute("framingData", \.framingData),
            .attribute("createdAt", \.createdAt), .attribute("isExample", \.isExample),
            .toMany("pages", \.pages), .toOne("supersededBy", \.supersededBy), .toMany("supersedes", \.supersedes),
            .toOne("asset", \.asset), .toOne("obligation", \.obligation), .toOne("historyEntry", \.historyEntry),
            .toOne("serviceItem", \.serviceItem), .toOne("measurement", \.measurement), .toOne("provider", \.provider),
        ]
    }
    public var recordKey: String { id.uuidString }
    public static func blank() -> Self { Self(fileName: "", contentType: "public.data", data: nil) }
    public static func find(_ key: String, in context: ModelContext) -> Self? {
        guard let id = UUID(uuidString: key) else { return nil }
        return context.first(#Predicate<DosarSchemaV6.Attachment> { $0.id == id }) as? Self
    }
}

extension DosarSchemaV6.AttachmentPage: UndoableRecord {
    public static var storedProperties: [StoredProperty<DosarSchemaV6.AttachmentPage>] {
        [.attribute("id", \.id), .attribute("index", \.index), .attribute("imageData", \.imageData), .toOne("attachment", \.attachment)]
    }
    public var recordKey: String { id.uuidString }
    public static func blank() -> Self { Self(index: 0, imageData: nil) }
    public static func find(_ key: String, in context: ModelContext) -> Self? {
        guard let id = UUID(uuidString: key) else { return nil }
        return context.first(#Predicate<DosarSchemaV6.AttachmentPage> { $0.id == id }) as? Self
    }
}

extension DosarSchemaV6.Provider: UndoableRecord {
    public static var storedProperties: [StoredProperty<DosarSchemaV6.Provider>] {
        [
            .attribute("id", \.id), .attribute("name", \.name), .attribute("trades", \.trades), .attribute("phone", \.phone),
            .attribute("email", \.email), .attribute("address", \.address), .attribute("notes", \.notes),
            .attribute("manualRating", \.manualRating), .attribute("wouldCallAgain", \.wouldCallAgain),
            .attribute("contactIdentifier", \.contactIdentifier), .attribute("taxID", \.taxID),
            .attribute("isExample", \.isExample), .attribute("createdAt", \.createdAt), .attribute("updatedAt", \.updatedAt),
            .toMany("assets", \.assets), .toMany("historyEntries", \.historyEntries),
            .toMany("suppliedItems", \.suppliedItems), .toMany("attachments", \.attachments),
        ]
    }
    public var recordKey: String { id.uuidString }
    public static func blank() -> Self { Self(name: "") }
    public static func find(_ key: String, in context: ModelContext) -> Self? {
        guard let id = UUID(uuidString: key) else { return nil }
        return context.first(#Predicate<DosarSchemaV6.Provider> { $0.id == id }) as? Self
    }
}

extension DosarSchemaV6.CategoryTemplate: UndoableRecord {
    public static var storedProperties: [StoredProperty<DosarSchemaV6.CategoryTemplate>] {
        [
            .attribute("key", \.key), .attribute("name", \.name), .attribute("summary", \.summary), .attribute("symbol", \.symbol),
            .attribute("tintRaw", \.tintRaw), .attribute("heroStyleRaw", \.heroStyleRaw), .attribute("isBuiltIn", \.isBuiltIn),
            .attribute("builtInVersion", \.builtInVersion), .attribute("homeOrder", \.homeOrder), .attribute("isOnHome", \.isOnHome),
            .attribute("isSensitive", \.isSensitive), .attribute("sectionsData", \.sectionsData),
            .attribute("blueprintsData", \.blueprintsData), .attribute("componentsData", \.componentsData),
            .attribute("pocketsRaw", \.pocketsRaw), .attribute("behaviorData", \.behaviorData),
            .attribute("createdAt", \.createdAt), .attribute("updatedAt", \.updatedAt),
        ]
    }
    public var recordKey: String { key }
    public static func blank() -> Self {
        Self(definition: TemplateDefinition(key: "", name: "", symbol: "square.grid.2x2", tint: .gray, sections: []), isBuiltIn: false, homeOrder: 0)
    }
    public static func find(_ key: String, in context: ModelContext) -> Self? {
        context.first(#Predicate<DosarSchemaV6.CategoryTemplate> { $0.key == key }) as? Self
    }
}
