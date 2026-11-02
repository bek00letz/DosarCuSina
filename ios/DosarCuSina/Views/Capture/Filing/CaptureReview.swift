import Foundation
import SwiftData

/// A capture the person is checking before it is saved: what the document is,
/// the values read from it (editable), where it goes, and the reminder it sets.
/// Nothing is saved until `CaptureFiler.save(_:)`.
struct CaptureReview: Identifiable {
    enum Destination: Hashable, Sendable {
        /// Keep the document without filing it under a section.
        case none
        case asset(UUID)
        /// A new section of this category, named `newAssetName`.
        case newAsset(templateKey: String)
    }

    struct Field: Identifiable, Hashable, Sendable {
        var key: CaptureFieldKey
        var value: CaptureValue?
        var confidence: Double
        var sourceText: String?
        var tier: CaptureTier

        var id: String { key.rawValue }
        var label: String { CaptureMapping.label(for: key) }
        /// Read with little certainty: the review marks it for a check.
        var needsCheck: Bool { confidence < Self.checkThreshold }

        static let checkThreshold = 0.6
    }

    let id = UUID()
    let result: CaptureResult
    var kind: CaptureDocumentKind
    var title: String
    var fields: [Field]
    var destination: Destination
    var newAssetName: String
    /// For bills with a due date: a one-off reminder to pay it.
    var remindsToPay: Bool
    /// Already in the binder: the filed document it matches.
    var duplicateAttachmentID: UUID?

    /// The pages waiting in capture's store, when there are any to file.
    var documentID: UUID? {
        guard duplicateAttachmentID == nil else { return nil }
        return result.documentID
    }

    /// Fields shown on the review: everything read, except personal identifiers.
    var visibleFields: [Field] {
        fields.filter { !CaptureMapping.isPersonal($0.key) && $0.key != .lineItems }
    }

    func value(_ key: CaptureFieldKey) -> CaptureValue? {
        fields.first { $0.key == key }?.value
    }

    var valuesByKey: [CaptureFieldKey: CaptureValue] {
        Dictionary(fields.compactMap { field in field.value.map { (field.key, $0) } }, uniquingKeysWith: { first, _ in first })
    }

    /// The day the reminder follows (expiry, due date, next dose), from the current values.
    var reminderDay: CalendarDay? {
        CaptureMapping.reminderField(for: kind).flatMap { value($0)?.day }.map(CaptureMapping.calendarDay)
    }

    var total: Money? {
        (value(.total)?.money ?? value(.purchasePrice)?.money).map(CaptureMapping.money)
    }

    /// The date printed on the document.
    var documentDay: CalendarDay? {
        [CaptureFieldKey.issueDate, .startDate, .purchaseDate].lazy.compactMap { value($0)?.day }.first.map(CaptureMapping.calendarDay)
    }

    /// The template blueprint this document renews or schedules, if any.
    var blueprintKey: String? {
        for suggestion in result.suggestions {
            if case .obligation(let key, _) = suggestion.destination, let mapped = CaptureMapping.blueprintKey(key) { return mapped }
        }
        return nil
    }

    /// Which reading tier filled most of the fields, for the subtle note.
    var mainTier: CaptureTier? {
        let counts = Dictionary(grouping: fields, by: \.tier).mapValues(\.count)
        return counts.max { $0.value < $1.value }?.key
    }

    var usedCloudModel: Bool { result.tiersUsed.contains(.cloudModel) }

    // MARK: Building

    /// A review with the destination worked out from what was read: an existing
    /// section that matches an identifier (plate, VIN, POD, microchip, document
    /// number), the only section of the right category, or a new one.
    @MainActor
    init(result: CaptureResult, assets: [Asset], context: ModelContext) {
        self.result = result
        self.kind = result.kind
        self.fields = result.fields.map { Field(key: $0.key, value: $0.value, confidence: $0.confidence, sourceText: $0.sourceText, tier: $0.tier) }
        let values = Dictionary(result.fields.map { ($0.key, $0.value) }, uniquingKeysWith: { first, _ in first })
        self.title = CaptureMapping.defaultTitle(for: result.kind, fields: values)
        self.remindsToPay = result.kind == .utilityInvoice
        self.duplicateAttachmentID = nil
        for notice in result.notices {
            if case .duplicateDocument(let id) = notice, Self.isFiled(id, in: context) {
                self.duplicateAttachmentID = id
            }
        }
        let suggestion = Self.suggestDestination(result: result, assets: assets)
        self.destination = suggestion
        self.newAssetName = Self.defaultAssetName(kind: result.kind, values: values)
    }

    private static func isFiled(_ id: UUID, in context: ModelContext) -> Bool {
        var descriptor = FetchDescriptor<Attachment>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        return ((try? context.fetchCount(descriptor)) ?? 0) > 0
    }

    @MainActor
    static func suggestDestination(result: CaptureResult, assets: [Asset]) -> Destination {
        let candidates = assets.filter { !$0.isExample }
        // 1. An identifier on the document matches a section.
        let hints = result.suggestions.flatMap(\.assetHints)
        for hint in hints {
            let wanted = CaptureMapping.normalizedIdentifier(hint.value)
            guard !wanted.isEmpty else { continue }
            if let match = candidates.first(where: { asset in
                asset.values.contains { _, value in
                    value.textValue.map(CaptureMapping.normalizedIdentifier) == wanted
                }
            }) {
                return .asset(match.id)
            }
        }
        // 2. The category the document belongs to.
        let templateKey = result.suggestions.lazy.compactMap { suggestion -> String? in
            switch suggestion.destination {
            case .newAsset(let key): return CaptureMapping.templateKey(key)
            case .obligation(_, let key?): return CaptureMapping.templateKey(key)
            case .historyEntry(let key?): return CaptureMapping.templateKey(key)
            default: return nil
            }
        }.first ?? CaptureMapping.templateKey(for: result.kind)
        guard let templateKey else { return .none }
        // New documents, products and cars get their own section; bills and
        // policies go to the only section of their kind when there is one.
        let createsNew = result.suggestions.contains {
            if case .newAsset = $0.destination { return true }
            return false
        }
        let sameKind = candidates.filter { $0.templateKey == templateKey }
        if !createsNew, sameKind.count == 1, let only = sameKind.first { return .asset(only.id) }
        if createsNew || sameKind.isEmpty { return .newAsset(templateKey: templateKey) }
        return .none
    }

    static func defaultAssetName(kind: CaptureDocumentKind, values: [CaptureFieldKey: CaptureValue]) -> String {
        switch kind {
        case .vehicleRegistration, .rcaPolicy, .itpReport, .serviceInvoice:
            let makeModel = [values[.make]?.text, values[.model]?.text].compactMap { $0 }.joined(separator: " ")
            if !makeModel.isEmpty { return makeModel }
            return values[.licensePlate]?.text ?? String(localized: "Mașina")
        case .utilityInvoice: return String(localized: "Locuința")
        case .veterinaryRecord: return values[.petName]?.text ?? String(localized: "Animalul")
        case .medicalResult: return String(localized: "Sănătate")
        default: return CaptureMapping.defaultTitle(for: kind, fields: values)
        }
    }
}
