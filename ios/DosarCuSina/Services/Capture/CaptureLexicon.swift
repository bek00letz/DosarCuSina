import Foundation

/// The words capture's shared readers look for that aren't one kind's field labels: what
/// is never a line of an invoice, where the buyer's block starts, what comes before an
/// issuer's name, a company's legal forms, which address labels name the place a service is
/// supplied, what sits beside a policyholder's name, and which words only identity documents
/// print.
///
/// A kind's own labels are its profile's table (`CaptureKindProfile.labels`); a value
/// printed in parts is `CompositeLabels`'; a personal document's layout is its template
/// (`IdentityTemplates`). Every list is written folded (`RomanianText.fold`), so a new
/// wording is a new entry here, never a list where it is read (the
/// `labels-outside-their-table` check).
enum CaptureLexicon {

    // MARK: Invoices and receipts

    /// Words on lines that are never something done or bought: totals, taxes, the issuer's
    /// and the buyer's details, payment, the odometer, the warranty.
    static let nonItemWords = [
        "total", "tva", "subtotal", "rest", "de plata", "cui", "cif", "cod fiscal", "nr.", "cont", "iban",
        "data", "tel", "telefon", "adresa", "banca", "capital", "reg. com", "j40", "numerar", "card",
        "rest", "achitat", "bon fiscal", "discount", "scadent", "client", "cumparator", "furnizor",
        "km bord", "kilometraj", "odometru", "garanti", "valabil",
    ]

    /// Words of a line that is the work itself, never a part or a job done to one: the labour
    /// ("Manoperă 1,5 ore", „mână de lucru”, hours worked), read by `LabourLine` on every line,
    /// whoever wrote it (a reader, a model, the person). Each word matches only where a word
    /// starts, so it reaches its endings („manoperei”) and nothing longer: never "labor", which
    /// a laboratory's „laborator” starts with.
    static let labourWords = [
        "manopera", "mana de lucru", "mana lucru", "ore lucrate", "ore de lucru", "ore munca", "ore de munca", "labour",
    ]

    /// Labels that start the buyer's block: a firm named within two lines after one is the
    /// customer, never the issuer.
    static let buyerLabels = ["client", "cumparator", "beneficiar", "asigurat", "contractant"]

    /// What comes before an issuer's name on its line and isn't part of it, folded, in the
    /// order they are taken off ("Furnizor: S.C. …" loses both).
    static let issuerPrefixes = ["furnizor:", "furnizor", "vanzator:", "emitent:", "s.c.", "sc "]

    /// A company's legal forms, folded, read with their dots printed or left out ("S.R.L.",
    /// "SRL", `RomanianFieldExtractor.printed`): a line that names one names a firm, never a
    /// person.
    static let companyForms = ["s.r.l.", "s.a.", "s.c.s.", "p.f.a.", "i.i."]

    // MARK: Bills and contracts

    /// Address labels on a bill or a contract. Longer wordings win. The payer's address and
    /// the consumption point's codes are labels too, so their values are never read as the
    /// supply address and "cod loc de consum" never reads as "loc de consum".
    static let supplyAddressLabels: [(ContractReader.AddressLabel, [String])] = [
        (.place, [
            "adresa locului de consum", "adresa loc de consum", "adresa loc consum", "adresa locului de livrare",
            "adresa de livrare", "adresa punctului de consum", "adresa punct de consum", "adresa punct consum",
            "adresa de consum", "adresa locului de furnizare", "adresa de furnizare", "adresa de instalare",
            "adresa instalarii", "adresa instalare", "adresa de instalare a serviciului", "adresa de instalare a serviciilor",
            "locatia de instalare", "locatie instalare", "locul instalarii",
            "adresa de prestare", "adresa prestarii serviciului", "adresa serviciului",
            "locul de consum", "loc de consum", "loc consum", "punctul de consum", "punct de consum",
        ]),
        (.other, holderAddressLabels + [
            "cod loc de consum", "cod loc consum", "cod punct de consum", "cod punct consum", "cod locul de consum",
            "nr loc consum", "nr. loc consum", "numar loc consum", "numar loc de consum", "id loc consum",
            "denumire loc consum", "denumire loc de consum", "tip loc consum", "tip loc de consum",
        ]),
    ]

    /// Where the person or the firm on a paper lives or is based, as a bill, a contract or a
    /// policy labels it: never the place the paper is about (the supply address, the home a
    /// policy insures).
    static let holderAddressLabels = [
        "adresa de facturare", "adresa facturare", "adresa de corespondenta", "adresa corespondenta",
        "adresa client", "adresa clientului", "adresa titular", "adresa titularului", "adresa platitorului",
        "adresa sediului", "sediul social", "sediul", "sediu", "domiciliul", "domiciliu",
    ]

    // MARK: Policies

    /// What a policy prints beside its holder's name and CNP (their address and contacts,
    /// the policy's series, the insurer), so the name never runs into it. The holder's own
    /// labels are the policy table's (`CaptureKindProfile.policyLabels`).
    static let policyholderNeighbourLabels = [
        "adresa", "adresa proprietar", "domiciliu", "telefon", "email", "e-mail", "seria", "serie", "nr. polita", "asigurator",
    ]

    // MARK: Personal documents

    /// Words printed only on identity and other personal documents, folded
    /// (`IdentitySignals.hasIdentityWords`).
    static let identityWords = [
        "carte de identitate", "carte electronica de identitate", "identity card", "carte d'identite",
        "pasaport", "passport", "passeport", "permis de sedere", "residence permit", "permis de conducere", "driving licence", "permis de conduire",
        "cod numeric personal", "data nasterii", "date of birth", "locul nasterii", "place of birth", "cetatenie",
        "cazier", "card european de asigurari", "european health insurance card", "asigurari sociale de sanatate",
        "international motor insurance card", "carte internationala de asigurare",
        "certificat calificat", "semnatura electronica calificata", "valid thru", "good thru",
    ]

    // MARK: The classifier

    /// The classifier's signals whose longer forms mean something else, so they only count
    /// whole: a meter's "index" isn't the "indexare" of a price.
    static let wholeSignalWords: Set<String> = ["index"]
}
