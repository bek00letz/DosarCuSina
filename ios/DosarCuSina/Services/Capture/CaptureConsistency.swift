import Foundation

/// Checks a document's dates against each other once every tier has run, so no tier
/// (patterns, the on-device model, Gemini) can leave an impossible combination: a
/// birth date repeated as the issue or expiry date, an expiry before the issue, an
/// identity card issued to a child.
///
/// The rules are data. When two values break a rule, the less trusted one goes, in the
/// order `ReadingArbiter` defines: the machine-readable zone with valid check digits,
/// then other checked values (a CNP with a valid control digit and what it encodes),
/// then the AI provider, then a printed label read in place, then the on-device model.
/// On a tie the value the rule is about goes, and the one it was checked against is
/// marked for a look.
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
        /// `field` falls inside a window relative to today. Outside it, the value is
        /// dropped or kept only for a look, as `outside` says.
        case within(CaptureFieldKey, DateWindow.Rule, outside: Outcome)
    }

    /// What happens to a value outside its window.
    enum Outcome: Hashable, Sendable {
        /// Impossible for this document: never shown.
        case drop
        /// Unusual but possible: kept, marked "Verifică".
        case verify
    }

    /// Rules for every kind of document.
    static let general: [Rule] = [
        .differs(.issueDate, from: .birthDate),
        .differs(.startDate, from: .birthDate),
        .differs(.expiryDate, from: .birthDate),
        .notInFuture(.issueDate),
        .after(.issueDate, anchor: .birthDate),
        .after(.expiryDate, anchor: .issueDate),
        .after(.expiryDate, anchor: .birthDate),
        // A person alive today: born in the last 120 years, and not in the future.
        .within(.birthDate, DateWindow.Rule(earliest: .yearsFromToday(-120), latest: .today), outside: .drop),
    ]

    /// The rules for a kind: the general ones, its templates' own and its kind's.
    static func rules(for kind: CaptureDocumentKind) -> [Rule] {
        general + IdentityTemplates.agreements(for: kind) + kindRules(kind)
    }

    /// Rules a kind of document carries beyond identity templates.
    static func kindRules(_ kind: CaptureDocumentKind) -> [Rule] {
        switch kind {
        case .contract:
            [
                // Contracts for household services run for years, not generations, and one
                // signed today may start next month.
                .within(.startDate, DateWindow.Rule(earliest: .yearsFromToday(-40), latest: .yearsFromToday(1)), outside: .drop),
                // A minimum period ends after the contract starts, at most ten years on.
                .within(.minimumPeriodEnd, DateWindow.Rule(earliest: .yearsFromToday(-40), latest: .yearsFromToday(11)), outside: .drop),
                .after(.minimumPeriodEnd, anchor: .startDate),
            ]
        default:
            []
        }
    }

    /// The window a date of `key` falls in on this kind of document, for deciding the
    /// century of a two-digit year and for checking a model's answer. Keys without a
    /// rule get a window around today (80 years back, 20 ahead).
    static func window(for key: CaptureFieldKey, kind: CaptureDocumentKind, today: CaptureDay) -> DateWindow {
        for rule in rules(for: kind) {
            if case .within(key, let window, _) = rule, let resolved = window.resolved(today: today) { return resolved }
        }
        return DateWindow.around(today)
    }

    /// Whether a date passes its own window on this kind of document (no rule: it passes).
    static func isPlausible(_ day: CaptureDay, for key: CaptureFieldKey, kind: CaptureDocumentKind, today: CaptureDay) -> Bool {
        for rule in rules(for: kind) {
            if case .within(key, let window, _) = rule, let resolved = window.resolved(today: today) { return resolved.contains(day) }
        }
        return true
    }

    /// Only the window rules, for one tier's answers before they are merged with the
    /// others, so an impossible date never pushes out a possible one.
    static func plausible(_ fields: [CaptureField], kind: CaptureDocumentKind, today: CaptureDay) -> [CaptureField] {
        var result = fields
        for rule in rules(for: kind) {
            guard case .within(let key, let window, let outside) = rule, let resolved = window.resolved(today: today) else { continue }
            result = result.compactMap { field in
                guard field.key == key, let day = field.value.day, !resolved.contains(day) else { return field }
                switch outside {
                case .drop: return nil
                case .verify:
                    return CaptureField(key: field.key, value: field.value, confidence: min(field.confidence, disputed),
                                        sourceText: field.sourceText, tier: field.tier)
                }
            }
        }
        return result
    }

    /// The confidence a value kept despite a disagreement drops to, so the review marks it.
    static let disputed = 0.5

    /// The fields with every rule applied, and the keys that were dropped.
    static func resolve(_ fields: [CaptureField], kind: CaptureDocumentKind, today: CaptureDay) -> (fields: [CaptureField], dropped: [CaptureFieldKey]) {
        let checked = plausible(fields, kind: kind, today: today)
        var dropped: [CaptureFieldKey] = fields.map(\.key).filter { key in !checked.contains { $0.key == key } }
        var fields = preferPersonalNumberBirthDate(checked)
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
            case .within:
                // Applied first, by `plausible`.
                continue
            }
        }
        if !dropped.isEmpty {
            CaptureLog.engine.info("Consistency dropped \(dropped.count) fields: \(dropped.map(\.rawValue).joined(separator: ","), privacy: .public)")
        }
        return (fields, dropped)
    }

    /// How far a value can be trusted when two disagree: `ReadingArbiter`'s order.
    static func trust(_ field: CaptureField) -> ReadingArbiter.Standing {
        ReadingArbiter.standing(field)
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
        if trust(existing) == .machineReadableZone || (existing.value == derived.value && existing.tier == .deterministic) { return fields }
        var result = fields
        result[index] = derived
        return result
    }
}

// MARK: - Date windows

/// The days a date can plausibly fall on, inclusive.
struct DateWindow: Hashable, Sendable {
    let earliest: CaptureDay
    let latest: CaptureDay

    func contains(_ day: CaptureDay) -> Bool { earliest <= day && day <= latest }

    /// A window relative to today, as the rules state it.
    struct Rule: Hashable, Sendable {
        let earliest: Bound
        let latest: Bound

        func resolved(today: CaptureDay) -> DateWindow? {
            guard let from = earliest.day(today: today), let to = latest.day(today: today), from <= to else { return nil }
            return DateWindow(earliest: from, latest: to)
        }
    }

    enum Bound: Hashable, Sendable {
        case today
        /// Whole years before (negative) or after today.
        case yearsFromToday(Int)
        /// A fixed day, such as the first identity documents with a machine-readable zone.
        case day(year: Int, month: Int, day: Int)

        func day(today: CaptureDay) -> CaptureDay? {
            switch self {
            case .today: today
            case .yearsFromToday(let years): today.addingMonths(years * 12)
            case .day(let year, let month, let day): CaptureDay(year: year, month: month, day: day)
            }
        }
    }

    /// The fallback around the real today, for readers that aren't told the day.
    static var aroundToday: DateWindow { around(CaptureDay(date: Date())) }

    /// The fallback for dates no rule covers: 80 years back, 20 ahead.
    static func around(_ today: CaptureDay) -> DateWindow {
        DateWindow(earliest: today.addingMonths(-80 * 12) ?? today, latest: today.addingMonths(20 * 12) ?? today)
    }

    /// The day a two-digit year means: the candidate inside the window (the later one
    /// when both fit), else the one nearest the window, so the rules can still judge it.
    func resolve(twoDigitYear yy: Int, month: Int, day: Int) -> CaptureDay? {
        guard (0...99).contains(yy) else { return nil }
        let centuries = Set([earliest.year / 100, latest.year / 100, earliest.year / 100 - 1, latest.year / 100 + 1])
        let candidates = centuries.sorted().compactMap { CaptureDay(year: $0 * 100 + yy, month: month, day: day) }
        if let inside = candidates.filter(contains).max() { return inside }
        return candidates.min { distance($0) < distance($1) }
    }

    /// Roughly how many days a day is from the window; 0 inside it.
    private func distance(_ day: CaptureDay) -> Int {
        func ordinal(_ value: CaptureDay) -> Int { value.year * 372 + value.month * 31 + value.day }
        if day < earliest { return ordinal(earliest) - ordinal(day) }
        if day > latest { return ordinal(day) - ordinal(latest) }
        return 0
    }
}
