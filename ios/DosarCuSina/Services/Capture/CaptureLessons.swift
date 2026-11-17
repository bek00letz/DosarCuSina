import CryptoKit
import Foundation

/// Who issued a paper, as capture knows it again on the next one: its CUI when the page prints
/// one whose control digit holds, else the name the page names it by (a provider the phone knows,
/// `UtilityProviders`, else the company printed as the issuer). Read the same way when a lesson
/// is learned and when it is used (`read(in:)`), so a lesson from one bill meets the next bill of
/// the same issuer.
public struct IssuerKey: RawRepresentable, Hashable, Codable, Sendable, Comparable {
    public let rawValue: String

    public init(rawValue: String) { self.rawValue = rawValue }

    /// The issuer by its CUI (`ProviderTaxID`).
    static func byTaxID(_ text: String) -> IssuerKey? {
        ProviderTaxID.normalized(text).map { IssuerKey(rawValue: "cui:" + $0) }
    }

    /// The issuer by its name, compared the one way (`RomanianText.compact`).
    static func byName(_ text: String) -> IssuerKey? {
        let compact = RomanianText.compact(text)
        return compact.isEmpty ? nil : IssuerKey(rawValue: "name:" + compact)
    }

    /// The CUI it stands for, digits only; nil for an issuer known by its name.
    var taxID: String? {
        rawValue.hasPrefix("cui:") ? String(rawValue.dropFirst(4)) : nil
    }

    /// The issuer a page names: its CUI, checked; else a provider the phone knows by name; else
    /// the company printed as the issuer. Nil when the page names none.
    static func read(in text: CaptureText) -> IssuerKey? {
        if let found = RomanianFieldExtractor.taxID(in: text), found.valid, let key = byTaxID(found.value) { return key }
        if let known = UtilityProviders.named(in: text) { return byName(known.name) }
        if let issuer = RomanianFieldExtractor.issuerName(in: text) { return byName(issuer.name) }
        return nil
    }

    public static func < (lhs: IssuerKey, rhs: IssuerKey) -> Bool { lhs.rawValue < rhs.rawValue }
}

/// One thing learned from what the person saved: this issuer prints this value of this kind of
/// paper under this label. It is a reader's evidence like any other: told to the readers through
/// the kind's label table (`LessonBook.teaching`), never read by code of its own, and
/// `ReadingArbiter` still decides between what every reader read.
public struct CaptureLesson: Hashable, Codable, Sendable {
    public let issuer: IssuerKey
    public let kind: CaptureDocumentKind
    public let field: CaptureFieldKey
    /// The label as printed: a few words, no digits (`CaptureLessonLearner.accepts`).
    public let label: String

    public init(issuer: IssuerKey, kind: CaptureDocumentKind, field: CaptureFieldKey, label: String) {
        self.issuer = issuer
        self.kind = kind
        self.field = field
        self.label = label
    }

    /// The label as the readers compare it, folded like every row of a label table.
    var folded: String { RomanianText.fold(label) }

    /// The lesson's own id: the same issuer, kind, field and label give the same id on every
    /// device, so two devices that learn the same lesson keep one record (`RecordsMeet`).
    public var id: UUID {
        let name = [issuer.rawValue, kind.rawValue, field.rawValue, folded].joined(separator: "\u{1F}")
        var bytes = Array(SHA256.hash(data: Data(("issuer-lesson\u{1F}" + name).utf8)).prefix(16))
        // A name-based UUID (version 5's layout, from SHA-256).
        bytes[6] = (bytes[6] & 0x0F) | 0x50
        bytes[8] = (bytes[8] & 0x3F) | 0x80
        return UUID(uuid: (bytes[0], bytes[1], bytes[2], bytes[3], bytes[4], bytes[5], bytes[6], bytes[7],
                           bytes[8], bytes[9], bytes[10], bytes[11], bytes[12], bytes[13], bytes[14], bytes[15]))
    }

    /// Whether the two give one label of one issuer's paper to two different values: the evidence
    /// points two ways, and neither stands.
    func contradicts(_ other: CaptureLesson) -> Bool {
        issuer == other.issuer && kind == other.kind && field != other.field && folded == other.folded
    }
}

/// Every lesson the binder keeps, as one capture's readers are told them. A value, so it goes with
/// the reading (`CaptureReadingSource.lessons`) and a page read again as another kind is read with
/// the same lessons.
public struct LessonBook: Hashable, Codable, Sendable {
    public let lessons: [CaptureLesson]

    public init(_ lessons: [CaptureLesson]) {
        self.lessons = lessons
    }

    public static let empty = LessonBook([])

    public var isEmpty: Bool { lessons.isEmpty }

    /// The lessons two of them contradict (`CaptureLesson.contradicts`): one label given to two
    /// values of one issuer's paper, by two papers, two devices or a backup. None of them stands.
    static func contradicted(_ lessons: [CaptureLesson]) -> Set<CaptureLesson> {
        let byLabel = Dictionary(grouping: lessons) { [$0.issuer.rawValue, $0.kind.rawValue, $0.folded] }
        return Set(byLabel.values.filter { Set($0.map(\.field)).count > 1 }.joined())
    }

    /// The lessons that stand for an issuer's papers of a kind: every one no other contradicts.
    func standing(for issuer: IssuerKey, kind: CaptureDocumentKind) -> [CaptureLesson] {
        let mine = lessons.filter { $0.issuer == issuer && $0.kind == kind }
        let out = Self.contradicted(mine)
        return mine.filter { !out.contains($0) }
    }

    /// `profile` with what was learned of `issuer`'s papers of its kind told to its readers, for
    /// one read: each field's learned labels before the kind's own (`CaptureKindProfile.labels(for:)`),
    /// longer wordings first, as a label table orders them. The profile as it is for an issuer
    /// nothing was learned of, or a kind that learns nothing (`learnsIssuerLabels`).
    func teaching(_ profile: CaptureKindProfile, issuer: IssuerKey?) -> CaptureKindProfile {
        guard let issuer, profile.learnsIssuerLabels else { return profile }
        let mine = standing(for: issuer, kind: profile.kind)
        guard !mine.isEmpty else { return profile }
        var taught = profile
        taught.learnedLabels = Dictionary(grouping: mine, by: \.field)
            .sorted { $0.key.rawValue < $1.key.rawValue }
            .map { entry in
                (entry.key, Set(entry.value.map(\.folded)).sorted { $0.count != $1.count ? $0.count > $1.count : $0 < $1 })
            }
        return taught
    }
}

extension CaptureKindProfile {
    /// Whether capture learns its issuers' labels from what the person saves: every kind but a
    /// personal document or a talon (`DocumentKind.identity`), whose issuer is the state and whose
    /// values are the holder's.
    var learnsIssuerLabels: Bool { documentKind != .identity }
}
