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
        /// A new section of this category, named `newAssetName`. For an identity
        /// document, a new household member (`member`) the document is filed under.
        case newAsset(templateKey: String)
    }

    struct Field: Identifiable, Hashable, Sendable {
        var key: CaptureFieldKey
        var value: CaptureValue?
        var confidence: Double
        var sourceText: String?
        var tier: CaptureTier
        /// What the machine-readable zone says, checked by its digits, when it differs
        /// from a value the person typed. Shown beside their value; never applied by itself.
        var documentValue: CaptureValue?

        var id: String { key.rawValue }
        var label: String { CaptureMapping.label(for: key) }
        /// Doubtful: it failed a format or a cross-check, or only a model read it. The
        /// review marks only these; values that passed their checks show plainly.
        var needsCheck: Bool {
            guard let value else { return false }
            return CaptureField(key: key, value: value, confidence: confidence, sourceText: sourceText, tier: tier).needsCheck
        }

        /// The person typed this value: certain, and their own.
        mutating func confirm(_ newValue: CaptureValue?) {
            value = newValue
            confidence = 1
            tier = .deterministic
            if newValue == documentValue { documentValue = nil }
        }

        /// Takes what the document's zone says instead of the person's value.
        mutating func useDocumentValue() {
            guard let documentValue else { return }
            value = documentValue
            confidence = 0.99
            tier = .deterministic
            sourceText = CaptureField.machineReadableSource
            self.documentValue = nil
        }
    }

    /// What the review suggested before the person changed anything, so a re-read
    /// (after adding the back of a card) keeps exactly what they edited.
    struct Suggested: Hashable {
        var kind: CaptureDocumentKind
        var title: String
        var destination: Destination
        var newAssetName: String
        var fields: [CaptureFieldKey: CaptureValue]
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
    /// Filed under a household member, it becomes one of their documents whatever
    /// its kind (a cazier, a bank card), not a loose paper on the person.
    var filesAsPersonalDocument = false
    let suggested: Suggested

    /// The pages waiting in capture's store, when there are any to file.
    var documentID: UUID? {
        guard duplicateAttachmentID == nil else { return nil }
        return result.documentID
    }

    /// Fields shown on the review: everything read, in a sensible order, without repeats.
    var visibleFields: [Field] {
        let keys = Set(fields.map(\.key))
        let order = Dictionary(uniqueKeysWithValues: CaptureMapping.reviewOrder.enumerated().map { ($1, $0) })
        return fields.enumerated()
            .filter { CaptureMapping.isShownInReview($0.element.key, among: keys) }
            .sorted { (order[$0.element.key] ?? 100 + $0.offset, $0.offset) < (order[$1.element.key] ?? 100 + $1.offset, $1.offset) }
            .map(\.element)
    }

    /// An identity card read without the zone on its back: the review offers to add it.
    var asksForBackPage: Bool {
        kind == .identityCard && result.notices.contains(.identityBackMissing)
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
    /// number), the household member an identity document belongs to, the only
    /// section of the right category, or a new one.
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
        self.destination = Self.suggestDestination(result: result, assets: assets)
        self.newAssetName = Self.defaultAssetName(kind: result.kind, values: values)
        self.suggested = Suggested(kind: kind, title: title, destination: destination, newAssetName: newAssetName, fields: values)
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
        // 2. An identity document goes to its holder: the matching member, or a new one.
        if result.kind.isIdentityDocument {
            let values = Dictionary(result.fields.map { ($0.key, $0.value) }, uniquingKeysWith: { first, _ in first })
            if let holder = CaptureMapping.holderName(values) {
                let members = candidates.filter { $0.templateKey == BuiltInTemplates.Key.member }.map { (id: $0.id, name: $0.name) }
                if let member = CaptureMapping.matchingMember(holderSurname: values[.surname]?.text, holderName: holder, among: members) {
                    return .asset(member)
                }
                return .newAsset(templateKey: BuiltInTemplates.Key.member)
            }
        }
        // 3. The category the document belongs to.
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
        case .passport, .identityCard, .drivingLicence:
            // A new member is named after the holder.
            return CaptureMapping.holderName(values) ?? CaptureMapping.defaultTitle(for: kind, fields: values)
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

    // MARK: Reading again

    /// A value read from the machine-readable zone with valid check digits.
    static func isCheckedZoneValue(_ field: Field) -> Bool {
        field.value != nil && field.tier == .deterministic && field.sourceText == CaptureField.machineReadableSource
    }

    /// This review read again (with the back of the card added), keeping everything
    /// the person changed in `previous`. Values they typed stay theirs; the rest comes
    /// from the new read, where the checked zone on the back wins over printed labels.
    func carryingEdits(from previous: CaptureReview) -> CaptureReview {
        var merged = self
        let before = previous.suggested
        for field in previous.fields where field.value != before.fields[field.key] {
            var kept = field
            if let index = merged.fields.firstIndex(where: { $0.key == field.key }) {
                // The person's value stays; a checked zone value that disagrees is offered beside it.
                let fresh = merged.fields[index]
                kept.documentValue = Self.isCheckedZoneValue(fresh) && fresh.value != field.value ? fresh.value : nil
                merged.fields[index] = kept
            } else {
                merged.fields.append(kept)
            }
        }
        // Values the person cleared stay cleared.
        for key in before.fields.keys where !previous.fields.contains(where: { $0.key == key && $0.value != nil }) {
            if let index = merged.fields.firstIndex(where: { $0.key == key }) { merged.fields[index].value = nil }
        }
        if previous.kind != before.kind { merged.kind = previous.kind }
        if previous.title != before.title { merged.title = previous.title }
        if previous.destination != before.destination { merged.destination = previous.destination }
        if previous.newAssetName != before.newAssetName { merged.newAssetName = previous.newAssetName }
        merged.remindsToPay = previous.remindsToPay
        merged.filesAsPersonalDocument = previous.filesAsPersonalDocument
        return merged
    }
}
