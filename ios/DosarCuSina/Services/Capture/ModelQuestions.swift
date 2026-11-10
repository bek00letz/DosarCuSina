import Foundation

// What a language model is asked about a document, the same whoever answers: Apple's
// on-device model, which reads the text the phone recognised, and the person's AI
// provider, which sees the page. Each field is described once, here (its name, meaning,
// type and format), and asked for as its kind's profile lists it (`CaptureKindProfile`).
// The answers go through one mapper (`ModelAnswerMapper`), then `ReadingArbiter`.

/// How a field's value is written in an answer, and how it is checked.
enum ModelFieldFormat: Hashable, Sendable {
    case text
    case name
    case date
    case personalNumber
    case documentNumber
    case sex
    case country
    case categories
    case money
    case integer
    /// A meter's index, as printed, decimals and all: read by the one number reader as a
    /// meter index (`RomanianNumber`), so it is read the way the phone reads a bill.
    case meterIndex
    case lineItems
    case vin
    case plate
    case phone
    /// One of the service keys (`ServiceKind`).
    case serviceKind
    /// One of the cover keys (`InsuranceCover`).
    case coverage
    /// The machine-readable zone's lines, checked by their own digits.
    case machineReadableZone
    /// A bank card's last four digits, and never more.
    case cardLastFour
    /// One of the card network keys (`PaymentCardNetwork`).
    case cardNetwork
}

/// One field a model is asked for.
struct ModelField: Hashable, Sendable {
    /// The answer's property: the field key's raw value, or `machineReadableZone`.
    let name: String
    let key: CaptureFieldKey?
    let format: ModelFieldFormat
    let description: String
}

/// What a model is asked about a document of one kind: exactly the fields its profile
/// lists (`CaptureKindProfile.expectedKeys`), in its order, each described once. A reader
/// that sees the page is also asked for the machine-readable zone, which its own check
/// digits prove; a reader of the phone's text has nothing to add to the phone's own
/// reading of the zone.
struct ModelQuestions: Sendable {

    /// What the reader sees, which decides what its answers are worth (`ModelAnswerMapper`).
    enum Reader: Sendable, Equatable {
        /// The page itself: the person's AI provider. It may read what the phone misread.
        case page
        /// Only the text the phone recognised: Apple's on-device model. What isn't in that
        /// text, it can't have read.
        case text

        var tier: CaptureTier {
            switch self {
            case .page: .cloudModel
            case .text: .onDeviceModel
            }
        }
    }

    /// The kind asked about: the phone's guess, when the reader is asked every kind's fields.
    let kind: CaptureDocumentKind
    let fields: [ModelField]
    let reader: Reader

    static let kindName = "documentKind"
    static let zoneName = "machineReadableZone"
    /// The currencies an amount is asked in (`ModelAnswerMapper.normalizedCurrency` reads them back).
    static let currencies = ["RON", "EUR", "USD"]

    init(kind: CaptureDocumentKind, fields: [ModelField], reader: Reader) {
        self.kind = kind
        self.fields = fields
        self.reader = reader
    }

    /// The questions about a document of `kind`, exactly as its profile lists them.
    init(kind: CaptureDocumentKind, reader: Reader) {
        self.init(kind: kind, fields: Self.fields(of: kind, reader: reader), reader: reader)
    }

    /// The fields a document of `kind` carries, as its profile lists them. A personal
    /// document's say where its templates find each value printed.
    static func fields(of kind: CaptureDocumentKind, reader: Reader) -> [ModelField] {
        var fields = kind.expectedKeys.map { key in
            let format = format(of: key)
            var description = description(of: key, format: format)
            if kind.isPersonalDocument {
                let printed = IdentityTemplates.labels(of: key, for: kind).compactMap { wording -> String? in
                    switch wording {
                    case .words(let words): "\"\(words)\""
                    case .numbered(let number): "field \(number)."
                    }
                }.prefix(2).joined(separator: " or ")
                if !printed.isEmpty { description += " Printed at \(printed)." }
            }
            return ModelField(name: key.rawValue, key: key, format: format, description: description)
        }
        if reader == .page, IdentityTemplates.all.contains(where: { $0.kind == kind && !$0.machineReadableFormats.isEmpty }) {
            fields.append(ModelField(name: zoneName, key: nil, format: .machineReadableZone,
                                     description: "Each line of the machine-readable zone at the bottom, exactly as printed, every < included. Empty when there is none."))
        }
        return fields
    }

    // MARK: Each field, once

    /// How a field's value is written and checked, whatever the document.
    static func format(of key: CaptureFieldKey) -> ModelFieldFormat {
        switch key {
        case .issueDate, .startDate, .expiryDate, .dueDate, .purchaseDate, .warrantyUntil, .nextDoseDate, .firstRegistrationDate, .birthDate,
             .minimumPeriodEnd: .date
        case .total, .purchasePrice, .monthlyPrice: .money
        case .warrantyMonths, .odometer, .minimumMonths: .integer
        case .meterIndex: .meterIndex
        case .serviceKind: .serviceKind
        case .coverageType: .coverage
        case .lineItems: .lineItems
        case .vin: .vin
        case .licensePlate: .plate
        case .claimsPhone, .providerPhone, .phoneNumber: .phone
        case .personalNumber: .personalNumber
        case .surname, .givenNames, .holderName: .name
        case .documentNumber: .documentNumber
        case .sex: .sex
        case .nationality, .issuingCountry: .country
        case .licenceCategories: .categories
        case .cardLastFour: .cardLastFour
        case .cardNetwork: .cardNetwork
        default: .text
        }
    }

    /// What a field is and how to write it, for every model.
    static func description(of key: CaptureFieldKey, format: ModelFieldFormat) -> String {
        let what: String = switch key {
        case .provider: "The company, clinic or authority that issued the document, as printed (not the customer)."
        case .retailer: "The shop that sold the product, as printed."
        case .policyNumber: "The insurance policy's own series and number (\"Seria … nr. …\", \"Seria și numărul\", or under "
            + "\"Codul țării / Codul asigurătorului / Numărul\"), never a registration, contract or identification number."
        case .invoiceNumber: "The invoice's series and number."
        case .documentNumber: "The document's own series and number (an identity card's \"SERIA XT NR 123456\" is XT123456). "
            + "Null on an insurance policy, an invoice or a contract: their numbers are policyNumber, invoiceNumber and contractNumber."
        case .civNumber: "The series and number of the vehicle's identity card (CIV)."
        case .issueDate: "The date of issue."
        case .startDate: "The first day of validity, coverage or of the contract."
        case .expiryDate: "The last day of validity."
        case .dueDate: "The payment due date."
        case .purchaseDate: "The date of purchase."
        case .warrantyUntil: "The last day of the warranty."
        case .nextDoseDate: "The date of the next vaccine or booster."
        case .firstRegistrationDate: "The date of first registration."
        case .birthDate: "The holder's date of birth."
        case .total: "The total amount to pay or paid."
        case .purchasePrice: "The price paid."
        case .claimsPhone: "The phone number for claims or assistance."
        case .licensePlate: "The Romanian registration plate, e.g. B 123 ABC."
        case .vin: "The 17-character vehicle identification number."
        case .make: "The vehicle make."
        case .model: "The vehicle model."
        case .odometer: "The odometer reading in kilometres."
        case .clientCode: "The client code."
        case .contractNumber: "The contract's number (or the addendum's), as printed."
        case .serviceKind: "What the service is: gas, electricity, water, fixed internet or TV, a mobile phone plan, or something else."
        case .coverageType: "What the policy covers: \(InsuranceCover.rca) (compulsory motor insurance), \(InsuranceCover.casco) (motor damage), "
            + "\(InsuranceCover.pad) (compulsory home insurance) or \(InsuranceCover.home) (optional home insurance)."
        case .providerTaxID: "The issuer's tax ID (CUI or CIF), digits only, without RO."
        case .phoneNumber: "The customer's own mobile phone number the plan is for (not the provider's support line)."
        case .minimumMonths: "The minimum contract period in months (perioada minimă), e.g. 24."
        case .minimumPeriodEnd: "The last day of the minimum contract period."
        case .monthlyPrice: "The monthly price of the subscription or plan."
        case .supplyAddress: "The address where the gas, electricity, water, internet or TV is supplied (adresa locului de consum, "
            + "adresa de instalare), as printed. Never the customer's billing or correspondence address."
        case .directDebit: "Only if the bill states that it is paid by direct debit (the bank pays it automatically), "
            + "that statement copied as printed. Null when it isn't, and for an offer or invitation to set up direct debit."
        case .podCode: "The POD code of the consumption point."
        case .clcCode: "The CLC code of the consumption point."
        case .meterIndex: "The meter's new index (the current reading, not the previous one), exactly as printed, "
            + "with its decimals, e.g. \"12.345,678\"."
        case .productName: "The product bought."
        case .serialNumber: "The product's serial number or IMEI."
        case .warrantyMonths: "The warranty length in months."
        case .petName: "The animal's name."
        case .microchip: "The 15-digit microchip number."
        case .vaccineName: "The vaccine given."
        case .bonusMalusClass: "The policyholder's bonus-malus class, as printed: B0 to B8 or M1 to M8."
        case .policyholder: "The person or company the policy insures (the owner, \"Proprietar\" or \"Asigurat\"), as printed."
        case .lineItems: "Each part, service or labour line with its amount."
        case .surname: "The holder's surname."
        case .givenNames: "The holder's given names."
        case .personalNumber: "The holder's personal numeric code (CNP), 13 digits."
        case .sex: "The holder's sex."
        case .nationality: "The nationality, as a three-letter code when printed so."
        case .issuer: "The issuing authority."
        case .licenceCategories: "The driving licence categories."
        case .holderName: "The holder's full name, as printed."
        case .recordResult: "What the certificate says about the holder's record, copied as printed (for example that they don't appear in it)."
        case .cardLastFour: "Only the last four digits of the card number. Never the whole number, never the security code."
        case .cardNetwork: "The card network printed on the card: \(PaymentCardNetwork.visa), \(PaymentCardNetwork.mastercard), "
            + "\(PaymentCardNetwork.maestro), \(PaymentCardNetwork.amex) or \(PaymentCardNetwork.other)."
        default: "As printed."
        }
        let how: String = switch format {
        case .date: " As YYYY-MM-DD."
        case .sex: " M or F."
        case .personalNumber: " Digits only."
        case .categories: " Separated by commas, e.g. A, B, C."
        case .money: " Amount with a dot for decimals; currency as \(currencies.dropLast().joined(separator: ", ")) or \(currencies.last ?? "")."
        default: ""
        }
        // A value printed in parts is asked for whole, written one way (`CompositeValue`).
        let parts = CompositeValue.byKey[key].flatMap { $0.series == nil ? nil : " The series and the number together as one value, e.g. \($0.example)." } ?? ""
        return what + parts + how
    }

    /// What every model is told the kinds are, from their profiles.
    static var kindDescription: String {
        let kinds = CaptureDocumentKind.allCases.map { "\($0.rawValue) (\($0.profile.modelDescription))" }.joined(separator: ", ")
        return "What the document is: \(kinds)."
    }

    // MARK: Reading an answer's values

    /// A whole number from an answer: a JSON number that is whole, or text read by the one
    /// number reader ("45.724" km is 45724). Never cut short: 45,7 is refused.
    static func wholeNumber(_ raw: JSONValue, kind: NumberKind) -> Int? {
        switch raw {
        case .int(let value): return value
        case .number(let value): return value == value.rounded() ? Int(exactly: value) : nil
        case .string(let text): return RomanianNumber.value(text, as: kind, from: .document).flatMap { Int(exactly: NSDecimalNumber(decimal: $0).doubleValue) }
        default: return nil
        }
    }

    /// A meter's index from an answer, read the way the phone reads one on a bill: text
    /// through the one number reader as a meter index (decimals kept, a number that could
    /// read two ways marked), a JSON number as the plain machine form it is.
    static func meterIndex(_ raw: JSONValue) -> RomanianNumber.Reading? {
        switch raw {
        case .string(let text): return try? RomanianNumber.read(text, as: .meterIndex, from: .document).get()
        case .int(let value): return RomanianNumber.Reading(value: Decimal(value), isAmbiguous: false, needsCheck: false)
        case .number(let value):
            return RomanianNumber.canonical(String(value)).map { RomanianNumber.Reading(value: $0, isAmbiguous: false, needsCheck: false) }
        default: return nil
        }
    }
}
