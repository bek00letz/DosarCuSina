import Foundation

/// Checks a document's dates against each other once every tier has run, so no tier
/// (patterns, the on-device model, Gemini) can leave an impossible combination: a
/// birth date repeated as the issue or expiry date, an expiry before the issue, an
/// identity card issued to a child.
///
/// The rules are data. When two values break a rule, the less trusted one goes:
/// the machine-readable zone with valid check digits, then a CNP with a valid
/// control digit (and what it encodes), then a printed label read in place, then
/// the on-device model, then Gemini. On a tie the value the rule is about goes,
/// and the one it was checked against is marked for a look.
enum CaptureConsistency {

    enum Rule: Hashable, Sendable {
        /// `field` never equals `anchor`.
        case differs(CaptureFieldKey, from: CaptureFieldKey)
        /// `field` is not after today.
        case notInFuture(CaptureFieldKey)
        /// `field` is at least `years` after `anchor`.
        case atLeastYearsAfter(CaptureFieldKey, anchor: CaptureFieldKey, years: Int)
        /// `field` is after `anchor`.
        case after(CaptureFieldKey, anchor: CaptureFieldKey)
    }

    /// Rules for every kind of document.
    static let general: [Rule] = [
        .differs(.issueDate, from: .birthDate),
        .differs(.startDate, from: .birthDate),
        .differs(.expiryDate, from: .birthDate),
        .notInFuture(.issueDate),
        .after(.expiryDate, anchor: .issueDate),
        .after(.expiryDate, anchor: .birthDate),
    ]

    /// The rules for a kind: the general ones and its templates' own.
    static func rules(for kind: CaptureDocumentKind) -> [Rule] {
        general + IdentityTemplates.agreements(for: kind)
    }

    /// The confidence a value kept despite a disagreement drops to, so the review marks it.
    static let disputed = 0.5

    /// The fields with every rule applied, and the keys that were dropped.
    static func resolve(_ fields: [CaptureField], kind: CaptureDocumentKind, today: CaptureDay) -> (fields: [CaptureField], dropped: [CaptureFieldKey]) {
        var fields = preferPersonalNumberBirthDate(fields)
        var dropped: [CaptureFieldKey] = []
        func field(_ key: CaptureFieldKey) -> CaptureField? { fields.first { $0.key == key } }
        func drop(_ key: CaptureFieldKey) {
            fields.removeAll { $0.key == key }
            dropped.append(key)
        }
        /// Drops the less trusted of two values that break a rule; on a tie, `subject`.
        func settle(_ subject: CaptureField, _ anchor: CaptureField) {
            if trust(subject) > trust(anchor) {
                drop(anchor.key)
            } else {
                if trust(subject) == trust(anchor), anchor.tier != .deterministic,
                   let index = fields.firstIndex(where: { $0.key == anchor.key }) {
                    fields[index] = CaptureField(key: anchor.key, value: anchor.value, confidence: min(anchor.confidence, disputed), sourceText: anchor.sourceText, tier: anchor.tier)
                }
                drop(subject.key)
            }
        }

        for rule in rules(for: kind) {
            switch rule {
            case .differs(let key, let anchorKey):
                if let subject = field(key), let anchor = field(anchorKey), subject.value.day != nil, subject.value.day == anchor.value.day {
                    settle(subject, anchor)
                }
            case .notInFuture(let key):
                if let subject = field(key), let day = subject.value.day, day > today { drop(key) }
            case .atLeastYearsAfter(let key, let anchorKey, let years):
                if let subject = field(key), let anchor = field(anchorKey), let day = subject.value.day,
                   let earliest = anchor.value.day?.addingMonths(years * 12), day < earliest {
                    settle(subject, anchor)
                }
            case .after(let key, let anchorKey):
                if let subject = field(key), let anchor = field(anchorKey), let day = subject.value.day,
                   let start = anchor.value.day, day <= start {
                    settle(subject, anchor)
                }
            }
        }
        if !dropped.isEmpty {
            CaptureLog.engine.info("Consistency dropped \(dropped.count) fields: \(dropped.map(\.rawValue).joined(separator: ","), privacy: .public)")
        }
        return (fields, dropped)
    }

    /// How far a value can be trusted when two disagree: the zone's check digits,
    /// then other checked values (a CNP), then a label read in place, then the models.
    static func trust(_ field: CaptureField) -> Int {
        switch field.tier {
        case .deterministic: field.sourceText == CaptureField.machineReadableSource ? 5 : 4
        case .heuristic: 3
        case .onDeviceModel: 2
        case .cloudModel: 1
        }
    }

    /// A CNP with a valid control digit decides the birth date, unless the
    /// machine-readable zone, checked by its own digits, already did.
    static func preferPersonalNumberBirthDate(_ fields: [CaptureField]) -> [CaptureField] {
        guard let cnp = fields.first(where: { $0.key == .personalNumber })?.value.text,
              RomanianFieldExtractor.isValidCNP(cnp),
              let birth = RomanianFieldExtractor.birthDate(fromCNP: cnp) else { return fields }
        let derived = CaptureField(key: .birthDate, value: .day(birth), confidence: 0.97,
                                   sourceText: fields.first { $0.key == .personalNumber }?.sourceText, tier: .deterministic)
        guard let index = fields.firstIndex(where: { $0.key == .birthDate }) else { return fields + [derived] }
        let existing = fields[index]
        if trust(existing) == 5 || (existing.value == derived.value && existing.tier == .deterministic) { return fields }
        var result = fields
        result[index] = derived
        return result
    }
}
