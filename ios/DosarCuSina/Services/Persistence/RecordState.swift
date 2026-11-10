import CryptoKit
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

/// A picture or a file a record keeps outside the database (a page's photo, a document's
/// file or thumbnail, a section's photo: the schema's `.externalStorage`), known by its
/// SHA-256 and size. States compare these without holding the bytes; whoever must write
/// one back keeps the bytes itself (`UndoFiles`).
public struct FileDigest: Hashable, Sendable {
    let sha256: Data
    let byteCount: Int

    init(_ data: Data) {
        sha256 = Data(SHA256.hash(data: data))
        byteCount = data.count
    }

    /// Its digest as text, for a file named after it.
    var name: String { MachineText.hex(sha256) }
}

/// One stored property's value: an attribute as it is stored, a picture or a file by its
/// digest, or a relationship as the records it points to.
public enum StoredValue: Hashable {
    case attribute(AnyHashable)
    /// A picture or a file kept outside the database; nil when there is none.
    case file(FileDigest?)
    case one(RecordRef?)
    case many(Set<RecordRef>)
}

/// Every stored property of one record, as plain values, pictures and files by their
/// digest. An undo receipt keeps these for the records a step changed or deleted, and puts
/// them back; tests compare them to check that undo restores exactly the state before.
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

    /// Only the relationships of `model`: what a delete reaches and what a rollback fetches
    /// again, read without its values (so without reading a picture).
    static func links(any model: any PersistentModel) -> RecordState? {
        guard let record = model as? any UndoableRecord else { return nil }
        return links(record)
    }

    static func links<M: UndoableRecord>(_ record: M) -> RecordState {
        RecordState(ref: RecordRef(record), values: Dictionary(uniqueKeysWithValues: M.storedProperties.filter(\.isLink).map { ($0.name, $0.read(record)) }))
    }

    /// Every record this one points to, through any relationship.
    var linked: Set<RecordRef> {
        values.values.reduce(into: []) { refs, value in refs.formUnion(value.refs) }
    }

    /// The names of the properties whose values differ between this state and `other`.
    func changed(from other: RecordState) -> Set<String> {
        Set(values.keys).union(other.values.keys).filter { values[$0] != other.values[$0] }
    }
}

extension StoredValue {
    /// The records a relationship points to; none for an attribute.
    var refs: Set<RecordRef> {
        switch self {
        case .attribute, .file: []
        case .one(let ref): ref.map { [$0] } ?? []
        case .many(let refs): refs
        }
    }
}

/// What writing a state back needs beside its values: the records its links name, and the
/// bytes of the pictures and files it names.
public struct RestoreSources {
    let record: RecordResolver
    let file: (FileDigest) -> Data?
}

/// One stored property of `Model`: how to read it into a `StoredValue` and write it back.
/// A relationship is written with the records `RestoreSources` finds for its refs, a picture
/// or a file with the bytes it has for its digest.
public struct StoredProperty<Model: PersistentModel> {
    let name: String
    /// Whether the record keeps this itself, so changing it changes the record (`ChangeTimes`):
    /// its values, the records it points to, and a list it keeps of its own (a firm's sections,
    /// a visit's firms). Not a list of the records that point at it (a section's history): those
    /// records keep the link, and adding one doesn't change the section.
    let isOwn: Bool
    /// Whether it is a relationship.
    let isLink: Bool
    let read: (Model) -> StoredValue
    let write: (Model, StoredValue, RestoreSources) -> Void
    /// A picture's or a file's bytes, to keep what a step takes away; nil for every other property.
    let bytes: ((Model) -> Data?)?

    static func attribute<Value: Hashable>(_ name: String, _ keyPath: ReferenceWritableKeyPath<Model, Value>) -> Self {
        value(name, keyPath)
    }

    /// Data the schema keeps outside the database (`.externalStorage`: a picture, a file) is
    /// read as its digest (`StoredValue.file`); any other data as it is.
    static func attribute(_ name: String, _ keyPath: ReferenceWritableKeyPath<Model, Data?>) -> Self {
        guard UndoableRecords.keptOutside[String(describing: Model.self)]?.contains(name) == true else { return value(name, keyPath) }
        return Self(name: name, isOwn: true, isLink: false, read: { .file($0[keyPath: keyPath].map(FileDigest.init)) }, write: { model, value, sources in
            guard case .file(let digest) = value else { return assertionFailure("\(name) is a picture or a file") }
            model[keyPath: keyPath] = digest.flatMap(sources.file)
        }, bytes: { $0[keyPath: keyPath] })
    }

    private static func value<Value: Hashable>(_ name: String, _ keyPath: ReferenceWritableKeyPath<Model, Value>) -> Self {
        Self(name: name, isOwn: true, isLink: false, read: { .attribute(AnyHashable($0[keyPath: keyPath])) }, write: { model, value, _ in
            guard case .attribute(let stored) = value, let typed = stored.base as? Value else {
                assertionFailure("\(name) holds a value of another type")
                return
            }
            model[keyPath: keyPath] = typed
        }, bytes: nil)
    }

    static func toOne<Target: UndoableRecord>(_ name: String, _ keyPath: ReferenceWritableKeyPath<Model, Target?>) -> Self {
        Self(name: name, isOwn: true, isLink: true, read: { model in
            .one(model[keyPath: keyPath].flatMap { $0.isDeleted ? nil : RecordRef($0) })
        }, write: { model, value, sources in
            guard case .one(let ref) = value else { return assertionFailure("\(name) is a relationship to one record") }
            model[keyPath: keyPath] = ref.flatMap { sources.record($0) as? Target }
        }, bytes: nil)
    }

    /// The records that point at this one (a section's history, a document's pages).
    static func toMany<Target: UndoableRecord>(_ name: String, _ keyPath: ReferenceWritableKeyPath<Model, [Target]?>) -> Self {
        list(name, keyPath, isOwn: false)
    }

    /// A list of records this one keeps itself, the side of a many-to-many link it owns (the
    /// sections a firm looks after, the firms that did a visit): backups carry it on this record.
    static func links<Target: UndoableRecord>(_ name: String, _ keyPath: ReferenceWritableKeyPath<Model, [Target]?>) -> Self {
        list(name, keyPath, isOwn: true)
    }

    private static func list<Target: UndoableRecord>(_ name: String, _ keyPath: ReferenceWritableKeyPath<Model, [Target]?>, isOwn: Bool) -> Self {
        Self(name: name, isOwn: isOwn, isLink: true, read: { model in
            .many(Set((model[keyPath: keyPath] ?? []).filter { !$0.isDeleted }.map { RecordRef($0) }))
        }, write: { model, value, sources in
            guard case .many(let refs) = value else { return assertionFailure("\(name) is a relationship to many records") }
            model[keyPath: keyPath] = refs.compactMap { sources.record($0) as? Target }
        }, bytes: nil)
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

/// How undo takes back a step's change of one record, property by property: only what the
/// step changed, and never over something newer.
///
/// - The record's own state (`ChangeTimes.isOwnState`, the one definition change times read
///   too: its values and its own links): what the step changed must still be as the step left
///   it, or undo refuses; then it goes back as it was. A field the step didn't change is never
///   written, so a newer change there stays.
/// - Its change time, and what of a built-in category is the catalog's: back as it was while
///   still as the step left it; a newer one stays.
/// - A list of the records that point at it (a section's history): it follows those records.
///   Only what the step itself added or took away is taken back; what another step added since
///   stays. On a record the step only linked to (the section a completion went into), that
///   never stops an undo. On a record whose own state the step changed or that it made,
///   something that came to point at it since was built on the step (another completion of
///   the same deadline, a document filed under the person it made), and undo refuses.
///
/// A record the step made goes whole (undo deletes it): its own state must still be as the
/// step left it.
extension UndoableRecord {
    static var recordType: String { String(describing: Self.self) }

    /// Whether the record still holds what the step left (`after`) in every property the step
    /// changed from `before`; with no `before` (a record the step made), in every property.
    func isStillAsLeft(before: RecordState?, after: RecordState) -> Bool {
        let changed = before.map { after.changed(from: $0) }
        let stepChanged = { (name: String) in changed?.contains(name) ?? true }
        // A record the step made, or whose own state it changed: whatever came to point at it
        // since was built on what the step did (another completion of the same deadline, a
        // document filed under the person the step made), and the undo would pull it away.
        let ownStateChanged = Self.storedProperties.contains { stepChanged($0.name) && ChangeTimes.isOwnState($0, of: self) }
        for property in Self.storedProperties {
            guard let left = after.values[property.name] else { continue }
            if ChangeTimes.isOwnState(property, of: self) {
                guard !stepChanged(property.name) || property.read(self) == left else { return false }
            } else if !property.isOwn, ownStateChanged, !property.read(self).refs.isSubset(of: left.refs) {
                return false
            }
        }
        return true
    }

    /// Writes back `before` where the step changed it from `after`; with no `after` (a record
    /// the step deleted, brought back blank), every property.
    func takeBack(to before: RecordState, from after: RecordState?, sources: RestoreSources) {
        let changed = after.map { before.changed(from: $0) }
        for property in Self.storedProperties where changed?.contains(property.name) ?? true {
            guard let old = before.values[property.name] else { continue }
            let now = property.read(self)
            var restored = old
            if let left = after?.values[property.name], !ChangeTimes.isOwnState(property, of: self) {
                if !property.isOwn {
                    // Only the step's own additions and removals.
                    restored = .many(now.refs.subtracting(left.refs.subtracting(old.refs)).union(old.refs.subtracting(left.refs)))
                } else if now != left {
                    // Changed again since: the newer one stays.
                    continue
                }
            }
            guard now != restored else { continue }
            property.write(self, restored, sources)
        }
    }

    /// The bytes of the pictures and files `state` names that `current` no longer holds in the
    /// same place (all of them, when there is no `current`): what a step is about to take away,
    /// read from this record as it is in the store.
    func files(of state: RecordState, notIn current: (any UndoableRecord)?) -> [FileDigest: Data] {
        let current = current as? Self
        var found: [FileDigest: Data] = [:]
        for property in Self.storedProperties {
            guard let bytes = property.bytes, case .file(let digest?) = state.values[property.name] else { continue }
            if let current, property.read(current) == .file(digest) { continue }
            if let data = bytes(self) { found[digest] = data }
        }
        return found
    }
}

/// Every recorded type of the schema, by name.
enum UndoableRecords {
    static var types: [String: any UndoableRecord.Type] {
        Dictionary(uniqueKeysWithValues: DosarSchemaV12.models.compactMap { $0 as? any UndoableRecord.Type }.map { ($0.recordType, $0) })
    }

    /// What the schema says, by type: read once, from the models' own declarations.
    private static let schemaFacts: (owned: [String: Set<String>], keptOutside: [String: Set<String>]) = {
        let schema = Schema(versionedSchema: DosarSchemaV12.self)
        let owned = Dictionary(uniqueKeysWithValues: schema.entities.map { entity in
            (entity.name, Set(entity.relationships.filter { if case .cascade = $0.deleteRule { true } else { false } }.map(\.name)))
        })
        let keptOutside = Dictionary(uniqueKeysWithValues: schema.entities.map { entity in
            (entity.name, Set(entity.attributes.filter { $0.options.contains(.externalStorage) }.map(\.name)))
        })
        return (owned, keptOutside)
    }()

    /// The relationships whose records go with their owner when it is deleted, by type:
    /// read from the schema's own delete rules, so they're written once, on the models.
    static var ownedRelationships: [String: Set<String>] { schemaFacts.owned }

    /// The attributes the store keeps outside the database, by type (pictures and files, the
    /// models' `.externalStorage`): read and compared by their digest (`StoredValue.file`).
    static var keptOutside: [String: Set<String>] { schemaFacts.keptOutside }

    /// The records `state`'s record owns: deleting it deletes them too.
    static func owned(by state: RecordState) -> Set<RecordRef> {
        let names = ownedRelationships[state.ref.type] ?? []
        return names.reduce(into: []) { refs, name in refs.formUnion(state.values[name]?.refs ?? []) }
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

extension DosarSchemaV12.Asset: UndoableRecord {
    public static var storedProperties: [StoredProperty<DosarSchemaV12.Asset>] {
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
        return context.first(#Predicate<DosarSchemaV12.Asset> { $0.id == id }) as? Self
    }
}

extension DosarSchemaV12.Obligation: UndoableRecord {
    public static var storedProperties: [StoredProperty<DosarSchemaV12.Obligation>] {
        [
            .attribute("id", \.id), .attribute("title", \.title), .attribute("notes", \.notes),
            .attribute("blueprintKey", \.blueprintKey), .attribute("kindRaw", \.kindRaw), .attribute("dueDayISO", \.dueDayISO),
            .attribute("dueMetric", \.dueMetric), .attribute("reminderLeadDays", \.reminderLeadDays),
            .attribute("consequenceRaw", \.consequenceRaw), .attribute("graceDays", \.graceDays),
            .attribute("followUpAfterLapse", \.followUpAfterLapse), .attribute("travelMarginDays", \.travelMarginDays),
            .attribute("remindersCustomized", \.remindersCustomized),
            .attribute("reminderMinuteOfDay", \.reminderMinuteOfDay),
            .attribute("recurrenceData", \.recurrenceData), .attribute("estimatedCostAmount", \.estimatedCostAmount),
            .attribute("estimatedCostCurrency", \.estimatedCostCurrency), .attribute("provider", \.provider),
            .attribute("reference", \.reference), .attribute("statusRaw", \.statusRaw), .attribute("snoozedUntilISO", \.snoozedUntilISO),
            .attribute("isExample", \.isExample), .attribute("createdAt", \.createdAt), .attribute("updatedAt", \.updatedAt),
            .attribute("cycleKnownAt", \.cycleKnownAt), .attribute("remindersData", \.remindersData),
            .toOne("asset", \.asset), .toMany("historyEntries", \.historyEntries), .toMany("attachments", \.attachments),
        ]
    }
    public var recordKey: String { id.uuidString }
    public static func blank() -> Self { Self(title: "", kind: .routine, dueDay: CalendarDay(Date())) }
    public static func find(_ key: String, in context: ModelContext) -> Self? {
        guard let id = UUID(uuidString: key) else { return nil }
        return context.first(#Predicate<DosarSchemaV12.Obligation> { $0.id == id }) as? Self
    }
}

extension DosarSchemaV12.HistoryEntry: UndoableRecord {
    public static var storedProperties: [StoredProperty<DosarSchemaV12.HistoryEntry>] {
        [
            .attribute("id", \.id), .attribute("kindRaw", \.kindRaw), .attribute("title", \.title),
            .attribute("occurredAt", \.occurredAt), .attribute("metricReading", \.metricReading),
            .attribute("totalCostAmount", \.totalCostAmount), .attribute("totalCostCurrency", \.totalCostCurrency),
            .attribute("note", \.note), .attribute("reference", \.reference), .attribute("rating", \.rating),
            .attribute("isExample", \.isExample), .attribute("cycleDueDayISO", \.cycleDueDayISO), .attribute("nextDueDayISO", \.nextDueDayISO),
            .attribute("previousStatusRaw", \.previousStatusRaw), .attribute("previousDueMetric", \.previousDueMetric),
            .attribute("updatedAt", \.updatedAt),
            .toOne("asset", \.asset), .toOne("obligation", \.obligation), .links("providers", \.providers),
            .toMany("items", \.items), .toMany("attachments", \.attachments),
        ]
    }
    public var recordKey: String { id.uuidString }
    public static func blank() -> Self { Self(kind: .note, title: "", occurredAt: Date()) }
    public static func find(_ key: String, in context: ModelContext) -> Self? {
        guard let id = UUID(uuidString: key) else { return nil }
        return context.first(#Predicate<DosarSchemaV12.HistoryEntry> { $0.id == id }) as? Self
    }
}

extension DosarSchemaV12.ServiceItem: UndoableRecord {
    public static var storedProperties: [StoredProperty<DosarSchemaV12.ServiceItem>] {
        [
            .attribute("id", \.id), .attribute("name", \.name), .attribute("componentKey", \.componentKey),
            .attribute("group", \.group), .attribute("partBrandOrCode", \.partBrandOrCode),
            .attribute("partSerialNumber", \.partSerialNumber), .attribute("costAmount", \.costAmount),
            .attribute("laborCostAmount", \.laborCostAmount), .attribute("partsCostAmount", \.partsCostAmount),
            .attribute("currency", \.currency), .toOne("supplier", \.supplier), .attribute("batchOrTicket", \.batchOrTicket),
            .attribute("locationDetail", \.locationDetail), .attribute("daysInService", \.daysInService),
            .attribute("warrantyMonths", \.warrantyMonths), .attribute("notes", \.notes), .attribute("isExample", \.isExample),
            .attribute("updatedAt", \.updatedAt), .toOne("entry", \.entry), .toMany("attachments", \.attachments),
        ]
    }
    public var recordKey: String { id.uuidString }
    public static func blank() -> Self { Self(name: "") }
    public static func find(_ key: String, in context: ModelContext) -> Self? {
        guard let id = UUID(uuidString: key) else { return nil }
        return context.first(#Predicate<DosarSchemaV12.ServiceItem> { $0.id == id }) as? Self
    }
}

extension DosarSchemaV12.MeasurementLog: UndoableRecord {
    public static var storedProperties: [StoredProperty<DosarSchemaV12.MeasurementLog>] {
        [
            .attribute("id", \.id), .attribute("kindRaw", \.kindRaw), .attribute("name", \.name), .attribute("value", \.value),
            .attribute("secondaryValue", \.secondaryValue), .attribute("unit", \.unit), .attribute("recordedAt", \.recordedAt),
            .attribute("unitPriceAmount", \.unitPriceAmount), .attribute("unitPriceCurrency", \.unitPriceCurrency),
            .attribute("isSelfRead", \.isSelfRead), .attribute("referenceMin", \.referenceMin),
            .attribute("referenceMax", \.referenceMax), .attribute("source", \.source), .attribute("notes", \.notes),
            .attribute("isExample", \.isExample), .attribute("updatedAt", \.updatedAt), .attribute("startsCounter", \.startsCounter),
            .toOne("asset", \.asset), .toMany("attachments", \.attachments),
        ]
    }
    public var recordKey: String { id.uuidString }
    public static func blank() -> Self { Self(kind: .custom, name: "", value: 0) }
    public static func find(_ key: String, in context: ModelContext) -> Self? {
        guard let id = UUID(uuidString: key) else { return nil }
        return context.first(#Predicate<DosarSchemaV12.MeasurementLog> { $0.id == id }) as? Self
    }
}

extension DosarSchemaV12.Attachment: UndoableRecord {
    public static var storedProperties: [StoredProperty<DosarSchemaV12.Attachment>] {
        [
            .attribute("id", \.id), .attribute("title", \.title), .attribute("fileName", \.fileName),
            .attribute("kindRaw", \.kindRaw), .attribute("contentType", \.contentType), .attribute("fileData", \.fileData),
            .attribute("thumbnailData", \.thumbnailData), .attribute("byteCount", \.byteCount), .attribute("sha256", \.sha256),
            .attribute("extractedText", \.extractedText), .attribute("documentDayISO", \.documentDayISO),
            .attribute("validUntilISO", \.validUntilISO), .attribute("documentID", \.documentID), .attribute("isArchived", \.isArchived),
            .attribute("compactedAt", \.compactedAt), .attribute("framingData", \.framingData),
            .attribute("createdAt", \.createdAt), .attribute("isExample", \.isExample), .attribute("updatedAt", \.updatedAt),
            .toMany("pages", \.pages), .toOne("supersededBy", \.supersededBy), .toMany("supersedes", \.supersedes),
            .toOne("asset", \.asset), .toOne("obligation", \.obligation), .toOne("historyEntry", \.historyEntry),
            .toOne("serviceItem", \.serviceItem), .toOne("measurement", \.measurement), .toOne("provider", \.provider),
        ]
    }
    public var recordKey: String { id.uuidString }
    public static func blank() -> Self { Self(fileName: "", contentType: "public.data", data: nil) }
    public static func find(_ key: String, in context: ModelContext) -> Self? {
        guard let id = UUID(uuidString: key) else { return nil }
        return context.first(#Predicate<DosarSchemaV12.Attachment> { $0.id == id }) as? Self
    }
}

extension DosarSchemaV12.AttachmentPage: UndoableRecord {
    public static var storedProperties: [StoredProperty<DosarSchemaV12.AttachmentPage>] {
        [.attribute("id", \.id), .attribute("index", \.index), .attribute("imageData", \.imageData), .toOne("attachment", \.attachment)]
    }
    public var recordKey: String { id.uuidString }
    public static func blank() -> Self { Self(index: 0, imageData: nil) }
    public static func find(_ key: String, in context: ModelContext) -> Self? {
        guard let id = UUID(uuidString: key) else { return nil }
        return context.first(#Predicate<DosarSchemaV12.AttachmentPage> { $0.id == id }) as? Self
    }
}

extension DosarSchemaV12.Provider: UndoableRecord {
    public static var storedProperties: [StoredProperty<DosarSchemaV12.Provider>] {
        [
            .attribute("id", \.id), .attribute("name", \.name), .attribute("trades", \.trades), .attribute("phone", \.phone),
            .attribute("email", \.email), .attribute("address", \.address), .attribute("notes", \.notes),
            .attribute("manualRating", \.manualRating), .attribute("wouldCallAgain", \.wouldCallAgain),
            .attribute("contactIdentifier", \.contactIdentifier), .attribute("taxID", \.taxID),
            .attribute("isExample", \.isExample), .attribute("createdAt", \.createdAt), .attribute("updatedAt", \.updatedAt),
            .links("assets", \.assets), .toMany("historyEntries", \.historyEntries),
            .toMany("suppliedItems", \.suppliedItems), .toMany("attachments", \.attachments),
        ]
    }
    public var recordKey: String { id.uuidString }
    public static func blank() -> Self { Self(name: "") }
    public static func find(_ key: String, in context: ModelContext) -> Self? {
        guard let id = UUID(uuidString: key) else { return nil }
        return context.first(#Predicate<DosarSchemaV12.Provider> { $0.id == id }) as? Self
    }
}

extension DosarSchemaV12.CategoryTemplate: UndoableRecord {
    public static var storedProperties: [StoredProperty<DosarSchemaV12.CategoryTemplate>] {
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
        context.first(#Predicate<DosarSchemaV12.CategoryTemplate> { $0.key == key }) as? Self
    }
}
