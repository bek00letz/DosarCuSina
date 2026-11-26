import Foundation

/// What a readiness check says, as a kind with what it is about (a day, a number of months, a
/// name), never as text: the engine decides which sentence a check says, and `text` says it in
/// the app's words. One sentence is one case, so the Android app's engine gives the same kinds
/// for the same binder (`shared/test-vectors/readiness/`, `ReadinessVectorsTests`) and says them
/// in its own words, compared through the copy matrix.
public enum ReadinessWords: Hashable, Sendable {
    // MARK: Shared

    /// Words of the binder's, as they are: a person's, a car's or a pet's name, a deadline's title.
    case text(String)
    /// A document type's name, by its key (`DocumentType`): "Carte de identitate", "Pașaport".
    case documentType(String)
    /// „Valabil până pe 3 mai 2027.”
    case validUntil(CalendarDay)
    /// „Valabilă până pe 3 mai 2027.”
    case validUntilFeminine(CalendarDay)

    // MARK: Trip: who goes

    /// Personal documents filed under no one, chosen as one traveller.
    case unfiledTraveller
    /// An EU citizen's identity document, either one.
    case identityOrPassport

    // MARK: Trip: a document that covers the trip

    /// An identity card valid long enough after a trip to Moldova or the Western Balkans: the day, the months.
    case idCardValidPastReturn(CalendarDay, Int)
    case idCardValid(CalendarDay)
    /// The identity card isn't valid long enough after the trip; the passport is: the day, the months.
    case passportInsteadPastReturn(CalendarDay, Int)
    /// The identity card ends before return; the passport covers the trip.
    case passportInstead(CalendarDay)
    case passportValidPastReturn(CalendarDay, Int)
    /// No identity card, but the passport is valid inside the EU.
    case passportValidInEU(CalendarDay)
    /// The passport is good for travel past the end of the trip.
    case passportGoodForTravel(CalendarDay)
    case residencePermitValid(CalendarDay)

    // MARK: Trip: a document that doesn't last

    case idCardExpired(CalendarDay)
    /// An identity card without a chip stops being a travel document before the trip ends: the last day it is.
    case idCardWithoutChipEnds(CalendarDay)
    case idCardEndsPastReturn(CalendarDay, Int)
    case idCardEnds(CalendarDay)
    /// The passport, an EU citizen's only identity document, has already expired.
    case identityPassportExpired(CalendarDay)
    case identityPassportEndsPastReturn(CalendarDay, Int)
    case identityPassportEnds(CalendarDay)
    case passportExpired(CalendarDay)
    /// The passport expires before the end of an EU trip, for a citizen of a country outside the EU.
    case passportEnds(CalendarDay)
    /// The passport's travel cut-off has already passed, though it hasn't expired: the cut-off, the expiry.
    case passportCutoffPassed(CalendarDay, CalendarDay)
    /// The passport's travel cut-off falls before the end of the trip: the cut-off, the expiry.
    case passportCutoffBeforeReturn(CalendarDay, CalendarDay)
    case residencePermitExpired(CalendarDay)
    case residencePermitEnds(CalendarDay)

    // MARK: Trip: nothing meets the need

    case identityMissingPastReturn(Int)
    case identityMissing
    case passportMissingForTravel
    case passportMissingInEU
    case residencePermitMissing
    /// The only identity documents in the binder are no travel document (the simple identity card).
    case notATravelDocument
    /// A document of the need with no expiry written down.
    case undated

    // MARK: Trip: citizenship and visa

    case citizenshipTitle
    case citizenshipAsked
    case citizenshipOfUnfiled
    case visaTitle
    case visaDetail

    // MARK: Trip: the European health card

    case healthCardMissing
    case healthCardExpired(CalendarDay)
    case healthCardEnds(CalendarDay)

    // MARK: Trip: the car

    case rcaTitle
    case itpTitle
    case greenCardTitle
    case vignetteTitle
    case rcaEnds(CalendarDay)
    case rcaExpired(CalendarDay)
    case rcaMissing
    case itpEnds(CalendarDay)
    case itpExpired(CalendarDay)
    case itpMissing
    case greenCardWithRCA
    case greenCardRCAExpired
    case greenCardRCAEnds
    case greenCardNoRCA
    case vignetteEndsDuringTrip(CalendarDay)
    case vignetteExpired(CalendarDay)
    case vignetteEndsBeforeTrip(CalendarDay)
    case vignetteMissing
    case licenceExpired(CalendarDay)
    case licenceEnds(CalendarDay)
    case licenceMissing

    // MARK: Trip: a pet

    case petPassportTitle
    case petPassportKept
    case petPassportMissing
    case rabiesTitle
    case rabiesExpired(CalendarDay)
    case rabiesEnds(CalendarDay)
    /// A booster given close to departure, before the one before ran out: the day given, the day it lasts to.
    case rabiesBoosterOnTime(CalendarDay, CalendarDay)
    /// Given after the one before lapsed, too close to departure: the day given, the last day it could have been.
    case rabiesAfterLapse(CalendarDay, CalendarDay)
    /// Given close to departure, not known whether as a booster on time: the day given.
    case rabiesTooClose(CalendarDay)
    /// Valid, but its date isn't known: the day it lasts to.
    case rabiesUndated(CalendarDay)
    case rabiesMissing
    case petRulesTitle
    case petRulesDetail

    // MARK: Selling a car

    case saleBuyerGroup
    case saleMoneyGroup
    case saleAfterGroup
    case registrationTitle
    case registrationDetail
    case civTitle
    case civKept
    case vinTitle
    case vinKept
    /// A value to add from the registration certificate.
    case factMissing
    case saleITPValid(CalendarDay)
    case saleITPExpired(CalendarDay)
    case saleITPMissing
    case saleRCAValid(CalendarDay)
    case saleRCAExpired(CalendarDay)
    case saleRCAMissing
    case serviceHistoryTitle
    /// How many records of history a buyer can be shown.
    case serviceHistoryCount(Int)
    case serviceHistoryMissing
    case serviceInvoicesTitle
    case serviceInvoicesKept
    case serviceInvoicesMissing
    case saleContractTitle
    case saleContractDetail
    case ownerIDTitle
    case ownerIDDetail
    case deregisterTitle
    case deregisterDetail
    /// Cancel a policy, by its deadline's title ("RCA", "CASCO").
    case cancelPolicy(String)
    /// Cancel a policy whose deadline has no title.
    case cancelUnnamedPolicy
    case cancelPolicyDetail
    /// An unpaid amount and the day it was due.
    case owedWithAmount(CalendarDay, Money)
    case owed(CalendarDay)
    case carTaxTitle
    case carTaxDetail
    case finesTitle
    case finesDetail
    case loanTitle
    case loanDetail

    // MARK: A claim

    case claimPolicyGroup
    case claimPhotosGroup
    case claimPapersGroup
    case whenRCA
    case whenCASCO
    case whenPAD
    case whenHomeInsurance
    case policyNumberTitle
    case policyNumberMissing
    case claimsPhoneTitle
    case claimsPhoneMissing
    case policyValidityTitle
    case policyExpired(CalendarDay)
    case policyValidityUnknown
    case policyDocumentTitle
    case policyFiled
    case policyPhotoMissing
    case photoCarsTitle
    case photoCarsDetail
    case photoDamageTitle
    case photoDamageDetail
    case photoPlaceTitle
    case photoPlaceDetail
    case photoOtherDriverTitle
    case photoOtherDriverDetail
    case photoReportTitle
    case photoReportDetail
    case paperDriverTitle
    case paperDriverDetail
    case paperCarTitle
    case paperCarDetail
    case paperReportTitle
    case paperReportDetail
    case photoRoomsTitle
    case photoRoomsDetail
    case photoSourceTitle
    case photoSourceDetail
    case photoGoodsTitle
    case photoGoodsDetail
    case paperIDTitle
    case paperIDDetail
    case paperDeedTitle
    case paperDeedDetail
    case paperOfficialReportTitle
    case paperOfficialReportDetail

    /// The words, in the app's language. One switch over every case, so a new sentence can't go unsaid.
    public var text: String {
        switch self {
        case .text(let words): words
        case .documentType(let key): DocumentType.label(for: key) ?? key
        case .validUntil(let day): String(localized: "Valabil până pe \(Self.long(day)).", comment: "Readiness: a deadline valid until a day.")
        case .validUntilFeminine(let day): String(localized: "Valabilă până pe \(Self.long(day)).", comment: "Readiness: something valid until a day (feminine).")
        case .unfiledTraveller:
            String(localized: "Acte fără titular", comment: "Trip: personal documents not filed under any person, chosen as one traveller.")
        case .identityOrPassport:
            String(localized: "Carte de identitate sau pașaport", comment: "Trip check: an EU citizen's identity document, either one.")
        case .idCardValidPastReturn(let day, let months):
            String(localized: "Valabilă până pe \(Self.long(day)), și la \(Self.months(months)) după ce te întorci, cât cer țările de acolo.", comment: "Trip check: an ID card valid long enough after a trip to Moldova or the Western Balkans. The second argument is a number of months.")
        case .idCardValid(let day):
            String(localized: "Valabilă până pe \(Self.long(day)). Ajunge pentru toată UE.", comment: "Trip check: an ID card valid for the whole trip.")
        case .passportInsteadPastReturn(let day, let months):
            String(localized: "Valabil până pe \(Self.long(day)). Ia-l pe el: cartea de identitate nu mai e valabilă la \(Self.months(months)) după ce te întorci.", comment: "Trip check: the ID card isn't valid long enough after a trip to Moldova or the Western Balkans; the passport is. The second argument is a number of months.")
        case .passportInstead(let day):
            String(localized: "Valabil până pe \(Self.long(day)). Ia-l pe el: cartea de identitate nu mai e valabilă la întoarcere.", comment: "Trip check: the ID card ends before return, the passport covers the trip.")
        case .passportValidPastReturn(let day, let months):
            String(localized: "Valabil până pe \(Self.long(day)), și la \(Self.months(months)) după ce te întorci, cât cer țările de acolo.", comment: "Trip check: a passport valid long enough after a trip to Moldova or the Western Balkans. The second argument is a number of months.")
        case .passportValidInEU(let day):
            String(localized: "Valabil până pe \(Self.long(day)). În UE ajunge și pașaportul.", comment: "Trip check: no ID card, but the passport is valid inside the EU.")
        case .passportGoodForTravel(let day):
            String(localized: "Bun de călătorit până pe \(Self.long(day)), după ce te întorci.", comment: "Trip check: the passport is good for travel past the end of the trip.")
        case .residencePermitValid(let day):
            String(localized: "Valabil până pe \(Self.long(day)). Ia-l cu tine: îți trebuie ca să intri înapoi în țară.", comment: "Trip check: the residence permit covers the trip; it is needed to come back.")
        case .idCardExpired(let day):
            String(localized: "A expirat pe \(Self.long(day)). Fă-ți alta sau ia un pașaport valabil.", comment: "Trip check: the ID card has already expired.")
        case .idCardWithoutChipEnds(let good):
            String(localized: "Fără cip, e bună de călătorit doar până pe \(Self.long(good)). Fă-ți cartea electronică sau ia un pașaport valabil.", comment: "Trip check: an ID card without a chip stops being a travel document before the trip ends (EU rules).")
        case .idCardEndsPastReturn(let day, let months):
            String(localized: "Expiră pe \(Self.long(day)), la mai puțin de \(Self.months(months)) după ce te întorci, iar țările de acolo o cer valabilă cel puțin atât. Fă-ți alta sau ia un pașaport valabil.", comment: "Trip check: the ID card isn't valid long enough after a trip to Moldova or the Western Balkans. The second argument is a number of months.")
        case .idCardEnds(let day):
            String(localized: "Expiră pe \(Self.long(day)), înainte să te întorci. Fă-ți alta sau ia un pașaport valabil.", comment: "Trip check: the ID card expires before the end of an EU trip.")
        case .identityPassportExpired(let day):
            String(localized: "A expirat pe \(Self.long(day)). Fă-ți altul sau ia o carte de identitate valabilă.", comment: "Trip check: the passport, an EU citizen's only identity document, has already expired.")
        case .identityPassportEndsPastReturn(let day, let months):
            String(localized: "Expiră pe \(Self.long(day)), la mai puțin de \(Self.months(months)) după ce te întorci, iar țările de acolo îl cer valabil cel puțin atât. Fă-ți altul sau ia o carte de identitate valabilă.", comment: "Trip check: the passport isn't valid long enough after a trip to Moldova or the Western Balkans. The second argument is a number of months.")
        case .identityPassportEnds(let day):
            String(localized: "Expiră pe \(Self.long(day)), înainte să te întorci. Fă-ți altul sau ia o carte de identitate valabilă.", comment: "Trip check: the passport, an EU citizen's only identity document, expires before the end of an EU trip.")
        case .passportExpired(let day):
            String(localized: "A expirat pe \(Self.long(day)). Fă-ți altul înainte de plecare.", comment: "Trip check: the passport has already expired.")
        case .passportEnds(let day):
            String(localized: "Expiră pe \(Self.long(day)), înainte să te întorci. Fă-ți altul înainte de plecare.", comment: "Trip check: the passport expires before the end of an EU trip, for a citizen of a country outside the EU.")
        case .passportCutoffPassed(let good, let day):
            String(localized: "Era bun de călătorit doar până pe \(Self.long(good)). Expiră pe \(Self.long(day)), iar multe țări nu primesc un pașaport atât de aproape de expirare. Fă-ți altul înainte de plecare.", comment: "Trip check: the passport's travel cut-off has already passed, though it hasn't expired.")
        case .passportCutoffBeforeReturn(let good, let day):
            String(localized: "Bun de călătorit doar până pe \(Self.long(good)). Expiră pe \(Self.long(day)), iar multe țări nu primesc un pașaport atât de aproape de expirare. Fă-ți altul înainte de plecare.", comment: "Trip check: the passport's travel cut-off falls before the end of a trip outside the EU.")
        case .residencePermitExpired(let day):
            String(localized: "A expirat pe \(Self.long(day)). Fără un permis valabil nu poți intra înapoi în țară. Întreabă la Imigrări ce poți face înainte de plecare.", comment: "Trip check: the residence permit has already expired.")
        case .residencePermitEnds(let day):
            String(localized: "Expiră pe \(Self.long(day)), înainte să te întorci. Cere prelungirea cu cel puțin 30 de zile înainte să expire.", comment: "Trip check: the residence permit expires before the end of the trip.")
        case .identityMissingPastReturn(let months):
            String(localized: "Nu sunt în dosar. Acolo merge oricare, dacă e valabil și la \(Self.months(months)) după ce te întorci. Adaugă-l cu o poză și verific.", comment: "Trip check: neither an ID card nor a passport in the binder, for a trip to Moldova or the Western Balkans. The argument is a number of months.")
        case .identityMissing:
            String(localized: "Nu sunt în dosar. Adaugă unul dintre ele cu o poză și verific până când e valabil.", comment: "Trip check: neither an ID card nor a passport in the binder, for an EU citizen.")
        case .passportMissingForTravel:
            String(localized: "Nu e în dosar. Pentru drumul acesta ai nevoie de pașaport. Adaugă-l cu o poză și verific până când e bun.", comment: "Trip check: no passport for a trip outside the EU and the Schengen area.")
        case .passportMissingInEU:
            String(localized: "Nu e în dosar. Fără cetățenie europeană, ai nevoie de pașaport și în UE. Adaugă-l cu o poză și verific până când e valabil.", comment: "Trip check: no passport for an EU trip, for a citizen of a country outside the EU.")
        case .residencePermitMissing:
            String(localized: "Nu e în dosar. Fără el nu poți intra înapoi în țară. Adaugă-l cu o poză și verific până când e valabil.", comment: "Trip check: no residence permit in the binder.")
        case .notATravelDocument:
            String(localized: "Cartea de identitate simplă nu e act de călătorie: e bună doar în țară. Ia un pașaport sau fă-ți cartea electronică.", comment: "Trip check: the simple identity card (CIS) isn't a travel document.")
        case .undated:
            String(localized: "Nu știu până când e valabil. Adaugă data de expirare.", comment: "Trip check: an identity document without an expiry date.")
        case .citizenshipTitle:
            String(localized: "Cetățenia", comment: "Trip check: a traveller's citizenship, not known yet.")
        case .citizenshipAsked:
            String(localized: "Spune-mi ce cetățenie are, ca să știu ce acte îi trebuie.", comment: "Trip check: a member's citizenship isn't known; tapping asks it.")
        case .citizenshipOfUnfiled:
            String(localized: "Nu știu ce cetățenie are titularul. Mută actele la persoana lor și spune-mi ce cetățenie are.", comment: "Trip check: documents filed under no one, with no citizenship known.")
        case .visaTitle:
            String(localized: "Viza pentru țara în care mergi", comment: "Trip reminder: look up the destination's visa rules.")
        case .visaDetail:
            String(localized: "Unele țări cer viză sau o autorizație de călătorie, după cetățenie. Verifică ce cere țara înainte de plecare.", comment: "Trip reminder: visa rules depend on the destination and the citizenship.")
        case .healthCardMissing:
            String(localized: "Te ajută dacă ai nevoie de un medic în UE. Adaugă-l dacă îl ai.", comment: "Trip check: no European health card in the binder, which is optional.")
        case .healthCardExpired(let day):
            String(localized: "A expirat pe \(Self.long(day)). Cere altul de la casa de asigurări de sănătate.", comment: "Trip check: the European health card has already expired.")
        case .healthCardEnds(let day):
            String(localized: "Expiră pe \(Self.long(day)), înainte să te întorci. Cere altul de la casa de asigurări de sănătate.", comment: "Trip check: the European health card ends before the end of the trip.")
        case .rcaTitle: String(localized: "RCA")
        case .itpTitle: String(localized: "ITP")
        case .greenCardTitle: String(localized: "Carte verde (RCA)", comment: "Trip check: the green card, which comes with the RCA.")
        case .vignetteTitle: String(localized: "Rovinietă")
        case .rcaEnds(let day):
            String(localized: "Expiră pe \(Self.long(day)), înainte să te întorci. Reînnoiește-l înainte de plecare.", comment: "Trip check: the RCA ends during the trip.")
        case .rcaExpired(let day):
            String(localized: "A expirat pe \(Self.long(day)). Fără RCA valabil nu ai voie să ieși cu mașina. Reînnoiește-l înainte de plecare.", comment: "Trip check: the RCA has already expired.")
        case .rcaMissing:
            String(localized: "Nu e în dosar. Fără RCA valabil nu ai voie să ieși cu mașina.", comment: "Trip check: no RCA deadline.")
        case .itpEnds(let day):
            String(localized: "Expiră pe \(Self.long(day)), înainte să te întorci. Fă-l înainte de plecare.", comment: "Trip check: the ITP ends during the trip.")
        case .itpExpired(let day):
            String(localized: "A expirat pe \(Self.long(day)). Fă-l înainte de plecare.", comment: "Trip check: the ITP has already expired.")
        case .itpMissing:
            String(localized: "Nu e în dosar. Adaugă data ca să verific.", comment: "Trip check: no ITP deadline.")
        case .greenCardWithRCA:
            String(localized: "Inclusă în RCA. Ia-o cu tine, tipărită sau pe telefon.", comment: "Trip check: the green card comes with a valid RCA.")
        case .greenCardRCAExpired:
            String(localized: "Vine cu RCA-ul, care a expirat.", comment: "Trip check: no green card because the RCA has already expired.")
        case .greenCardRCAEnds:
            String(localized: "Vine cu RCA-ul, care expiră înainte să te întorci.", comment: "Trip check: no green card because the RCA ends during the trip.")
        case .greenCardNoRCA:
            String(localized: "Vine cu RCA-ul. Adaugă RCA-ul ca să verific.", comment: "Trip check: no RCA, so no green card.")
        case .vignetteEndsDuringTrip(let day):
            String(localized: "Expiră pe \(Self.long(day)), cât ești plecat. Cumpără alta pentru drumul înapoi, online sau la benzinărie.", comment: "Trip check: the vignette ends during the trip.")
        case .vignetteExpired(let day):
            String(localized: "A expirat pe \(Self.long(day)). Ai nevoie de ea până la graniță. O cumperi online sau la benzinărie.", comment: "Trip check: the vignette has ended before the trip starts.")
        case .vignetteEndsBeforeTrip(let day):
            String(localized: "Expiră pe \(Self.long(day)), înainte să pleci. Ai nevoie de ea până la graniță. O cumperi online sau la benzinărie.", comment: "Trip check: the vignette ends before the trip starts, on a day still to come.")
        case .vignetteMissing:
            String(localized: "Nu e în dosar. Ai nevoie de ea până la graniță și la întoarcere.", comment: "Trip check: no vignette deadline.")
        case .licenceExpired(let day):
            String(localized: "A expirat pe \(Self.long(day)). Fă-ți altul înainte de plecare.", comment: "Trip check: the driving licence has already expired.")
        case .licenceEnds(let day):
            String(localized: "Expiră pe \(Self.long(day)), înainte să te întorci.", comment: "Trip check: the driving licence ends during the trip.")
        case .licenceMissing:
            String(localized: "Nu e în dosar pentru cine pleacă. Adaugă permisul celui care conduce.", comment: "Trip check: no driving licence among the people going.")
        case .petPassportTitle: String(localized: "Pașaport european", comment: "Trip check: a pet's European passport.")
        case .petPassportKept: String(localized: "Numărul e în dosar. Ia pașaportul cu tine.", comment: "Trip check: the pet's passport number is in the binder.")
        case .petPassportMissing: String(localized: "Adaugă numărul pașaportului. Fără el animalul nu trece granița.", comment: "Trip check: no pet passport number.")
        case .rabiesTitle: String(localized: "Vaccin antirabic", comment: "Trip check: a pet's rabies vaccine.")
        case .rabiesExpired(let day):
            String(localized: "A expirat pe \(Self.long(day)). Fă-l din nou cu cel puțin 21 de zile înainte de plecare.", comment: "Trip check: the rabies vaccine has already expired.")
        case .rabiesEnds(let day):
            String(localized: "Expiră pe \(Self.long(day)), înainte să te întorci. Fă-l din nou înainte să expire, ca să fie valabil de îndată.", comment: "Trip check: the rabies vaccine ends during the trip; a booster before it ends counts at once.")
        case .rabiesBoosterOnTime(let given, let until):
            String(localized: "Rapel făcut pe \(Self.long(given)), înainte să expire cel vechi, deci e valabil de îndată. Valabil până pe \(Self.long(until)).", comment: "Trip check: a rabies booster given close to departure, but before the previous one ran out, counts at once.")
        case .rabiesAfterLapse(let given, let latest):
            String(localized: "Făcut pe \(Self.long(given)), după ce expirase cel vechi. Trebuie făcut cu cel puțin 21 de zile înainte de plecare, adică până pe \(Self.long(latest)). Întreabă medicul veterinar.", comment: "Trip check: the rabies vaccine was given after the previous one lapsed, too close to departure.")
        case .rabiesTooClose(let given):
            String(localized: "Făcut pe \(Self.long(given)), cu mai puțin de 21 de zile înainte de plecare. Un rapel făcut înainte să expire cel vechi e valabil de îndată. Altfel, întreabă medicul veterinar.", comment: "Trip check: a rabies vaccine close to departure, not known whether it was a booster on time.")
        case .rabiesUndated(let until):
            String(localized: "Valabil până pe \(Self.long(until)). Verifică în pașaport că e făcut cu cel puțin 21 de zile înainte de plecare.", comment: "Trip check: the rabies vaccine is valid but its date isn't known.")
        case .rabiesMissing:
            String(localized: "Nu e în dosar. Adaugă data vaccinului ca să verific.", comment: "Trip check: no rabies vaccine deadline.")
        case .petRulesTitle: String(localized: "Ce cere țara pentru animale", comment: "Trip reminder: rules for pets outside the EU.")
        case .petRulesDetail: String(localized: "Unele țări din afara UE cer și un test de anticorpi, făcut cu luni înainte. Întreabă medicul veterinar.", comment: "Trip reminder: rabies antibody test for some countries.")
        case .saleBuyerGroup: String(localized: "Pentru cumpărător", comment: "Sale group: the documents and papers for the buyer.")
        case .saleMoneyGroup: String(localized: "De achitat înainte", comment: "Sale group: what must be paid before selling.")
        case .saleAfterGroup: String(localized: "După vânzare", comment: "Sale group: what to cancel or move after the sale.")
        case .registrationTitle: String(localized: "Certificatul de înmatriculare (talonul)", comment: "Sale: the registration certificate.")
        case .registrationDetail: String(localized: "Originalul îl dai cumpărătorului.", comment: "Sale: hand the original over.")
        case .civTitle: String(localized: "Cartea de identitate a vehiculului (CIV)")
        case .civKept: String(localized: "Seria e în dosar. Originalul îl dai cumpărătorului.", comment: "Sale check: the CIV number is in the binder.")
        case .vinTitle: String(localized: "Serie de șasiu (VIN)")
        case .vinKept: String(localized: "E în dosar, pentru contract.", comment: "Sale check: the VIN is in the binder.")
        case .factMissing: String(localized: "Adaugă-o înainte de vânzare. O găsești pe talon.", comment: "Sale check: a value to add from the registration certificate.")
        case .saleITPValid(let day):
            String(localized: "Valabil până pe \(Self.long(day)). Cumpărătorul are nevoie de el ca să înmatriculeze mașina.", comment: "Sale check: the ITP is valid.")
        case .saleITPExpired(let day):
            String(localized: "A expirat pe \(Self.long(day)). Fără ITP valabil, cumpărătorul nu poate înmatricula mașina.", comment: "Sale check: the ITP has expired.")
        case .saleITPMissing:
            String(localized: "Nu e în dosar. Cumpărătorul are nevoie de ITP valabil ca să înmatriculeze mașina.", comment: "Sale check: no ITP deadline.")
        case .saleRCAValid(let day):
            String(localized: "Valabil până pe \(Self.long(day)). Nu trece la cumpărător: el își face polița lui.", comment: "Sale check: the RCA is valid; the buyer needs their own.")
        case .saleRCAExpired(let day):
            String(localized: "A expirat pe \(Self.long(day)). Până la vânzare nu ai voie să circuli cu mașina.", comment: "Sale check: the RCA has expired.")
        case .saleRCAMissing:
            String(localized: "Nu e în dosar. Cumpărătorul poate cere să-l vadă.", comment: "Sale check: no RCA deadline.")
        case .serviceHistoryTitle: String(localized: "Istoric de service")
        case .serviceHistoryCount(let count):
            String(localized: "\(count) intrări de arătat cumpărătorului.", locale: .dosarDefault, comment: "Readiness: how many history entries a buyer can be shown.")
        case .serviceHistoryMissing:
            String(localized: "Un istoric complet crește încrederea și prețul. Adaugă reviziile pe care le știi.", comment: "Sale check: no service history, which is optional.")
        case .serviceInvoicesTitle: String(localized: "Facturi de service")
        case .serviceInvoicesKept: String(localized: "Sunt facturi în dosar.")
        case .serviceInvoicesMissing:
            String(localized: "Dacă le ai, arată cumpărătorului cum a fost îngrijită mașina.", comment: "Sale check: no service invoices filed on the car, which are optional.")
        case .saleContractTitle: String(localized: "Contractul de vânzare-cumpărare", comment: "Sale: the sale contract.")
        case .saleContractDetail:
            String(localized: "Semnat de amândoi, câte un exemplar pentru tine, pentru cumpărător și pentru primărie.", comment: "Sale: copies of the sale contract.")
        case .ownerIDTitle: String(localized: "Cartea ta de identitate", comment: "Sale: the seller's ID card.")
        case .ownerIDDetail: String(localized: "Pentru contract și la primărie.", comment: "Sale: why the seller's ID card is needed.")
        case .deregisterTitle:
            String(localized: "Scoate mașina de pe numele tău la primărie", comment: "After the sale: deregister the car at the local tax office.")
        case .deregisterDetail:
            String(localized: "La biroul de taxe locale, cu contractul. Altfel plătești impozit pe ea mai departe.", comment: "After the sale: why to deregister the car.")
        case .cancelPolicy(let name):
            String(localized: "Reziliază \(name)", comment: "After the sale: cancel a policy. The name is the deadline's, e.g. RCA or CASCO.")
        case .cancelUnnamedPolicy:
            ReadinessWords.cancelPolicy(String(localized: "polița", comment: "After the sale: a policy without a name.")).text
        case .cancelPolicyDetail:
            String(localized: "Cu contractul de vânzare, la asigurător. Primești înapoi banii pe lunile rămase.", comment: "After the sale: cancelling a policy returns the unused months.")
        case .owedWithAmount(let day, let amount):
            String(localized: "Trebuia plătit pe \(Self.long(day)) · \(amount.formatted())", comment: "Sale check: an unpaid amount and the day it was due.")
        case .owed(let day):
            String(localized: "Trebuia plătit pe \(Self.long(day)).", comment: "Sale check: an unpaid deadline and the day it was due.")
        case .carTaxTitle: String(localized: "Impozitul pe mașină, plătit pe tot anul", comment: "Sale: pay the car tax for the year.")
        case .carTaxDetail: String(localized: "Primăria îți dă certificatul fiscal pentru vânzare doar fără datorii.", comment: "Sale: the tax certificate needs no debts.")
        case .finesTitle: String(localized: "Amenzile neplătite", comment: "Sale: unpaid fines.")
        case .finesDetail: String(localized: "Tot pentru certificatul fiscal. Le vezi pe ghiseul.ro.", comment: "Sale: where to see unpaid fines.")
        case .loanTitle: String(localized: "Leasing sau credit pe mașină", comment: "Sale: a lease or loan on the car.")
        case .loanDetail:
            String(localized: "Dacă mașina e încă în leasing sau garanție la bancă, o vinzi doar după ce e achitată.", comment: "Sale: a car under a lease or pledge.")
        case .claimPolicyGroup: String(localized: "Polița", comment: "Claim group: the policy.")
        case .claimPhotosGroup: String(localized: "Ce fotografiezi", comment: "Claim group: what to photograph.")
        case .claimPapersGroup: String(localized: "Acte de avut la îndemână", comment: "Claim group: documents to have ready.")
        case .whenRCA:
            String(localized: "Când ai lovit pe altcineva: îi dai lui datele poliței. Dacă te-a lovit altcineva, plătește RCA-ul lui.", comment: "Claim: when the car's RCA is the policy to use.")
        case .whenCASCO: String(localized: "Pentru mașina ta, oricine e de vină.", comment: "Claim: when CASCO is the policy to use.")
        case .whenPAD: String(localized: "Cutremur, inundație sau alunecare de teren.", comment: "Claim: what the mandatory home policy (PAD) covers.")
        case .whenHomeInsurance: String(localized: "Apă de la vecini, incendiu, furt și ce mai scrie pe poliță.", comment: "Claim: what the optional home policy covers.")
        case .policyNumberTitle: String(localized: "Număr poliță")
        case .policyNumberMissing: String(localized: "Îl cere asigurătorul la primul telefon. E scris pe poliță.", comment: "Claim check: no policy number.")
        case .claimsPhoneTitle: String(localized: "Telefon pentru daune")
        case .claimsPhoneMissing:
            String(localized: "E pe poliță sau pe site-ul asigurătorului. Adaugă-l ca să suni dintr-o atingere.", comment: "Claim check: no claims phone.")
        case .policyValidityTitle: String(localized: "Valabilitatea poliței", comment: "Claim check: whether the policy is still valid.")
        case .policyExpired(let day):
            String(localized: "A expirat pe \(Self.long(day)). Sună totuși: asigurătorul îți spune ce acoperă.", comment: "Claim check: the policy has expired.")
        case .policyValidityUnknown:
            String(localized: "Nu știu până când e valabilă. Adaugă termenul poliței.", comment: "Claim check: the policy's deadline isn't in the binder.")
        case .policyDocumentTitle: String(localized: "Polița")
        case .policyFiled: String(localized: "E în dosar, cu poză.", comment: "Claim check: the policy is filed.")
        case .policyPhotoMissing: String(localized: "Fă o poză poliței, ca s-o ai la îndemână.", comment: "Claim check: no policy filed.")
        case .photoCarsTitle: String(localized: "Mașinile, cu numerele la vedere", comment: "Claim photo: the cars.")
        case .photoCarsDetail: String(localized: "Din față, din spate și din lateral, înainte să le mutați.", comment: "Claim photo: angles of the cars.")
        case .photoDamageTitle: String(localized: "Fiecare avarie", comment: "Claim photo: each damage.")
        case .photoDamageDetail: String(localized: "De aproape și de departe, ca să se vadă unde e.", comment: "Claim photo: how to photograph damage.")
        case .photoPlaceTitle: String(localized: "Locul", comment: "Claim photo: the place.")
        case .photoPlaceDetail: String(localized: "Indicatoare, marcaje, urme pe carosabil.", comment: "Claim photo: what of the place.")
        case .photoOtherDriverTitle: String(localized: "Actele celuilalt șofer", comment: "Claim photo: the other driver's papers.")
        case .photoOtherDriverDetail: String(localized: "Talonul, permisul și polița RCA, dacă e și altă mașină.", comment: "Claim photo: which papers of the other driver.")
        case .photoReportTitle: String(localized: "Constatarea amiabilă", comment: "Claim photo: the joint accident report.")
        case .photoReportDetail:
            String(localized: "După ce o semnați amândoi. Dacă nu vă înțelegeți, mergi la Poliție.", comment: "Claim photo: the signed joint report. Without agreement the drivers go to the police station; a call to 112 is only for injuries.")
        case .paperDriverTitle: String(localized: "Permisul de conducere și cartea de identitate", comment: "Claim paper: the driver's papers.")
        case .paperDriverDetail: String(localized: "Ale celui care conducea.", comment: "Claim paper: whose papers.")
        case .paperCarTitle: String(localized: "Talonul și cartea de identitate a mașinii", comment: "Claim paper: the car's papers.")
        case .paperCarDetail: String(localized: "Le cere asigurătorul la constatare.", comment: "Claim paper: why the car's papers.")
        case .paperReportTitle: String(localized: "Constatarea amiabilă sau procesul-verbal de la poliție", comment: "Claim paper: the accident report.")
        case .paperReportDetail: String(localized: "Originalul, nu doar poza.", comment: "Claim paper: the original report.")
        case .photoRoomsTitle:
            String(localized: "Fiecare zonă afectată", comment: "Claim photo: each damaged area of the home (a room, a wall, the roof, the stairs).")
        case .photoRoomsDetail: String(localized: "Întâi de departe, apoi avariile de aproape.", comment: "Claim photo: how to photograph each damaged area.")
        case .photoSourceTitle: String(localized: "De unde a pornit", comment: "Claim photo: the cause.")
        case .photoSourceDetail: String(localized: "Țeava, acoperișul, geamul sau peretele.", comment: "Claim photo: what the cause can be.")
        case .photoGoodsTitle: String(localized: "Lucrurile stricate", comment: "Claim photo: damaged belongings.")
        case .photoGoodsDetail: String(localized: "Înainte să arunci ceva, cu bonurile dacă le ai.", comment: "Claim photo: keep damaged things until photographed.")
        case .paperIDTitle: String(localized: "Cartea de identitate", comment: "Claim paper: the ID card.")
        case .paperIDDetail: String(localized: "A celui care are polița.", comment: "Claim paper: whose ID card.")
        case .paperDeedTitle: String(localized: "Actul de proprietate", comment: "Claim paper: the property deed.")
        case .paperDeedDetail: String(localized: "Contractul sau extrasul de carte funciară.", comment: "Claim paper: which property paper.")
        case .paperOfficialReportTitle: String(localized: "Procesul-verbal, dacă a venit cineva", comment: "Claim paper: an official report.")
        case .paperOfficialReportDetail: String(localized: "De la pompieri, poliție sau administratorul blocului.", comment: "Claim paper: who writes the report.")
        }
    }

    static func long(_ day: CalendarDay) -> String { DosarFormat.longDay(day) }

    /// "3 luni", for the months a destination asks after the trip.
    static func months(_ count: Int) -> String { CalendarCount.months(count) }
}
