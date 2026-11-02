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

    public var id: String { key }

    public init(key: String, label: String, aliases: [String] = []) {
        self.key = key
        self.label = label
        self.aliases = aliases
    }

    private enum CodingKeys: String, CodingKey { case key, label, aliases }

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
            aliases: try c.decodeIfPresent([String].self, forKey: .aliases) ?? []
        )
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(key, forKey: .key)
        try c.encode(label, forKey: .label)
        if !aliases.isEmpty { try c.encode(aliases, forKey: .aliases) }
    }

    /// Whether `text` names this option: its key, its label or an alias.
    public func matches(_ text: String) -> Bool {
        if text == key { return true }
        let needle = Self.fold(text)
        guard !needle.isEmpty else { return false }
        return ([label] + aliases).contains { Self.fold($0) == needle }
    }

    /// Case and diacritics folded, whitespace collapsed, signs kept (so "A+" and "A-" stay apart).
    static func fold(_ text: String) -> String {
        text.replacingOccurrences(of: "−", with: "-")
            .replacingOccurrences(of: "ş", with: "ș").replacingOccurrences(of: "ţ", with: "ț")
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "ro_RO"))
            .split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }
}

extension Array where Element == ChoiceOption {
    /// The option for a stored key or for legacy display text.
    public func option(for text: String) -> ChoiceOption? {
        first { $0.key == text } ?? first { $0.matches(text) }
    }
}

// MARK: - Built-in option sets

private func option(_ key: String, _ label: String.LocalizationValue, _ aliases: [String] = []) -> ChoiceOption {
    ChoiceOption(key: key, label: String(localized: label), aliases: aliases)
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
            option(euHealthCard, "Card european de sănătate", ["CEASS", "EHIC"]),
            option(greenCard, "Carte verde", ["Green card"]),
            option(bankCard, "Card bancar", ["Card"]),
            option(eSignature, "Semnătură electronică", ["Certificat digital", "Token"]),
            option(criminalRecord, "Cazier", ["Cazier judiciar"]),
            option(other, "Alt document", ["Altul"]),
        ]
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
}
