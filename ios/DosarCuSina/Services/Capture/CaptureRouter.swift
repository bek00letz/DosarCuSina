import Foundation

/// Turns a classified capture into suggestions (where it could go) and a reminder hint (how early to warn).
///
/// Template keys match Core's built-in templates (`vehicle`, `home`, `pet`, `health`,
/// `documents`, `warranties`, `subscriptions`). Blueprint and profile keys name Core's
/// obligation blueprints and reminder profiles; the lead days are a fallback for when
/// Core has no profile under that key.
public enum CaptureRouter {

    /// How early to warn, by how hard the renewal is and how bad lateness would be.
    public struct ReminderDefault: Sendable, Hashable {
        public let profileKey: String
        public let leadDays: [Int]
    }

    public static let reminderDefaults: [CaptureDocumentKind: ReminderDefault] = [
        // About 9 months: many countries want 6 months of validity left, and renewal needs an appointment.
        .passport: ReminderDefault(profileKey: "passport", leadDays: [270, 180, 60]),
        // Appointments at the records office often take weeks.
        .identityCard: ReminderDefault(profileKey: "identityCard", leadDays: [90, 30]),
        // Needs a medical check and an appointment.
        .drivingLicence: ReminderDefault(profileKey: "drivingLicence", leadDays: [60, 30]),
        // A month to compare offers, then a week, then the day itself.
        .rcaPolicy: ReminderDefault(profileKey: "rca", leadDays: [30, 7, 0]),
        .insurancePolicy: ReminderDefault(profileKey: "insurancePolicy", leadDays: [30, 7]),
        .itpReport: ReminderDefault(profileKey: "itp", leadDays: [30, 7]),
        // "Last chance": time to get anything fixed while it's still free.
        .warrantyCertificate: ReminderDefault(profileKey: "warranty", leadDays: [30]),
        .fiscalReceipt: ReminderDefault(profileKey: "warranty", leadDays: [30]),
        .utilityInvoice: ReminderDefault(profileKey: "bill", leadDays: [3, 0]),
        // A few days late is fine; the day before is enough.
        .veterinaryRecord: ReminderDefault(profileKey: "petVaccine", leadDays: [1]),
    ]

    public struct Routing: Sendable, Hashable {
        public let suggestions: [CaptureSuggestion]
        public let reminder: CaptureReminderHint?
    }

    public static func route(kind: CaptureDocumentKind, kindConfidence: Double, fields: [CaptureField]) -> Routing {
        let lookup = Dictionary(fields.map { ($0.key, $0) }, uniquingKeysWith: { first, _ in first })
        func text(_ key: CaptureFieldKey) -> String? { lookup[key]?.value.text }
        func day(_ key: CaptureFieldKey) -> CaptureDay? { lookup[key]?.value.day }
        func hints(_ keys: [CaptureFieldKey]) -> [CaptureAssetHint] {
            keys.compactMap { key in text(key).map { CaptureAssetHint(key: key, value: $0) } }
        }
        func reminder(on day: CaptureDay?) -> CaptureReminderHint? {
            guard let day, let defaults = reminderDefaults[kind] else { return nil }
            return CaptureReminderHint(day: day, profileKey: defaults.profileKey, leadDays: defaults.leadDays)
        }
        let confidence = kindConfidence
        let vehicleHints = hints([.licensePlate, .vin])
        let providerSuggestion = text(.provider).map {
            CaptureSuggestion(destination: .provider(name: $0, trade: trade(for: kind)), confidence: confidence * 0.9)
        }

        var suggestions: [CaptureSuggestion] = []
        var reminderHint: CaptureReminderHint?

        switch kind {
        case .passport, .identityCard, .drivingLicence:
            let blueprint = switch kind {
            case .passport: "passportRenewal"
            case .identityCard: "identityCardRenewal"
            default: "drivingLicenceRenewal"
            }
            suggestions.append(CaptureSuggestion(destination: .newAsset(templateKey: "documents"), assetHints: hints([.documentNumber]), confidence: confidence))
            suggestions.append(CaptureSuggestion(destination: .obligation(blueprintKey: blueprint, templateKey: "documents"), assetHints: hints([.documentNumber]), confidence: confidence))
            reminderHint = reminder(on: day(.expiryDate))

        case .vehicleRegistration:
            suggestions.append(CaptureSuggestion(destination: .newAsset(templateKey: "vehicle"), assetHints: vehicleHints, confidence: confidence))

        case .rcaPolicy:
            suggestions.append(CaptureSuggestion(destination: .obligation(blueprintKey: "rca", templateKey: "vehicle"), assetHints: vehicleHints, confidence: confidence))
            suggestions.append(CaptureSuggestion(destination: .historyEntry(templateKey: "vehicle"), assetHints: vehicleHints, confidence: confidence * 0.7))
            reminderHint = reminder(on: day(.expiryDate))

        case .insurancePolicy:
            let coverage = CaptureText.fold(text(.coverageType) ?? "")
            let isVehicle = coverage.contains("casco") || !vehicleHints.isEmpty
            let blueprint = isVehicle ? "casco" : (coverage.contains("pad") ? "padPolicy" : "homeInsurance")
            let template = isVehicle ? "vehicle" : "home"
            suggestions.append(CaptureSuggestion(destination: .obligation(blueprintKey: blueprint, templateKey: template), assetHints: isVehicle ? vehicleHints : [], confidence: confidence))
            reminderHint = reminder(on: day(.expiryDate))

        case .utilityInvoice:
            let utilityHints = hints([.podCode, .clcCode, .clientCode])
            suggestions.append(CaptureSuggestion(destination: .historyEntry(templateKey: "home"), assetHints: utilityHints, confidence: confidence))
            if day(.dueDate) != nil {
                suggestions.append(CaptureSuggestion(destination: .obligation(blueprintKey: "utilityBill", templateKey: "home"), assetHints: utilityHints, confidence: confidence * 0.8))
            }
            reminderHint = reminder(on: day(.dueDate))

        case .serviceInvoice:
            suggestions.append(CaptureSuggestion(destination: .historyEntry(templateKey: "vehicle"), assetHints: vehicleHints, confidence: confidence))

        case .itpReport:
            suggestions.append(CaptureSuggestion(destination: .historyEntry(templateKey: "vehicle"), assetHints: vehicleHints, confidence: confidence))
            suggestions.append(CaptureSuggestion(destination: .obligation(blueprintKey: "itp", templateKey: "vehicle"), assetHints: vehicleHints, confidence: confidence))
            reminderHint = reminder(on: day(.expiryDate))

        case .fiscalReceipt, .warrantyCertificate:
            let hasProduct = text(.productName) != nil || text(.serialNumber) != nil || lookup[.warrantyMonths] != nil
            if hasProduct || kind == .warrantyCertificate {
                suggestions.append(CaptureSuggestion(destination: .newAsset(templateKey: "warranties"), assetHints: hints([.serialNumber]), confidence: confidence))
            } else {
                suggestions.append(CaptureSuggestion(destination: .attachOnly, confidence: confidence * 0.6))
            }
            reminderHint = reminder(on: day(.warrantyUntil))

        case .veterinaryRecord:
            let petHints = hints([.microchip, .petName])
            suggestions.append(CaptureSuggestion(destination: .historyEntry(templateKey: "pet"), assetHints: petHints, confidence: confidence))
            if day(.nextDoseDate) != nil {
                suggestions.append(CaptureSuggestion(destination: .obligation(blueprintKey: "petVaccine", templateKey: "pet"), assetHints: petHints, confidence: confidence))
            }
            reminderHint = reminder(on: day(.nextDoseDate))

        case .medicalResult:
            suggestions.append(CaptureSuggestion(destination: .historyEntry(templateKey: "health"), confidence: confidence))

        case .other:
            suggestions.append(CaptureSuggestion(destination: .attachOnly, confidence: 0.5))
        }

        if let providerSuggestion, !kind.isIdentityDocument { suggestions.append(providerSuggestion) }
        return Routing(suggestions: suggestions, reminder: reminderHint)
    }

    /// The trade a provider most likely has, given the document it issued.
    static func trade(for kind: CaptureDocumentKind) -> String? {
        switch kind {
        case .serviceInvoice: "mecanic"
        case .rcaPolicy, .insurancePolicy: "asigurator"
        case .itpReport: "statieITP"
        case .veterinaryRecord: "veterinar"
        case .medicalResult: "medic"
        case .utilityInvoice: "furnizorUtilitati"
        case .fiscalReceipt, .warrantyCertificate: "magazin"
        default: nil
        }
    }
}
