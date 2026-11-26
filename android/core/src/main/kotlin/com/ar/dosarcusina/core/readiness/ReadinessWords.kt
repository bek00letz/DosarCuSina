package com.ar.dosarcusina.core.readiness

import com.ar.dosarcusina.core.values.CalendarDay
import com.ar.dosarcusina.core.values.Money

/**
 * What a readiness check says, as a kind and what it is about, never as text: the iOS app's
 * `ReadinessWords` (ios/DosarCuSina/Services/Readiness/ReadinessWords.swift), one phrase per
 * sentence, its [arguments] in the order the iOS case carries them. The engine decides which
 * sentence a check says; the app says it in its own words (Phase 4), compared with the iOS
 * app's through the copy matrix.
 */
data class ReadinessWords(val phrase: ReadinessPhrase, val arguments: List<ReadinessArgument> = emptyList()) {
    companion object {
        /** Words of the binder's, as they are: a name, a deadline's title. */
        fun text(text: String): ReadinessWords =
            ReadinessWords(ReadinessPhrase.Text, listOf(ReadinessArgument.Text(text)))

        /** A document type's name, by its key. */
        fun documentType(key: String): ReadinessWords =
            ReadinessWords(ReadinessPhrase.DocumentType, listOf(ReadinessArgument.Text(key)))
    }
}

/** What a sentence is about, as the iOS case's values: a day, a number (of months, of records), a name, an amount. */
sealed interface ReadinessArgument {
    data class Day(val day: CalendarDay) : ReadinessArgument

    data class Number(val number: Int) : ReadinessArgument

    data class Text(val text: String) : ReadinessArgument

    data class Amount(val money: Money) : ReadinessArgument
}

internal operator fun ReadinessPhrase.invoke(): ReadinessWords = ReadinessWords(this)

internal operator fun ReadinessPhrase.invoke(day: CalendarDay): ReadinessWords =
    ReadinessWords(this, listOf(ReadinessArgument.Day(day)))

internal operator fun ReadinessPhrase.invoke(day: CalendarDay, other: CalendarDay): ReadinessWords =
    ReadinessWords(this, listOf(ReadinessArgument.Day(day), ReadinessArgument.Day(other)))

internal operator fun ReadinessPhrase.invoke(day: CalendarDay, number: Int): ReadinessWords =
    ReadinessWords(this, listOf(ReadinessArgument.Day(day), ReadinessArgument.Number(number)))

internal operator fun ReadinessPhrase.invoke(number: Int): ReadinessWords =
    ReadinessWords(this, listOf(ReadinessArgument.Number(number)))

internal operator fun ReadinessPhrase.invoke(text: String): ReadinessWords =
    ReadinessWords(this, listOf(ReadinessArgument.Text(text)))

internal operator fun ReadinessPhrase.invoke(day: CalendarDay, amount: Money): ReadinessWords =
    ReadinessWords(this, listOf(ReadinessArgument.Day(day), ReadinessArgument.Amount(amount)))

/**
 * Every sentence the checks say, each named as the iOS case is ([raw]), with the same arguments.
 * The comments say what a sentence is about where its name doesn't; the iOS file holds its words.
 */
enum class ReadinessPhrase {
    // Shared

    /** The binder's own words (a text). */
    Text,

    /** A document type's name (its key). */
    DocumentType,

    /** „Valabil până pe …” (a day). */
    ValidUntil,

    /** „Valabilă până pe …” (a day). */
    ValidUntilFeminine,

    // Trip: who goes

    UnfiledTraveller,
    IdentityOrPassport,

    // Trip: a document that covers the trip (a day, and the months after return where it says so)

    IdCardValidPastReturn,
    IdCardValid,
    PassportInsteadPastReturn,
    PassportInstead,
    PassportValidPastReturn,
    PassportValidInEU,
    PassportGoodForTravel,
    ResidencePermitValid,

    // Trip: a document that doesn't last

    IdCardExpired,

    /** The last day an identity card without a chip is good for travel. */
    IdCardWithoutChipEnds,
    IdCardEndsPastReturn,
    IdCardEnds,
    IdentityPassportExpired,
    IdentityPassportEndsPastReturn,
    IdentityPassportEnds,
    PassportExpired,
    PassportEnds,

    /** The travel cut-off, then the expiry. */
    PassportCutoffPassed,

    /** The travel cut-off, then the expiry. */
    PassportCutoffBeforeReturn,
    ResidencePermitExpired,
    ResidencePermitEnds,

    // Trip: nothing meets the need

    /** The months after return. */
    IdentityMissingPastReturn,
    IdentityMissing,
    PassportMissingForTravel,
    PassportMissingInEU,
    ResidencePermitMissing,
    NotATravelDocument,
    Undated,

    // Trip: citizenship and visa

    CitizenshipTitle,
    CitizenshipAsked,
    CitizenshipOfUnfiled,
    VisaTitle,
    VisaDetail,

    // Trip: the European health card

    HealthCardMissing,
    HealthCardExpired,
    HealthCardEnds,

    // Trip: the car

    RcaTitle,
    ItpTitle,
    GreenCardTitle,
    VignetteTitle,
    RcaEnds,
    RcaExpired,
    RcaMissing,
    ItpEnds,
    ItpExpired,
    ItpMissing,
    GreenCardWithRCA,
    GreenCardRCAExpired,
    GreenCardRCAEnds,
    GreenCardNoRCA,
    VignetteEndsDuringTrip,
    VignetteExpired,
    VignetteEndsBeforeTrip,
    VignetteMissing,
    LicenceExpired,
    LicenceEnds,
    LicenceMissing,

    // Trip: a pet

    PetPassportTitle,
    PetPassportKept,
    PetPassportMissing,
    RabiesTitle,
    RabiesExpired,
    RabiesEnds,

    /** The day given, the day it lasts to. */
    RabiesBoosterOnTime,

    /** The day given, the last day it could have been. */
    RabiesAfterLapse,

    /** The day given. */
    RabiesTooClose,

    /** The day it lasts to. */
    RabiesUndated,
    RabiesMissing,
    PetRulesTitle,
    PetRulesDetail,

    // Selling a car

    SaleBuyerGroup,
    SaleMoneyGroup,
    SaleAfterGroup,
    RegistrationTitle,
    RegistrationDetail,
    CivTitle,
    CivKept,
    VinTitle,
    VinKept,
    FactMissing,
    SaleITPValid,
    SaleITPExpired,
    SaleITPMissing,
    SaleRCAValid,
    SaleRCAExpired,
    SaleRCAMissing,
    ServiceHistoryTitle,

    /** How many records of history. */
    ServiceHistoryCount,
    ServiceHistoryMissing,
    ServiceInvoicesTitle,
    ServiceInvoicesKept,
    ServiceInvoicesMissing,
    SaleContractTitle,
    SaleContractDetail,
    OwnerIDTitle,
    OwnerIDDetail,
    DeregisterTitle,
    DeregisterDetail,

    /** The policy's deadline title. */
    CancelPolicy,
    CancelUnnamedPolicy,
    CancelPolicyDetail,

    /** The day it was due, the amount. */
    OwedWithAmount,
    Owed,
    CarTaxTitle,
    CarTaxDetail,
    FinesTitle,
    FinesDetail,
    LoanTitle,
    LoanDetail,

    // A claim

    ClaimPolicyGroup,
    ClaimPhotosGroup,
    ClaimPapersGroup,
    WhenRCA,
    WhenCASCO,
    WhenPAD,
    WhenHomeInsurance,
    PolicyNumberTitle,
    PolicyNumberMissing,
    ClaimsPhoneTitle,
    ClaimsPhoneMissing,
    PolicyValidityTitle,
    PolicyExpired,
    PolicyValidityUnknown,
    PolicyDocumentTitle,
    PolicyFiled,
    PolicyPhotoMissing,
    PhotoCarsTitle,
    PhotoCarsDetail,
    PhotoDamageTitle,
    PhotoDamageDetail,
    PhotoPlaceTitle,
    PhotoPlaceDetail,
    PhotoOtherDriverTitle,
    PhotoOtherDriverDetail,
    PhotoReportTitle,
    PhotoReportDetail,
    PaperDriverTitle,
    PaperDriverDetail,
    PaperCarTitle,
    PaperCarDetail,
    PaperReportTitle,
    PaperReportDetail,
    PhotoRoomsTitle,
    PhotoRoomsDetail,
    PhotoSourceTitle,
    PhotoSourceDetail,
    PhotoGoodsTitle,
    PhotoGoodsDetail,
    PaperIDTitle,
    PaperIDDetail,
    PaperDeedTitle,
    PaperDeedDetail,
    PaperOfficialReportTitle,
    PaperOfficialReportDetail,
    ;

    /** The iOS case's name: "idCardValidPastReturn". */
    val raw: String get() = name.replaceFirstChar { it.lowercaseChar() }

    companion object {
        fun of(raw: String): ReadinessPhrase? = entries.firstOrNull { it.raw == raw }
    }
}
