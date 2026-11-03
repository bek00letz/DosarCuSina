import Foundation

/// How what capture read lands in the binder's own fields: capture fields to template
/// fields, capture values to field values, and the words the review shows. What a kind
/// of document means (its category, its deadline, its title) is the kind's profile
/// (`CaptureKindProfile`), not this.
enum CaptureMapping {
    // MARK: Kinds

    /// A name a person recognizes, used as the document title and a new section's name.
    /// Identity documents carry their holder: "Carte de identitate – Manole Corina Ioana".
    static func defaultTitle(for kind: CaptureDocumentKind, fields: [CaptureFieldKey: CaptureValue]) -> String {
        if kind.isIdentityDocument, let holder = holderName(fields) {
            return DocumentNaming.name(document: kind.profile.title, holder: holder)
        }
        return kind.profile.defaultTitle(fields: fields)
    }

    /// What the document is, in a few words, for the review header.
    static func kindTitle(_ kind: CaptureDocumentKind) -> String {
        kind.profile.title
    }

    // MARK: Fields

    /// Template fields a capture field can fill, most specific first. A policy's insurer,
    /// number and claims phone aren't here: they go where its deadline's facts say.
    static let candidates: [CaptureFieldKey: [String]] = [
        .licensePlate: [VehicleFields.plate],
        .vin: [VehicleFields.vin],
        .make: [VehicleFields.make],
        .model: [VehicleFields.model],
        .odometer: [VehicleFields.odometer],
        .documentNumber: [DocumentFields.number],
        .personalNumber: [DocumentFields.personalNumber],
        .birthDate: [DocumentFields.birthDate],
        .sex: [DocumentFields.sex],
        .nationality: [DocumentFields.nationality],
        .licenceCategories: [DocumentFields.categories],
        .issueDate: [DocumentFields.issueDate],
        .issuer: [DocumentFields.issuer],
        .podCode: [HomeFields.pod, SubscriptionFields.pod],
        .clcCode: [HomeFields.clc, SubscriptionFields.clc],
        .clientCode: [SubscriptionFields.clientCode],
        .contractNumber: [SubscriptionFields.contractNumber],
        .phoneNumber: [SubscriptionFields.phoneNumber],
        .serviceKind: [SubscriptionFields.service],
        .startDate: [SubscriptionFields.startDate],
        .minimumMonths: [SubscriptionFields.minimumMonths],
        .minimumPeriodEnd: [SubscriptionFields.minimumUntil],
        .monthlyPrice: [SubscriptionFields.price],
        .provider: [SubscriptionFields.provider],
        .microchip: [PetFields.microchip],
        .serialNumber: [PurchaseFieldKeys.serial],
        .productName: [PurchaseFieldKeys.model],
        .warrantyMonths: [PurchaseFieldKeys.warrantyMonths],
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

    /// The deadline fact a capture field is, on a policy.
    static func factRole(of key: CaptureFieldKey) -> BlueprintFactRole? {
        switch key {
        case .provider: .insurer
        case .policyNumber: .policyNumber
        case .claimsPhone: .claimsPhone
        default: nil
        }
    }

    /// The template field a capture field fills, if any. `deadline` is the blueprint the
    /// document sets in this template (`CaptureFilingPlan`):
    /// - a policy's insurer, number and claims phone go to the fields its deadline's facts
    ///   name, so a CASCO policy fills CASCO's and never RCA's; a policy whose deadline the
    ///   category doesn't keep fills none of a category's policy facts;
    /// - a deadline whose day is its own (an RCA, an ITP) keeps that day off the section.
    static func fieldKey(for key: CaptureFieldKey, kind: CaptureDocumentKind, in template: TemplateDefinition, deadline: ObligationBlueprint?) -> String? {
        let profile = kind.profile
        if profile.readsCover, let role = factRole(of: key) {
            if let facts = deadline?.facts {
                return facts.field(for: role).flatMap { template.field($0) != nil ? $0 : nil }
            }
            // No deadline here keeps this policy's facts: a category that keeps other
            // policies' facts gets none (a CASCO never lands in RCA's fields).
            guard !template.blueprints.contains(where: { $0.facts != nil }) else { return nil }
            return role == .insurer ? template.field(withRole: .issuer)?.key : nil
        }
        if key == profile.deadlineField {
            if let deadline, !deadline.isFieldDriven { return nil }
            if deadline == nil, profile.readsCover { return nil }
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

    /// The choices a capture field offers in the review, kept as their stable keys: the
    /// service a contract is for, the cover of a policy. Nil for a field typed as text.
    static func choices(for key: CaptureFieldKey, kind: CaptureDocumentKind) -> [ChoiceOption]? {
        switch key {
        case .serviceKind: ServiceKind.options
        case .coverageType: InsuranceCover.options.filter { kind.profile.covers.contains($0.key) }
        default: nil
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
        case .coverageType: return String(localized: "Ce acoperă")
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
        case .serviceKind: return String(localized: "Serviciu")
        case .contractNumber: return String(localized: "Număr contract")
        case .phoneNumber: return String(localized: "Număr de telefon")
        case .minimumMonths: return String(localized: "Perioadă minimă (luni)")
        case .minimumPeriodEnd: return String(localized: "Perioada minimă se termină")
        case .monthlyPrice: return String(localized: "Preț pe lună")
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
        .documentNumber, .licenceCategories, .issuer, .coverageType, .issueDate, .startDate, .expiryDate,
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

    /// A value as a person reads it: "SP1236343", "6 aprilie 2035", "CASCO".
    static func displayText(_ value: CaptureValue) -> String {
        switch value {
        case .text(let text):
            if ServiceKind.all.contains(text) { return ServiceKind.label(for: text) ?? text }
            if InsuranceCover.all.contains(text) { return InsuranceCover.label(for: text) ?? text }
            return text
        case .day(let day):
            return DosarFormat.longDay(CalendarDay(year: day.year, month: day.month, day: day.day))
        case .money(let amount): return Self.money(amount).formattedCompact()
        case .number(let number): return NSDecimalNumber(decimal: number).stringValue
        case .metric(let number, let unit): return "\(NSDecimalNumber(decimal: number).stringValue) \(unit.label)"
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
        let romanian = Locale.dosarDefault
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
        RomanianText.fold(name)
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

