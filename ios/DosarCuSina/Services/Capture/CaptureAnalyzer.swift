import Foundation

/// A parser that knows one family of documents exactly (for example a utility company's
/// invoice layout) and can claim it with deterministic fields.
public protocol CaptureSpecializedParser: Sendable {
    func parse(_ text: CaptureText) -> CaptureAnalyzer.SpecializedParse?
}

/// The deterministic and heuristic tiers: everything that runs without a language model.
///
/// Pure and synchronous, so it can be tested with plain strings and run anywhere.
/// The engine calls it first, then lets the on-device or cloud model fill the gaps.
public struct CaptureAnalyzer: Sendable {

    public struct SpecializedParse: Sendable {
        public let kind: CaptureDocumentKind
        public let fields: [CaptureField]

        public init(kind: CaptureDocumentKind, fields: [CaptureField]) {
            self.kind = kind
            self.fields = fields
        }
    }

    public struct Analysis: Sendable {
        public let text: CaptureText
        public let kind: CaptureDocumentKind
        public let kindConfidence: Double
        /// What the kind rests on, for `ReadingArbiter`.
        public let kindEvidence: CaptureKindEvidence
        public let fields: [CaptureField]
        public let notices: [CaptureNotice]
        /// Whether a machine-readable zone was found.
        public let hasMachineReadableZone: Bool
        /// The text for people: each printed label followed by its value, columns kept together.
        public let readableText: String
    }

    let specializedParsers: [any CaptureSpecializedParser]
    let componentResolver: any CaptureComponentResolving
    let insurerNames: [(keyword: String, name: String)]
    /// The kinds' profiles whose label tables the readers are told: the registry, unless a
    /// test gives a table another wording (`reading(labelsOf:)`).
    private(set) var profiles: [CaptureKindProfile] = CaptureKindProfile.all

    public init(
        specializedParsers: [any CaptureSpecializedParser] = [],
        componentResolver: any CaptureComponentResolving = CatalogComponentResolver(),
        insurerNames: [(keyword: String, name: String)] = CaptureAnalyzer.catalogInsurers
    ) {
        self.specializedParsers = specializedParsers
        self.componentResolver = componentResolver
        self.insurerNames = insurerNames
    }

    /// The same analyzer, its readers told `profiles`' label tables: a wording added to a
    /// kind's table is read with no change to the readers.
    func reading(labelsOf profiles: [CaptureKindProfile]) -> CaptureAnalyzer {
        var analyzer = self
        analyzer.profiles = profiles
        return analyzer
    }

    /// The profile whose labels the readers are told for `kind`.
    func profile(of kind: CaptureDocumentKind) -> CaptureKindProfile {
        profiles.first { $0.kind == kind } ?? kind.profile
    }

    /// Insurers from the shared Romanian catalog, keyed by a word that appears on their documents.
    public static var catalogInsurers: [(keyword: String, name: String)] {
        RomanianInsuranceCatalog.recommendedInsurers
            .filter { $0.id != "other" }
            .map { ($0.id, $0.name) }
    }

    /// Below this classifier confidence, a provider-specific reader may claim a document
    /// of another kind; above it, the classifier's kind stands.
    static let specializedClaimBelow = 0.6

    // MARK: - Analysis

    /// `kind`, when given, is what the document is known to be (the AI provider named it),
    /// so the patterns read it as that kind instead of classifying it again.
    public func analyze(text rawText: String, barcodes: [CaptureBarcode] = [], referenceDate: Date = Date(), as kind: CaptureDocumentKind? = nil) -> Analysis {
        analyze(CaptureText(rawText), rawText: rawText, barcodes: barcodes, referenceDate: referenceDate, as: kind)
    }

    /// Recognized pages, with where each line sits, so labels find the values in their columns.
    public func analyze(pages: [[RecognizedLine]], barcodes: [CaptureBarcode] = [], referenceDate: Date = Date(), as kind: CaptureDocumentKind? = nil) -> Analysis {
        let text = CaptureText(pages: pages)
        return analyze(text, rawText: text.joinedOriginal, barcodes: barcodes, referenceDate: referenceDate, as: kind)
    }

    /// `lines` keeps recognized fragments apart, with their positions, for documents read
    /// by their printed labels (identity documents). Every other reader works on whole
    /// rows, so an invoice line's description and amount stay on one line.
    func analyze(_ lines: CaptureText, rawText: String, barcodes: [CaptureBarcode], referenceDate: Date, as knownKind: CaptureDocumentKind? = nil) -> Analysis {
        var notices: [CaptureNotice] = []
        var fields = FieldSet()
        var text = lines.joiningRows()
        let today = CalendarDay(referenceDate)
        // Two-digit years on documents no rule covers take the century nearest today.
        let years = DateWindow.around(today)

        let mrz = MRZParser.parse(text: rawText, referenceDate: referenceDate)
        let classification = knownKind.map { DocumentClassifier.Classification(kind: $0, confidence: 1) }
            ?? DocumentClassifier.classify(text: text, mrz: mrz)
        // A provider-specific reader claims a document only when the classifier agrees
        // or isn't sure: an RCA policy that mentions "digital" stays a policy. A known
        // kind is never claimed by a reader of another.
        let specialized = specializedParsers.lazy
            .compactMap { $0.parse(text) }
            .first { parse in
                // A contract quotes the provider's name and codes too; a bill reader never takes it.
                parse.kind == classification.kind
                    || (knownKind == nil && classification.confidence < Self.specializedClaimBelow && classification.kind != .contract)
            }

        let kind: CaptureDocumentKind
        let kindConfidence: Double
        var kindEvidence: CaptureKindEvidence
        if let specialized {
            kind = specialized.kind
            kindConfidence = 0.95
            kindEvidence = specialized.kind == classification.kind ? .providerFormat : .providerFormatAlone
            fields.add(specialized.fields)
        } else {
            kind = classification.kind
            kindConfidence = classification.confidence
            kindEvidence = .classifier
        }
        if let mrz, mrz.allChecksValid, kind.isIdentityDocument {
            kindEvidence = .machineReadableZone
        } else if kind.profile.isBill, !kindEvidence.isDeterministic, barcodes.contains(where: \.isPaymentCode) {
            kindEvidence = .paymentBarcode
        }

        if let mrz {
            fields.add(Self.machineReadableFields(mrz))
            if !mrz.allChecksValid { notices.append(.machineReadableZoneUnverified) }
        }

        let template = IdentityTemplates.template(for: kind, text: text, machineReadableFormat: mrz?.format)
        if template != nil { text = lines }
        // Every reader below is told the kind's own labels (`CaptureKindProfile.labels`), and
        // what every document prints the same way where the kind has no row of its own.
        let profile = self.profile(of: kind)
        switch kind {
        case .passport, .identityCard, .drivingLicence, .criminalRecord, .healthInsuranceCard, .bankCard, .greenCard, .electronicSignature:
            // Printed labels, read with the document's template. The MRZ (when on the
            // photo) already added checked values, which win; agreeing values reinforce.
            // A personal document is read the same way, whatever it is: a new one is a template.
            if let template {
                fields.add(IdentityDocumentReader.read(text, template: template, today: today))
                if let variant = template.documentVariant {
                    fields.add(.documentVariant, .text(variant), 0.9, nil, tier: .deterministic)
                }
            }
        case .vehicleRegistration:
            addVehicleIdentity(text, profile: profile, into: &fields)
            if let civ = RomanianFieldExtractor.civNumber(in: text, labels: profile.labels(for: .civNumber)) {
                fields.add(.civNumber, .text(civ.value), civ.quality.confidence, civ.source)
            }
            for (key, entry) in RomanianFieldExtractor.registrationFields(in: text, labels: profile.labels).sorted(by: { $0.key.rawValue < $1.key.rawValue }) {
                fields.add(key, entry.0, 0.65, entry.1)
            }
        case .rcaPolicy, .insurancePolicy:
            addInsurance(text, profile: profile, years: years, into: &fields)
        case .utilityInvoice:
            // The bill's own labels (its dates, the meter's index, how to pay it), for every
            // provider the same way; the issuer, the number and the total as on any invoice.
            addIssuer(text, profile: profile, into: &fields)
            addInvoiceNumberAndTotal(text, profile: profile, into: &fields)
            fields.add(BillReader.fields(in: text, window: years))
            // The bill's own issue-date wordings are its layout's; when they find none, the
            // date as every document labels it.
            if fields.day(.issueDate) == nil {
                addIssueDate(text, labels: CaptureKindProfile.commonLabels(for: .issueDate), years: years, into: &fields)
            }
            // What ties the bill to its contract: the codes and the service.
            fields.add(ContractReader.identifierFields(in: text))
        case .contract:
            addContractProvider(text, profile: profile, into: &fields)
            fields.add(ContractReader.contractFields(in: text, window: years))
        case .serviceInvoice:
            addInvoiceBasics(text, profile: profile, years: years, into: &fields)
            addVehicleIdentity(text, profile: profile, into: &fields)
            addLineItems(text, into: &fields)
            addOdometer(text, profile: profile, into: &fields)
        case .fiscalReceipt, .warrantyCertificate:
            addPurchase(text, profile: profile, years: years, into: &fields)
        case .itpReport:
            addVehicleIdentity(text, profile: profile, into: &fields)
            if let expiry = RomanianFieldExtractor.labelledDate(profile.labels(for: .expiryDate), in: text, window: years) {
                fields.add(.expiryDate, .day(expiry.day), 0.8, expiry.source)
            }
            addOdometer(text, profile: profile, into: &fields)
            addIssuer(text, profile: profile, into: &fields)
            addIssueDate(text, labels: profile.labels(for: .issueDate), years: years, into: &fields)
        case .veterinaryRecord:
            if let chip = RomanianFieldExtractor.microchip(in: text, labels: profile.labels(for: .microchip)) {
                fields.add(.microchip, .text(chip.value), 0.85, chip.source)
            }
            // The vaccine is the line that names it, as printed.
            if let index = text.lines(containing: profile.labels(for: .vaccineName)).first {
                fields.add(.vaccineName, .text(text.original[index]), 0.55, text.original[index])
            }
            if let next = RomanianFieldExtractor.labelledDate(profile.labels(for: .nextDoseDate), in: text, window: years) {
                fields.add(.nextDoseDate, .day(next.day), 0.75, next.source)
            }
            addIssuer(text, profile: profile, into: &fields)
            addIssueDate(text, labels: profile.labels(for: .issueDate), years: years, into: &fields)
        case .medicalResult:
            addIssuer(text, profile: profile, into: &fields)
            addIssueDate(text, labels: profile.labels(for: .issueDate), years: years, into: &fields)
        case .other:
            addInvoiceBasics(text, profile: profile, years: years, into: &fields)
        }

        if profile.readsPaymentCode,
           let barcode = barcodes.first(where: { !$0.payload.isEmpty }) {
            fields.add(.paymentCode, .text(barcode.payload), 0.95, nil, tier: .deterministic)
        }

        if mrz == nil, text.joinedOriginal.filter(\.isLetter).count < 20 {
            notices.append(.littleTextRecognized)
        }

        let readable: [String]
        if let template {
            readable = LabelledLayout(text: text, labels: template.labelTable).readableLines()
        } else {
            readable = text.original
        }
        return Analysis(
            text: text, kind: kind, kindConfidence: kindConfidence, kindEvidence: kindEvidence, fields: fields.fields, notices: notices,
            hasMachineReadableZone: mrz != nil, readableText: readable.joined(separator: "\n")
        )
    }

    // MARK: - Field groups

    /// The fields a machine-readable zone holds: certain where its check digits pass.
    /// Every field the machine-readable zone can give (`machineReadableFields`).
    static let machineReadableKeys: Set<CaptureFieldKey> = [
        .documentCode, .issuingCountry, .documentNumber, .nationality, .surname, .givenNames, .holderName,
        .birthDate, .expiryDate, .sex, .personalNumber,
    ]

    static func machineReadableFields(_ mrz: MRZParser.Result) -> [CaptureField] {
        let tier: CaptureTier = mrz.allChecksValid ? .deterministic : .heuristic
        let source = CaptureField.machineReadableSource
        var result: [CaptureField] = [
            CaptureField(key: .documentCode, value: .text(mrz.documentCode), confidence: 0.99, sourceText: source, tier: .deterministic),
            CaptureField(key: .issuingCountry, value: .text(mrz.issuingCountry), confidence: 0.95, sourceText: source, tier: tier),
            CaptureField(key: .documentNumber, value: .text(mrz.documentNumber), confidence: mrz.documentNumberValid ? 0.99 : 0.5, sourceText: source, tier: mrz.documentNumberValid ? .deterministic : .heuristic),
            CaptureField(key: .nationality, value: .text(mrz.nationality), confidence: 0.95, sourceText: source, tier: tier),
            CaptureField(key: .surname, value: .text(mrz.surname), confidence: 0.9, sourceText: source, tier: tier),
            CaptureField(key: .givenNames, value: .text(mrz.givenNames), confidence: 0.9, sourceText: source, tier: tier),
            CaptureField(key: .holderName, value: .text("\(mrz.givenNames) \(mrz.surname)".trimmingCharacters(in: .whitespaces)), confidence: 0.9, sourceText: source, tier: tier),
        ]
        if let birth = mrz.birthDate {
            result.append(CaptureField(key: .birthDate, value: .day(birth), confidence: mrz.birthDateValid ? 0.99 : 0.5, sourceText: source, tier: mrz.birthDateValid ? .deterministic : .heuristic))
        }
        if let expiry = mrz.expiryDate {
            result.append(CaptureField(key: .expiryDate, value: .day(expiry), confidence: mrz.expiryDateValid ? 0.99 : 0.5, sourceText: source, tier: mrz.expiryDateValid ? .deterministic : .heuristic))
        }
        if let sex = mrz.sex {
            result.append(CaptureField(key: .sex, value: .text(sex), confidence: 0.95, sourceText: source, tier: tier))
        }
        let personal = mrz.optionalData.filter(\.isNumber)
        if personal.count == 13 {
            result.append(CaptureField(key: .personalNumber, value: .text(personal), confidence: mrz.compositeValid ? 0.95 : 0.5, sourceText: source, tier: tier))
        }
        return result
    }

    private func addInvoiceBasics(_ text: CaptureText, profile: CaptureKindProfile, years: DateWindow, into fields: inout FieldSet) {
        addIssuer(text, profile: profile, into: &fields)
        addInvoiceNumberAndTotal(text, profile: profile, into: &fields)
        addIssueDate(text, labels: profile.labels(for: .issueDate), years: years, into: &fields)
    }

    private func addInvoiceNumberAndTotal(_ text: CaptureText, profile: CaptureKindProfile, into fields: inout FieldSet) {
        if let invoice = RomanianFieldExtractor.invoiceNumber(in: text, labels: profile.labels(for: .invoiceNumber)) {
            fields.add(.invoiceNumber, .text(invoice.value), invoice.quality.confidence, invoice.source)
        }
        if let total = RomanianFieldExtractor.total(in: text, labels: profile.labels(for: .total)) {
            fields.add(.total, .money(total.money), Self.confidence(total.strong ? 0.8 : 0.6, ambiguous: total.ambiguous), total.source)
        }
    }

    /// A confidence that marks the field "Verifică" when its amount could be read two ways ("3,750").
    static func confidence(_ confidence: Double, ambiguous: Bool) -> Double {
        ambiguous ? min(confidence, CaptureField.checkThreshold - 0.1) : confidence
    }

    private func addIssuer(_ text: CaptureText, profile: CaptureKindProfile, into fields: inout FieldSet) {
        if let taxID = RomanianFieldExtractor.taxID(in: text, labels: profile.labels(for: .providerTaxID)) {
            fields.add(.providerTaxID, .text(taxID.value), taxID.valid ? 0.97 : 0.5, text.original[taxID.line], tier: taxID.valid ? .deterministic : .heuristic)
        }
        if let issuer = RomanianFieldExtractor.issuerName(in: text) {
            fields.add(.provider, .text(issuer.name), 0.65, text.original[issuer.line])
        }
    }

    /// Who provides the service: a provider the phone knows by name (`UtilityProviders`),
    /// else the company printed as the issuer.
    private func addContractProvider(_ text: CaptureText, profile: CaptureKindProfile, into fields: inout FieldSet) {
        if let known = UtilityProviders.named(in: text) {
            fields.add(.provider, .text(known.name), 0.85, nil)
        }
        addIssuer(text, profile: profile, into: &fields)
    }

    /// The day the document was issued: after one of `labels`, else the first date on the page.
    private func addIssueDate(_ text: CaptureText, labels: [String], years: DateWindow, into fields: inout FieldSet) {
        if let issue = RomanianFieldExtractor.labelledDate(labels, in: text, window: years) {
            fields.add(.issueDate, .day(issue.day), 0.7, issue.source)
        } else if let first = RomanianFieldExtractor.allDates(in: text, window: years).first {
            fields.add(.issueDate, .day(first.day), 0.45, text.original[first.line])
        }
    }

    private func addVehicleIdentity(_ text: CaptureText, profile: CaptureKindProfile, into fields: inout FieldSet) {
        if let plate = RomanianFieldExtractor.licensePlate(in: text) {
            fields.add(.licensePlate, .text(plate.value), 0.8, plate.source)
        }
        if let vin = RomanianFieldExtractor.vin(in: text, labels: profile.labels(for: .vin)) {
            fields.add(.vin, .text(vin.value), vin.checksumValid ? 0.97 : 0.75, vin.source, tier: vin.checksumValid ? .deterministic : .heuristic)
        }
    }

    private func addOdometer(_ text: CaptureText, profile: CaptureKindProfile, into fields: inout FieldSet) {
        if let odometer = RomanianFieldExtractor.odometer(in: text, labels: profile.labels(for: .odometer)) {
            fields.add(.odometer, .metric(value: odometer.km, unit: .kilometres), odometer.labelled ? 0.8 : 0.55, odometer.source)
        }
    }

    private func addLineItems(_ text: CaptureText, into fields: inout FieldSet) {
        let currency = RomanianFieldExtractor.dominantCurrency(in: text)
        let items = RomanianFieldExtractor.lineItems(in: text, currency: currency, resolver: componentResolver)
        if !items.isEmpty {
            fields.add(.lineItems, .lineItems(items), 0.6, nil)
        }
    }

    private func addInsurance(_ text: CaptureText, profile: CaptureKindProfile, years: DateWindow, into fields: inout FieldSet) {
        let haystack = text.joinedFolded
        if let insurer = insurerNames.first(where: { CaptureText.containsWord($0.keyword, inFolded: haystack) }) {
            fields.add(.provider, .text(insurer.name), 0.85, nil)
        } else {
            addIssuer(text, profile: profile, into: &fields)
        }
        if let taxID = RomanianFieldExtractor.taxID(in: text, labels: profile.labels(for: .providerTaxID)), taxID.valid {
            fields.add(.providerTaxID, .text(taxID.value), 0.97, text.original[taxID.line], tier: .deterministic)
        }
        if let policy = RomanianFieldExtractor.policyNumber(in: text, labels: profile.labels(for: .policyNumber)) {
            fields.add(.policyNumber, .text(policy.value), policy.quality.confidence, policy.source)
        }
        if let phone = RomanianFieldExtractor.claimsPhone(in: text, labels: profile.labels(for: .claimsPhone)) {
            fields.add(.claimsPhone, .text(phone.value), 0.75, phone.source)
        }
        if let period = RomanianFieldExtractor.validityPeriod(in: text, labels: profile.labels(for: .validityPeriod), window: years) {
            fields.add(.startDate, .day(period.start), 0.75, period.source)
            fields.add(.expiryDate, .day(period.end), 0.8, period.source)
        } else if let expiry = RomanianFieldExtractor.labelledDate(profile.labels(for: .expiryDate), in: text, window: years) {
            fields.add(.expiryDate, .day(expiry.day), 0.65, expiry.source)
        }
        if let premium = RomanianFieldExtractor.total(in: text, labels: profile.labels(for: .total)) {
            fields.add(.total, .money(premium.money), Self.confidence(premium.strong ? 0.75 : 0.5, ambiguous: premium.ambiguous), premium.source)
        }
        if let classValue = RomanianFieldExtractor.bonusMalus(in: text, labels: profile.labels(for: .bonusMalusClass)) {
            fields.add(.bonusMalusClass, .text(classValue), 0.7, nil)
        }
        // Who it insures: the person whose class it is (`Policyholders`).
        fields.add(PolicyholderReader.fields(in: text))
        // The cover: an RCA policy is RCA; any other policy's is read once, as whole words.
        // When the page names none, the review asks the person to pick it.
        if let cover = profile.defaultCover ?? InsuranceCover.read(in: haystack, among: profile.covers) {
            fields.add(.coverageType, .text(cover), 0.7, nil)
        }
        addVehicleIdentity(text, profile: profile, into: &fields)
    }

    private func addPurchase(_ text: CaptureText, profile: CaptureKindProfile, years: DateWindow, into fields: inout FieldSet) {
        if let taxID = RomanianFieldExtractor.taxID(in: text, labels: profile.labels(for: .providerTaxID)) {
            fields.add(.providerTaxID, .text(taxID.value), taxID.valid ? 0.97 : 0.5, text.original[taxID.line], tier: taxID.valid ? .deterministic : .heuristic)
        }
        if let issuer = RomanianFieldExtractor.issuerName(in: text) {
            fields.add(.retailer, .text(issuer.name), 0.65, text.original[issuer.line])
            fields.add(.provider, .text(issuer.name), 0.6, text.original[issuer.line])
        }
        let purchaseDate = RomanianFieldExtractor.labelledDate(profile.labels(for: .purchaseDate), in: text, window: years).map { ($0.day, $0.source, 0.75) }
            ?? RomanianFieldExtractor.allDates(in: text, window: years).first.map { ($0.day, text.original[$0.line], 0.55) }
        if let purchaseDate {
            fields.add(.purchaseDate, .day(purchaseDate.0), purchaseDate.2, purchaseDate.1)
        }
        // The price paid is the total the receipt states.
        if let total = RomanianFieldExtractor.total(in: text, labels: profile.labels(for: .total)) {
            fields.add(.purchasePrice, .money(total.money), Self.confidence(total.strong ? 0.8 : 0.65, ambiguous: total.ambiguous), total.source)
        }
        if let serial = RomanianFieldExtractor.serialNumber(in: text, labels: profile.labels(for: .serialNumber)) {
            fields.add(.serialNumber, .text(serial.value), 0.7, serial.source)
        }
        let currency = RomanianFieldExtractor.dominantCurrency(in: text)
        let items = RomanianFieldExtractor.lineItems(in: text, currency: currency, resolver: componentResolver)
        if !items.isEmpty {
            fields.add(.lineItems, .lineItems(items), 0.55, nil)
            if let biggest = items.max(by: { ($0.amount?.amount ?? 0) < ($1.amount?.amount ?? 0) }) {
                fields.add(.productName, .text(biggest.description), items.count == 1 ? 0.65 : 0.45, nil)
            }
        }
        if let warranty = RomanianFieldExtractor.warrantyMonths(in: text, labels: profile.labels(for: .warrantyMonths)) {
            fields.add(.warrantyMonths, .number(Decimal(warranty.months)), 0.75, warranty.source)
            if let start = fields.day(.purchaseDate), let until = start.printed(addingMonths: warranty.months) {
                fields.add(.warrantyUntil, .day(until), 0.7, warranty.source)
            }
        }
    }
}

// MARK: - Field set

/// Collects fields and keeps the best one per key while the analyzer runs.
struct FieldSet {
    private(set) var fields: [CaptureField] = []

    mutating func add(_ newFields: [CaptureField]) {
        for field in newFields { add(field) }
    }

    /// Keeps the better value per key; two readings that agree (the MRZ and the printed
    /// label, say) reinforce each other.
    mutating func add(_ field: CaptureField) {
        fields = FieldMerger.merge(fields, with: [field])
    }

    mutating func add(_ key: CaptureFieldKey, _ value: CaptureValue, _ confidence: Double, _ source: String?, tier: CaptureTier = .heuristic) {
        add(CaptureField(key: key, value: value, confidence: confidence, sourceText: source, tier: tier))
    }

    func text(_ key: CaptureFieldKey) -> String? { fields.first { $0.key == key }?.value.text }
    func day(_ key: CaptureFieldKey) -> CalendarDay? { fields.first { $0.key == key }?.value.day }
}

// MARK: - Merging tiers

/// Combines fields from several readers into one best answer per key. Which value wins
/// is decided in one place, `ReadingArbiter`.
public enum FieldMerger {

    static func prefers(_ candidate: CaptureField, over existing: CaptureField) -> Bool {
        ReadingArbiter.prefers(candidate, over: existing)
    }

    /// Merges a later reader's fields into earlier ones. When two readers agree on a value,
    /// the agreement raises confidence, keeps the earlier source text, and counts as read
    /// from the document rather than guessed by a model.
    public static func merge(_ base: [CaptureField], with incoming: [CaptureField]) -> [CaptureField] {
        var result = base
        for candidate in incoming {
            guard let index = result.firstIndex(where: { $0.key == candidate.key }) else {
                result.append(candidate)
                continue
            }
            let existing = result[index]
            if let agreed = ReadingArbiter.agreedValue(existing, candidate) {
                result[index] = ReadingArbiter.agreeing(existing, candidate, value: agreed)
            } else if prefers(candidate, over: existing) {
                result[index] = candidate
            }
        }
        return result
    }
}
