import Foundation

/// How a value printed on an identity document is checked.
enum IdentityFormat: Hashable, Sendable {
    /// A person's name: letters, spaces, hyphens, apostrophes.
    case name
    /// A Romanian CNP: 13 digits with a valid control digit.
    case personalNumber
    /// A document number printed as one code; the pattern's capture groups, joined, are the number.
    case documentNumber(pattern: String)
    /// A document number printed in parts, a series and a number ("SERIA XT NR 123456"),
    /// read by the one rule for such values (`CompositeValue`, `LabelledLayout.composite`).
    case composite(CompositeValue)
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
    /// A bank card's number, kept only as its last four digits (`PaymentCardNumbers`).
    case cardLastFour
    /// A bank card's expiry, printed as month and year ("08/28"): the month's last day.
    case cardExpiry
    /// A bank card's network, from its printed name or its number's first digits.
    case cardNetwork
    /// The bank that issued a card, by its name (`RomanianBanks`).
    case bankName
    /// What a cazier says: the line with "figurează", as printed.
    case recordResult
    /// A person's name printed with their address under one caption ("Numele și adresa
    /// asiguratului"): the name is what comes before the address starts (a comma, a digit
    /// or an address word, `PostalAddress.isMarker`). A firm is no one's name.
    case nameBeforeAddress
    /// A Romanian registration plate, written "B 123 ABC" (`RomanianFieldExtractor.licensePlate`).
    case licensePlate
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

/// The identity and other personal documents a Romanian household keeps, as templates:
/// the identity card (both layouts), the passport, the EU driving licence, the cazier
/// (judiciar, fiscal or auto), the European health insurance card, the bank card, the
/// green card and the qualified electronic signature certificate.
///
/// The national health insurance card isn't here: its printed fields couldn't be
/// confirmed against an official specimen, and it is being phased out. It is a document
/// type (`DocumentType.nationalHealthCard`) the person adds with its holder and expiry.
enum IdentityTemplates {

    static let all: [IdentityTemplate] = [
        electronicIdentityCard, identityCard, passport, drivingLicence,
        criminalRecordJudicial, criminalRecordFiscal, criminalRecordDriving,
        europeanHealthCard,
        bankCard, debitCard, creditCard,
        greenCard, electronicSignature,
    ]

    /// Every field key a kind's templates read.
    static func fieldKeys(for kind: CaptureDocumentKind) -> Set<CaptureFieldKey> {
        Set(orderedFieldKeys(for: kind))
    }

    /// Every field key a kind's templates read, once each, in the order they list them:
    /// a validity printed as one range gives its first day, then its last.
    static func orderedFieldKeys(for kind: CaptureDocumentKind) -> [CaptureFieldKey] {
        all.filter { $0.kind == kind }.flatMap { template in
            template.fields.flatMap { field -> [CaptureFieldKey] in
                if case .dateRange(let start) = field.format { return [start, field.key] }
                return [field.key]
            }
        }.reduce(into: []) { keys, key in if !keys.contains(key) { keys.append(key) } }
    }

    /// The printed labels of a field on a kind's templates, the first template that
    /// prints it: a range's first day is printed under the range's labels.
    static func labels(of key: CaptureFieldKey, for kind: CaptureDocumentKind) -> [LabelWording] {
        for template in all where template.kind == kind {
            for field in template.fields {
                if field.key == key { return field.labels }
                if case .dateRange(let start) = field.format, start == key { return field.labels }
            }
        }
        return []
    }

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
                  .composite(.identityCard), searchesEverywhere: true),
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
            .init(.documentNumber, ["seria"], .composite(.identityCard)),
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

    // MARK: Cazier

    /// The words a criminal record certificate is printed with. Its layout (Hotărârea
    /// Guvernului nr. 345/2010, anexa 18) couldn't be checked against the specimen, so
    /// these are the wordings such certificates use, read as labels with the value beside
    /// or under them; the AI provider is asked for the same fields.
    private static func criminalRecord(_ id: String, variant: String, distinctive: [String]) -> IdentityTemplate {
        IdentityTemplate(
            id: id,
            kind: .criminalRecord,
            signals: [("cazier judiciar", 5), ("cazierul judiciar", 4), ("certificat de cazier", 4), ("cazier fiscal", 5), ("cazierul fiscal", 4),
                      ("cazier auto", 5), ("cazier rutier", 4), ("nu figureaza", 2)],
            distinctive: distinctive,
            machineReadableFormats: [],
            fields: [
                .init(.holderName, ["numele si prenumele", "nume si prenume"], .name),
                .init(.surname, ["numele", "nume"], .name),
                .init(.givenNames, ["prenumele", "prenume"], .name),
                .init(.birthDate, ["data nasterii", "nascut la", "nascuta la", "nascut(a) la"], .date),
                .init(.personalNumber, ["cod numeric personal", "cnp"], .personalNumber, searchesEverywhere: true),
                .init(.documentNumber, ["nr. certificat", "certificat nr.", "certificat nr", "numarul certificatului", "numar certificat"],
                      .documentNumber(pattern: #"\b([A-Z]{0,4}\s?\d{3,12}(?:/\d{1,6})?)\b"#)),
                .init(.issueDate, ["data eliberarii", "eliberat la", "eliberat astazi", "data emiterii", "emis la"], .date),
                .init(.issuer, ["eliberat de", "emis de", "unitatea emitenta", "emitent"], .text),
                .init(.recordResult, [], .recordResult, searchesEverywhere: true),
            ],
            otherLabels: [
                "romania", "ministerul afacerilor interne", "agentia nationala de administrare fiscala", "certificat de cazier judiciar",
                "certificat de cazier fiscal", "prenumele parintilor", "prenume tata", "prenume mama", "locul nasterii", "domiciliul", "domiciliu",
                "scopul", "solicitat pentru", "semnatura", "stampila",
            ].map(LabelWording.words),
            agreements: [
                // A certificate is asked for a purpose and kept a few years at most.
                .within(.issueDate, DateWindow.Rule(earliest: .yearsFromToday(-10), latest: .today), outside: .verify),
            ],
            documentVariant: variant
        )
    }

    static let criminalRecordJudicial = criminalRecord("ro.cazier.judiciar", variant: DocumentType.Variant.criminalRecordJudicial,
                                                       distinctive: ["cazier judiciar", "cazierul judiciar", "ministerul afacerilor interne"])
    static let criminalRecordFiscal = criminalRecord("ro.cazier.fiscal", variant: DocumentType.Variant.criminalRecordFiscal,
                                                     distinctive: ["cazier fiscal", "cazierul fiscal", "agentia nationala de administrare fiscala", "anaf"])
    static let criminalRecordDriving = criminalRecord("ro.cazier.auto", variant: DocumentType.Variant.criminalRecordDriving,
                                                      distinctive: ["cazier auto", "cazier rutier", "cazierul auto", "cazierul rutier"])

    // MARK: Health insurance

    /// A field of the European health insurance card: its number and caption, as the
    /// card prints them above the value ("5. Data nașterii"), with or without the number.
    private static func numberedCaption(_ number: Int, _ captions: [String]) -> [String] {
        captions.flatMap { caption in ["\(number). \(caption)", "\(number).\(caption)", "\(number) \(caption)", caption] }
    }

    /// The European health insurance card, as the EU sets it (Decision No S2 of the
    /// Administrative Commission, OJ C 106/26, 24.4.2010) and CNAS prints it (Ordinul CNAS
    /// nr. 559/2006, anexa 1): numbered captions in the issuing state's language, each
    /// value under its caption. 3 Nume, 4 Prenume, 5 Data nașterii (ZZ/LL/AAAA),
    /// 6 Codul personal de identificare (the CNP), 7 Numărul de identificare al instituției,
    /// 8 Numărul de identificare al cardului, 9 Data expirării (ZZ/LL/AAAA). Fields 1 and
    /// 2 (blank, "RO") carry nothing to keep.
    static let europeanHealthCard = IdentityTemplate(
        id: "eu.ehic",
        kind: .healthInsuranceCard,
        signals: [("card european de asigurari de sanatate", 6), ("card european de asigurari sociale de sanatate", 6),
                  ("cardul european de asigurari sociale de sanatate", 6), ("european health insurance card", 5), ("ceass", 3)],
        distinctive: [],
        machineReadableFormats: [],
        fields: [
            .init(.surname, numberedCaption(3, ["nume", "name"]), .name),
            .init(.givenNames, numberedCaption(4, ["prenume", "given names"]), .name),
            .init(.birthDate, numberedCaption(5, ["data nasterii", "date of birth"]), .date),
            .init(.personalNumber, numberedCaption(6, ["codul personal de identificare", "cod personal de identificare", "personal identification number"]),
                  .personalNumber, searchesEverywhere: true),
            .init(.issuer, numberedCaption(7, ["numarul de identificare al institutiei", "identification number of the institution"]), .text),
            .init(.documentNumber, numberedCaption(8, ["numarul de identificare al cardului", "identification number of the card"]),
                  .documentNumber(pattern: #"\b(\d{10,20})\b"#)),
            .init(.expiryDate, numberedCaption(9, ["data expirarii", "expiry date"]), .date),
        ],
        otherLabels: [
            "card european de asigurari de sanatate", "european health insurance card", "casa nationala de asigurari de sanatate",
            "www.ceass.ro", "ceass.ro",
        ].map(LabelWording.words),
        agreements: [
            // Romania has issued the card since 1 January 2007 (Ordinul CNAS nr. 559/2006).
            .within(.expiryDate, DateWindow.Rule(earliest: .day(year: 2007, month: 1, day: 1), latest: .yearsFromToday(10)), outside: .drop),
        ]
    )

    // MARK: Bank cards

    /// A bank card: its network, the last four digits of its number, the month it expires
    /// and its bank, wherever they are printed. Its full number is never kept: the reader
    /// takes only the last four digits, and the text kept is masked (`PaymentCardNumbers`).
    /// Debit or credit, when the card says so, is its variant.
    private static func paymentCard(_ id: String, variant: String?, distinctive: [String]) -> IdentityTemplate {
        IdentityTemplate(
            id: id,
            kind: .bankCard,
            signals: [("valid thru", 4), ("valid through", 4), ("good thru", 4), ("expires end", 3), ("mastercard", 3), ("maestro", 3),
                      ("visa", 2), ("debit", 1), ("credit", 1), ("contactless", 1)],
            distinctive: distinctive,
            machineReadableFormats: [],
            fields: [
                .init(.cardLastFour, [], .cardLastFour, searchesEverywhere: true),
                .init(.expiryDate, cardExpiryCaptions + ["expira la", "valabil pana la"], .cardExpiry, searchesEverywhere: true),
                .init(.cardNetwork, [], .cardNetwork, searchesEverywhere: true),
                .init(.issuer, [], .bankName, searchesEverywhere: true),
            ],
            otherLabels: ["debit", "credit", "contactless", "business", "member since", "client din"].map(LabelWording.words),
            agreements: [
                // A card lasts a few years; one that ended long ago or ends a decade on is a misread.
                .within(.expiryDate, DateWindow.Rule(earliest: .yearsFromToday(-5), latest: .yearsFromToday(10)), outside: .drop),
            ],
            documentVariant: variant
        )
    }

    /// The captions a card prints over its expiry and nothing else prints: a cue that digits
    /// near them are a card's number (`CardNumberCues`). "Expiră la" and "valabil până la"
    /// caption a card's expiry too, but a vaccine's or an inspection's as well, so they read the
    /// expiry and are no cue.
    static let cardExpiryCaptions = ["valid thru", "valid through", "valid until", "good thru", "expires end", "exp. date"]

    /// A card that doesn't say whether it is debit or credit: no variant is guessed.
    static let bankCard = paymentCard("card.bank", variant: nil, distinctive: [])
    static let debitCard = paymentCard("card.debit", variant: DocumentType.Variant.bankCardDebit, distinctive: ["debit"])
    static let creditCard = paymentCard("card.credit", variant: DocumentType.Variant.bankCardCredit, distinctive: ["credit"])

    // MARK: Green card

    /// The international motor insurance card (carte verde), as the Council of Bureaux
    /// model prints it, each caption in the issuing country's language beside its English
    /// one, the values under them: 3 the validity, from and to (both days included); 4 the
    /// country's code, the insurer's code and the number; 5 the registration number; 6 the
    /// category and 7 the make; 8 the countries it covers; 9 the policyholder's name and
    /// address; 10 the insurer who issued it. The Romanian captions are BAAR's wordings for
    /// the same fields on its own models; they weren't checked on a Romanian green card
    /// itself, so the English ones, which every card prints, are read too.
    static let greenCard = IdentityTemplate(
        id: "cobx.greenCard",
        kind: .greenCard,
        signals: [("carte verde", 5), ("cartea verde", 4), ("green card", 4), ("international motor insurance card", 6),
                  ("carte internationale d'assurance automobile", 5), ("carte internationala de asigurare", 5), ("territorial validity", 2)],
        distinctive: [],
        machineReadableFormats: [],
        fields: [
            .init(.holderName, ["numele si adresa asiguratului (sau a utilizatorului)", "numele si adresa asiguratului",
                                "numele si adresa titularului", "name and address of the policyholder (or user of the vehicle)",
                                "name and address of the policyholder"], .nameBeforeAddress),
            .init(.documentNumber, labels: CompositeLabels.greenCardNumber, .composite(.policy)),
            .init(.licensePlate, ["nr. de inmatriculare/inregistrare, (daca nu are) seria de sasiu sau de motor",
                                  "registration no. (or if none) chassis or engine no.", "registration no. (and or if not) chassis or engine no.",
                                  "nr. de inmatriculare/inregistrare", "nr. de inmatriculare", "numar de inmatriculare", "nr. inmatriculare",
                                  "registration no", "registration number"], .licensePlate, searchesEverywhere: true),
            .init(.expiryDate, labels: [.numbered("3")] + ["valabilitate / valid", "valabilitate/valid", "perioada de valabilitate", "valabilitate",
                                                           "period of validity", "valabila de la", "valid from"].map(LabelWording.words),
                  .dateRange(start: .startDate)),
            .init(.issuer, ["aceasta carte a fost emisa de", "aceasta asigurare a fost emisa de", "this card has been issued by",
                            "numele si adresa asiguratorului", "name and address of the insurer"], .text),
        ],
        otherLabels: [
            "carte verde", "green card", "international motor insurance card", "carte internationale d'assurance automobile",
            "categoria si marca vehiculului", "categoria vehiculului", "marca vehiculului", "category and make of vehicle", "category of vehicle",
            "category of vehicles", "make of vehicle", "valabilitate teritoriala", "territorial validity", "semnatura asiguratorului",
            "signature of insurer", "signature of the insurer", "cele doua date sunt incluse", "both dates inclusive",
        ].map(LabelWording.words),
        agreements: [
            // A green card covers a year at most, often a month or two; one that ended long
            // ago or ends years on is a misread.
            .within(.expiryDate, DateWindow.Rule(earliest: .yearsFromToday(-5), latest: .yearsFromToday(2)), outside: .drop),
            .within(.startDate, DateWindow.Rule(earliest: .yearsFromToday(-6), latest: .yearsFromToday(1)), outside: .verify),
        ]
    )

    // MARK: Electronic signature

    /// A qualified electronic signature certificate, as a trust service provider hands it
    /// over (the paper or PDF with the certificate's details, or the certificate as a
    /// computer shows it): the holder, their CNP when it is printed, the provider that
    /// issued it, the certificate's serial number and the days it is valid between. No
    /// official layout exists: each provider prints its own, so these are the wordings
    /// certificates are shown with, in Romanian and in English.
    static let electronicSignature = IdentityTemplate(
        id: "eidas.qualifiedCertificate",
        kind: .electronicSignature,
        signals: [("semnatura electronica calificata", 6), ("certificat calificat", 5), ("certificat digital calificat", 6),
                  ("semnatura electronica", 3), ("qualified certificate", 5), ("furnizor de servicii de incredere", 3),
                  ("qualified electronic signature", 5), ("certificat digital", 2)],
        distinctive: [],
        machineReadableFormats: [],
        fields: [
            .init(.holderName, ["titularul certificatului", "titular certificat", "nume titular", "titular", "emis pentru", "emis catre",
                                "issued to", "nume si prenume", "numele si prenumele"], .name),
            .init(.personalNumber, ["cod numeric personal", "cnp"], .personalNumber, searchesEverywhere: true),
            .init(.documentNumber, ["numar serial", "numarul serial", "numar de serie", "numarul de serie", "serie certificat",
                                    "seria certificatului", "serial number", "serial no", "nr. serie"],
                  .documentNumber(pattern: #"\b([0-9A-F]{2}(?:[ :]?[0-9A-F]{2}){3,24})\b"#)),
            .init(.issueDate, ["valabil de la", "valabilitate de la", "valid from", "not before", "data emiterii", "emis la"], .date),
            .init(.expiryDate, ["valabil pana la", "valabilitate pana la", "valid to", "valid until", "not after", "data expirarii", "expira la",
                                "pana la"], .date),
            .init(.issuer, ["furnizor de servicii de incredere calificat", "furnizor de servicii de incredere", "emitent", "emis de", "issued by",
                            "furnizor", "autoritatea de certificare", "certification authority"], .text),
        ],
        otherLabels: [
            "certificat calificat", "certificat digital calificat", "qualified certificate", "e-mail", "email", "adresa de e-mail",
            "telefon", "algoritm", "algorithm", "cheie publica", "public key", "amprenta", "thumbprint", "fingerprint", "versiune", "version",
            "dispozitiv", "token", "semnatura", "signature",
        ].map(LabelWording.words),
        agreements: [
            // A qualified certificate is issued for one to three years.
            .within(.expiryDate, DateWindow.Rule(earliest: .yearsFromToday(-5), latest: .yearsFromToday(5)), outside: .drop),
            .within(.issueDate, DateWindow.Rule(earliest: .yearsFromToday(-8), latest: .today), outside: .verify),
        ]
    )

    /// The template for a document of `kind`: the one whose machine-readable zone and
    /// distinctive words match best. Nil for kinds that aren't identity documents.
    static func template(for kind: CaptureDocumentKind, text: CaptureText, machineReadableFormat: MRZParser.Format?) -> IdentityTemplate? {
        let candidates = all.filter { $0.kind == kind }
        guard candidates.count > 1 else { return candidates.first }
        let haystack = text.joinedFolded
        func score(_ template: IdentityTemplate) -> Int {
            let zone = machineReadableFormat.map { template.machineReadableFormats.contains($0) ? 5 : 0 } ?? 0
            return zone + template.distinctive.filter { CaptureText.containsWord($0, inFolded: haystack) }.count
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
