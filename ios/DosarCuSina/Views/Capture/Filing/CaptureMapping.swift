import Foundation

/// How what capture read lands in the binder's own vocabulary: capture's
/// template and blueprint names to the built-in keys, capture fields to
/// template fields, capture values to field values. One table, used by the
/// review screen and by the save.
enum CaptureMapping {
    // MARK: Templates and blueprints

    /// The built-in template a capture suggestion names. Capture uses its own
    /// plural names for a few categories.
    static func templateKey(_ captureKey: String) -> String {
        switch captureKey {
        case "warranties", "warranty": return BuiltInTemplates.Key.purchase
        case "subscriptions": return BuiltInTemplates.Key.subscription
        default: return captureKey
        }
    }

    /// The template blueprint a capture suggestion names, when the binder has one.
    static func blueprintKey(_ captureKey: String) -> String? {
        switch captureKey {
        case "rca": return "vehicle.rca"
        case "itp": return "vehicle.itp"
        case "casco": return "vehicle.casco"
        case "padPolicy": return "home.pad"
        case "passportRenewal", "identityCardRenewal", "drivingLicenceRenewal": return "document.renew"
        case "petVaccine": return "pet.vaccine"
        default: return nil
        }
    }

    /// The built-in template a document kind belongs to, for "where it goes".
    static func templateKey(for kind: CaptureDocumentKind) -> String? {
        switch kind {
        case .passport, .identityCard, .drivingLicence: return BuiltInTemplates.Key.documents
        case .vehicleRegistration, .rcaPolicy, .itpReport, .serviceInvoice: return BuiltInTemplates.Key.vehicle
        case .utilityInvoice: return BuiltInTemplates.Key.home
        case .fiscalReceipt, .warrantyCertificate: return BuiltInTemplates.Key.purchase
        case .veterinaryRecord: return BuiltInTemplates.Key.pet
        case .medicalResult: return BuiltInTemplates.Key.health
        case .insurancePolicy, .other: return nil
        }
    }

    /// `document.type` for identity documents.
    static func documentType(for kind: CaptureDocumentKind) -> String? {
        switch kind {
        case .passport: return DocumentType.passport
        case .identityCard: return DocumentType.idCard
        case .drivingLicence: return DocumentType.drivingLicence
        default: return nil
        }
    }

    /// The field whose date the reminder follows, per document kind (the same rule capture's router uses).
    static func reminderField(for kind: CaptureDocumentKind) -> CaptureFieldKey? {
        switch kind {
        case .passport, .identityCard, .drivingLicence, .rcaPolicy, .insurancePolicy, .itpReport: return .expiryDate
        case .utilityInvoice: return .dueDate
        case .veterinaryRecord: return .nextDoseDate
        case .fiscalReceipt, .warrantyCertificate: return .warrantyUntil
        default: return nil
        }
    }

    /// Invoices with parts and jobs open the visit flow instead of the plain review.
    static func opensVisitFlow(_ kind: CaptureDocumentKind) -> Bool {
        kind == .serviceInvoice || kind == .veterinaryRecord
    }

    // MARK: Fields

    /// Template fields a capture field can fill, most specific first.
    private static let candidates: [CaptureFieldKey: [String]] = [
        .licensePlate: ["vehicle.plate"],
        .vin: ["vehicle.vin"],
        .make: ["vehicle.make"],
        .model: ["vehicle.model"],
        .odometer: ["vehicle.odometer"],
        .policyNumber: ["home.policyNumber"],
        .claimsPhone: ["home.claimsPhone"],
        .documentNumber: ["document.number"],
        .personalNumber: ["document.personalNumber"],
        .birthDate: ["document.birthDate"],
        .sex: ["document.sex"],
        .nationality: ["document.nationality"],
        .licenceCategories: ["document.categories"],
        .issueDate: ["document.issueDate"],
        .issuer: ["document.issuer"],
        .podCode: ["home.pod"],
        .clcCode: ["home.clc"],
        .microchip: ["pet.microchip"],
        .serialNumber: ["purchase.serial"],
        .productName: ["purchase.model"],
        .warrantyMonths: ["purchase.warrantyMonths"],
    ]

    /// Field roles a capture field can fill when the template has no specific match.
    private static func role(for key: CaptureFieldKey) -> FieldRole? {
        switch key.role {
        case .purchaseDate: return .purchaseDate
        case .purchasePrice: return .purchasePrice
        case .retailer: return .retailer
        case .warrantyUntil: return .warrantyUntil
        case .expiry: return .expiryDate
        case .keyFact, .title, .none: return nil
        }
    }

    /// Where a vehicle policy's details go, by its cover: RCA and CASCO each keep
    /// their own insurer, policy number and claims phone.
    private static let vehicleCoverFields: [String: [CaptureFieldKey: String]] = [
        "RCA": [.provider: "vehicle.insurer", .policyNumber: "vehicle.policyNumber", .claimsPhone: "vehicle.claimsPhone"],
        "CASCO": [.provider: "vehicle.cascoInsurer", .policyNumber: "vehicle.cascoPolicyNumber", .claimsPhone: "vehicle.cascoClaimsPhone"],
    ]
    private static let vehiclePolicyFields = Set(vehicleCoverFields.values.flatMap(\.values))

    /// The template field a capture field fills, if any. `coverage` is the policy's
    /// cover as read ("RCA", "CASCO", …), which decides where a vehicle policy's details go.
    static func fieldKey(for key: CaptureFieldKey, kind: CaptureDocumentKind, in template: TemplateDefinition, coverage: String? = nil) -> String? {
        let isPolicy = kind == .rcaPolicy || kind == .insurancePolicy
        if isPolicy, [.provider, .policyNumber, .claimsPhone].contains(key),
           vehiclePolicyFields.contains(where: { template.field($0) != nil }) {
            // A vehicle: the cover picks the fields; an unknown cover fills none, never RCA's.
            let cover = (coverage ?? (kind == .rcaPolicy ? "RCA" : "")).uppercased()
            return vehicleCoverFields[cover]?[key].flatMap { template.field($0) != nil ? $0 : nil }
        }
        // The insurer named on a policy goes into the insurer field.
        if key == .provider, isPolicy {
            return template.field(withRole: .issuer)?.key
        }
        // A policy's end date is the obligation's date, not an asset field.
        if key == .expiryDate, kind == .rcaPolicy || kind == .insurancePolicy || kind == .itpReport {
            return nil
        }
        if let match = candidates[key]?.first(where: { template.field($0) != nil }) {
            return match
        }
        return role(for: key).flatMap { template.field(withRole: $0)?.key }
    }

    /// The field value for a template field, converted to the field's type.
    static func fieldValue(_ value: CaptureValue, for field: FieldDefinition) -> FieldValue? {
        switch (field.type.valueKind, value) {
        case (.text, .text(let text)):
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : .text(trimmed)
        case (.text, .number(let number)):
            return .text(NSDecimalNumber(decimal: number).stringValue)
        case (.date, .day(let day)):
            return .date(calendarDay(day))
        case (.money, .money(let money)):
            return .money(Money(money.amount, currency: money.currencyCode))
        case (.number, .number(let number)):
            return .number(NSDecimalNumber(decimal: number).doubleValue)
        case (.number, .metric(let number, _)):
            return .number(NSDecimalNumber(decimal: number).doubleValue)
        case (.number, .money(let money)):
            return .number(NSDecimalNumber(decimal: money.amount).doubleValue)
        default:
            return nil
        }
    }

    static func calendarDay(_ day: CaptureDay) -> CalendarDay {
        CalendarDay(year: day.year, month: day.month, day: day.day)
    }

    static func money(_ money: CaptureMoney) -> Money {
        Money(money.amount, currency: money.currencyCode)
    }

    /// Values compared without spaces, dashes or case, so "B 123 ABC" finds "B-123-ABC".
    static func normalizedIdentifier(_ text: String) -> String {
        text.uppercased().filter { $0.isLetter || $0.isNumber }
    }

    /// The provider trade for a document's issuer, when it is someone worth keeping in Oameni.
    static func providerTrade(for kind: CaptureDocumentKind) -> ProviderTrade? {
        switch kind {
        case .serviceInvoice: return .mechanic
        case .itpReport: return .inspectionStation
        case .veterinaryRecord: return .vet
        case .medicalResult: return .doctor
        default: return nil
        }
    }

    /// How the document is filed.
    static func documentKind(for kind: CaptureDocumentKind) -> DocumentKind {
        DocumentKind(capturedKind: kind)
    }

    /// A name a person recognizes, used as the document title and a new section's name.
    static func defaultTitle(for kind: CaptureDocumentKind, fields: [CaptureFieldKey: CaptureValue]) -> String {
        let provider = fields[.provider]?.text
        // Identity documents carry their holder: "Carte de identitate – Manole Corina Ioana".
        if kind.isIdentityDocument, let holder = holderName(fields) {
            return DocumentNaming.name(document: kindTitle(kind), holder: holder)
        }
        switch kind {
        case .passport: return String(localized: "Pașaport")
        case .identityCard: return String(localized: "Carte de identitate")
        case .drivingLicence: return String(localized: "Permis de conducere")
        case .vehicleRegistration: return String(localized: "Certificat de înmatriculare")
        case .rcaPolicy:
            if let year = fields[.startDate]?.day?.year ?? fields[.issueDate]?.day?.year { return String(localized: "Poliță RCA \(String(year))") }
            return String(localized: "Poliță RCA")
        case .insurancePolicy: return String(localized: "Poliță de asigurare")
        case .utilityInvoice, .serviceInvoice:
            return provider.map { String(localized: "Factură \($0)") } ?? String(localized: "Factură")
        case .fiscalReceipt: return fields[.productName]?.text ?? String(localized: "Bon fiscal")
        case .warrantyCertificate: return fields[.productName]?.text ?? String(localized: "Certificat de garanție")
        case .itpReport: return String(localized: "Raport ITP")
        case .veterinaryRecord: return String(localized: "Fișă veterinar")
        case .medicalResult: return String(localized: "Rezultat analize")
        case .other: return String(localized: "Document")
        }
    }

    /// What the document is, in a few words, for the review header.
    static func kindTitle(_ kind: CaptureDocumentKind) -> String {
        switch kind {
        case .passport: return String(localized: "Pașaport")
        case .identityCard: return String(localized: "Carte de identitate")
        case .drivingLicence: return String(localized: "Permis de conducere")
        case .vehicleRegistration: return String(localized: "Talon (certificat de înmatriculare)")
        case .rcaPolicy: return String(localized: "Poliță RCA")
        case .insurancePolicy: return String(localized: "Poliță de asigurare")
        case .utilityInvoice: return String(localized: "Factură de utilități")
        case .serviceInvoice: return String(localized: "Factură de service")
        case .fiscalReceipt: return String(localized: "Bon fiscal")
        case .warrantyCertificate: return String(localized: "Certificat de garanție")
        case .itpReport: return String(localized: "Raport ITP")
        case .veterinaryRecord: return String(localized: "Fișă de la veterinar")
        case .medicalResult: return String(localized: "Rezultat medical")
        case .other: return String(localized: "Alt document")
        }
    }

    /// The label a capture field gets on the review screen.
    static func label(for key: CaptureFieldKey) -> String {
        switch key {
        case .documentNumber: return String(localized: "Serie și număr")
        case .documentCode: return String(localized: "Tip document")
        case .issuingCountry: return String(localized: "Țara")
        case .nationality: return String(localized: "Cetățenie")
        case .surname: return String(localized: "Nume de familie")
        case .givenNames: return String(localized: "Prenume")
        case .holderName: return String(localized: "Titular")
        case .birthDate: return String(localized: "Data nașterii")
        case .sex: return String(localized: "Sex")
        case .personalNumber: return String(localized: "CNP")
        case .licenceCategories: return String(localized: "Categorii")
        case .issueDate: return String(localized: "Data emiterii")
        case .startDate: return String(localized: "Valabil de la")
        case .expiryDate: return String(localized: "Valabil până la")
        case .dueDate: return String(localized: "De plătit până la")
        case .issuer: return String(localized: "Emis de")
        case .provider: return String(localized: "Furnizor")
        case .providerTaxID: return String(localized: "CUI furnizor")
        case .providerPhone: return String(localized: "Telefon furnizor")
        case .total: return String(localized: "Total")
        case .lineItems: return String(localized: "Ce s-a făcut")
        case .invoiceNumber: return String(localized: "Număr factură")
        case .paymentCode: return String(localized: "Cod de plată")
        case .policyNumber: return String(localized: "Număr poliță")
        case .claimsPhone: return String(localized: "Telefon pentru daune")
        case .coverageType: return String(localized: "Tip asigurare")
        case .bonusMalusClass: return String(localized: "Clasă bonus-malus")
        case .licensePlate: return String(localized: "Număr de înmatriculare")
        case .vin: return String(localized: "Serie de șasiu (VIN)")
        case .make: return String(localized: "Marcă")
        case .model: return String(localized: "Model")
        case .firstRegistrationDate: return String(localized: "Prima înmatriculare")
        case .odometer: return String(localized: "Kilometraj")
        case .clientCode: return String(localized: "Cod client")
        case .podCode: return String(localized: "Cod loc de consum (POD)")
        case .clcCode: return String(localized: "Cod loc de consum gaze (CLC)")
        case .meterIndex: return String(localized: "Index contor")
        case .productName: return String(localized: "Produs")
        case .serialNumber: return String(localized: "Serie")
        case .retailer: return String(localized: "Magazin")
        case .purchaseDate: return String(localized: "Data cumpărării")
        case .purchasePrice: return String(localized: "Preț")
        case .warrantyMonths: return String(localized: "Garanție (luni)")
        case .warrantyUntil: return String(localized: "Garanție până la")
        case .petName: return String(localized: "Nume animal")
        case .microchip: return String(localized: "Microcip")
        case .vaccineName: return String(localized: "Vaccin")
        case .nextDoseDate: return String(localized: "Următoarea doză")
        default: return key.rawValue
        }
    }

    // MARK: Review

    /// The order fields are shown in the review: who, then the document, then the dates.
    /// Anything not listed follows in the order it was read.
    static let reviewOrder: [CaptureFieldKey] = [
        .surname, .givenNames, .personalNumber, .birthDate, .sex, .nationality,
        .documentNumber, .licenceCategories, .issuer, .issueDate, .startDate, .expiryDate,
    ]

    /// Whether the review shows a field. Everything read is shown (identity documents
    /// sit behind Face ID), except what has its own place or repeats other fields.
    static func isShownInReview(_ key: CaptureFieldKey, among keys: Set<CaptureFieldKey>) -> Bool {
        switch key {
        // Bookkeeping, not something read off the page: filing uses it, people don't need to check it.
        case .lineItems, .documentCode, .issuingCountry, .documentVariant: return false
        case .holderName: return !keys.contains(.surname) && !keys.contains(.givenNames)
        default: return true
        }
    }

    /// A value as a person reads it: "SP1236343", "6 aprilie 2035".
    static func displayText(_ value: CaptureValue) -> String {
        switch value {
        case .text(let text): return text
        case .day(let day):
            return day.date().map { $0.formatted(.dateTime.day().month(.wide).year().locale(.dosarDefault)) } ?? day.description
        case .money(let amount): return Self.money(amount).formattedCompact()
        case .number(let number): return NSDecimalNumber(decimal: number).stringValue
        case .metric(let number, let unit): return "\(NSDecimalNumber(decimal: number).stringValue) \(unit)"
        case .lineItems(let items): return items.map(\.description).joined(separator: ", ")
        }
    }

    // MARK: Holders

    /// The holder as printed on Romanian documents, surname first, in title case with
    /// diacritics kept: "MANOLE" "CORINA IOANA" → "Manole Corina Ioana".
    static func holderName(_ fields: [CaptureFieldKey: CaptureValue]) -> String? {
        let parts = [fields[.surname]?.text, fields[.givenNames]?.text].compactMap { $0 }
        let raw = parts.isEmpty ? fields[.holderName]?.text : parts.joined(separator: " ")
        guard let raw else { return nil }
        let name = titleCased(raw)
        return name.isEmpty ? nil : name
    }

    /// "ION-ANDREI ȘTEFĂNESCU" → "Ion-Andrei Ștefănescu". Words start after spaces, hyphens and apostrophes.
    static func titleCased(_ text: String) -> String {
        let romanian = Locale(identifier: "ro_RO")
        var result = ""
        var startsWord = true
        for character in text.trimmingCharacters(in: .whitespacesAndNewlines) {
            if character.isWhitespace {
                if !result.hasSuffix(" ") { result.append(" ") }
                startsWord = true
                continue
            }
            let piece = String(character)
            result += startsWord ? piece.uppercased(with: romanian) : piece.lowercased(with: romanian)
            startsWord = character == "-" || character == "'" || character == "’"
        }
        return result
    }

    /// The words of a name for comparing people: folded (no case, no diacritics), in any order.
    static func nameWords(_ name: String) -> [String] {
        CaptureText.fold(name)
            .components(separatedBy: CharacterSet.letters.inverted)
            .filter { !$0.isEmpty }
    }

    /// The member a holder's document belongs to: the one with exactly the holder's
    /// names, in any order, or else the only one whose names are all among the holder's
    /// (at least two, including the surname), so "Corina Manole" matches "Manole Corina Ioana".
    static func matchingMember(holderSurname surname: String?, holderName: String, among members: [(id: UUID, name: String)]) -> UUID? {
        let holder = nameWords(holderName)
        guard !holder.isEmpty else { return nil }
        let holderSet = Set(holder)
        if let exact = members.first(where: { nameWords($0.name).sorted() == holder.sorted() }) { return exact.id }
        let surnameWords = Set(surname.map(nameWords) ?? [])
        let partial = members.filter { member in
            let words = Set(nameWords(member.name))
            return words.count >= 2 && words.isSubset(of: holderSet) && (surnameWords.isEmpty || !words.isDisjoint(with: surnameWords))
        }
        return partial.count == 1 ? partial[0].id : nil
    }
}
