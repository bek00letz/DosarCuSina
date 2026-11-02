import Foundation

/// How a value printed on an identity document is checked.
enum IdentityFormat: Hashable, Sendable {
    /// A person's name: letters, spaces, hyphens, apostrophes.
    case name
    /// A Romanian CNP: 13 digits with a valid control digit.
    case personalNumber
    /// A document number; the pattern's capture groups, joined, are the number.
    case documentNumber(pattern: String)
    case date
    /// A validity printed as one range ("12.03.18-31.12.2028"); the first date fills `start`.
    case dateRange(start: CaptureFieldKey)
    /// M or F.
    case sex
    /// A three-letter country code, or the nationality in words.
    case country
    /// Any text with letters: an issuing authority.
    case text
    /// Driving licence categories: "B", "A1 B C1".
    case categories
}

/// What a known identity document looks like, as data: how to recognize it, the
/// fields it carries with their printed labels and formats, and which values must
/// agree. `IdentityDocumentReader` applies any template, so supporting another
/// document means adding a template here, not reading code.
///
/// Labels are folded (lowercase, no diacritics). Regions, when given, are where a
/// field usually sits on the flattened card (0…1 from the top-left) and only break
/// ties when a label is missing or unreadable.
struct IdentityTemplate: Sendable {
    struct Field: Sendable {
        let key: CaptureFieldKey
        let labels: [LabelWording]
        let format: IdentityFormat
        var region: TextBox? = nil
        /// Read anywhere on the page by its format when its label isn't found. Only for
        /// formats nothing else on the document matches (a CNP's control digit, a whole
        /// line shaped like the document number).
        var searchesEverywhere = false

        init(_ key: CaptureFieldKey, _ labels: [String], _ format: IdentityFormat, region: TextBox? = nil, searchesEverywhere: Bool = false) {
            self.init(key, labels: labels.map(LabelWording.words), format, region: region, searchesEverywhere: searchesEverywhere)
        }

        init(_ key: CaptureFieldKey, labels: [LabelWording], _ format: IdentityFormat, region: TextBox? = nil, searchesEverywhere: Bool = false) {
            self.key = key
            self.labels = labels
            self.format = format
            self.region = region
            self.searchesEverywhere = searchesEverywhere
        }
    }

    let id: String
    let kind: CaptureDocumentKind
    /// Weighted words that tell this kind of document from others (for the classifier).
    let signals: [(String, Double)]
    /// Words that tell this template from others of the same kind.
    let distinctive: [String]
    /// The machine-readable zone formats this document carries.
    let machineReadableFormats: Set<MRZParser.Format>
    let fields: [Field]
    /// Printed labels whose values aren't read. They stop a value search.
    let otherLabels: [LabelWording]
    /// Rules the document's values must satisfy on top of the general ones.
    let agreements: [CaptureConsistency.Rule]
    /// The document variant this layout identifies (the electronic identity card
    /// or the older one), so filing sets it and the variant's fields, such as the
    /// PIN codes, appear without asking.
    var documentVariant: String? = nil

    /// The label table `LabelledLayout` reads with: each field's labels, then the others.
    var labelTable: [(IdentityLabelKey, [LabelWording])] {
        fields.map { (IdentityLabelKey.field($0.key), $0.labels) } + [(.other, otherLabels)]
    }
}

/// A label in a template's table: a field's, or one whose value isn't read.
enum IdentityLabelKey: Hashable, Sendable {
    case field(CaptureFieldKey)
    case other
}

/// The identity documents a Romanian household keeps.
///
/// The national health insurance card isn't here: its printed fields couldn't be
/// confirmed against an official specimen, and it is being phased out.
enum IdentityTemplates {

    static let all: [IdentityTemplate] = [electronicIdentityCard, identityCard, passport, drivingLicence]

    private static let personalNumberLabel = IdentityTemplate.Field(.personalNumber, ["cnp / pin", "cnp/pin", "cnp", "pin"], .personalNumber, searchesEverywhere: true)
    private static let cardSignals: [(String, Double)] = [
        ("carte de identitate", 4), ("carte electronica de identitate", 4), ("identity card", 3), ("buletin", 2), ("cnp", 1),
    ]
    /// When an identity document's dates can fall. Every Romanian identity document is
    /// valid for at most 10 years (the permanent card has no expiry date), so:
    /// - an expiry is between 2000 (the first cards with a machine-readable zone) and
    ///   15 years from today; anything else is a misread and is dropped;
    /// - an issue date more than 15 years ago is possible only on a permanent card, so
    ///   it is kept for a look rather than shown as fact.
    /// These windows also decide the century of two-digit years (the zone, "12.03.18").
    static let identityDates: [CaptureConsistency.Rule] = [
        .within(.expiryDate, DateWindow.Rule(earliest: .day(year: 2000, month: 1, day: 1), latest: .yearsFromToday(15)), outside: .drop),
        .within(.issueDate, DateWindow.Rule(earliest: .yearsFromToday(-15), latest: .today), outside: .verify),
    ]
    private static let issuedFromFourteen: [CaptureConsistency.Rule] = identityDates + [
        .atLeastYearsAfter(.issueDate, anchor: .birthDate, years: 14),
    ]

    /// The electronic identity card (CEI): bilingual labels with the value under them,
    /// in columns on the front; the issuing authority and the TD1 zone on the back.
    static let electronicIdentityCard = IdentityTemplate(
        id: "ro.cei",
        kind: .identityCard,
        signals: cardSignals,
        distinctive: ["surname", "given names", "document no", "date of expiry", "holder's signature", "semnatura titularului"],
        machineReadableFormats: [.td1],
        fields: [
            .init(.surname, ["nume / surname", "nume/surname", "nume de familie", "nume", "surname"], .name),
            .init(.givenNames, ["prenume / given names", "prenume/given names", "prenume", "given names"], .name),
            .init(.sex, ["sex / sex", "sex/sex", "sex"], .sex),
            .init(.nationality, ["cetatenie / nationality", "cetatenie/nationality", "cetatenie", "nationality"], .country),
            .init(.birthDate, ["data nasterii / date of birth", "data nasterii", "date of birth"], .date),
            personalNumberLabel,
            .init(.documentNumber, ["nr. document / document no", "nr. document/document no", "nr. document", "document no"],
                  .documentNumber(pattern: #"\b([A-Z]{2})\s?(\d{6,7})\b"#), searchesEverywhere: true),
            .init(.expiryDate, ["data expirarii / date of expiry", "data expirarii", "date of expiry"], .date),
            .init(.issueDate, ["data emiterii / date of issue", "data emiterii", "date of issue", "data eliberarii"], .date),
            .init(.issuer, ["emisa de / issued by", "emisa de", "issued by", "autoritatea emitenta", "issuing authority"], .text),
        ],
        otherLabels: [
            "romania", "carte de identitate", "carte electronica de identitate", "identity card", "semnatura titularului",
            "semnatura", "holder's signature", "signature", "domiciliu", "address", "loc nastere", "locul nasterii", "place of birth",
        ].map(LabelWording.words),
        agreements: issuedFromFourteen,
        documentVariant: DocumentType.Variant.idCardElectronic
    )

    /// The older identity card: trilingual labels, "SERIA XT NR 123456" at the top,
    /// the validity as one range, and a TD2 zone on the front.
    static let identityCard = IdentityTemplate(
        id: "ro.ci",
        kind: .identityCard,
        signals: cardSignals,
        distinctive: ["seria", "last name", "first name", "nom", "prenom", "valabilitate", "validite", "delivree par", "lieu de naissance"],
        machineReadableFormats: [.td2],
        fields: [
            .init(.surname, ["nume/nom/last name", "nume/nom", "nume", "last name"], .name),
            .init(.givenNames, ["prenume/prenom/first name", "prenume/prenom", "prenume", "first name"], .name),
            .init(.sex, ["sex/sexe/sex", "sex"], .sex),
            .init(.nationality, ["cetatenie/nationalite/nationality", "cetatenie", "nationality"], .country),
            personalNumberLabel,
            .init(.documentNumber, ["seria"], .documentNumber(pattern: #"\b([A-Z]{2})\s*,?\s*(?:NR\.?)?\s*(\d{6,7})\b"#)),
            .init(.expiryDate, ["valabilitate/validite/validity", "valabilitate", "validity"], .dateRange(start: .issueDate)),
            .init(.issuer, ["emisa de/delivree par/issued by", "emisa de", "issued by"], .text),
        ],
        otherLabels: [
            "loc nastere/lieu de naissance/place of birth", "loc nastere", "place of birth", "domiciliu/adresse/address", "domiciliu",
            "address", "romania", "roumanie", "carte de identitate", "identity card", "carte d'identite",
        ].map(LabelWording.words),
        agreements: issuedFromFourteen,
        documentVariant: DocumentType.Variant.idCardWithoutChip
    )

    /// The passport data page: bilingual labels with values under them, and a TD3 zone.
    /// Children get passports, so there is no minimum age at issue.
    static let passport = IdentityTemplate(
        id: "ro.passport",
        kind: .passport,
        signals: [("pasaport", 3), ("passport", 3), ("passeport", 2)],
        distinctive: ["passport no", "date of issue", "authority"],
        machineReadableFormats: [.td3],
        fields: [
            .init(.documentNumber, ["nr. pasaport / passport no", "nr. pasaport", "passport no", "pasaport nr"],
                  .documentNumber(pattern: #"\b(\d{8,9}|[A-Z]{1,2}\d{6,8})\b"#)),
            .init(.surname, ["nume / surname", "nume/surname", "nume", "surname"], .name),
            .init(.givenNames, ["prenume / given names", "prenume/given names", "prenume", "given names"], .name),
            .init(.nationality, ["cetatenie / nationality", "cetatenie", "nationality"], .country),
            .init(.birthDate, ["data nasterii / date of birth", "data nasterii", "date of birth"], .date),
            .init(.personalNumber, ["cnp / personal no", "cnp", "personal no"], .personalNumber, searchesEverywhere: true),
            .init(.sex, ["sex / sex", "sex"], .sex),
            .init(.issueDate, ["data eliberarii / date of issue", "data eliberarii", "date of issue", "data emiterii"], .date),
            .init(.expiryDate, ["data expirarii / date of expiry", "data expirarii", "date of expiry"], .date),
            .init(.issuer, ["autoritatea / authority", "autoritatea", "authority"], .text),
        ],
        otherLabels: [
            "tip / type", "tip", "type", "cod tara / code", "cod tara", "code", "locul nasterii / place of birth", "locul nasterii",
            "place of birth", "semnatura titularului", "semnatura", "signature", "pasaport", "passport", "romania",
        ].map(LabelWording.words),
        agreements: identityDates
    )

    /// The EU driving licence: numbered fields, the value after the number. On Romanian
    /// licences 4d holds the CNP; it is only taken as one when its control digit is valid.
    static let drivingLicence = IdentityTemplate(
        id: "eu.drivingLicence",
        kind: .drivingLicence,
        signals: [("permis de conducere", 4), ("driving licence", 3), ("permis", 1), ("4b.", 1), ("4a.", 1)],
        distinctive: [],
        machineReadableFormats: [],
        fields: [
            .init(.surname, labels: [.numbered("1")], .name),
            .init(.givenNames, labels: [.numbered("2")], .name),
            .init(.birthDate, labels: [.numbered("3")], .date),
            .init(.issueDate, labels: [.numbered("4a")], .date),
            .init(.expiryDate, labels: [.numbered("4b")], .date),
            .init(.issuer, labels: [.numbered("4c")], .text),
            .init(.personalNumber, labels: [.numbered("4d")], .personalNumber),
            .init(.documentNumber, labels: [.numbered("5")], .documentNumber(pattern: #"\b([A-Z0-9]{5,14})\b"#)),
            .init(.licenceCategories, labels: [.numbered("9")], .categories),
        ],
        otherLabels: [.numbered("6"), .numbered("7"), .numbered("8")],
        agreements: issuedFromFourteen
    )

    /// The template for a document of `kind`: the one whose machine-readable zone and
    /// distinctive words match best. Nil for kinds that aren't identity documents.
    static func template(for kind: CaptureDocumentKind, text: CaptureText, machineReadableFormat: MRZParser.Format?) -> IdentityTemplate? {
        let candidates = all.filter { $0.kind == kind }
        guard candidates.count > 1 else { return candidates.first }
        let haystack = text.joinedFolded
        func score(_ template: IdentityTemplate) -> Int {
            let zone = machineReadableFormat.map { template.machineReadableFormats.contains($0) ? 5 : 0 } ?? 0
            return zone + template.distinctive.filter { DocumentClassifier.containsWord($0, in: haystack) }.count
        }
        // Ties keep the first listed.
        let best = candidates.map(score).max() ?? 0
        return candidates.first { score($0) == best }
    }

    /// Kind-level classifier signals, from every template of each kind.
    static var classifierSignals: [CaptureDocumentKind: [(String, Double)]] {
        var result: [CaptureDocumentKind: [String: Double]] = [:]
        for template in all {
            for (word, weight) in template.signals {
                result[template.kind, default: [:]][word] = max(result[template.kind]?[word] ?? 0, weight)
            }
        }
        return result.mapValues { words in words.sorted { $0.key < $1.key }.map { ($0.key, $0.value) } }
    }

    /// Value rules for a kind of document, from its templates.
    static func agreements(for kind: CaptureDocumentKind) -> [CaptureConsistency.Rule] {
        var seen = Set<CaptureConsistency.Rule>()
        return all.filter { $0.kind == kind }.flatMap(\.agreements).filter { seen.insert($0).inserted }
    }
}
