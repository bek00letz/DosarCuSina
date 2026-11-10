import Foundation

/// What the app says about a paper already in the binder (`FiledPaper`): the notice's title,
/// what saving does with it, and its two actions. The one wording for the review, the visit
/// form and "Am rezolvat", drawn by `DSFiledPaperNotice`.
enum FiledPaperWording {
    /// What the paper is: a subscription's bill, or the invoice of a visit, repair or purchase.
    enum Paper: Equatable, Sendable {
        case bill
        case invoice
    }

    static var title: String {
        String(localized: "Factura e deja în dosar", comment: "Notice: the bill or invoice being filed is already in the binder.")
    }

    /// Opens the entry the paper is logged as.
    static var open: String {
        String(localized: "Vezi factura", comment: "Opens the bill or invoice already in the binder.")
    }

    /// The person says it is another paper, when the match isn't certain.
    static var another: String {
        String(localized: "E altă factură", comment: "The person says the paper is another bill or invoice, not the one already filed.")
    }

    /// Where the paper is, how it was known, and what saving does with it.
    static func message(_ filed: FiledPaper, paper: Paper, today: CalendarDay) -> String {
        let date = DueWording.date(filed.day, today: today)
        let section = filed.section
        switch (paper, filed.match) {
        case (.bill, .sameDocument):
            return String(localized: "E în „\(section)”, cea din \(date). Dacă salvezi, o actualizez cu ce am citit acum.",
                          comment: "Capture review: the same bill's photo filed again.")
        case (.bill, .number):
            return String(localized: "E în „\(section)”, cea din \(date), cu același număr. Dacă salvezi, o actualizez cu ce am citit acum, iar poza asta devine copia ei nouă.",
                          comment: "Capture review: another photo of a bill already filed, known by its invoice number.")
        case (.bill, .numberOnly):
            return String(localized: "În „\(section)” e una cu același număr, cea din \(date). Dacă e aceeași, o actualizez, iar poza asta devine copia ei nouă.",
                          comment: "Capture review: a bill with the same number as one already filed, nothing more to confirm it is the same.")
        case (.bill, .dayAndTotal):
            return String(localized: "În „\(section)” e una cu aceeași dată și același total, cea din \(date). Dacă e aceeași, o actualizez, iar poza asta devine copia ei nouă.",
                          comment: "Capture review: another photo of what looks like a bill already filed, by its day and total.")
        case (.invoice, .sameDocument):
            return String(localized: "E în istoricul „\(section)”, din \(date). Dacă salvezi, actualizez ce s-a trecut atunci cu ce e aici.",
                          comment: "Visit form: the same invoice photo filed again.")
        case (.invoice, .number):
            return String(localized: "E în istoricul „\(section)”, din \(date), cu același număr. Dacă salvezi, actualizez ce s-a trecut atunci cu ce e aici, iar poza asta devine copia ei nouă.",
                          comment: "Visit form: another photo of an invoice already filed, known by its number and its firm.")
        case (.invoice, .numberOnly):
            return String(localized: "În istoricul „\(section)” e una cu același număr, din \(date). Dacă e aceeași factură, o actualizez, iar poza asta devine copia ei nouă.",
                          comment: "Visit form: an invoice with the same number as one already filed, from a firm not named on both or on another day.")
        case (.invoice, .dayAndTotal):
            return String(localized: "În istoricul „\(section)” e una cu aceeași dată și același total, din \(date). Dacă e aceeași factură, o actualizez, iar poza asta devine copia ei nouă.",
                          comment: "Visit form: another photo of what looks like an invoice already filed, by its day and total.")
        }
    }
}
