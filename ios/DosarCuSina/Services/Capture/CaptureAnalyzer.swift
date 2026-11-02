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
        public let fields: [CaptureField]
        public let notices: [CaptureNotice]
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

    // MARK: - Analysis

    public func analyze(text rawText: String, barcodes: [CaptureBarcode] = [], referenceDate: Date = Date()) -> Analysis {
        let text = CaptureText(rawText)
        var notices: [CaptureNotice] = []
        var fields = FieldSet()

        let mrz = MRZParser.parse(text: rawText, referenceDate: referenceDate)
        let specialized = specializedParsers.lazy.compactMap { $0.parse(text) }.first

        let kind: CaptureDocumentKind
        let kindConfidence: Double
        if let specialized {
            kind = specialized.kind
            kindConfidence = 0.95
            fields.add(specialized.fields)
        } else {
            let classification = DocumentClassifier.classify(text: text, mrz: mrz)
            kind = classification.kind
            kindConfidence = classification.confidence
        }

        if let mrz {
            fields.add(mrzFields(mrz))
            if !mrz.allChecksValid { notices.append(.machineReadableZoneUnverified) }
        }

        switch kind {
        case .passport, .identityCard:
            if let period = RomanianFieldExtractor.validityPeriod(in: text) {
                fields.add(.expiryDate, .day(period.end), 0.7, period.source)
                fields.add(.issueDate, .day(period.start), 0.7, period.source)
            }
            if let expiry = RomanianFieldExtractor.labelledDate(["data expirarii", "date of expiry", "expira", "valabil pana"], in: text) {
                fields.add(.expiryDate, .day(expiry.day), 0.65, expiry.source)
            }
        case .drivingLicence:
            for (key, entry) in RomanianFieldExtractor.drivingLicenceFields(in: text).sorted(by: { $0.key.rawValue < $1.key.rawValue }) {
                fields.add(key, entry.0, 0.75, entry.1)
            }
            if let surname = fields.text(.surname) {
                let full = [fields.text(.givenNames), surname].compactMap { $0 }.joined(separator: " ")
                fields.add(.holderName, .text(full), 0.7, nil)
            }
        case .vehicleRegistration:
            addVehicleIdentity(text, into: &fields)
            for (key, entry) in RomanianFieldExtractor.registrationFields(in: text).sorted(by: { $0.key.rawValue < $1.key.rawValue }) {
                fields.add(key, entry.0, 0.65, entry.1)
            }
        case .rcaPolicy, .insurancePolicy:
            addInsurance(text, kind: kind, into: &fields)
        case .utilityInvoice:
            addInvoiceBasics(text, into: &fields)
            if let due = RomanianFieldExtractor.labelledDate(["scadent", "termen de plata", "data scadentei", "de platit pana la"], in: text) {
                fields.add(.dueDate, .day(due.day), 0.75, due.source)
            }
        case .serviceInvoice:
            addInvoiceBasics(text, into: &fields)
            addVehicleIdentity(text, into: &fields)
            addLineItems(text, into: &fields)
            if let odometer = RomanianFieldExtractor.odometer(in: text) {
                fields.add(.odometer, .metric(value: odometer.km, unit: "km"), odometer.labelled ? 0.8 : 0.55, odometer.source)
            }
        case .fiscalReceipt, .warrantyCertificate:
            addPurchase(text, kind: kind, into: &fields)
        case .itpReport:
            addVehicleIdentity(text, into: &fields)
            if let expiry = RomanianFieldExtractor.labelledDate(["valabila pana la", "valabil pana la", "urmatoarea inspectie", "data urmatoarei inspectii", "valabilitate"], in: text) {
                fields.add(.expiryDate, .day(expiry.day), 0.8, expiry.source)
            }
            if let odometer = RomanianFieldExtractor.odometer(in: text) {
                fields.add(.odometer, .metric(value: odometer.km, unit: "km"), odometer.labelled ? 0.8 : 0.55, odometer.source)
            }
            addIssuer(text, into: &fields)
            addIssueDate(text, into: &fields)
        case .veterinaryRecord:
            if let chip = RomanianFieldExtractor.microchip(in: text) {
                fields.add(.microchip, .text(chip.value), 0.85, chip.source)
            }
            if let index = text.lines(containing: ["vaccin", "antirabic"]).first {
                fields.add(.vaccineName, .text(text.original[index]), 0.55, text.original[index])
            }
            if let next = RomanianFieldExtractor.labelledDate(["rapel", "revaccinare", "urmatorul vaccin", "urmatoarea vaccinare", "valabil pana la"], in: text) {
                fields.add(.nextDoseDate, .day(next.day), 0.75, next.source)
            }
            addIssuer(text, into: &fields)
            addIssueDate(text, into: &fields)
        case .medicalResult:
            addIssuer(text, into: &fields)
            addIssueDate(text, into: &fields)
        case .other:
            addInvoiceBasics(text, into: &fields)
        }

        if kind == .utilityInvoice || kind == .serviceInvoice || kind == .other,
           let barcode = barcodes.first(where: { !$0.payload.isEmpty }) {
            fields.add(.paymentCode, .text(barcode.payload), 0.95, nil, tier: .deterministic)
        }

        if mrz == nil, text.joinedOriginal.filter(\.isLetter).count < 20 {
            notices.append(.littleTextRecognized)
        }

        return Analysis(text: text, kind: kind, kindConfidence: kindConfidence, fields: fields.fields, notices: notices)
    }

    // MARK: - Field groups

    private func mrzFields(_ mrz: MRZParser.Result) -> [CaptureField] {
        let tier: CaptureTier = mrz.allChecksValid ? .deterministic : .heuristic
        let source = "MRZ"
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

    private func addInvoiceBasics(_ text: CaptureText, into fields: inout FieldSet) {
        addIssuer(text, into: &fields)
        if let invoice = RomanianFieldExtractor.invoiceNumber(in: text) {
            fields.add(.invoiceNumber, .text(invoice.value), 0.7, invoice.source)
        }
        if let total = RomanianFieldExtractor.total(in: text) {
            fields.add(.total, .money(total.money), total.strong ? 0.8 : 0.6, total.source)
        }
        addIssueDate(text, into: &fields)
    }

    private func addIssuer(_ text: CaptureText, into fields: inout FieldSet) {
        if let taxID = RomanianFieldExtractor.taxID(in: text) {
            fields.add(.providerTaxID, .text(taxID.value), taxID.valid ? 0.97 : 0.5, text.original[taxID.line], tier: taxID.valid ? .deterministic : .heuristic)
        }
        if let issuer = RomanianFieldExtractor.issuerName(in: text) {
            fields.add(.provider, .text(issuer.name), 0.65, text.original[issuer.line])
        }
    }

    private func addIssueDate(_ text: CaptureText, into fields: inout FieldSet) {
        if let issue = RomanianFieldExtractor.labelledDate(["data emiterii", "data facturii", "data eliberarii", "emisa la", "data:"], in: text) {
            fields.add(.issueDate, .day(issue.day), 0.7, issue.source)
        } else if let first = RomanianFieldExtractor.allDates(in: text).first {
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

    private func addInsurance(_ text: CaptureText, kind: CaptureDocumentKind, into fields: inout FieldSet) {
        let haystack = text.joinedFolded
        if let insurer = insurerNames.first(where: { DocumentClassifier.containsWord($0.keyword, in: haystack) }) {
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
        if let period = RomanianFieldExtractor.validityPeriod(in: text) {
            fields.add(.startDate, .day(period.start), 0.75, period.source)
            fields.add(.expiryDate, .day(period.end), 0.8, period.source)
        } else if let expiry = RomanianFieldExtractor.labelledDate(["pana la", "expira", "data expirarii", "valabila pana"], in: text) {
            fields.add(.expiryDate, .day(expiry.day), 0.65, expiry.source)
        }
        if let premium = RomanianFieldExtractor.total(in: text) {
            fields.add(.total, .money(premium.money), premium.strong ? 0.75 : 0.5, premium.source)
        }
        if let classValue = RomanianFieldExtractor.bonusMalus(in: text) {
            fields.add(.bonusMalusClass, .text(classValue), 0.7, nil)
        }
        let coverage: String
        if kind == .rcaPolicy { coverage = "RCA" }
        else if haystack.contains("casco") { coverage = "CASCO" }
        else if DocumentClassifier.containsWord("pad", in: haystack) || haystack.contains("paid") { coverage = "PAD" }
        else { coverage = "Facultativă" }
        fields.add(.coverageType, .text(coverage), 0.7, nil)
        addVehicleIdentity(text, into: &fields)
    }

    private func addPurchase(_ text: CaptureText, kind: CaptureDocumentKind, into fields: inout FieldSet) {
        if let taxID = RomanianFieldExtractor.taxID(in: text) {
            fields.add(.providerTaxID, .text(taxID.value), taxID.valid ? 0.97 : 0.5, text.original[taxID.line], tier: taxID.valid ? .deterministic : .heuristic)
        }
        if let issuer = RomanianFieldExtractor.issuerName(in: text) {
            fields.add(.retailer, .text(issuer.name), 0.65, text.original[issuer.line])
            fields.add(.provider, .text(issuer.name), 0.6, text.original[issuer.line])
        }
        let purchaseDate = RomanianFieldExtractor.labelledDate(["data vanzarii", "data cumpararii", "data achizitiei", "data livrarii", "data:"], in: text).map { ($0.day, $0.source, 0.75) }
            ?? RomanianFieldExtractor.allDates(in: text).first.map { ($0.day, text.original[$0.line], 0.55) }
        if let purchaseDate {
            fields.add(.purchaseDate, .day(purchaseDate.0), purchaseDate.2, purchaseDate.1)
        }
        if let total = RomanianFieldExtractor.total(in: text) {
            fields.add(.purchasePrice, .money(total.money), total.strong ? 0.8 : 0.65, total.source)
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

    mutating func add(_ field: CaptureField) {
        if let index = fields.firstIndex(where: { $0.key == field.key }) {
            if FieldMerger.prefers(field, over: fields[index]) { fields[index] = field }
        } else {
            fields.append(field)
        }
    }

    mutating func add(_ key: CaptureFieldKey, _ value: CaptureValue, _ confidence: Double, _ source: String?, tier: CaptureTier = .heuristic) {
        add(CaptureField(key: key, value: value, confidence: confidence, sourceText: source, tier: tier))
    }

    func text(_ key: CaptureFieldKey) -> String? { fields.first { $0.key == key }?.value.text }
    func day(_ key: CaptureFieldKey) -> CaptureDay? { fields.first { $0.key == key }?.value.day }
}

// MARK: - Merging tiers

/// Combines fields from several tiers into one best answer per key.
public enum FieldMerger {

    /// A checksum-verified value is never replaced. Otherwise the more confident value wins,
    /// and on a tie the more reliable tier wins.
    static func prefers(_ candidate: CaptureField, over existing: CaptureField) -> Bool {
        if existing.tier == .deterministic && candidate.tier != .deterministic { return false }
        if candidate.tier == .deterministic && existing.tier != .deterministic { return true }
        if candidate.confidence != existing.confidence { return candidate.confidence > existing.confidence }
        return candidate.tier < existing.tier
    }

    /// Merges a later tier's fields into earlier ones. When two tiers agree on a value,
    /// the agreement raises confidence and keeps the earlier source text.
    public static func merge(_ base: [CaptureField], with incoming: [CaptureField]) -> [CaptureField] {
        var result = base
        for candidate in incoming {
            guard let index = result.firstIndex(where: { $0.key == candidate.key }) else {
                result.append(candidate)
                continue
            }
            let existing = result[index]
            if existing.value == candidate.value {
                result[index] = CaptureField(
                    key: existing.key,
                    value: existing.value,
                    confidence: max(existing.confidence, candidate.confidence) + 0.1,
                    sourceText: existing.sourceText ?? candidate.sourceText,
                    tier: min(existing.tier, candidate.tier)
                )
            } else if prefers(candidate, over: existing) {
                result[index] = candidate
            }
        }
        return result
    }
}
