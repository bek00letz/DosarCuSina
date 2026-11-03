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
        /// Why the suggested place is worth a look: the supply address only partly agrees.
        var placeCheck: SubscriptionMatcher.HouseCheck? = nil
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
    /// Filed under a household member, it becomes one of their documents whatever
    /// its kind (a cazier, a bank card), not a loose paper on the person.
    var filesAsPersonalDocument = false
    /// The person asked to keep the photo of a document whose photo is kept only on
    /// request ("Păstrează și poza cardului"). Off until they turn it on.
    var keepsPhotoOnRequest = false
    /// The person confirmed that the bank pays this subscription by direct debit, as the
    /// bill says ("Plătesc prin debit direct"). Never on until they turn it on.
    var turnsOnDirectDebit = false
    /// The person chose the place themselves, even the one suggested: nothing to check.
    private(set) var placeConfirmed = false
    /// The person is adding a document read only on the phone (the capture started from a
    /// bank card's page): the AI provider never reads it.
    var staysOnPhone = false
    var suggested: Suggested
    /// Kinds another reader saw, offered beside the kind shown ("Pe telefon părea: …").
    var kindAlternatives: [CaptureAlternative<CaptureDocumentKind>]
    /// The reading behind the kind shown, when the person took it from the alternatives.
    private var chosenKind: CaptureAlternative<CaptureDocumentKind>?
    /// The person chose the kind shown. No later reading changes it.
    private(set) var kindEdited = false
    /// What each category does, read when the review was made, so where a document can
    /// go is decided by the categories' parts (a home, a subscription, a person), never their keys.
    let behaviors: [String: CategoryBehavior]

    /// The document this review files: pages waiting in capture's store, or the copy
    /// the binder already keeps (it moves to where this review files it).
    var document: CapturedDocumentRef? { result.document }

    /// Already in the binder: the filed document it matches.
    var duplicateAttachmentID: UUID? { document?.keptAttachmentID }

    /// The pages waiting in capture's store, when there are any.
    var documentID: UUID? { document?.pendingID }

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
        !lineItems.isEmpty || (kind.profile.carriesLineItems && kind.profile.filing != .keepOnly)
    }

    func value(_ key: CaptureFieldKey) -> CaptureValue? {
        fields.first { $0.key == key }?.value
    }

    var valuesByKey: [CaptureFieldKey: CaptureValue] {
        Dictionary(fields.compactMap { field in field.value.map { (field.key, $0) } }, uniquingKeysWith: { first, _ in first })
    }

    /// The day the reminder follows (expiry, due date, next dose), from the current values:
    /// the kind's deadline field, for a minimum period the end its terms give, and for a
    /// document valid for a set time after it is issued (a cazier judiciar) that time
    /// after its issue date.
    var reminderDay: CalendarDay? {
        let field = kind.profile.deadlineField
        if field == .minimumPeriodEnd { return minimumPeriodEnd }
        if let day = field.flatMap({ value($0)?.day }) { return CaptureMapping.calendarDay(day) }
        return validityEnd
    }

    /// The last valid day by the document's rule, from its issue date, when it prints no
    /// expiry: what saving writes through the documents category's own derivation.
    var validityEnd: CalendarDay? {
        guard kind.profile.deadlineField == .expiryDate, value(.expiryDate) == nil,
              let issued = value(.issueDate)?.day else { return nil }
        return DocumentType.validUntil(issued: CaptureMapping.calendarDay(issued), type: kind.profile.documentType,
                                       variant: value(.documentVariant)?.text)
    }

    /// The months a document of this kind and variant is valid after its issue, when a rule says so.
    var validityMonths: Int? {
        DocumentType.validityMonths(type: kind.profile.documentType, variant: value(.documentVariant)?.text)
    }

    /// Saving keeps the document's photo: always, except where the kind keeps it only on
    /// request (a bank card) and the person hasn't asked.
    var keepsPhoto: Bool {
        !kind.profile.photoIsOptIn || keepsPhotoOnRequest
    }

    /// When a contract's minimum period ends: as printed, or its length after its start.
    /// Once the person corrects the start or the length, the end follows them, unless
    /// they set the end themselves.
    var minimumPeriodEnd: CalendarDay? {
        func edited(_ key: CaptureFieldKey) -> Bool { fields.contains { $0.key == key && $0.isEdited } }
        let printed = value(.minimumPeriodEnd)?.day
        let worked: CaptureDay? = {
            guard let start = value(.startDate)?.day, let months = value(.minimumMonths), case .number(let count) = months else { return nil }
            return start.addingMonths(NSDecimalNumber(decimal: count).intValue)
        }()
        let termsEdited = edited(.startDate) || edited(.minimumMonths)
        let end = (printed != nil && (edited(.minimumPeriodEnd) || !termsEdited)) ? printed : (worked ?? printed)
        return end.map(CaptureMapping.calendarDay)
    }

    var total: Money? {
        (value(.total)?.money ?? value(.purchasePrice)?.money).map(CaptureMapping.money)
    }

    /// The date printed on the document.
    var documentDay: CalendarDay? {
        kind.profile.documentDateFields.lazy.compactMap { value($0)?.day }.first.map(CaptureMapping.calendarDay)
    }

    /// The last day the document itself is valid, as read (a policy's end, an identity
    /// card's expiry), kept on the filed document. Nil for a bill's due date or a next dose.
    var validUntil: CalendarDay? {
        let field = kind.profile.deadlineField
        guard field == .expiryDate || field == .warrantyUntil else { return nil }
        return reminderDay
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

    /// What a policy covers: as read or chosen, else the kind's own, else from what it names.
    var cover: String? {
        kind.profile.cover(read: value(.coverageType)?.text, hasVehicle: value(.licensePlate) != nil || value(.vin) != nil)
    }

    /// The blueprint this document renews or schedules, if any, from the kind's profile.
    var blueprintKey: String? {
        kind.profile.deadline(cover: cover)?.blueprintKey
    }

    /// The deadline this document sets in `template`: the profile's blueprint when the
    /// category keeps it, else (a category of the person's own) the deadline that follows
    /// the field the document's date fills.
    @MainActor
    func deadlineBlueprint(in template: TemplateDefinition) -> ObligationBlueprint? {
        if let key = blueprintKey, let blueprint = template.blueprints.first(where: { $0.key == key }) { return blueprint }
        guard kind.profile.deadlineField != nil else { return nil }
        let values = CaptureFiler.values(from: self, for: template, deadline: nil)
        return template.blueprints.first { blueprint in
            blueprint.drivingField.map { values[$0] != nil } ?? false
        }
    }

    /// The section that already exists and that saving writes the values into: the one
    /// chosen, or the subscription a chosen home holds for this bill. Nil when saving makes
    /// a new one (a new section, a person's new document, a home's new subscription).
    @MainActor
    func existingSection(assets: [Asset], templates: [String: CategoryTemplate]) -> Asset? {
        guard case .asset(let id) = destination, let asset = assets.first(where: { $0.id == id }) else { return nil }
        if CaptureFiler.holderDocumentTemplateKey(for: self, destinationTemplateKey: asset.templateKey, templates: templates) != nil { return nil }
        if kind.profile.filing == .subscription, templates.plays(.home, asset.templateKey) {
            return existingSubscription(assets: assets)
        }
        return asset
    }

    /// Expected fields of this kind that weren't read, so the person can add them: an RCA
    /// policy corrected from a bill can get its expiry.
    var addableKeys: [CaptureFieldKey] {
        let present = Set(fields.map(\.key))
        let expected = kind.expectedKeys.reduce(into: [CaptureFieldKey]()) { list, key in
            if !list.contains(key) { list.append(key) }
        }
        return expected.filter { key in
            !present.contains(key) && kind.allows(key) && key != .lineItems && key != .serviceKind
                && CaptureMapping.isShownInReview(key, among: present.union([key]))
        }
    }

    /// Adds an expected field the reading didn't find, empty, for the person to fill in.
    mutating func addField(_ key: CaptureFieldKey) {
        guard !fields.contains(where: { $0.key == key }) else { return }
        var field = Field(key: key, value: nil, confidence: 1, sourceText: nil, tier: .deterministic)
        field.isEdited = true
        fields.append(field)
    }

    /// The person chose another kind: from the list, or another reader's ("Folosește-l").
    /// The page is read again as that kind (`CaptureEngine.reinterpret`: that kind's
    /// patterns and labels, merged with what the models read, only the fields it carries),
    /// and the review keeps everything they changed. What depends on the kind follows
    /// (`kindChanged`), unless they chose it themselves.
    @MainActor
    func choosingKind(_ kind: CaptureDocumentKind, from alternative: CaptureAlternative<CaptureDocumentKind>? = nil,
                      assets: [Asset], context: ModelContext, engine: CaptureEngine = .standard()) -> CaptureReview {
        var previous = self
        if let alternative { previous.useKind(alternative) } else { previous.kind = kind }
        guard previous.kind != self.kind || alternative != nil else { return self }
        previous.kindEdited = true
        let read = CaptureReview(result: engine.reinterpret(result, as: previous.kind), assets: assets, context: context)
        var merged = read.carryingEdits(from: previous, assets: assets)
        // The field rules hold for the person's own values too: an ID card carries no total.
        merged.fields.removeAll { !merged.kind.allows($0.key) }
        merged.kindAlternatives = previous.kindAlternatives.filter { $0.value != previous.kind }
        merged.chosenKind = previous.chosenKind
        return merged
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
            remindsToPay = kind.profile.deadlineIsOptIn
            suggested.remindsToPay = remindsToPay
        }
        let values = Dictionary(currentFields.map { ($0.key, $0.value) }, uniquingKeysWith: { first, _ in first })
        if destination == suggested.destination, !placeConfirmed {
            let place = Self.suggestPlace(kind: kind, suggestions: suggestions, fields: currentFields, assets: assets, behaviors: behaviors)
            destination = place.destination
            suggested.destination = destination
            suggested.placeCheck = place.check
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

    // MARK: Subscriptions

    /// What the bill or contract says about its ongoing contract, as it stands now.
    var subscriptionReading: SubscriptionMatcher.Reading {
        Self.subscriptionReading(kind: kind, values: valuesByKey)
    }

    static func subscriptionReading(kind: CaptureDocumentKind, values: [CaptureFieldKey: CaptureValue]) -> SubscriptionMatcher.Reading {
        let codes: [SubscriptionMatcher.Code: CaptureFieldKey] = [
            .pod: .podCode, .clc: .clcCode, .phoneNumber: .phoneNumber, .contractNumber: .contractNumber, .clientCode: .clientCode,
        ]
        return SubscriptionMatcher.Reading(
            provider: values[.provider]?.text,
            service: values[.serviceKind]?.text,
            codes: codes.compactMapValues { values[$0]?.text },
            isBill: kind == .utilityInvoice,
            supplyAddress: values[.supplyAddress]?.text
        )
    }

    /// The place to check, when the supply address chose it without being sure and the
    /// person hasn't chosen it themselves: "Verifică".
    var placeCheck: SubscriptionMatcher.HouseCheck? {
        guard !placeConfirmed, destination == suggested.destination else { return nil }
        return suggested.placeCheck
    }

    /// The person chose where the document goes, from the list: their choice, nothing to check.
    mutating func choosePlace(_ place: Destination) {
        destination = place
        placeConfirmed = true
    }

    /// The subscription that already exists and that saving would file into: the one
    /// chosen, or the one a chosen home holds for this contract. Nil for a new one.
    @MainActor
    func existingSubscription(assets: [Asset]) -> Asset? {
        guard kind.profile.filing == .subscription, case .asset(let id) = destination,
              let asset = assets.first(where: { $0.id == id }) else { return nil }
        if behaviors.plays(.subscription, asset.templateKey) { return asset }
        guard behaviors.plays(.home, asset.templateKey) else { return nil }
        let children = (asset.children ?? []).filter { behaviors.plays(.subscription, $0.templateKey) }
        let decision = SubscriptionMatcher.match(
            subscriptionReading,
            subscriptions: children.map { SubscriptionMatcher.Subscription(id: $0.id, parentID: asset.id, values: $0.values) },
            homes: [], within: asset.id
        )
        guard case .existing(let match) = decision else { return nil }
        return children.first { $0.id == match }
    }

    /// The bank pays the subscription this bill goes to by direct debit: it already says
    /// so, or the person just confirmed what the bill says.
    @MainActor
    func paysByDirectDebit(assets: [Asset]) -> Bool {
        turnsOnDirectDebit || subscriptionPaysByDirectDebit(assets: assets)
    }

    @MainActor
    private func subscriptionPaysByDirectDebit(assets: [Asset]) -> Bool {
        existingSubscription(assets: assets).map { SubscriptionFields.paysByDirectDebit($0.values) } ?? false
    }

    /// What the bill prints about direct debit ("Factura se achită prin debit direct"), when
    /// it says it is paid so and its subscription doesn't know yet: the review offers to turn
    /// "Plătesc prin debit direct" on. Never turned on by itself.
    @MainActor
    func directDebitStatement(assets: [Asset]) -> String? {
        guard kind.profile.filing == .subscription, kind.allows(.directDebit),
              let statement = value(.directDebit)?.text, !subscriptionPaysByDirectDebit(assets: assets) else { return nil }
        return statement
    }

    /// Which reading tier filled most of the fields, for the subtle note.
    var mainTier: CaptureTier? {
        let counts = Dictionary(grouping: fields, by: \.tier).mapValues(\.count)
        return counts.max { $0.value < $1.value }?.key
    }

    /// The person's AI provider read this document.
    var usedCloudModel: Bool { result.readWithCloudModel }

    /// Whether the person's AI provider may read this document (`PhoneOnlyReading`): never
    /// one read only on the phone, whether the person is adding one, chose that kind, or the
    /// phone read one (or can't be sure it didn't). The review offers "Citește mai bine"
    /// only when it may.
    var providerMayRead: Bool {
        !staysOnPhone && !PhoneOnlyReading.isPhoneOnly(kind) && !PhoneOnlyReading.mayBeOne(result)
            && !kindAlternatives.contains { PhoneOnlyReading.isPhoneOnly($0.value) }
    }

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
        let behaviors = (try? TemplateStore(context: context).behaviorsByKey()) ?? [:]
        self.behaviors = behaviors
        let values = Dictionary(result.fields.map { ($0.key, $0.value) }, uniquingKeysWith: { first, _ in first })
        self.title = CaptureMapping.defaultTitle(for: result.kind, fields: values)
        self.remindsToPay = result.kind.profile.deadlineIsOptIn
        let place = Self.suggestPlace(kind: result.kind, suggestions: result.suggestions, fields: result.fields, assets: assets, behaviors: behaviors)
        self.destination = place.destination
        self.newAssetName = Self.defaultAssetName(kind: result.kind, values: values)
        self.suggested = Suggested(kind: kind, title: title, destination: destination, newAssetName: newAssetName, remindsToPay: remindsToPay,
                                   fields: values, placeCheck: place.check)
    }

    /// Where a document of `kind` goes, from what routing suggests for it.
    @MainActor
    static func suggestDestination(kind: CaptureDocumentKind, suggestions: [CaptureSuggestion], fields: [CaptureField], assets: [Asset],
                                   behaviors: [String: CategoryBehavior]) -> Destination {
        suggestPlace(kind: kind, suggestions: suggestions, fields: fields, assets: assets, behaviors: behaviors).destination
    }

    /// Where a document of `kind` goes, and what the person should check about it: a bill
    /// put in a home by a supply address that only partly agrees is marked "Verifică".
    @MainActor
    static func suggestPlace(kind: CaptureDocumentKind, suggestions: [CaptureSuggestion], fields: [CaptureField], assets: [Asset],
                             behaviors: [String: CategoryBehavior]) -> (destination: Destination, check: SubscriptionMatcher.HouseCheck?) {
        let candidates = assets.filter { !$0.isExample }
        // A bill or a contract: its ongoing contract, or where a new one goes.
        if kind.profile.filing == .subscription {
            let values = Dictionary(fields.map { ($0.key, $0.value) }, uniquingKeysWith: { first, _ in first })
            let placement = SubscriptionMatcher.place(
                subscriptionReading(kind: kind, values: values),
                subscriptions: candidates.filter { behaviors.plays(.subscription, $0.templateKey) }
                    .map { SubscriptionMatcher.Subscription(id: $0.id, parentID: $0.parent?.id, values: $0.values) },
                homes: candidates.filter { behaviors.plays(.home, $0.templateKey) }.map { SubscriptionMatcher.Home(id: $0.id, values: $0.values) }
            )
            switch placement.decision {
            case .existing(let id): return (.asset(id), placement.check)
            // A home: filed into a new subscription under it (`CaptureFiler`).
            case .newUnder(let home): return (.asset(home), placement.check)
            case .newStandalone: return (behaviors.key(withRole: .subscription).map { .newAsset(templateKey: $0) } ?? .none, nil)
            case .undecided: return (.none, nil)
            }
        }
        return (otherDestination(kind: kind, suggestions: suggestions, fields: fields, candidates: candidates, behaviors: behaviors), nil)
    }

    /// Where any other document goes: by an identifier, its holder, or its category.
    @MainActor
    private static func otherDestination(kind: CaptureDocumentKind, suggestions: [CaptureSuggestion], fields: [CaptureField], candidates: [Asset],
                                         behaviors: [String: CategoryBehavior]) -> Destination {
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
        // 2. A personal document goes to its holder: the matching member, or a new one.
        if kind.isPersonalDocument {
            let values = Dictionary(fields.map { ($0.key, $0.value) }, uniquingKeysWith: { first, _ in first })
            if let holder = CaptureMapping.holderName(values), let holders = behaviors.key(withRole: .holder) {
                let members = candidates.filter { behaviors.plays(.holder, $0.templateKey) }.map { (id: $0.id, name: $0.name) }
                if let member = CaptureMapping.matchingMember(holderSurname: values[.surname]?.text, holderName: holder, among: members) {
                    return .asset(member)
                }
                return .newAsset(templateKey: holders)
            }
        }
        // 3. The category the document belongs to.
        let templateKey = suggestions.lazy.compactMap { suggestion -> String? in
            switch suggestion.destination {
            case .newAsset(let key): return key
            case .obligation(_, let key?): return key
            case .historyEntry(let key?): return key
            default: return nil
            }
        }.first ?? kind.profile.templateKey
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

    /// What a new section made from the document is called, by the kind's profile: a new
    /// person after the holder, a car after its make and model, a subscription after its firm.
    static func defaultAssetName(kind: CaptureDocumentKind, values: [CaptureFieldKey: CaptureValue]) -> String {
        kind.profile.newSectionName(fields: values, holder: CaptureMapping.holderName(values),
                                    title: CaptureMapping.defaultTitle(for: kind, fields: values))
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
        if previous.kindEdited || previous.kind != before.kind {
            merged.kindEdited = true
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
        if previous.destination != before.destination || previous.placeConfirmed { merged.destination = previous.destination }
        if previous.newAssetName != before.newAssetName { merged.newAssetName = previous.newAssetName }
        if previous.remindsToPay != before.remindsToPay { merged.remindsToPay = previous.remindsToPay }
        merged.filesAsPersonalDocument = previous.filesAsPersonalDocument
        merged.keepsPhotoOnRequest = previous.keepsPhotoOnRequest
        merged.turnsOnDirectDebit = previous.turnsOnDirectDebit
        if previous.placeConfirmed { merged.placeConfirmed = true }
        merged.staysOnPhone = previous.staysOnPhone
        return merged
    }
}
