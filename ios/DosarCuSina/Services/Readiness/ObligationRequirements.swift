import Foundation

/// Something to have at hand to get an obligation done: the papers the ITP
/// station asks for, what a passport renewal needs.
public struct ObligationRequirement: Hashable, Sendable, Identifiable {
    /// How the binder can tell whether it's already in the dosar.
    public enum Check: Hashable, Sendable {
        /// A value on the asset, such as the VIN.
        case field(String)
        /// A current document of this kind filed on the asset.
        case document(DocumentKind)
        /// Another obligation of the asset that must still be valid on the day (RCA for ITP).
        case validObligation(String)
        /// The binder can't tell; it's a reminder only.
        case none
    }

    public var id: String
    public var title: String
    public var check: Check
}

/// What to bring for each built-in obligation, by blueprint key. Kept short:
/// the papers people are actually asked for, not legal fine print.
public enum ObligationRequirements {
    public static func list(forBlueprint key: String?, values: FieldValues = FieldValues()) -> [ObligationRequirement] {
        func item(_ id: String, _ title: String, _ check: ObligationRequirement.Check = .none) -> ObligationRequirement {
            ObligationRequirement(id: id, title: title, check: check)
        }
        let registration = item("registration", String(localized: "Certificatul de înmatriculare (talonul)"))
        let civ = item("civ", String(localized: "Cartea de identitate a vehiculului (CIV)"), .field(VehicleFields.civ))
        let ownerID = item("ownerID", String(localized: "Actul de identitate al proprietarului"))
        switch key {
        case BuiltInBlueprints.vehicleITP:
            return [registration, civ, item("rca", String(localized: "Polița RCA valabilă"), .validObligation(BuiltInBlueprints.vehicleRCA))]
        case BuiltInBlueprints.vehicleRCA, BuiltInBlueprints.vehicleCASCO:
            return [registration, ownerID]
        case BuiltInBlueprints.vehicleVignette:
            return [item("plate", String(localized: "Numărul de înmatriculare"), .field(VehicleFields.plate)),
                    item("vin", String(localized: "Seria de șasiu (VIN)"), .field(VehicleFields.vin))]
        case BuiltInBlueprints.homePAD:
            return [item("deed", String(localized: "Actul de proprietate")), ownerID]
        case BuiltInBlueprints.homeBoilerCheck:
            return [item("boilerBook", String(localized: "Cartea tehnică a centralei")),
                    item("lastReport", String(localized: "Raportul de la verificarea trecută"), .document(.report))]
        case BuiltInBlueprints.homeGasCheck, BuiltInBlueprints.homeGasRevision:
            return [item("gasContract", String(localized: "Contractul de furnizare a gazelor"), .document(.contract)),
                    item("lastReport", String(localized: "Procesul-verbal de la verificarea trecută"), .document(.report))]
        case BuiltInBlueprints.documentRenew:
            switch values[DocumentType.typeFieldKey]?.textValue {
            case DocumentType.passport?:
                return [item("idCard", String(localized: "Cartea de identitate")),
                        item("oldPassport", String(localized: "Pașaportul vechi")),
                        item("appointment", String(localized: "O programare la serviciul de pașapoarte"))]
            case DocumentType.idCard?:
                return [item("oldID", String(localized: "Cartea de identitate veche")),
                        item("birth", String(localized: "Certificatul de naștere")),
                        item("home", String(localized: "Actul locuinței (contract sau extras de carte funciară)"))]
            case DocumentType.drivingLicence?:
                return [item("oldLicence", String(localized: "Permisul vechi")),
                        item("medical", String(localized: "Avizul medical")),
                        item("idCard", String(localized: "Cartea de identitate"))]
            default:
                return []
            }
        case BuiltInBlueprints.petRabies, BuiltInBlueprints.petVaccine:
            return [item("petBook", String(localized: "Carnetul de sănătate sau pașaportul animalului"), .field(PetFields.passport))]
        case HouseholdRules.rentalDeclarationKey:
            return [item("leases", String(localized: "Contractele de închiriere"), .document(.contract)),
                    item("income", String(localized: "Cât ai încasat din chirii anul trecut"))]
        case BuiltInBlueprints.healthEUCard:
            return [item("idCard", String(localized: "Cartea de identitate"))]
        default:
            return []
        }
    }

    /// Whether the binder already holds it: true, false, or nil when it can't tell.
    @MainActor
    public static func isInDosar(_ requirement: ObligationRequirement, asset: Asset?, on day: CalendarDay, calendar: Calendar = .dosar) -> Bool? {
        guard let asset else { return nil }
        switch requirement.check {
        case .none:
            return nil
        case .field(let key):
            return asset.value(key) != nil
        case .document(let kind):
            return (asset.attachments ?? []).contains { $0.kind == kind && !$0.isArchived }
        case .validObligation(let key):
            guard let other = asset.activeObligations.first(where: { $0.blueprintKey == key }) else { return false }
            return other.isValid(on: day, calendar: calendar)
        }
    }
}
