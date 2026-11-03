import Foundation

/// What one kind of captured document means to the binder, written once for every kind:
/// where it is filed, the deadline it sets and the field that dates it, how it is kept,
/// who issued it, which fields it carries and what it is called.
///
/// Routing (`CaptureRouter`), the field rules (`CaptureFieldRules`), the AI provider's
/// questions (`CloudSchema`), the review, its reminder preview and the filer all read
/// this registry, so they can't disagree. Template and blueprint keys are the built-in
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
    /// The fields a document of this kind usually carries, beyond identity documents
    /// (whose fields come from `IdentityTemplates`). The AI provider is asked for these.
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
    /// What the AI provider is told this kind is.
    let modelDescription: String
    /// Its deadline is made only when the person asks for it: a bill to pay ("Amintește-mi să o plătesc").
    var deadlineIsOptIn = false
    /// What a new section made from it is called.
    var sectionName: SectionNameRule = .title

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

    /// The cover of a policy: as read or chosen, else this kind's own (RCA), else CASCO
    /// for a policy that names a car, else a home's optional policy. Nil for a kind that
    /// isn't a policy.
    func cover(read: String?, hasVehicle: Bool) -> String? {
        guard readsCover else { return nil }
        if let read = InsuranceCover.key(for: read) { return read }
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
        identity(.passport, type: DocumentType.passport, name: "Pașaport", model: "passport data page"),
        identity(.identityCard, type: DocumentType.idCard, name: "Carte de identitate", model: "identity card"),
        identity(.drivingLicence, type: DocumentType.drivingLicence, name: "Permis de conducere", model: "EU driving licence"),
        CaptureKindProfile(
            kind: .vehicleRegistration, templateKey: BuiltInTemplates.Key.vehicle, filing: .newSection, blueprintKey: nil,
            readsCover: false, defaultCover: nil, deadlineField: nil, documentDateFields: issuedOn,
            documentKind: .identity, documentType: nil, trade: nil,
            expectedKeys: [.licensePlate, .vin, .make, .model, .firstRegistrationDate],
            carriesLineItems: false, opensVisitFlow: false, logsHistory: false, identifierKeys: [.licensePlate, .vin],
            name: "Talon (certificat de înmatriculare)", titleRule: .name, modelDescription: "vehicle registration certificate", sectionName: .vehicle
        ),
        CaptureKindProfile(
            kind: .rcaPolicy, templateKey: BuiltInTemplates.Key.vehicle, filing: .intoSection, blueprintKey: nil,
            readsCover: true, defaultCover: InsuranceCover.rca, deadlineField: .expiryDate, documentDateFields: issuedOn,
            documentKind: .policy, documentType: nil, trade: .insurer,
            expectedKeys: [.provider, .providerTaxID, .policyNumber, .coverageType, .startDate, .expiryDate, .total, .claimsPhone, .licensePlate, .vin, .bonusMalusClass],
            carriesLineItems: false, opensVisitFlow: false, logsHistory: true, identifierKeys: [.licensePlate, .vin],
            name: "Poliță RCA", titleRule: .nameAndYear, modelDescription: "compulsory motor insurance (RCA) policy", sectionName: .vehicle
        ),
        CaptureKindProfile(
            kind: .insurancePolicy, templateKey: nil, filing: .intoSection, blueprintKey: nil,
            readsCover: true, defaultCover: nil, deadlineField: .expiryDate, documentDateFields: issuedOn,
            documentKind: .policy, documentType: nil, trade: .insurer,
            expectedKeys: [.provider, .providerTaxID, .policyNumber, .coverageType, .startDate, .expiryDate, .total, .claimsPhone, .licensePlate],
            carriesLineItems: false, opensVisitFlow: false, logsHistory: false, identifierKeys: [.licensePlate, .vin],
            name: "Poliță de asigurare", titleRule: .name, modelDescription: "insurance policy (CASCO, home or other)"
        ),
        CaptureKindProfile(
            kind: .utilityInvoice, templateKey: BuiltInTemplates.Key.subscription, filing: .subscription, blueprintKey: SubscriptionFields.billBlueprint,
            readsCover: false, defaultCover: nil, deadlineField: .dueDate, documentDateFields: issuedOn,
            documentKind: .invoice, documentType: nil, trade: nil,
            expectedKeys: [.provider, .serviceKind, .invoiceNumber, .issueDate, .dueDate, .total, .clientCode, .contractNumber, .podCode, .clcCode,
                           .phoneNumber, .meterIndex],
            carriesLineItems: false, opensVisitFlow: false, logsHistory: true, identifierKeys: subscriptionCodes,
            name: "Factură de utilități", titleRule: .wordAndProvider("Factură"), modelDescription: "utility, internet, TV or phone bill", deadlineIsOptIn: true, sectionName: .subscription
        ),
        CaptureKindProfile(
            kind: .contract, templateKey: BuiltInTemplates.Key.subscription, filing: .subscription, blueprintKey: SubscriptionFields.minimumEndsBlueprint,
            readsCover: false, defaultCover: nil, deadlineField: .minimumPeriodEnd, documentDateFields: issuedOn,
            documentKind: .contract, documentType: nil, trade: nil,
            expectedKeys: [.provider, .serviceKind, .contractNumber, .clientCode, .startDate, .minimumMonths, .minimumPeriodEnd, .monthlyPrice,
                           .phoneNumber, .podCode, .clcCode],
            carriesLineItems: false, opensVisitFlow: false, logsHistory: false, identifierKeys: subscriptionCodes,
            name: "Contract sau act adițional", titleRule: .wordAndProvider("Contract"),
            modelDescription: "contract or addendum for gas, electricity, water, internet, TV or a mobile plan", sectionName: .subscription
        ),
        CaptureKindProfile(
            kind: .serviceInvoice, templateKey: BuiltInTemplates.Key.vehicle, filing: .intoSection, blueprintKey: nil,
            readsCover: false, defaultCover: nil, deadlineField: nil, documentDateFields: issuedOn,
            documentKind: .invoice, documentType: nil, trade: .mechanic,
            expectedKeys: [.provider, .providerTaxID, .invoiceNumber, .issueDate, .total, .licensePlate, .vin, .odometer, .lineItems],
            carriesLineItems: true, opensVisitFlow: true, logsHistory: true, identifierKeys: [.licensePlate, .vin],
            name: "Factură de service", titleRule: .wordAndProvider("Factură"), modelDescription: "car service invoice", sectionName: .vehicle
        ),
        CaptureKindProfile(
            kind: .fiscalReceipt, templateKey: BuiltInTemplates.Key.purchase, filing: .newSection, blueprintKey: BuiltInBlueprints.warrantyEnds,
            readsCover: false, defaultCover: nil, deadlineField: .warrantyUntil, documentDateFields: issuedOn,
            documentKind: .receipt, documentType: nil, trade: nil,
            expectedKeys: [.retailer, .purchaseDate, .purchasePrice, .productName, .serialNumber, .lineItems],
            carriesLineItems: true, opensVisitFlow: false, logsHistory: false, identifierKeys: [.serialNumber],
            name: "Bon fiscal", titleRule: .product, modelDescription: "fiscal receipt"
        ),
        CaptureKindProfile(
            kind: .warrantyCertificate, templateKey: BuiltInTemplates.Key.purchase, filing: .newSection, blueprintKey: BuiltInBlueprints.warrantyEnds,
            readsCover: false, defaultCover: nil, deadlineField: .warrantyUntil, documentDateFields: issuedOn,
            documentKind: .warranty, documentType: nil, trade: nil,
            expectedKeys: [.retailer, .productName, .serialNumber, .purchaseDate, .warrantyMonths, .warrantyUntil],
            carriesLineItems: false, opensVisitFlow: false, logsHistory: false, identifierKeys: [.serialNumber],
            name: "Certificat de garanție", titleRule: .product, modelDescription: "warranty certificate"
        ),
        CaptureKindProfile(
            kind: .itpReport, templateKey: BuiltInTemplates.Key.vehicle, filing: .intoSection, blueprintKey: BuiltInBlueprints.vehicleITP,
            readsCover: false, defaultCover: nil, deadlineField: .expiryDate, documentDateFields: issuedOn,
            documentKind: .report, documentType: nil, trade: .inspectionStation,
            expectedKeys: [.provider, .licensePlate, .vin, .issueDate, .expiryDate, .odometer],
            carriesLineItems: false, opensVisitFlow: false, logsHistory: true, identifierKeys: [.licensePlate, .vin],
            name: "Raport ITP", titleRule: .name, modelDescription: "periodic technical inspection (ITP) report", sectionName: .vehicle
        ),
        CaptureKindProfile(
            kind: .veterinaryRecord, templateKey: BuiltInTemplates.Key.pet, filing: .intoSection, blueprintKey: BuiltInBlueprints.petVaccine,
            readsCover: false, defaultCover: nil, deadlineField: .nextDoseDate, documentDateFields: issuedOn,
            documentKind: .report, documentType: nil, trade: .vet,
            expectedKeys: [.provider, .petName, .microchip, .vaccineName, .issueDate, .nextDoseDate],
            carriesLineItems: true, opensVisitFlow: true, logsHistory: true, identifierKeys: [.microchip, .petName],
            name: "Fișă de la veterinar", titleRule: .name, modelDescription: "veterinary record", sectionName: .pet
        ),
        CaptureKindProfile(
            kind: .medicalResult, templateKey: BuiltInTemplates.Key.health, filing: .intoSection, blueprintKey: nil,
            readsCover: false, defaultCover: nil, deadlineField: nil, documentDateFields: issuedOn,
            documentKind: .report, documentType: nil, trade: .doctor,
            expectedKeys: [.provider, .issueDate],
            carriesLineItems: false, opensVisitFlow: false, logsHistory: true, identifierKeys: [],
            name: "Rezultat medical", titleRule: .name, modelDescription: "medical test result", sectionName: .fixed("Sănătate")
        ),
        other,
    ]

    static let other = CaptureKindProfile(
        kind: .other, templateKey: nil, filing: .keepOnly, blueprintKey: nil,
        readsCover: false, defaultCover: nil, deadlineField: nil, documentDateFields: issuedOn,
        documentKind: .other, documentType: nil, trade: nil,
        expectedKeys: [.provider, .documentNumber, .invoiceNumber, .issueDate, .dueDate, .expiryDate, .total],
        carriesLineItems: true, opensVisitFlow: false, logsHistory: false, identifierKeys: [],
        name: "Alt document", titleRule: .name, modelDescription: "household document"
    )

    /// The codes that find a bill's or a contract's subscription, most specific first.
    static let subscriptionCodes: [CaptureFieldKey] = [.podCode, .clcCode, .phoneNumber, .contractNumber, .clientCode]

    /// An identity document: a personal document of its holder, renewed by its expiry.
    private static func identity(_ kind: CaptureDocumentKind, type: String, name: LocalizedStringResource, model: String) -> CaptureKindProfile {
        CaptureKindProfile(
            kind: kind, templateKey: BuiltInTemplates.Key.documents, filing: .newSection, blueprintKey: BuiltInBlueprints.documentRenew,
            readsCover: false, defaultCover: nil, deadlineField: .expiryDate, documentDateFields: issuedOn,
            documentKind: .identity, documentType: type, trade: nil,
            expectedKeys: IdentityTemplates.all.filter { $0.kind == kind }.flatMap { $0.fields.map(\.key) },
            carriesLineItems: false, opensVisitFlow: false, logsHistory: false, identifierKeys: [.documentNumber],
            name: name, titleRule: .name, modelDescription: model, sectionName: .holder
        )
    }
}

extension CaptureDocumentKind {
    /// What this kind means to the binder.
    var profile: CaptureKindProfile { CaptureKindProfile.of(self) }
}
