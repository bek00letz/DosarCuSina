import Foundation

// The keys of the built-in fields and deadlines that code reads by name, defined once.
// The catalog (`BuiltInTemplates`) declares its fields and blueprints with these, and
// any code that needs one names the constant, never the text. Keys are part of the
// `.dosar` contract: never rename them. (`SubscriptionFields` and `DocumentType` hold
// the subscription's and the document type's own.)

public enum VehicleFields {
    public static let plate = "vehicle.plate"
    public static let make = "vehicle.make"
    public static let model = "vehicle.model"
    public static let year = "vehicle.year"
    public static let vin = "vehicle.vin"
    public static let civ = "vehicle.civ"
    public static let odometer = "vehicle.odometer"
    public static let usage = "vehicle.usage"
    public static let insurer = "vehicle.insurer"
    public static let policyNumber = "vehicle.policyNumber"
    public static let claimsPhone = "vehicle.claimsPhone"
    public static let cascoInsurer = "vehicle.cascoInsurer"
    public static let cascoPolicyNumber = "vehicle.cascoPolicyNumber"
    public static let cascoClaimsPhone = "vehicle.cascoClaimsPhone"
}

public enum HomeFields {
    public static let pod = "home.pod"
    public static let clc = "home.clc"
    /// The mandatory policy's (PAD). Earlier versions kept any home policy here.
    public static let insurer = "home.insurer"
    public static let policyNumber = "home.policyNumber"
    public static let claimsPhone = "home.claimsPhone"
    /// The optional (facultative) policy's, kept apart from PAD's like a car's CASCO from its RCA.
    public static let optionalInsurer = "home.optionalInsurer"
    public static let optionalPolicyNumber = "home.optionalPolicyNumber"
    public static let optionalClaimsPhone = "home.optionalClaimsPhone"
}

public enum DocumentFields {
    public static let number = "document.number"
    public static let personalNumber = "document.personalNumber"
    public static let birthDate = "document.birthDate"
    public static let sex = "document.sex"
    public static let nationality = "document.nationality"
    public static let categories = "document.categories"
    public static let issuer = "document.issuer"
    public static let issueDate = "document.issueDate"
    public static let expiry = "document.expiry"
    /// What a cazier says: "Nu figurează în cazierul judiciar", as printed.
    public static let recordResult = "document.recordResult"
    /// A bank card's network (`PaymentCardNetwork`).
    public static let cardNetwork = "document.cardNetwork"
    /// A bank card's last four digits, and never more (`PaymentCardNumbers.sanitizing`).
    public static let cardLastFour = "document.cardLastFour"
}

public enum PetFields {
    public static let microchip = "pet.microchip"
    public static let passport = "pet.passport"
}

public enum PurchaseFieldKeys {
    public static let model = "purchase.model"
    public static let serial = "purchase.serial"
    public static let warrantyMonths = "purchase.warrantyMonths"
    public static let warrantyUntil = "purchase.warrantyUntil"
}

/// Built-in deadlines that code names: capture files into them, the readiness checks
/// and "Ce-ți trebuie" read them.
public enum BuiltInBlueprints {
    public static let vehicleITP = "vehicle.itp"
    public static let vehicleRCA = "vehicle.rca"
    public static let vehicleCASCO = "vehicle.casco"
    public static let vehicleVignette = "vehicle.vignette"
    public static let homePAD = "home.pad"
    /// A home's optional (facultative) insurance.
    public static let homeInsurance = "home.insurance"
    public static let homeBoilerCheck = "home.boilerCheck"
    public static let homeGasCheck = "home.gasCheck"
    public static let homeGasRevision = "home.gasRevision"
    public static let documentRenew = "document.renew"
    public static let petRabies = "pet.rabies"
    public static let petVaccine = "pet.vaccine"
    public static let warrantyEnds = "purchase.warrantyEnds"
    public static let healthEUCard = "health.euCard"
}
