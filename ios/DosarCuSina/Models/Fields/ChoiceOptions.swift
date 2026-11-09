import Foundation

/// One option of a choice field. Values store the stable `key`; screens show
/// the `label`. Keys are part of the `.dosar` contract: never rename them.
public struct ChoiceOption: Hashable, Sendable, Codable, Identifiable {
    /// Stable key, such as `vehicleUse.personal`.
    public var key: String
    public var label: String
    /// Other ways the value was written before keys existed (older backups,
    /// other languages). Matched without case or diacritics.
    public var aliases: [String]
    /// Offered only while another value matches, such as "Cazier fiscal" only for a cazier.
    public var appliesWhen: BlueprintCondition?

    public var id: String { key }

    public init(key: String, label: String, aliases: [String] = [], appliesWhen: BlueprintCondition? = nil) {
        self.key = key
        self.label = label
        self.aliases = aliases
        self.appliesWhen = appliesWhen
    }

    private enum CodingKeys: String, CodingKey { case key, label, aliases, appliesWhen }

    public init(from decoder: Decoder) throws {
        // Older template definitions listed options as plain text.
        if let text = try? decoder.singleValueContainer().decode(String.self) {
            self.init(key: text, label: text)
            return
        }
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            key: try c.decode(String.self, forKey: .key),
            label: try c.decode(String.self, forKey: .label),
            aliases: try c.decodeIfPresent([String].self, forKey: .aliases) ?? [],
            appliesWhen: try? c.decodeIfPresent(BlueprintCondition.self, forKey: .appliesWhen)
        )
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(key, forKey: .key)
        try c.encode(label, forKey: .label)
        if !aliases.isEmpty { try c.encode(aliases, forKey: .aliases) }
        try c.encodeIfPresent(appliesWhen, forKey: .appliesWhen)
    }

    /// Whether the option is offered for these values.
    public func isOffered(for values: FieldValues) -> Bool {
        appliesWhen?.isMet(by: values) ?? true
    }

    /// Whether `text` names this option: its key, its label or an alias.
    public func matches(_ text: String) -> Bool {
        if text == key { return true }
        let needle = Self.fold(text)
        guard !needle.isEmpty else { return false }
        return ([label] + aliases).contains { Self.fold($0) == needle }
    }

    /// Folded (`RomanianText.fold`), whitespace collapsed, signs kept (so "A+" and "A-" stay apart).
    static func fold(_ text: String) -> String {
        RomanianText.fold(text).split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }
}

extension Array where Element == ChoiceOption {
    /// The option for a stored key or for legacy display text.
    public func option(for text: String) -> ChoiceOption? {
        first { $0.key == text } ?? first { $0.matches(text) }
    }
}

// MARK: - Built-in option sets

private func option(_ key: String, _ label: String.LocalizationValue, _ aliases: [String] = [], when condition: BlueprintCondition? = nil) -> ChoiceOption {
    ChoiceOption(key: key, label: String(localized: label), aliases: aliases, appliesWhen: condition)
}

public enum VehicleUse {
    public static let personal = "vehicleUse.personal"
    public static let commercial = "vehicleUse.commercial"

    public static var options: [ChoiceOption] {
        [
            option(personal, "Personală", ["Personal", "Private"]),
            option(commercial, "Ridesharing sau taxi", ["Ridesharing", "Taxi", "Uber", "Bolt", "Comercial"]),
        ]
    }
}

public enum FuelType {
    public static let petrol = "fuel.petrol"
    public static let diesel = "fuel.diesel"
    public static let hybrid = "fuel.hybrid"
    public static let plugInHybrid = "fuel.plugInHybrid"
    public static let electric = "fuel.electric"
    public static let lpg = "fuel.lpg"

    public static var options: [ChoiceOption] {
        [
            option(petrol, "Benzină", ["Benzina", "Petrol", "Gasoline"]),
            option(diesel, "Motorină", ["Motorina", "Diesel"]),
            option(hybrid, "Hibrid", ["Hybrid", "HEV"]),
            option(plugInHybrid, "Hibrid plug-in", ["Plug-in Hybrid", "PHEV"]),
            option(electric, "Electric", ["EV", "Electrică"]),
            option(lpg, "GPL", ["LPG"]),
        ]
    }
}

public enum DocumentType {
    public static let idCard = "documentType.idCard"
    public static let passport = "documentType.passport"
    public static let drivingLicence = "documentType.drivingLicence"
    public static let euHealthCard = "documentType.euHealthCard"
    /// The national health insurance card (cardul național de asigurări sociale de sănătate).
    public static let nationalHealthCard = "documentType.nationalHealthCard"
    public static let greenCard = "documentType.greenCard"
    public static let bankCard = "documentType.bankCard"
    public static let eSignature = "documentType.eSignature"
    public static let criminalRecord = "documentType.criminalRecord"
    public static let other = "documentType.other"

    public static var options: [ChoiceOption] {
        [
            option(idCard, "Carte de identitate", ["Buletin", "CI", "ID card"]),
            option(passport, "Pașaport", ["Pasaport", "Passport"]),
            option(drivingLicence, "Permis de conducere", ["Permis", "Driving licence"]),
            option(euHealthCard, "Card european de sănătate", ["CEASS", "EHIC", "Card european de asigurări sociale de sănătate"]),
            option(nationalHealthCard, "Card național de sănătate", ["Card de sănătate", "Cardul de sănătate", "Card național de asigurări sociale de sănătate"]),
            option(greenCard, "Carte verde", ["Green card"]),
            option(bankCard, "Card bancar", ["Card"]),
            option(eSignature, "Semnătură electronică", ["Certificat digital", "Token"]),
            option(criminalRecord, "Cazier", ["Cazier judiciar"]),
            option(other, "Alt document", ["Altul"]),
        ]
    }

    /// The document's name for a type: "Carte de identitate", "Pașaport".
    public static func label(for type: String) -> String? {
        options.option(for: type)?.label
    }

    // MARK: Travel

    /// How long before its printed expiry a type of document stops being good for travel,
    /// in days (whole months count as calendar months, as a reminder's lead does: 180 is six
    /// months). Data, read by the catalog's reminder profile for the type, the deadline
    /// page and the trip check; no code asks for a type by name.
    ///
    /// Only a passport (every variant of it) has one: many countries refuse entry with less
    /// than six months left, and six months covers every country's rule, including those
    /// that ask for three. It is fixed, not a setting. An identity card is good for travel
    /// in the EU until it expires, and every other document keeps its plain expiry.
    public static let travelMargins: [String: Int] = [passport: 180]

    /// The travel margin of a type (its key, or a label stored by an earlier version); 0 when
    /// it is good for travel until it expires.
    public static func travelMarginDays(for type: String?) -> Int {
        guard let type, let key = options.option(for: type)?.key else { return 0 }
        return travelMargins[key] ?? 0
    }

    /// The travel margin of a document from its values: its type's (a variant has its type's).
    public static func travelMarginDays(in values: FieldValues) -> Int {
        travelMarginDays(for: values[typeFieldKey]?.textValue)
    }

    // MARK: Reading

    /// The types read only on the phone: never sent to the person's AI provider, not on
    /// "Citește mai bine", not by "Citește automat", not when pages are added. Data, read by
    /// `PhoneOnlyReading`, the one rule for whether a capture may go to the provider.
    ///
    /// Only a bank card: its photo shows the whole number, which the binder never keeps
    /// and never hands on, and the phone reads everything a card carries.
    public static let readOnPhoneOnly: Set<String> = [bankCard]

    /// Whether a type (its key, or a label stored by an earlier version) is read only on the phone.
    public static func isReadOnPhoneOnly(_ type: String?) -> Bool {
        guard let type, let key = options.option(for: type)?.key else { return false }
        return readOnPhoneOnly.contains(key)
    }

    // MARK: Sharing

    /// The types whose picture shows what must not be handed to just anyone: a bank card's
    /// whole number. Sending one ("Trimite") says so first. Data, read by the share sheet.
    public static let sharedWithCare: Set<String> = [bankCard]

    /// Whether sending a type's picture says to send it only to someone the person trusts.
    public static func isSharedWithCare(_ type: String?) -> Bool {
        guard let type, let key = options.option(for: type)?.key else { return false }
        return sharedWithCare.contains(key)
    }

    // MARK: Validity

    /// How long a kind of document is valid after it is issued, in months, when that is a
    /// documented rule rather than a date printed on it. Data, read by the documents
    /// category's expiry (`FieldDerivation.validityAfterIssue`) and by capture's review.
    ///
    /// Only the criminal record certificate (cazier judiciar): "Certificatele de cazier
    /// judiciar sunt valabile 6 luni de la data eliberării", as Romania states it in the
    /// European Commission's repository of public documents (entry 431105), under Legea
    /// nr. 290/2004 privind cazierul judiciar. A cazier fiscal or auto has no rule here.
    public static let validityMonthsAfterIssue: [String: Int] = [Variant.criminalRecordJudicial: 6]

    /// The months a document of this type and variant is valid after it is issued, if a rule says so.
    public static func validityMonths(type: String?, variant: String?) -> Int? {
        guard let type, let key = options.option(for: type)?.key else { return nil }
        if let variant, variants.contains(where: { $0.type == key && $0.option.key == variant }), let months = validityMonthsAfterIssue[variant] {
            return months
        }
        return validityMonthsAfterIssue[key]
    }

    /// Whether a type is dated by the day it was issued, not by an expiry printed on it: the
    /// type, or one of its variants, has a validity from its issue. "Scriu eu" asks for that
    /// day for every variant (a cazier judiciar, fiscal or auto), and the expiry follows only
    /// where a rule gives one.
    public static func isDatedByIssue(_ type: String?) -> Bool {
        guard let type, let key = options.option(for: type)?.key else { return false }
        return validityMonthsAfterIssue[key] != nil || variants(of: key).contains { validityMonthsAfterIssue[$0.key] != nil }
    }

    /// The last day a document issued on `issued` is valid by its rule: the same day,
    /// `validityMonths` later (a shorter month ends on its last day). Nil without a rule.
    public static func validUntil(issued: CalendarDay, type: String?, variant: String?, calendar: Calendar = .current) -> CalendarDay? {
        guard let months = validityMonths(type: type, variant: variant) else { return nil }
        return RecurrenceEngine.add(.months(months), to: issued, calendar: calendar)
    }

    // MARK: Variants

    /// The kinds of a document type that really differ: what the paper is called,
    /// how long it lasts or what it carries (only the electronic identity card has
    /// PIN codes). Data, read by the template, the add flow and the naming.
    public enum Variant {
        public static let idCardElectronic = "documentVariant.idCard.electronic"
        public static let idCardWithoutChip = "documentVariant.idCard.withoutChip"
        public static let passportElectronic = "documentVariant.passport.electronic"
        public static let passportTemporary = "documentVariant.passport.temporary"
        public static let bankCardDebit = "documentVariant.bankCard.debit"
        public static let bankCardCredit = "documentVariant.bankCard.credit"
        public static let criminalRecordJudicial = "documentVariant.criminalRecord.judicial"
        public static let criminalRecordFiscal = "documentVariant.criminalRecord.fiscal"
        public static let criminalRecordDriving = "documentVariant.criminalRecord.driving"
    }

    /// One variant: its option (offered only for its type) and, when it differs
    /// from the type's, the name the document takes.
    public struct VariantSpec: Sendable {
        public var type: String
        public var option: ChoiceOption
        public var documentName: String?
    }

    public static var variants: [VariantSpec] {
        func variant(_ type: String, _ key: String, _ label: String.LocalizationValue, name: String.LocalizationValue? = nil) -> VariantSpec {
            VariantSpec(type: type, option: option(key, label, when: BlueprintCondition(field: typeFieldKey, oneOf: [type])),
                        documentName: name.map { String(localized: $0) })
        }
        return [
            variant(idCard, Variant.idCardElectronic, "Electronică, cu cip (CEI)"),
            variant(idCard, Variant.idCardWithoutChip, "Fără cip"),
            variant(passport, Variant.passportElectronic, "Simplu electronic"),
            variant(passport, Variant.passportTemporary, "Simplu temporar", name: "Pașaport temporar"),
            variant(bankCard, Variant.bankCardDebit, "De debit", name: "Card de debit"),
            variant(bankCard, Variant.bankCardCredit, "De credit", name: "Card de credit"),
            variant(criminalRecord, Variant.criminalRecordJudicial, "Judiciar", name: "Cazier judiciar"),
            variant(criminalRecord, Variant.criminalRecordFiscal, "Fiscal", name: "Cazier fiscal"),
            variant(criminalRecord, Variant.criminalRecordDriving, "Auto", name: "Cazier auto"),
        ]
    }

    /// The field that holds the type, which variants depend on.
    public static let typeFieldKey = "document.type"
    /// The field that holds the variant.
    public static let variantFieldKey = "document.variant"

    /// Every variant option, each offered only for its own type.
    public static var variantOptions: [ChoiceOption] { variants.map(\.option) }

    /// The types that have variants, so the variant question appears only for them.
    public static var typesWithVariants: [String] {
        variants.reduce(into: [String]()) { types, spec in if !types.contains(spec.type) { types.append(spec.type) } }
    }

    /// The variants of one type, in order.
    public static func variants(of type: String) -> [ChoiceOption] {
        variants.filter { $0.type == type }.map(\.option)
    }

    /// What the document is called: the variant's own name ("Cazier fiscal"), else the type's.
    public static func documentName(type: String, variant: String?) -> String {
        if let variant, let spec = variants.first(where: { $0.type == type && $0.option.key == variant }), let name = spec.documentName {
            return name
        }
        return label(for: type) ?? String(localized: "Document")
    }
}

public enum PetSpecies {
    public static let cat = "species.cat"
    public static let dog = "species.dog"
    public static let other = "species.other"

    public static var options: [ChoiceOption] {
        [
            option(cat, "Pisică", ["Pisica", "Cat", "Motan"]),
            option(dog, "Câine", ["Caine", "Dog", "Cățel"]),
            option(other, "Alt animal", ["Altul"]),
        ]
    }
}

public enum BloodType {
    public static var options: [ChoiceOption] {
        [
            ChoiceOption(key: "bloodType.0Positive", label: "0 I+", aliases: ["O+", "0+", "O I+"]),
            ChoiceOption(key: "bloodType.0Negative", label: "0 I−", aliases: ["O-", "0-", "0 I-", "O I-"]),
            ChoiceOption(key: "bloodType.aPositive", label: "A II+", aliases: ["A+"]),
            ChoiceOption(key: "bloodType.aNegative", label: "A II−", aliases: ["A-", "A II-"]),
            ChoiceOption(key: "bloodType.bPositive", label: "B III+", aliases: ["B+"]),
            ChoiceOption(key: "bloodType.bNegative", label: "B III−", aliases: ["B-", "B III-"]),
            ChoiceOption(key: "bloodType.abPositive", label: "AB IV+", aliases: ["AB+"]),
            ChoiceOption(key: "bloodType.abNegative", label: "AB IV−", aliases: ["AB-", "AB IV-"]),
        ]
    }
}

public enum BillingCycle {
    public static let monthly = "billing.monthly"
    public static let quarterly = "billing.quarterly"
    public static let yearly = "billing.yearly"

    public static var options: [ChoiceOption] {
        [
            option(monthly, "Lunar", ["Lunară", "Monthly"]),
            option(quarterly, "Trimestrial", ["Trimestrială", "Quarterly"]),
            option(yearly, "Anual", ["Anuală", "Yearly", "Annual"]),
        ]
    }

    /// How many months one cycle lasts; monthly when unknown.
    public static func months(_ key: String?) -> Int {
        switch key.flatMap({ options.option(for: $0)?.key }) {
        case yearly: return 12
        case quarterly: return 3
        default: return 1
        }
    }
}

/// What an ongoing contract is for. Gas, electricity, water and fixed internet or TV
/// are tied to an address, so they live under the home they supply; a mobile plan
/// lives in Abonamente, like a streaming service. Capture names the service with
/// these same keys (`CaptureFieldKey.serviceKind`).
public enum ServiceKind {
    public static let gas = "service.gas"
    public static let electricity = "service.electricity"
    public static let water = "service.water"
    public static let internetTV = "service.internetTV"
    public static let mobile = "service.mobile"
    public static let other = "service.other"

    public static let all = [gas, electricity, water, internetTV, mobile, other]

    public static var options: [ChoiceOption] {
        [
            option(gas, "Gaz", ["Gaze", "Gaze naturale"]),
            option(electricity, "Curent", ["Energie electrică", "Electricitate"]),
            option(water, "Apă", ["Apă și canal", "Apă-canal"]),
            option(internetTV, "Internet și TV", ["Internet", "Televiziune", "TV", "Cablu"]),
            option(mobile, "Telefon mobil", ["Mobil", "Abonament mobil", "Telefonie mobilă"]),
            option(other, "Alt abonament", ["Altul", "Altceva"]),
        ]
    }

    /// Supplied at an address: the contract belongs to the home, and each home has its own.
    public static func isTiedToHome(_ key: String?) -> Bool {
        [gas, electricity, water, internetTV].contains(key ?? "")
    }

    /// Billed on a rhythm the binder can expect: one bill per billing cycle.
    public static func sendsRegularBills(_ key: String?) -> Bool {
        isTiedToHome(key) || key == mobile
    }

    /// The service's name, in a few words: "Gaz".
    public static func label(for key: String?) -> String? {
        key.flatMap { options.option(for: $0)?.label }
    }
}

/// What an insurance policy covers. Capture reads it once from the page
/// (`InsuranceCover.read(in:)`), the review offers it as a choice, and the AI provider
/// answers with one of these keys. Which deadline and which fields a cover fills is
/// the kind profile's job (`CaptureKindProfile`).
/// The RCA bonus-malus classes, from the worst to the best: eight malus classes (M8 to
/// M1), the base class B0 a new policyholder starts in, and eight bonus classes (B1 to
/// B8). Source: Norma ASF nr. 20/2017 privind asigurările auto din România, the
/// bonus-malus system (a base class, eight bonus and eight malus classes). The class
/// follows the person's own history: a year without a paid claim moves them up, a paid
/// claim moves them down. Stored by stable key, written as printed.
public enum BonusMalusClass {
    /// Every class, worst first, as printed on a policy.
    public static let printed: [String] = (1...8).reversed().map { "M\($0)" } + (0...8).map { "B\($0)" }

    public static func storedKey(_ printed: String) -> String { "bonusMalus." + printed.lowercased() }

    public static var all: [String] { printed.map(storedKey) }

    public static var options: [ChoiceOption] {
        printed.map { ChoiceOption(key: storedKey($0), label: $0) }
    }

    /// The stored key for a class read or typed ("B6", "b6", or a key as it is), or nil
    /// for anything that isn't a class.
    public static func key(for text: String?) -> String? {
        guard let text = text?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else { return nil }
        if all.contains(text) { return text }
        let upper = text.uppercased()
        return printed.contains(upper) ? storedKey(upper) : nil
    }

    /// The class as printed: "B6".
    public static func label(for key: String?) -> String? {
        key.flatMap { options.option(for: $0)?.label }
    }
}

public enum InsuranceCover {
    public static let rca = "coverage.rca"
    public static let casco = "coverage.casco"
    public static let pad = "coverage.pad"
    public static let home = "coverage.home"

    public static let all = [rca, casco, pad, home]

    public static var options: [ChoiceOption] {
        [
            option(rca, "RCA", ["Răspundere civilă auto", "Asigurare obligatorie auto"]),
            option(casco, "CASCO", ["Asigurare facultativă auto"]),
            option(pad, "Asigurare obligatorie a locuinței (PAD)", ["PAD", "PAID"]),
            option(home, "Asigurare facultativă a locuinței", ["Facultativă", "Asigurare locuință"]),
        ]
    }

    /// The cover's name, in a few words: "CASCO".
    public static func label(for key: String?) -> String? {
        key.flatMap { options.option(for: $0)?.label }
    }

    /// The stored key for a cover read or typed: a key as it is, or a label or alias
    /// ("CASCO", "PAD", "Facultativă") as its key. Nil for anything else.
    public static func key(for text: String?) -> String? {
        text.flatMap { options.option(for: $0)?.key }
    }

    /// The words that name each cover on a policy, matched as whole words, most specific
    /// first: a CASCO policy that quotes the RCA rules is still CASCO.
    static let words: [(cover: String, names: [String])] = [
        (casco, ["casco"]),
        (pad, ["pad", "paid", "asigurare obligatorie a locuintei", "asigurarea obligatorie a locuintelor"]),
        (rca, ["rca", "raspundere civila auto", "raspunderii civile auto"]),
        (home, ["asigurare facultativa", "locuinta", "locuintei", "bunuri", "imobil"]),
    ]

    /// The cover a policy's text names, among `covers`, matching whole words ("pad" never
    /// matches "padding" or "Padina"), or nil when it names none.
    public static func read(in text: String, among covers: [String] = all) -> String? {
        let haystack = " " + SearchText.normalize(text) + " "
        return words.first { entry in covers.contains(entry.cover) && entry.names.contains { haystack.contains(" \($0) ") } }?.cover
    }
}
