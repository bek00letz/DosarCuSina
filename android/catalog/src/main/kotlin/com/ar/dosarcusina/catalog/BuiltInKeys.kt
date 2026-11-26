package com.ar.dosarcusina.catalog

// The keys of the built-in fields, deadlines and categories that code names, as the iOS app
// names them (ios/DosarCuSina/Services/Templates/BuiltInFieldKeys.swift, SubscriptionFields,
// BuiltInTemplates.Key), so Android code names a constant and never the text. Each object is the
// Swift type of the same name, each constant its Swift name in capitals. BuiltInKeysTest checks
// them against shared/catalog/keys.json, which the iOS tests export, both ways: a key added on
// iOS fails here until it is added here too. Keys are part of the .dosar contract: never rename them.

/** A car's fields. */
object VehicleFields {
    const val CASCO_CLAIMS_PHONE = "vehicle.cascoClaimsPhone"
    const val CASCO_INSURED_SUM = "vehicle.cascoInsuredSum"
    const val CASCO_INSURER = "vehicle.cascoInsurer"
    const val CASCO_POLICY_NUMBER = "vehicle.cascoPolicyNumber"
    const val CIV = "vehicle.civ"
    const val CLAIMS_PHONE = "vehicle.claimsPhone"
    const val INSURER = "vehicle.insurer"
    const val MAKE = "vehicle.make"
    const val MODEL = "vehicle.model"
    const val ODOMETER = "vehicle.odometer"
    const val PLATE = "vehicle.plate"
    const val POLICYHOLDER = "vehicle.policyholder"
    const val POLICY_NUMBER = "vehicle.policyNumber"
    const val USAGE = "vehicle.usage"
    const val VIN = "vehicle.vin"
    const val YEAR = "vehicle.year"
}

/** A home's fields. */
object HomeFields {
    const val ADDRESS = "home.address"
    const val CLAIMS_PHONE = "home.claimsPhone"
    const val CLC = "home.clc"
    const val INSURED_SUM = "home.insuredSum"
    const val INSURER = "home.insurer"
    const val OPTIONAL_CLAIMS_PHONE = "home.optionalClaimsPhone"
    const val OPTIONAL_INSURED_SUM = "home.optionalInsuredSum"
    const val OPTIONAL_INSURER = "home.optionalInsurer"
    const val OPTIONAL_POLICY_NUMBER = "home.optionalPolicyNumber"
    const val POD = "home.pod"
    const val POLICY_NUMBER = "home.policyNumber"
}

/** A personal document's fields. */
object DocumentFields {
    const val BIRTH_DATE = "document.birthDate"
    const val CARD_LAST_FOUR = "document.cardLastFour"
    const val CARD_NETWORK = "document.cardNetwork"
    const val CATEGORIES = "document.categories"
    const val EXPIRY = "document.expiry"
    const val ISSUER = "document.issuer"
    const val ISSUE_DATE = "document.issueDate"
    const val NATIONALITY = "document.nationality"
    const val NUMBER = "document.number"
    const val PERSONAL_NUMBER = "document.personalNumber"
    const val RECORD_RESULT = "document.recordResult"
    const val SEX = "document.sex"
    const val VEHICLE_PLATE = "document.vehiclePlate"
}

/** A person's fields. */
object MemberFields {
    const val BONUS_MALUS = "member.bonusMalus"
    const val CITIZENSHIP = "member.citizenship"
}

/** A pet's fields. */
object PetFields {
    const val MICROCHIP = "pet.microchip"
    const val PASSPORT = "pet.passport"
}

/** A purchase's fields. */
object PurchaseFieldKeys {
    const val MODEL = "purchase.model"
    const val SERIAL = "purchase.serial"
    const val WARRANTY_MONTHS = "purchase.warrantyMonths"
    const val WARRANTY_UNTIL = "purchase.warrantyUntil"
}

/** A subscription's fields and deadlines. */
object SubscriptionFields {
    const val ACCOUNT = "subscription.account"
    const val BILL_BLUEPRINT = "subscription.bill"
    const val CLC = "subscription.clc"
    const val CLIENT_CODE = "subscription.clientCode"
    const val CONTRACT_NUMBER = "subscription.contractNumber"
    const val CYCLE = "subscription.cycle"
    const val DIRECT_DEBIT = "subscription.directDebit"
    const val GROUP = "subscription.group"
    const val LAST_BILL = "subscription.lastBill"
    const val MINIMUM_ENDS_BLUEPRINT = "subscription.minimumEnds"
    const val MINIMUM_MONTHS = "subscription.minimumMonths"
    const val MINIMUM_UNTIL = "subscription.minimumUntil"
    const val PHONE_NUMBER = "subscription.phoneNumber"
    const val PLACE_CODE = "subscription.placeCode"
    const val POD = "subscription.pod"
    const val PRICE = "subscription.price"
    const val PROVIDER = "subscription.provider"
    const val SERVICE = "subscription.service"
    const val START_DATE = "subscription.startDate"
}

/** Built-in deadlines that code names. */
object BuiltInBlueprints {
    const val DOCUMENT_RENEW = "document.renew"
    const val HEALTH_EU_CARD = "health.euCard"
    const val HOME_BOILER_CHECK = "home.boilerCheck"
    const val HOME_GAS_CHECK = "home.gasCheck"
    const val HOME_GAS_REVISION = "home.gasRevision"
    const val HOME_INSURANCE = "home.insurance"
    const val HOME_PAD = "home.pad"
    const val PET_RABIES = "pet.rabies"
    const val PET_VACCINE = "pet.vaccine"
    const val VEHICLE_CASCO = "vehicle.casco"
    const val VEHICLE_ITP = "vehicle.itp"
    const val VEHICLE_RCA = "vehicle.rca"
    const val VEHICLE_VIGNETTE = "vehicle.vignette"
    const val WARRANTY_ENDS = "purchase.warrantyEnds"
}

/** The built-in categories' keys, in the catalog's order. */
object BuiltInTemplates {
    object Key {
        const val VEHICLE = "vehicle"
        const val HOME = "home"
        const val DOCUMENTS = "documents"
        const val PET = "pet"
        const val HEALTH = "health"
        const val PURCHASE = "purchase"
        const val SUBSCRIPTION = "subscription"
        const val OTHER = "other"
        const val BIKE = "bike"
        const val PLANTS = "plants"
        const val TENANCY = "tenancy"
        const val MEMBER = "member"
        const val ESPRESSO = "espresso"
    }
}
