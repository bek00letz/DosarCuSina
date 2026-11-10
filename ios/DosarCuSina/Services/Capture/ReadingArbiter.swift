import Foundation

/// The one place that decides between readers: which kind a document is, which value a
/// field keeps when readers disagree, and when the phone's reading is weak enough for the
/// person's AI provider to read it by itself (when they turned that on).
///
/// Evidence ranks, not the order the readers ran in. From most to least trusted:
///
/// 1. **The person's own edits** in the review: a value they typed or chose, the kind,
///    the place, the title and the name. No later reading changes them; a checked or AI
///    value that differs is offered beside them, never applied (`CaptureReview.carryingEdits`).
/// 2. **Checked values, from any reader:** the machine-readable zone with its check digits,
///    then a value that passes its own control digit (a CNP, and the birth date and sex it
///    encodes; a VIN; a CUI) or a payment code in a known barcode format.
/// 3. **The AI provider** (a second opinion on the whole page), for values no check can
///    prove.
/// 4. **The phone's patterns and labels**, a provider's known format first.
/// 5. **Apple's on-device model.**
///
/// How disagreements end:
/// - A check settles a disagreement: the checked value stays and isn't marked.
/// - Otherwise the higher reader wins, and when the AI's value replaces a different one
///   read on the phone the field is marked "Verifică" and the phone's value is kept as an
///   alternative the review offers ("Pe telefon am citit: …").
/// - Among the phone's own unprovable readings the more confident value wins (a model's
///   clear answer beats a weak first-date guess); a provider's known format is never
///   replaced by a pattern or a model; on a tie the order above decides.
/// - Two readers that agree reinforce each other. A value printed in parts (a policy's
///   series and number) agrees when it is the same value written differently, or when one
///   reader read only a part of it: the whole is kept, so a part never beats it, and two
///   parts read by different readers are joined (`agreedValue`).
/// - Being missing from the text recognised on the phone is never a reason to drop or
///   demote an AI value: it is kept, marked "Verifică" unless it passes its own check or
///   agrees with the phone (`ModelAnswerMapper`). A value outside its plausibility window
///   is still dropped (`CaptureConsistency`).
///
/// The kind: the AI's kind replaces the phone's unless the phone's rests on deterministic
/// evidence (`CaptureKindEvidence.isDeterministic`: a checked zone, a provider's format the
/// classifier agrees with, a decoded payment barcode). Apple's on-device model may change
/// the kind only when the classifier is unsure. Whatever kind is kept, the other is offered.
enum ReadingArbiter {

    // MARK: - Standing of a value

    /// How far a value can be trusted when two disagree; higher wins.
    enum Standing: Int, Comparable, Sendable {
        case onDeviceModel
        case pattern
        /// A phone value read by a provider's known format or a template, that no check proves.
        case knownFormat
        /// The AI provider's value, when no check proves it.
        case secondOpinion
        /// A value that passes its own control digit, or a known barcode format.
        case checked
        /// A value from a machine-readable zone whose check digits pass.
        case machineReadableZone

        static func < (lhs: Standing, rhs: Standing) -> Bool { lhs.rawValue < rhs.rawValue }
    }

    static func standing(_ field: CaptureField) -> Standing {
        // The phone's zone values are deterministic only where their check digits pass; the
        // AI's zone is kept only when all of them pass (`ModelAnswerMapper`).
        if field.sourceText == CaptureField.machineReadableSource, field.tier == .deterministic || field.tier == .cloudModel {
            return .machineReadableZone
        }
        if passesOwnCheck(field) { return .checked }
        switch field.tier {
        case .cloudModel: return .secondOpinion
        case .deterministic: return .knownFormat
        case .heuristic: return .pattern
        case .onDeviceModel: return .onDeviceModel
        }
    }

    /// Whether a value proves itself: a control digit, or what a checked CNP encodes, or a
    /// payment code in a known barcode format.
    static func passesOwnCheck(_ field: CaptureField) -> Bool {
        switch field.key {
        case .personalNumber:
            return field.value.text.map(RomanianFieldExtractor.isValidCNP) ?? false
        case .vin:
            return field.value.text.map(RomanianFieldExtractor.vinChecksumValid) ?? false
        case .providerTaxID:
            return field.value.text.map { RomanianFieldExtractor.isValidCUI($0.filter(\.isNumber)) } ?? false
        case .birthDate, .sex:
            // The phone sets these as deterministic only from a CNP whose control digit passed.
            return field.tier == .deterministic
        case .paymentCode:
            return field.tier == .deterministic
        default:
            return false
        }
    }

    /// Where an alternative came from, for the words the review offers it with.
    static func source(of field: CaptureField) -> CaptureAlternativeSource {
        let standing = standing(field)
        if standing >= .checked { return .checked(machineReadable: standing == .machineReadableZone) }
        return field.tier == .cloudModel ? .cloudModel : .phone
    }

    // MARK: - Which value a field keeps

    /// Whether `candidate` should replace `existing`, a different value for the same key.
    static func prefers(_ candidate: CaptureField, over existing: CaptureField) -> Bool {
        let new = standing(candidate), old = standing(existing)
        // A check, or the AI, is involved: evidence decides.
        if max(new, old) >= .secondOpinion {
            if new != old { return new > old }
            // Two values passing the same kind of check: the second opinion breaks the tie.
            if candidate.tier != existing.tier, candidate.tier == .cloudModel || existing.tier == .cloudModel {
                return candidate.tier == .cloudModel
            }
        }
        // The phone's own readings among themselves.
        if existing.tier == .deterministic && candidate.tier != .deterministic { return false }
        if candidate.tier == .deterministic && existing.tier != .deterministic { return true }
        if candidate.confidence != existing.confidence { return candidate.confidence > existing.confidence }
        if new != old { return new > old }
        return candidate.tier < existing.tier
    }

    /// The value two readers agree on, or nil when they disagree. Beyond the same text, a
    /// value printed in parts (`CompositeValue`) agrees when it is the same value written
    /// differently ("XT 123456" and "XT123456"), when one reader read only a part of the
    /// other's whole (the whole is kept, whoever read it: a part never beats it), or when
    /// each read the part the other missed (they are joined).
    static func agreedValue(_ existing: CaptureField, _ candidate: CaptureField) -> CaptureValue? {
        if existing.value == candidate.value { return existing.value }
        guard let first = existing.value.text, let second = candidate.value.text else { return nil }
        if let shape = CompositeValue.byKey[existing.key] {
            return shape.agreement(first, second).map(CaptureValue.text)
        }
        // A document number's shape is its document's; written differently, it is still the same.
        if existing.key == .documentNumber, CompositeValue.compact(first) == CompositeValue.compact(second) { return existing.value }
        return nil
    }

    /// Two readers that read the same value: more confident together, counted as the more
    /// trusted reader's, with the first source text. `value` is what they agree on
    /// (`agreedValue`), the existing value when not given.
    static func agreeing(_ existing: CaptureField, _ candidate: CaptureField, value: CaptureValue? = nil) -> CaptureField {
        CaptureField(
            key: existing.key,
            value: value ?? existing.value,
            confidence: max(existing.confidence, candidate.confidence) + 0.1,
            sourceText: existing.sourceText ?? candidate.sourceText,
            tier: standing(existing) >= standing(candidate) ? existing.tier : candidate.tier
        )
    }

    /// The phone's reading with the AI's second opinion: one value per key, every value
    /// the AI's replaced or lost to kept as an alternative.
    static func secondOpinion(phone: [CaptureField], ai: [CaptureField]) -> (fields: [CaptureField], alternatives: [CaptureFieldAlternative]) {
        var result = phone
        var alternatives: [CaptureFieldAlternative] = []
        for candidate in ai {
            guard let index = result.firstIndex(where: { $0.key == candidate.key }) else {
                result.append(candidate)
                continue
            }
            let existing = result[index]
            if let agreed = agreedValue(existing, candidate) {
                result[index] = agreeing(existing, candidate, value: agreed)
                continue
            }
            let winner = prefers(candidate, over: existing) ? candidate : existing
            let loser = winner == candidate ? existing : candidate
            // A check settles it; otherwise two readers disagree and the person decides.
            result[index] = standing(winner) >= .checked ? winner : disputed(winner)
            alternatives.append(CaptureFieldAlternative(key: loser.key, alternative: CaptureAlternative(loser.value, source: source(of: loser))))
        }
        return (result, alternatives)
    }

    /// A value kept despite a disagreement, marked for a look.
    static func disputed(_ field: CaptureField) -> CaptureField {
        CaptureField(key: field.key, value: field.value, confidence: min(field.confidence, CaptureConsistency.disputed),
                     sourceText: field.sourceText, tier: field.tier)
    }

    // MARK: - Which kind

    /// A reader's view of what the document is.
    struct KindReading: Hashable, Sendable {
        let kind: CaptureDocumentKind
        let confidence: Double
        let evidence: CaptureKindEvidence
    }

    /// Below this, the phone isn't sure what the document is.
    static let unsureKindBelow = 0.6
    /// How sure a kind is once the AI read the whole page and named it.
    static let secondOpinionKindConfidence = 0.9

    /// Whether a model's view of the kind can still change it: the classifier is unsure and
    /// nothing deterministic backs it. Apple's on-device model is asked what the document
    /// is only then (`SemanticInput.kindIsOpen`).
    static func kindIsOpen(_ phone: KindReading) -> Bool {
        phone.confidence < unsureKindBelow && !phone.evidence.isDeterministic
    }

    /// The kind an open reading takes from Apple's on-device model: the model's, unless it
    /// names none or "other", which is no opinion. The model is then asked that kind's facts.
    static func openKind(_ guess: CaptureDocumentKind, onDeviceModel model: CaptureDocumentKind?) -> CaptureDocumentKind {
        guard let model, model != .other else { return guess }
        return model
    }

    /// Apple's on-device model corrects the kind only when the classifier is unsure and
    /// nothing deterministic backs it.
    static func kind(_ phone: KindReading, onDeviceModel model: CaptureDocumentKind?) -> KindReading {
        guard kindIsOpen(phone) else { return phone }
        let kind = openKind(phone.kind, onDeviceModel: model)
        guard kind != phone.kind else { return phone }
        return KindReading(kind: kind, confidence: 0.65, evidence: .onDeviceModel)
    }

    /// The AI's kind replaces the phone's unless deterministic evidence backs the phone's.
    /// The kind not kept is offered as an alternative.
    static func kind(_ phone: KindReading, secondOpinion ai: CaptureDocumentKind?) -> (reading: KindReading, alternatives: [CaptureAlternative<CaptureDocumentKind>]) {
        // "Other" from the AI is no opinion.
        guard let ai, ai != .other else { return (phone, []) }
        if ai == phone.kind {
            let evidence = phone.evidence.isDeterministic ? phone.evidence : .secondOpinion
            return (KindReading(kind: ai, confidence: max(phone.confidence, secondOpinionKindConfidence), evidence: evidence), [])
        }
        if phone.evidence.isDeterministic {
            return (phone, [CaptureAlternative(ai, source: .cloudModel)])
        }
        return (KindReading(kind: ai, confidence: secondOpinionKindConfidence, evidence: .secondOpinion),
                [CaptureAlternative(phone.kind, source: .phone)])
    }

    // MARK: - A weak reading

    /// Why the phone's reading is weak enough to ask the AI provider by itself.
    enum Weakness: String, CaseIterable, Sendable {
        /// The classifier isn't sure what the document is.
        case unsureKind
        /// An identity document without one of its essentials (surname, number, expiry).
        case identityEssentialsMissing
        /// A value failed its own check (a CNP, a CUI, the zone's check digits) or a
        /// cross-check with another (`CaptureNotice.valueFailedCheck`).
        case failedCheck
        /// Little text was recognised.
        case littleText
        /// Only a provider's known format named the kind; the classifier didn't agree.
        case providerFormatAlone
    }

    /// Everything weak about a reading. Empty means the phone's reading is sound.
    static func weaknesses(of result: CaptureResult) -> Set<Weakness> {
        var found: Set<Weakness> = []
        if result.kindConfidence < unsureKindBelow { found.insert(.unsureKind) }
        if result.kind.isIdentityDocument,
           result.kind.essentialKeys.contains(where: { key in result.field(key) == nil }) {
            found.insert(.identityEssentialsMissing)
        }
        let selfCheckFailed = result.fields.contains { field in
            switch field.key {
            case .personalNumber, .providerTaxID: !passesOwnCheck(field)
            default: false
            }
        }
        if selfCheckFailed || result.notices.contains(.machineReadableZoneUnverified) || result.notices.contains(.valueFailedCheck) {
            found.insert(.failedCheck)
        }
        if result.notices.contains(.littleTextRecognized) { found.insert(.littleText) }
        if result.kindEvidence == .providerFormatAlone { found.insert(.providerFormatAlone) }
        return found
    }

    /// Whether the phone's reading is weak: the one test the automatic reading uses.
    static func isWeak(_ result: CaptureResult) -> Bool {
        !weaknesses(of: result).isEmpty
    }
}
