import Foundation

/// What one kind of captured document means to the binder, written once for every kind:
/// where it is filed, the deadline it sets and the field that dates it, how it is kept,
/// who issued it, which fields it carries and what it is called.
///
/// Routing (`CaptureRouter`), the field rules (`CaptureFieldRules`), the questions both
/// language models are asked (`ModelQuestions`), the review, its reminder preview and the
/// filer all read this registry, so they can't disagree. Template and blueprint keys are the built-in
/// catalog's own (`BuiltInTemplates`, `BuiltInBlueprints`); a contract test checks that
/// each one resolves. How early a deadline reminds comes only from its blueprint.
struct CaptureKindProfile: Sendable {
    /// How a document of this kind lands in the binder.
    enum Filing: Sendable, Equatable {
        /// It makes a section of its own: an identity document, a car, a product.
        case newSection
        /// It goes into the section it is about: the car its policy covers, the pet.
        case intoSection
        /// It belongs to an ongoing contract: a subscription found by its codes or made under its home.
        case subscription
        /// It is only kept, with no section suggested.
        case keepOnly
    }

    /// How the document's title is made.
    enum TitleRule: Sendable {
        /// The kind's name.
        case name
        /// A shorter name than the kind's own, for the paper itself: "Fișă veterinar".
        case fixed(LocalizedStringResource)
        /// The kind's name and the year it starts: "Poliță RCA 2026".
        case nameAndYear
        /// The kind's short word and the firm: "Factură ENGIE Romania S.A.".
        case wordAndProvider(LocalizedStringResource)
        /// The product bought, else the kind's name.
        case product
    }

    let kind: CaptureDocumentKind
    /// The built-in category a document of this kind is filed in, when it has one. For a
    /// policy, the category follows its cover (`deadline(cover:hasVehicle:)`).
    let templateKey: String?
    let filing: Filing
    /// The deadline the document sets, as a blueprint of `templateKey`. Nil when it sets none,
    /// or when it follows the cover (`readsCover`).
    let blueprintKey: String?
    /// A policy: what it covers decides its category and its deadline.
    let readsCover: Bool
    /// The cover a policy of this kind has when its page names none.
    let defaultCover: String?
    /// The field whose day the deadline follows: an expiry, a due date, the next dose.
    let deadlineField: CaptureFieldKey?
    /// The fields that date the document itself, first found wins.
    let documentDateFields: [CaptureFieldKey]
    /// How the filed document is kept.
    let documentKind: DocumentKind
    /// `document.type` for a personal document.
    let documentType: String?
    /// The trade of the firm or person who issued it, when they are worth keeping in Agendă.
    let trade: ProviderTrade?
    /// The fields a document of this kind usually carries (a personal document's are what
    /// its `IdentityTemplates` read). Apple's on-device model is asked for exactly these,
    /// and the AI provider for these first (`ModelQuestions`).
    let expectedKeys: [CaptureFieldKey]
    /// It lists what was done or bought, line by line ("Ce s-a făcut").
    let carriesLineItems: Bool
    /// An invoice with parts and jobs: it opens the visit form, not the plain review.
    let opensVisitFlow: Bool
    /// It is also something that happened, worth a line in the section's history.
    let logsHistory: Bool
    /// The values that can find the section it belongs to: a plate, a microchip.
    let identifierKeys: [CaptureFieldKey]
    /// What the kind is called, in a few words, for the review's header.
    let name: LocalizedStringResource
    let titleRule: TitleRule
    /// What the language models are told this kind is.
    let modelDescription: String
    /// A bill to pay: its deadline is made only when the person asks for it ("Amintește-mi
    /// să o plătesc"), its total is its subscription's last bill, it finds its subscription
    /// as a bill, and a payment barcode on it says what it is.
    var isBill = false
    /// What a new section made from it is called.
    var sectionName: SectionNameRule = .title
    /// Its photo is kept only when the person asks ("Păstrează și poza cardului"): a bank
    /// card's photo shows its whole number, which the binder never keeps otherwise.
    var photoIsOptIn = false
    /// The printed labels of this kind's own values, as data, folded. A bill's are read as a
    /// layout (`BillReader` through `LabelledLayout`: longer wordings win, and a value is
    /// never another label); every other kind's by the shared readers the analyzer runs
    /// for it, told this table (`labels(for:)`): a policy's expiry, period, claims line and
    /// class, an ITP report's next inspection, a vet's vaccine, booster and microchip, a
    /// receipt's date, warranty and serial number. A new wording is a new row, read without
    /// code. What every document prints the same way (its issue date, its total, a VIN, the
    /// odometer) is `commonLabels`; values printed in parts are `CompositeLabels`'.
    var labels: [(CaptureFieldKey, [String])] = []
    /// A payment barcode on it is its payment code (a bill, a service invoice, any other paper).
    var readsPaymentCode = false
    /// An identity document (passport, identity card, driving licence): it belongs in a
    /// sensitive category by default, and a reading without its essentials is retried with
    /// another view of the photo.
    var isIdentityDocument = false
    /// The fields that, read by the phone's own tiers with good confidence, make the
    /// on-device model unnecessary (`isComplete`), and by which a weak reading is judged
    /// (`lacksExpectedFields`). Empty means the model always helps.
    var essentialKeys: [CaptureFieldKey] = []
    /// Its machine-readable zone is printed on its back (an identity card): read from the
    /// front alone, the review offers to add the back, and the zone's values are said to be
    /// "Pe spatele actului".
    var hasMachineReadableBack = false

    /// How a new section made from a document is named.
    enum SectionNameRule: Sendable {
        /// The document's title.
        case title
        /// The holder, for a new person.
        case holder
        /// The car: make and model, else the plate, else "Mașina".
        case vehicle
        /// The ongoing contract: the firm and the service.
        case subscription
        /// The pet's name, else "Animalul".
        case pet
        /// A fixed name: "Sănătate".
        case fixed(LocalizedStringResource)
    }

    /// The name of a new section made from a document of this kind.
    func newSectionName(fields: [CaptureFieldKey: CaptureValue], holder: String?, title: String) -> String {
        switch sectionName {
        case .title: return title
        case .holder: return holder ?? title
        case .vehicle:
            let makeModel = [fields[.make]?.text, fields[.model]?.text].compactMap { $0 }.joined(separator: " ")
            if !makeModel.isEmpty { return makeModel }
            return fields[.licensePlate]?.text ?? String(localized: "Mașina")
        case .subscription: return SubscriptionNaming.name(provider: fields[.provider]?.text, service: fields[.serviceKind]?.text)
        case .pet: return fields[.petName]?.text ?? String(localized: "Animalul")
        case .fixed(let name): return String(localized: name)
        }
    }

    // MARK: Labels

    /// The wordings this kind prints `key` under: every row of its own table for `key`,
    /// else the one every document shares (`commonLabels`). Empty when neither has one.
    func labels(for key: CaptureFieldKey) -> [String] {
        let own = Self.labels(for: key, in: labels)
        return own.isEmpty ? Self.commonLabels(for: key) : own
    }

    /// The wordings every document prints `key` under, whatever its kind.
    static func commonLabels(for key: CaptureFieldKey) -> [String] {
        labels(for: key, in: commonLabels)
    }

    /// Every wording of `table`'s rows for `key`, for a reader told one table of its kind
    /// (a policy's number and holder, a contract's codes).
    static func labels(for key: CaptureFieldKey, in table: [(CaptureFieldKey, [String])]) -> [String] {
        table.filter { $0.0 == key }.flatMap { $0.1 }
    }

    // MARK: Lookup

    static func of(_ kind: CaptureDocumentKind) -> CaptureKindProfile {
        // Every kind has exactly one entry (`CaptureKindProfileTests`).
        all.first { $0.kind == kind } ?? other
    }

    // MARK: Deadlines

    /// Where a policy's details go and which deadline it sets, by its cover.
    static let coverDeadlines: [String: (templateKey: String, blueprintKey: String)] = [
        InsuranceCover.rca: (BuiltInTemplates.Key.vehicle, BuiltInBlueprints.vehicleRCA),
        InsuranceCover.casco: (BuiltInTemplates.Key.vehicle, BuiltInBlueprints.vehicleCASCO),
        InsuranceCover.pad: (BuiltInTemplates.Key.home, BuiltInBlueprints.homePAD),
        InsuranceCover.home: (BuiltInTemplates.Key.home, BuiltInBlueprints.homeInsurance),
    ]

    /// The covers a policy of this kind can have: an RCA policy is RCA; any other policy is
    /// CASCO, PAD or a home's optional one (an RCA is a kind of its own).
    var covers: [String] {
        guard readsCover else { return [] }
        return defaultCover.map { [$0] } ?? InsuranceCover.all.filter { $0 != InsuranceCover.rca }
    }

    /// The cover of a policy: as read or chosen (one this kind can have), else this kind's
    /// own (RCA), else CASCO for a policy that names a car, else a home's optional policy.
    /// Nil for a kind that isn't a policy.
    func cover(read: String?, hasVehicle: Bool) -> String? {
        guard readsCover else { return nil }
        if let read = InsuranceCover.key(for: read), covers.contains(read) { return read }
        if let defaultCover { return defaultCover }
        return hasVehicle ? InsuranceCover.casco : InsuranceCover.home
    }

    /// The category and the deadline a document of this kind sets, its cover taken into account.
    func deadline(cover: String?) -> (templateKey: String, blueprintKey: String)? {
        if readsCover { return cover.flatMap { Self.coverDeadlines[$0] } }
        guard let templateKey, let blueprintKey else { return nil }
        return (templateKey, blueprintKey)
    }

    /// The category it is filed in, its cover taken into account.
    func filedTemplateKey(cover: String?) -> String? {
        deadline(cover: cover)?.templateKey ?? templateKey
    }

    // MARK: Words

    /// What the document is, in a few words: "Poliță RCA". A personal document takes its
    /// type's own name ("Carte de identitate"), the one the binder uses everywhere.
    var title: String { documentType.flatMap(DocumentType.label(for:)) ?? String(localized: name) }

    /// A name a person recognises, for the document and a new section: "Poliță RCA 2026",
    /// "Factură ENGIE Romania S.A.", the product's name.
    func defaultTitle(fields: [CaptureFieldKey: CaptureValue]) -> String {
        switch titleRule {
        case .name:
            return title
        case .fixed(let name):
            return String(localized: name)
        case .nameAndYear:
            guard let year = fields[.startDate]?.day?.year ?? fields[.issueDate]?.day?.year else { return title }
            return "\(title) \(String(year))"
        case .wordAndProvider(let word):
            let word = String(localized: word)
            return fields[.provider]?.text.map { "\(word) \($0)" } ?? word
        case .product:
            return fields[.productName]?.text ?? title
        }
    }

    // MARK: Registry

    /// The dates a document is usually dated by, first found wins.
    private static let issuedOn: [CaptureFieldKey] = [.issueDate, .startDate, .purchaseDate]

    static let all: [CaptureKindProfile] = [
        identity(.passport, type: DocumentType.passport, name: "Pașaport", model: "passport data page", isIdentityDocument: true),
        identity(.identityCard, type: DocumentType.idCard, name: "Carte de identitate", model: "identity card", isIdentityDocument: true,
                 hasMachineReadableBack: true),
        identity(.drivingLicence, type: DocumentType.drivingLicence, name: "Permis de conducere", model: "EU driving licence", isIdentityDocument: true),
        identity(.criminalRecord, type: DocumentType.criminalRecord, name: "Cazier",
                 model: "Romanian criminal record certificate (certificat de cazier judiciar, fiscal or auto)"),
        identity(.healthInsuranceCard, type: DocumentType.euHealthCard, name: "Card european de sănătate", model: "European health insurance card"),
        identity(.bankCard, type: DocumentType.bankCard, name: "Card bancar",
                 model: "bank card (debit or credit); never copy its full number, only its last four digits", photoIsOptIn: true),
        identity(.greenCard, type: DocumentType.greenCard, name: "Carte verde",
                 model: "green card (international motor insurance card, carte verde), not the RCA policy itself"),
        identity(.electronicSignature, type: DocumentType.eSignature, name: "Semnătură electronică",
                 model: "qualified electronic signature certificate (certificat calificat de semnătură electronică)"),
        CaptureKindProfile(
            kind: .vehicleRegistration, templateKey: BuiltInTemplates.Key.vehicle, filing: .newSection, blueprintKey: nil,
            readsCover: false, defaultCover: nil, deadlineField: nil, documentDateFields: issuedOn,
            documentKind: .identity, documentType: nil, trade: nil,
            expectedKeys: [.licensePlate, .vin, .civNumber, .make, .model, .firstRegistrationDate],
            carriesLineItems: false, opensVisitFlow: false, logsHistory: false, identifierKeys: [.licensePlate, .vin],
            name: "Talon (certificat de înmatriculare)", titleRule: .fixed("Certificat de înmatriculare"), modelDescription: "vehicle registration certificate", sectionName: .vehicle
        ),
        CaptureKindProfile(
            kind: .rcaPolicy, templateKey: BuiltInTemplates.Key.vehicle, filing: .intoSection, blueprintKey: nil,
            readsCover: true, defaultCover: InsuranceCover.rca, deadlineField: .expiryDate, documentDateFields: issuedOn,
            documentKind: .policy, documentType: nil, trade: .insurer,
            expectedKeys: [.provider, .providerTaxID, .policyNumber, .coverageType, .startDate, .expiryDate, .total, .claimsPhone, .licensePlate, .vin, .bonusMalusClass,
                           .policyholder],
            carriesLineItems: false, opensVisitFlow: false, logsHistory: true, identifierKeys: [.licensePlate, .vin],
            name: "Poliță RCA", titleRule: .nameAndYear, modelDescription: "compulsory motor insurance (RCA) policy", sectionName: .vehicle,
            labels: policyLabels
        ),
        CaptureKindProfile(
            kind: .insurancePolicy, templateKey: nil, filing: .intoSection, blueprintKey: nil,
            readsCover: true, defaultCover: nil, deadlineField: .expiryDate, documentDateFields: issuedOn,
            documentKind: .policy, documentType: nil, trade: .insurer,
            expectedKeys: [.provider, .providerTaxID, .policyNumber, .coverageType, .startDate, .expiryDate, .total, .claimsPhone, .licensePlate,
                           .policyholder],
            carriesLineItems: false, opensVisitFlow: false, logsHistory: false, identifierKeys: [.licensePlate, .vin],
            name: "Poliță de asigurare", titleRule: .name, modelDescription: "insurance policy (CASCO, home or other)",
            labels: policyLabels
        ),
        CaptureKindProfile(
            kind: .utilityInvoice, templateKey: BuiltInTemplates.Key.subscription, filing: .subscription, blueprintKey: SubscriptionFields.billBlueprint,
            readsCover: false, defaultCover: nil, deadlineField: .dueDate, documentDateFields: issuedOn,
            documentKind: .invoice, documentType: nil, trade: nil,
            expectedKeys: [.provider, .serviceKind, .invoiceNumber, .issueDate, .dueDate, .total, .clientCode, .contractNumber, .podCode, .clcCode,
                           .phoneNumber, .meterIndex, .supplyAddress, .directDebit],
            carriesLineItems: false, opensVisitFlow: false, logsHistory: true, identifierKeys: subscriptionCodes,
            name: "Factură de utilități", titleRule: .wordAndProvider("Factură"), modelDescription: "utility, internet, TV or phone bill", isBill: true, sectionName: .subscription,
            labels: billLabels, readsPaymentCode: true
        ),
        CaptureKindProfile(
            kind: .contract, templateKey: BuiltInTemplates.Key.subscription, filing: .subscription, blueprintKey: SubscriptionFields.minimumEndsBlueprint,
            readsCover: false, defaultCover: nil, deadlineField: .minimumPeriodEnd, documentDateFields: issuedOn,
            documentKind: .contract, documentType: nil, trade: nil,
            expectedKeys: [.provider, .serviceKind, .contractNumber, .clientCode, .startDate, .minimumMonths, .minimumPeriodEnd, .monthlyPrice,
                           .phoneNumber, .podCode, .clcCode, .supplyAddress],
            carriesLineItems: false, opensVisitFlow: false, logsHistory: false, identifierKeys: subscriptionCodes,
            name: "Contract sau act adițional", titleRule: .wordAndProvider("Contract"),
            modelDescription: "contract or addendum for gas, electricity, water, internet, TV or a mobile plan", sectionName: .subscription,
            labels: contractLabels
        ),
        CaptureKindProfile(
            kind: .serviceInvoice, templateKey: BuiltInTemplates.Key.vehicle, filing: .intoSection, blueprintKey: nil,
            readsCover: false, defaultCover: nil, deadlineField: nil, documentDateFields: issuedOn,
            documentKind: .invoice, documentType: nil, trade: .mechanic,
            expectedKeys: [.provider, .providerTaxID, .invoiceNumber, .issueDate, .total, .licensePlate, .vin, .odometer, .lineItems],
            carriesLineItems: true, opensVisitFlow: true, logsHistory: true, identifierKeys: [.licensePlate, .vin],
            name: "Factură de service", titleRule: .wordAndProvider("Factură"), modelDescription: "car service invoice", sectionName: .vehicle,
            readsPaymentCode: true
        ),
        CaptureKindProfile(
            kind: .fiscalReceipt, templateKey: BuiltInTemplates.Key.purchase, filing: .newSection, blueprintKey: BuiltInBlueprints.warrantyEnds,
            readsCover: false, defaultCover: nil, deadlineField: .warrantyUntil, documentDateFields: issuedOn,
            documentKind: .receipt, documentType: nil, trade: nil,
            expectedKeys: [.retailer, .purchaseDate, .purchasePrice, .productName, .serialNumber, .warrantyMonths, .warrantyUntil, .lineItems],
            carriesLineItems: true, opensVisitFlow: false, logsHistory: false, identifierKeys: [.serialNumber],
            name: "Bon fiscal", titleRule: .product, modelDescription: "fiscal receipt",
            labels: purchaseLabels
        ),
        CaptureKindProfile(
            kind: .warrantyCertificate, templateKey: BuiltInTemplates.Key.purchase, filing: .newSection, blueprintKey: BuiltInBlueprints.warrantyEnds,
            readsCover: false, defaultCover: nil, deadlineField: .warrantyUntil, documentDateFields: issuedOn,
            documentKind: .warranty, documentType: nil, trade: nil,
            expectedKeys: [.retailer, .productName, .serialNumber, .purchaseDate, .warrantyMonths, .warrantyUntil],
            carriesLineItems: false, opensVisitFlow: false, logsHistory: false, identifierKeys: [.serialNumber],
            name: "Certificat de garanție", titleRule: .product, modelDescription: "warranty certificate",
            labels: purchaseLabels
        ),
        CaptureKindProfile(
            kind: .itpReport, templateKey: BuiltInTemplates.Key.vehicle, filing: .intoSection, blueprintKey: BuiltInBlueprints.vehicleITP,
            readsCover: false, defaultCover: nil, deadlineField: .expiryDate, documentDateFields: issuedOn,
            documentKind: .report, documentType: nil, trade: .inspectionStation,
            expectedKeys: [.provider, .licensePlate, .vin, .issueDate, .expiryDate, .odometer],
            carriesLineItems: false, opensVisitFlow: false, logsHistory: true, identifierKeys: [.licensePlate, .vin],
            name: "Raport ITP", titleRule: .name, modelDescription: "periodic technical inspection (ITP) report", sectionName: .vehicle,
            labels: inspectionLabels
        ),
        CaptureKindProfile(
            kind: .veterinaryRecord, templateKey: BuiltInTemplates.Key.pet, filing: .intoSection, blueprintKey: BuiltInBlueprints.petVaccine,
            readsCover: false, defaultCover: nil, deadlineField: .nextDoseDate, documentDateFields: issuedOn,
            documentKind: .report, documentType: nil, trade: .vet,
            expectedKeys: [.provider, .petName, .microchip, .vaccineName, .issueDate, .nextDoseDate],
            carriesLineItems: true, opensVisitFlow: true, logsHistory: true, identifierKeys: [.microchip, .petName],
            name: "Fișă de la veterinar", titleRule: .fixed("Fișă veterinar"), modelDescription: "veterinary record", sectionName: .pet,
            labels: veterinaryLabels
        ),
        CaptureKindProfile(
            kind: .medicalResult, templateKey: BuiltInTemplates.Key.health, filing: .intoSection, blueprintKey: nil,
            readsCover: false, defaultCover: nil, deadlineField: nil, documentDateFields: issuedOn,
            documentKind: .report, documentType: nil, trade: .doctor,
            expectedKeys: [.provider, .issueDate],
            carriesLineItems: false, opensVisitFlow: false, logsHistory: true, identifierKeys: [],
            name: "Rezultat medical", titleRule: .fixed("Rezultat analize"), modelDescription: "medical test result", sectionName: .fixed("Sănătate")
        ),
        other,
    ]

    static let other = CaptureKindProfile(
        kind: .other, templateKey: nil, filing: .keepOnly, blueprintKey: nil,
        readsCover: false, defaultCover: nil, deadlineField: nil, documentDateFields: issuedOn,
        documentKind: .other, documentType: nil, trade: nil,
        expectedKeys: [.provider, .documentNumber, .invoiceNumber, .issueDate, .dueDate, .expiryDate, .total],
        carriesLineItems: true, opensVisitFlow: false, logsHistory: false, identifierKeys: [],
        name: "Alt document", titleRule: .fixed("Document"), modelDescription: "household document",
        readsPaymentCode: true
    )

    /// A bill's own labels, folded: when it was issued, when to pay it, the meter's index and
    /// how to pay it. The codes it shares with its contract (client code, POD, CLC, contract
    /// number) are `ContractReader`'s. The previous index is a label too, so it is never
    /// read as the new one.
    static let billLabels: [(CaptureFieldKey, [String])] = [
        (.issueDate, ["data emiterii", "data emitere", "data facturii", "data factura", "data facturarii", "data facturare",
                      "emisa la", "emisa pe", "emisa in data de", "data:"]),
        (.dueDate, ["data scadentei", "data scadenta", "scadenta", "scadentei", "scadent la", "scadent pe", "scadent",
                    "data limita de plata", "data limita plata", "termen limita de plata", "termen limita plata", "termen de plata",
                    "termen plata", "de platit pana la", "de achitat pana la", "plateste pana la", "platiti pana la", "achitati pana la"]),
        (.meterIndex, ["index nou autocitit", "index autocitit nou", "index nou citit", "index nou", "index curent", "index actual",
                       "index citit", "index autocitit", "1.8.0"]),
        (.previousMeterIndex, ["index vechi", "index anterior", "index precedent"]),
        (.paymentCode, ["cod de plata", "codul de plata", "cod plata", "cod pentru plata", "cod bare client", "cod de bare", "cod bare",
                        "cod de inregistrare", "cod inregistrare", "cod de incasare", "cod incasare"]),
    ]

    /// What every document prints the same way, whatever its kind, folded: the day it was
    /// issued (a bill's own wordings are its table's; these are read when they find none),
    /// the amount it states, strongest first (`RomanianFieldExtractor.total`), a VIN printed
    /// in groups after its label, and the odometer on a car's papers.
    static let commonLabels: [(CaptureFieldKey, [String])] = [
        (.issueDate, ["data emiterii", "data facturii", "data eliberarii", "emisa la", "data:"]),
        (.total, ["total de plata", "total plata", "suma de plata", "rest de plata", "total general",
                  "total factura", "valoare totala", "prima de asigurare", "prima totala", "total cu tva", "de plata"]),
        (.vin, ["vin", "serie sasiu", "seria sasiu", "nr. identificare", "numar de identificare"]),
        (.odometer, ["kilometraj", "km bord", "km la bord", "odometru", "rulaj", "km parcursi"]),
    ]

    /// A policy's own labels, RCA or any other: its period of cover (both days on the line),
    /// its end when no period is printed, the line with the claims phone, the class, its
    /// series and number (read as one value, `CompositeLabels.policy`, with the green card's
    /// header an RCA may print), and who it insures with their CNP (`PolicyholderReader`).
    static let policyLabels: [(CaptureFieldKey, [String])] = [
        (.validityPeriod, ["valabil", "perioada", "valabilitate", "validity", "de la", "asigurare"]),
        (.expiryDate, ["pana la", "expira", "data expirarii", "valabila pana"]),
        (.claimsPhone, ["daune", "dauna", "avizare", "asistenta", "call center", "callcenter", "nonstop", "24/7", "suport clienti"]),
        (.bonusMalusClass, ["bonus", "malus", "clasa"]),
        (.policyNumber, ["seria si numarul politei", "seria si numarul", "seria si nr", "serie si numar", "seria/numarul", "serie/numar",
                         "seria / numarul", "serie / numar", "nr. polita", "nr polita", "numar polita", "numarul politei", "polita nr",
                         "polita seria", "polita rca seria", "serie polita", "seria", "serie"]),
        (.policyholder, ["nume/denumire proprietar", "nume / denumire proprietar", "denumire proprietar", "nume proprietar",
                         "proprietar/utilizator", "proprietar / utilizator", "proprietarul vehiculului", "proprietar", "nume asigurat",
                         "asiguratul", "asigurat", "contractant"]),
        (.policyholderPersonalNumber, ["c.u.i. / c.n.p. proprietar", "c.u.i./c.n.p. proprietar", "cui / cnp proprietar", "cui/cnp proprietar",
                                       "c.n.p. proprietar", "cnp proprietar", "c.n.p./c.u.i.", "cnp/cui", "cui/cnp", "cnp asigurat",
                                       "c.n.p. asigurat"]),
    ]

    /// A contract's own labels, and the codes a bill shares with its contract (client code,
    /// contract number, POD, CLC, the phone number of a plan), matched as whole words and
    /// read as one layout by `ContractReader`. Longer wordings win, so "contract de
    /// abonament nr" is a number, never a price.
    static let contractLabels: [(CaptureFieldKey, [String])] = [
        (.contractNumber, ["numar contract", "nr. contract", "nr contract", "contract nr", "contractul nr", "numarul contractului",
                           "contract de furnizare nr", "contract de abonament nr", "contract de prestari servicii nr",
                           "act aditional nr", "nr. contractului", "contract numarul"]),
        (.startDate, ["data intrarii in vigoare", "intra in vigoare la", "intra in vigoare", "data inceperii", "data incheierii",
                      "incheiat la data de", "incheiat astazi", "data semnarii", "data activarii", "incepand cu data de", "data de inceput"]),
        (.minimumMonths, ["perioada minima", "perioada contractuala", "durata minima", "durata contractului", "perioada initiala",
                          "perioada determinata", "durata minima a contractului"]),
        (.minimumPeriodEnd, ["perioada minima se incheie", "sfarsitul perioadei minime", "data de sfarsit a perioadei minime",
                             "perioada minima expira", "finalul perioadei minime"]),
        (.monthlyPrice, ["abonament lunar", "abonamentul lunar", "pret lunar", "pretul lunar", "tarif lunar", "cost lunar",
                         "valoare lunara", "pretul abonamentului", "tarif abonament", "pret abonament"]),
        (.clientCode, ["cod client", "cod abonat", "cont client", "numar client", "nr. client", "client nr", "client id",
                       "cod incasare", "cod de incasare", "cont facturare", "cont de facturare", "cod partener", "numar partener",
                       "cod client apa", "cod apa", "apa canal cod client", "apa canal cod", "apa nova cod client", "apa nova cod"]),
        (.podCode, ["pod", "cod pod", "codul pod", "punct de delimitare", "punct de delimitare pod", "cod punct de delimitare",
                    "punctul de delimitare", "loc consum"]),
        (.clcCode, ["clc", "cod clc", "cod loc consum", "cod loc consum (clc)", "cod loc de consum (clc)",
                    "loc consum gaze"]),
        (.phoneNumber, ["numar de telefon", "nr. de telefon", "numar telefon", "nr. telefon", "nr telefon", "msisdn", "numarul de telefon"]),
    ]

    /// An ITP report's own label: the day the next inspection is due.
    static let inspectionLabels: [(CaptureFieldKey, [String])] = [
        (.expiryDate, ["valabila pana la", "valabil pana la", "urmatoarea inspectie", "data urmatoarei inspectii", "valabilitate"]),
    ]

    /// A vet's record: the microchip's line, the vaccine's line and the booster's day.
    static let veterinaryLabels: [(CaptureFieldKey, [String])] = [
        (.microchip, ["microcip", "cip", "transponder"]),
        (.vaccineName, ["vaccin", "antirabic"]),
        (.nextDoseDate, ["rapel", "revaccinare", "urmatorul vaccin", "urmatoarea vaccinare", "valabil pana la"]),
    ]

    /// A receipt's or a warranty certificate's: the day of the sale, the warranty's length
    /// and the product's serial number.
    static let purchaseLabels: [(CaptureFieldKey, [String])] = [
        (.purchaseDate, ["data vanzarii", "data cumpararii", "data achizitiei", "data livrarii", "data:"]),
        (.warrantyMonths, ["garanti"]),
        (.serialNumber, ["s/n", "sn", "serial", "seria produs", "serie produs", "imei"]),
    ]

    /// What an identity document is judged by: its holder, its number and its expiry.
    static let identityEssentials: [CaptureFieldKey] = [.surname, .documentNumber, .expiryDate]

    /// The codes that find a bill's or a contract's subscription, most specific first.
    static let subscriptionCodes: [CaptureFieldKey] = [.podCode, .clcCode, .phoneNumber, .contractNumber, .clientCode]

    /// A personal document of its holder (an identity document, a cazier, a health card, a
    /// bank card, a green card, an electronic signature), read with its templates and
    /// renewed by its expiry. Its read text is
    /// kept like an identity document's: never searched.
    private static func identity(_ kind: CaptureDocumentKind, type: String, name: LocalizedStringResource, model: String,
                                 photoIsOptIn: Bool = false, isIdentityDocument: Bool = false,
                                 hasMachineReadableBack: Bool = false) -> CaptureKindProfile {
        var expected = IdentityTemplates.orderedFieldKeys(for: kind)
        // The day the deadline follows is always asked for, even where it is worked out
        // from another (a cazier judiciar's, six months from its issue).
        if !expected.contains(.expiryDate) { expected.append(.expiryDate) }
        var profile = CaptureKindProfile(
            kind: kind, templateKey: BuiltInTemplates.Key.documents, filing: .newSection, blueprintKey: BuiltInBlueprints.documentRenew,
            readsCover: false, defaultCover: nil, deadlineField: .expiryDate, documentDateFields: issuedOn,
            documentKind: .identity, documentType: type, trade: nil,
            expectedKeys: expected,
            carriesLineItems: false, opensVisitFlow: false, logsHistory: false, identifierKeys: [.documentNumber],
            name: name, titleRule: .name, modelDescription: model, sectionName: .holder
        )
        profile.photoIsOptIn = photoIsOptIn
        profile.isIdentityDocument = isIdentityDocument
        // An identity document is read well when its holder, its number and its expiry are.
        profile.essentialKeys = isIdentityDocument ? identityEssentials : []
        profile.hasMachineReadableBack = hasMachineReadableBack
        return profile
    }
}

extension CaptureFieldKey {
    /// A policy's period of cover ("Valabilă de la 01.11.2026 până la 31.10.2027"): a label
    /// of its table, whose line gives the start and the end. Never a field of its own.
    static let validityPeriod: CaptureFieldKey = "validityPeriod"
}

extension CaptureDocumentKind {
    /// What this kind means to the binder.
    var profile: CaptureKindProfile { CaptureKindProfile.of(self) }
}
