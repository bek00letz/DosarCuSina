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

    public init(
        specializedParsers: [any CaptureSpecializedParser] = [],
        componentResolver: any CaptureComponentResolving = CatalogComponentResolver(),
        insurerNames: [(keyword: String, name: String)] = CaptureAnalyzer.catalogInsurers
    ) {
        self.specializedParsers = specializedParsers
        self.componentResolver = componentResolver
        self.insurerNames = insurerNames
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
        let today = CaptureDay(date: referenceDate)
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
        } else if kind == .utilityInvoice, !kindEvidence.isDeterministic, barcodes.contains(where: \.isPaymentCode) {
            kindEvidence = .paymentBarcode
        }

        if let mrz {
            fields.add(Self.machineReadableFields(mrz))
            if !mrz.allChecksValid { notices.append(.machineReadableZoneUnverified) }
        }

        let template = IdentityTemplates.template(for: kind, text: text, machineReadableFormat: mrz?.format)
        if template != nil { text = lines }
        switch kind {
        case .passport, .identityCard, .drivingLicence:
            // Printed labels, read with the document's template. The MRZ (when on the
            // photo) already added checked values, which win; agreeing values reinforce.
            if let template {
                fields.add(IdentityDocumentReader.read(text, template: template, today: today))
                if let variant = template.documentVariant {
                    fields.add(.documentVariant, .text(variant), 0.9, nil, tier: .deterministic)
                }
            }
        case .vehicleRegistration:
            addVehicleIdentity(text, into: &fields)
            for (key, entry) in RomanianFieldExtractor.registrationFields(in: text).sorted(by: { $0.key.rawValue < $1.key.rawValue }) {
                fields.add(key, entry.0, 0.65, entry.1)
            }
        case .rcaPolicy, .insurancePolicy:
            addInsurance(text, kind: kind, years: years, into: &fields)
        case .utilityInvoice:
            addInvoiceBasics(text, years: years, into: &fields)
            if let due = RomanianFieldExtractor.labelledDate(["scadent", "termen de plata", "data scadentei", "de platit pana la"], in: text, window: years) {
                fields.add(.dueDate, .day(due.day), 0.75, due.source)
            }
            // What ties the bill to its contract: the codes and the service.
            fields.add(ContractReader.identifierFields(in: text))
        case .contract:
            addContractProvider(text, into: &fields)
            fields.add(ContractReader.contractFields(in: text, window: years))
        case .serviceInvoice:
            addInvoiceBasics(text, years: years, into: &fields)
            addVehicleIdentity(text, into: &fields)
            addLineItems(text, into: &fields)
            if let odometer = RomanianFieldExtractor.odometer(in: text) {
                fields.add(.odometer, .metric(value: odometer.km, unit: "km"), odometer.labelled ? 0.8 : 0.55, odometer.source)
            }
        case .fiscalReceipt, .warrantyCertificate:
            addPurchase(text, kind: kind, years: years, into: &fields)
        case .itpReport:
            addVehicleIdentity(text, into: &fields)
            if let expiry = RomanianFieldExtractor.labelledDate(["valabila pana la", "valabil pana la", "urmatoarea inspectie", "data urmatoarei inspectii", "valabilitate"], in: text, window: years) {
                fields.add(.expiryDate, .day(expiry.day), 0.8, expiry.source)
            }
            if let odometer = RomanianFieldExtractor.odometer(in: text) {
                fields.add(.odometer, .metric(value: odometer.km, unit: "km"), odometer.labelled ? 0.8 : 0.55, odometer.source)
            }
            addIssuer(text, into: &fields)
            addIssueDate(text, years: years, into: &fields)
        case .veterinaryRecord:
            if let chip = RomanianFieldExtractor.microchip(in: text) {
                fields.add(.microchip, .text(chip.value), 0.85, chip.source)
            }
            if let index = text.lines(containing: ["vaccin", "antirabic"]).first {
                fields.add(.vaccineName, .text(text.original[index]), 0.55, text.original[index])
            }
            if let next = RomanianFieldExtractor.labelledDate(["rapel", "revaccinare", "urmatorul vaccin", "urmatoarea vaccinare", "valabil pana la"], in: text, window: years) {
                fields.add(.nextDoseDate, .day(next.day), 0.75, next.source)
            }
            addIssuer(text, into: &fields)
            addIssueDate(text, years: years, into: &fields)
        case .medicalResult:
            addIssuer(text, into: &fields)
            addIssueDate(text, years: years, into: &fields)
        case .other:
            addInvoiceBasics(text, years: years, into: &fields)
        }

        if kind == .utilityInvoice || kind == .serviceInvoice || kind == .other,
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

    private func addInvoiceBasics(_ text: CaptureText, years: DateWindow, into fields: inout FieldSet) {
        addIssuer(text, into: &fields)
        if let invoice = RomanianFieldExtractor.invoiceNumber(in: text) {
            fields.add(.invoiceNumber, .text(invoice.value), 0.7, invoice.source)
        }
        if let total = RomanianFieldExtractor.total(in: text) {
            fields.add(.total, .money(total.money), Self.confidence(total.strong ? 0.8 : 0.6, ambiguous: total.ambiguous), total.source)
        }
        addIssueDate(text, years: years, into: &fields)
    }

    /// A confidence that marks the field "Verifică" when its amount could be read two ways ("3,750").
    static func confidence(_ confidence: Double, ambiguous: Bool) -> Double {
        ambiguous ? min(confidence, CaptureField.checkThreshold - 0.1) : confidence
    }

    private func addIssuer(_ text: CaptureText, into fields: inout FieldSet) {
        if let taxID = RomanianFieldExtractor.taxID(in: text) {
            fields.add(.providerTaxID, .text(taxID.value), taxID.valid ? 0.97 : 0.5, text.original[taxID.line], tier: taxID.valid ? .deterministic : .heuristic)
        }
        if let issuer = RomanianFieldExtractor.issuerName(in: text) {
            fields.add(.provider, .text(issuer.name), 0.65, text.original[issuer.line])
        }
    }

    /// Who provides the service: a provider whose documents the utility reader knows by
    /// name, else the company printed as the issuer.
    private func addContractProvider(_ text: CaptureText, into fields: inout FieldSet) {
        let known = RomanianUtilityParser.shared.detectProvider(in: RomanianUtilityParser.normalizeDiacritics(text.joinedOriginal))
        if known != .general {
            fields.add(.provider, .text(known.displayName), 0.85, nil)
        }
        addIssuer(text, into: &fields)
    }

    private func addIssueDate(_ text: CaptureText, years: DateWindow, into fields: inout FieldSet) {
        if let issue = RomanianFieldExtractor.labelledDate(["data emiterii", "data facturii", "data eliberarii", "emisa la", "data:"], in: text, window: years) {
            fields.add(.issueDate, .day(issue.day), 0.7, issue.source)
        } else if let first = RomanianFieldExtractor.allDates(in: text, window: years).first {
            fields.add(.issueDate, .day(first.day), 0.45, text.original[first.line])
        }
    }

    private func addVehicleIdentity(_ text: CaptureText, into fields: inout FieldSet) {
        if let plate = RomanianFieldExtractor.licensePlate(in: text) {
            fields.add(.licensePlate, .text(plate.value), 0.8, plate.source)
        }
        if let vin = RomanianFieldExtractor.vin(in: text) {
            fields.add(.vin, .text(vin.value), vin.checksumValid ? 0.97 : 0.75, vin.source, tier: vin.checksumValid ? .deterministic : .heuristic)
        }
    }

    private func addLineItems(_ text: CaptureText, into fields: inout FieldSet) {
        let currency = RomanianFieldExtractor.dominantCurrency(in: text)
        let items = RomanianFieldExtractor.lineItems(in: text, currency: currency, resolver: componentResolver)
        if !items.isEmpty {
            fields.add(.lineItems, .lineItems(items), 0.6, nil)
        }
    }

    private func addInsurance(_ text: CaptureText, kind: CaptureDocumentKind, years: DateWindow, into fields: inout FieldSet) {
        let haystack = text.joinedFolded
        if let insurer = insurerNames.first(where: { CaptureText.containsWord($0.keyword, inFolded: haystack) }) {
            fields.add(.provider, .text(insurer.name), 0.85, nil)
        } else {
            addIssuer(text, into: &fields)
        }
        if let taxID = RomanianFieldExtractor.taxID(in: text), taxID.valid {
            fields.add(.providerTaxID, .text(taxID.value), 0.97, text.original[taxID.line], tier: .deterministic)
        }
        if let policy = RomanianFieldExtractor.policyNumber(in: text) {
            fields.add(.policyNumber, .text(policy.value), 0.65, policy.source)
        }
        if let phone = RomanianFieldExtractor.claimsPhone(in: text) {
            fields.add(.claimsPhone, .text(phone.value), 0.75, phone.source)
        }
        if let period = RomanianFieldExtractor.validityPeriod(in: text, window: years) {
            fields.add(.startDate, .day(period.start), 0.75, period.source)
            fields.add(.expiryDate, .day(period.end), 0.8, period.source)
        } else if let expiry = RomanianFieldExtractor.labelledDate(["pana la", "expira", "data expirarii", "valabila pana"], in: text, window: years) {
            fields.add(.expiryDate, .day(expiry.day), 0.65, expiry.source)
        }
        if let premium = RomanianFieldExtractor.total(in: text) {
            fields.add(.total, .money(premium.money), Self.confidence(premium.strong ? 0.75 : 0.5, ambiguous: premium.ambiguous), premium.source)
        }
        if let classValue = RomanianFieldExtractor.bonusMalus(in: text) {
            fields.add(.bonusMalusClass, .text(classValue), 0.7, nil)
        }
        // The cover: an RCA policy is RCA; any other policy's is read once, as whole words.
        // When the page names none, the review asks the person to pick it.
        if let cover = kind.profile.defaultCover ?? InsuranceCover.read(in: haystack, among: kind.profile.covers) {
            fields.add(.coverageType, .text(cover), 0.7, nil)
        }
        addVehicleIdentity(text, into: &fields)
    }

    private func addPurchase(_ text: CaptureText, kind: CaptureDocumentKind, years: DateWindow, into fields: inout FieldSet) {
        if let taxID = RomanianFieldExtractor.taxID(in: text) {
            fields.add(.providerTaxID, .text(taxID.value), taxID.valid ? 0.97 : 0.5, text.original[taxID.line], tier: taxID.valid ? .deterministic : .heuristic)
        }
        if let issuer = RomanianFieldExtractor.issuerName(in: text) {
            fields.add(.retailer, .text(issuer.name), 0.65, text.original[issuer.line])
            fields.add(.provider, .text(issuer.name), 0.6, text.original[issuer.line])
        }
        let purchaseDate = RomanianFieldExtractor.labelledDate(["data vanzarii", "data cumpararii", "data achizitiei", "data livrarii", "data:"], in: text, window: years).map { ($0.day, $0.source, 0.75) }
            ?? RomanianFieldExtractor.allDates(in: text, window: years).first.map { ($0.day, text.original[$0.line], 0.55) }
        if let purchaseDate {
            fields.add(.purchaseDate, .day(purchaseDate.0), purchaseDate.2, purchaseDate.1)
        }
        if let total = RomanianFieldExtractor.total(in: text) {
            fields.add(.purchasePrice, .money(total.money), Self.confidence(total.strong ? 0.8 : 0.65, ambiguous: total.ambiguous), total.source)
        }
        if let serial = RomanianFieldExtractor.serialNumber(in: text) {
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
        if let warranty = RomanianFieldExtractor.warrantyMonths(in: text) {
            fields.add(.warrantyMonths, .number(Decimal(warranty.months)), 0.75, warranty.source)
            if let start = fields.day(.purchaseDate), let until = start.addingMonths(warranty.months) {
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
    func day(_ key: CaptureFieldKey) -> CaptureDay? { fields.first { $0.key == key }?.value.day }
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
            if existing.value == candidate.value {
                result[index] = ReadingArbiter.agreeing(existing, candidate)
            } else if prefers(candidate, over: existing) {
                result[index] = candidate
            }
        }
        return result
    }
}
