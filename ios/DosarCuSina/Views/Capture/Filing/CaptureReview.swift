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
        /// What other readers read here, shown beside the value with "Folosește-l" and
        /// never applied by themselves: the phone's value an AI value replaced, or, beside
        /// the person's own value, what a checked code or the AI read.
        var alternatives: [CaptureAlternative<CaptureValue>] = []
        /// The person typed or chose this value. No later reading changes it.
        var isEdited = false
        /// Who read the value the person chose from the alternatives; nil when they typed it.
        var chosenSource: CaptureAlternativeSource?

        var id: String { key.rawValue }
        var label: String { CaptureMapping.label(for: key) }
        /// Doubtful: it failed a format or a cross-check, or only a model read it. The
        /// review marks only these; values that passed their checks show plainly.
        var needsCheck: Bool {
            captureField?.needsCheck ?? false
        }

        /// The person typed this value: certain, and their own.
        mutating func confirm(_ newValue: CaptureValue?) {
            value = newValue
            confidence = 1
            tier = .deterministic
            isEdited = true
            chosenSource = nil
            alternatives.removeAll { $0.value == newValue }
        }

        /// Takes another reader's value instead of the one shown: the person's choice. The
        /// value it replaces is offered in its place, so they can switch back, unless they
        /// had typed it themselves.
        mutating func use(_ alternative: CaptureAlternative<CaptureValue>) {
            let shownSource = isEdited ? chosenSource : captureField.map(ReadingArbiter.source(of:))
            let shownValue = value
            confirm(alternative.value)
            chosenSource = alternative.source
            if let shownValue, let shownSource, shownValue != alternative.value {
                let replaced = CaptureAlternative(shownValue, source: shownSource)
                if !alternatives.contains(replaced) { alternatives.append(replaced) }
            }
        }

        /// The value as a capture field, for the checks.
        var captureField: CaptureField? {
            value.map { CaptureField(key: key, value: $0, confidence: confidence, sourceText: sourceText, tier: tier) }
        }
    }

    /// What the review suggested before the person changed anything, so a re-read
    /// (after adding the back of a card) keeps exactly what they edited.
    struct Suggested: Hashable {
        var kind: CaptureDocumentKind
        var title: String
        var destination: Destination
        var newAssetName: String
        var remindsToPay: Bool
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
    var suggested: Suggested
    /// Kinds another reader saw, offered beside the kind shown ("Pe telefon părea: …").
    var kindAlternatives: [CaptureAlternative<CaptureDocumentKind>]
    /// The reading behind the kind shown, when the person took it from the alternatives.
    private var chosenKind: CaptureAlternative<CaptureDocumentKind>?

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

    /// The bill's lines as the person left them: corrected, added or removed. An
    /// empty list removes the field.
    var lineItems: [CaptureLineItem] {
        get { value(.lineItems)?.lineItems ?? [] }
        set {
            if let index = fields.firstIndex(where: { $0.key == .lineItems }) {
                if newValue.isEmpty { fields.remove(at: index) } else { fields[index].confirm(.lineItems(newValue)) }
            } else if !newValue.isEmpty {
                var field = Field(key: .lineItems, value: nil, confidence: 1, sourceText: nil, tier: .deterministic)
                field.confirm(.lineItems(newValue))
                fields.append(field)
            }
        }
    }

    /// Whether the review offers "Ce s-a făcut": the kind lists lines, or some were read.
    var showsLineItems: Bool {
        !lineItems.isEmpty || [.serviceInvoice, .fiscalReceipt, .veterinaryRecord].contains(kind)
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

    /// The fields as they stand now, corrections included, for routing.
    var currentFields: [CaptureField] {
        fields.compactMap { field in
            field.value.map { CaptureField(key: field.key, value: $0, confidence: field.confidence, sourceText: field.sourceText, tier: field.tier) }
        }
    }

    /// What routing suggests for the document as it stands now: its current kind and
    /// fields, so changing the kind ("Nu e asta? Schimbă") changes the deadline too.
    var suggestions: [CaptureSuggestion] {
        kind == result.kind ? result.suggestions : CaptureRouter.route(kind: kind, kindConfidence: 1, fields: currentFields).suggestions
    }

    /// The template blueprint this document renews or schedules, if any.
    var blueprintKey: String? {
        for suggestion in suggestions {
            if case .obligation(let key, _) = suggestion.destination, let mapped = CaptureMapping.blueprintKey(key) { return mapped }
        }
        return nil
    }

    /// Takes another reader's kind: the person's choice. The kind it replaces is offered
    /// in its place, so they can switch back. What depends on the kind follows through
    /// `kindChanged`, which the review runs on every change of kind.
    mutating func useKind(_ alternative: CaptureAlternative<CaptureDocumentKind>) {
        // The kind shown came from the reading, or from an alternative taken before; one
        // the person picked from the list themselves isn't offered back.
        let replaced: CaptureAlternative<CaptureDocumentKind>? = if kind == suggested.kind, kind == result.kind {
            CaptureAlternative(kind, source: result.kindSource)
        } else if let chosenKind, chosenKind.value == kind {
            chosenKind
        } else {
            nil
        }
        kind = alternative.value
        chosenKind = alternative
        kindAlternatives.removeAll { $0 == alternative }
        if let replaced, replaced.value != kind, !kindAlternatives.contains(replaced) { kindAlternatives.append(replaced) }
    }

    /// After the kind changes (the person chose another, or a reading named another): what
    /// depends on it follows, unless they already chose it themselves (the place, the name,
    /// the title, the reminder to pay). Routing, the blueprint and the reminder follow by
    /// themselves through `suggestions`.
    @MainActor
    mutating func kindChanged(assets: [Asset]) {
        kindAlternatives.removeAll { $0.value == kind }
        if remindsToPay == suggested.remindsToPay {
            remindsToPay = kind == .utilityInvoice
            suggested.remindsToPay = remindsToPay
        }
        let values = Dictionary(currentFields.map { ($0.key, $0.value) }, uniquingKeysWith: { first, _ in first })
        if destination == suggested.destination {
            destination = Self.suggestDestination(kind: kind, suggestions: suggestions, fields: currentFields, assets: assets)
            suggested.destination = destination
        }
        if title == suggested.title {
            title = CaptureMapping.defaultTitle(for: kind, fields: values)
            suggested.title = title
        }
        if newAssetName == suggested.newAssetName {
            newAssetName = Self.defaultAssetName(kind: kind, values: values)
            suggested.newAssetName = newAssetName
        }
    }

    /// Which reading tier filled most of the fields, for the subtle note.
    var mainTier: CaptureTier? {
        let counts = Dictionary(grouping: fields, by: \.tier).mapValues(\.count)
        return counts.max { $0.value < $1.value }?.key
    }

    /// The person's AI provider read this document.
    var usedCloudModel: Bool { result.readWithCloudModel }

    // MARK: Building

    /// A review with the destination worked out from what was read: an existing
    /// section that matches an identifier (plate, VIN, POD, microchip, document
    /// number), the household member an identity document belongs to, the only
    /// section of the right category, or a new one.
    @MainActor
    init(result: CaptureResult, assets: [Asset], context: ModelContext) {
        self.result = result
        self.kind = result.kind
        self.fields = result.fields.map { field in
            // A check settles a disagreement: nothing is offered beside a checked value.
            let settled = ReadingArbiter.standing(field) >= .checked
            return Field(key: field.key, value: field.value, confidence: field.confidence, sourceText: field.sourceText, tier: field.tier,
                         alternatives: settled ? [] : result.alternatives(for: field.key).filter { $0.value != field.value })
        }
        self.kindAlternatives = result.kindAlternatives.filter { $0.value != result.kind }
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
        self.suggested = Suggested(kind: kind, title: title, destination: destination, newAssetName: newAssetName, remindsToPay: remindsToPay, fields: values)
    }

    private static func isFiled(_ id: UUID, in context: ModelContext) -> Bool {
        var descriptor = FetchDescriptor<Attachment>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        return ((try? context.fetchCount(descriptor)) ?? 0) > 0
    }

    @MainActor
    static func suggestDestination(result: CaptureResult, assets: [Asset]) -> Destination {
        suggestDestination(kind: result.kind, suggestions: result.suggestions, fields: result.fields, assets: assets)
    }

    /// Where a document of `kind` goes, from what routing suggests for it.
    @MainActor
    static func suggestDestination(kind: CaptureDocumentKind, suggestions: [CaptureSuggestion], fields: [CaptureField], assets: [Asset]) -> Destination {
        let candidates = assets.filter { !$0.isExample }
        // 1. An identifier on the document matches a section.
        let hints = suggestions.flatMap(\.assetHints)
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
        if kind.isIdentityDocument {
            let values = Dictionary(fields.map { ($0.key, $0.value) }, uniquingKeysWith: { first, _ in first })
            if let holder = CaptureMapping.holderName(values) {
                let members = candidates.filter { $0.templateKey == BuiltInTemplates.Key.member }.map { (id: $0.id, name: $0.name) }
                if let member = CaptureMapping.matchingMember(holderSurname: values[.surname]?.text, holderName: holder, among: members) {
                    return .asset(member)
                }
                return .newAsset(templateKey: BuiltInTemplates.Key.member)
            }
        }
        // 3. The category the document belongs to.
        let templateKey = suggestions.lazy.compactMap { suggestion -> String? in
            switch suggestion.destination {
            case .newAsset(let key): return CaptureMapping.templateKey(key)
            case .obligation(_, let key?): return CaptureMapping.templateKey(key)
            case .historyEntry(let key?): return CaptureMapping.templateKey(key)
            default: return nil
            }
        }.first ?? CaptureMapping.templateKey(for: kind)
        guard let templateKey else { return .none }
        // New documents, products and cars get their own section; bills and
        // policies go to the only section of their kind when there is one.
        let createsNew = suggestions.contains {
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

    /// Values that may be offered beside the person's own: checked ones and the AI's.
    /// The phone's patterns are what they corrected, so those aren't offered again.
    private static func offersBesideAnEdit(_ source: CaptureAlternativeSource) -> Bool {
        if case .phone = source { return false }
        return true
    }

    /// This review read again (with the back of the card added, or by the person's AI
    /// provider), keeping everything the person changed in `previous`: values they typed
    /// or chose, the kind, the place, the title, the name and the reminder to pay. A
    /// checked or AI value that differs from theirs is offered beside it, never applied.
    /// What they didn't touch comes from the new reading; when they kept a kind of their
    /// own, what depends on the kind follows theirs (`kindChanged`).
    @MainActor
    func carryingEdits(from previous: CaptureReview, assets: [Asset]) -> CaptureReview {
        var merged = self
        let before = previous.suggested
        for field in previous.fields where field.isEdited || field.value != before.fields[field.key] {
            var kept = field
            kept.isEdited = true
            if let index = merged.fields.firstIndex(where: { $0.key == field.key }) {
                let fresh = merged.fields[index]
                var offered: [CaptureAlternative<CaptureValue>] = []
                if let freshField = fresh.captureField {
                    offered.append(CaptureAlternative(freshField.value, source: ReadingArbiter.source(of: freshField)))
                }
                offered += merged.result.alternatives(for: field.key)
                kept.alternatives = offered.reduce(into: []) { list, alternative in
                    guard Self.offersBesideAnEdit(alternative.source), alternative.value != field.value,
                          !list.contains(where: { $0.value == alternative.value }) else { return }
                    list.append(alternative)
                }
                merged.fields[index] = kept
            } else {
                kept.alternatives = []
                merged.fields.append(kept)
            }
        }
        // Values the person cleared stay cleared.
        for key in before.fields.keys where !previous.fields.contains(where: { $0.key == key && $0.value != nil }) {
            if let index = merged.fields.firstIndex(where: { $0.key == key }) { merged.fields[index].value = nil }
        }
        if previous.kind != before.kind {
            // Their kind stays; the reading's own is offered beside it.
            let read = CaptureAlternative(merged.kind, source: merged.result.kindSource)
            merged.kind = previous.kind
            merged.kindAlternatives = ([read] + merged.kindAlternatives).reduce(into: []) { list, alternative in
                guard Self.offersBesideAnEdit(alternative.source), alternative.value != previous.kind,
                      !list.contains(where: { $0.value == alternative.value }) else { return }
                list.append(alternative)
            }
            merged.kindChanged(assets: assets)
        }
        if previous.title != before.title { merged.title = previous.title }
        if previous.destination != before.destination { merged.destination = previous.destination }
        if previous.newAssetName != before.newAssetName { merged.newAssetName = previous.newAssetName }
        if previous.remindsToPay != before.remindsToPay { merged.remindsToPay = previous.remindsToPay }
        merged.filesAsPersonalDocument = previous.filesAsPersonalDocument
        return merged
    }
}
