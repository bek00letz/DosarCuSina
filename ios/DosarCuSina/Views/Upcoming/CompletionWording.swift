import SwiftUI

/// How "Am rezolvat" puts what a kind asks (`CompletionShape`), in the app's words. Each word is
/// written once, as text (`…Words`, which `docs/COPY_MATRIX.md` lists, `CopyMatrixTests`), and
/// drawn through the key made from it.

extension CompletionShape {
    /// The deadline page's main button and Urmează's swipe: "Gata" for a chore done in one tap,
    /// else "Am rezolvat", which opens the sheet (`CompletionEntry`).
    var actionWords: String {
        isOneTap ? String(localized: "Gata") : String(localized: "Am rezolvat")
    }

    /// The same words in a menu and as VoiceOver's action: one that opens the sheet ends with
    /// "…", since it asks something before anything is done.
    var menuWords: String {
        isOneTap ? String(localized: "Gata") : String(localized: "Am rezolvat…")
    }

    var actionTitle: LocalizedStringKey { LocalizedStringKey(actionWords) }
    var menuTitle: LocalizedStringKey { LocalizedStringKey(menuWords) }
}

extension CompletionShape.Cost {
    /// The money field's title, as text.
    var words: String {
        switch self {
        case .cost: String(localized: "Cât a costat")
        case .paid: String(localized: "Cât ai plătit")
        }
    }

    /// The money field's title.
    var title: LocalizedStringKey { LocalizedStringKey(words) }
}

extension CompletionShape.Paper {
    /// The section's header in the sheet, as text.
    var headerWords: String {
        switch self {
        case .invoice, .bill: String(localized: "Factura")
        case .newDocument: String(localized: "Actul nou")
        case .policy: String(localized: "Polița nouă")
        case .certificate: String(localized: "Dovada")
        case .receipt: String(localized: "Chitanța")
        case .result: String(localized: "Rezultatul")
        }
    }

    /// Under the header, as text: that it is optional, and what the photo is for.
    var purposeWords: String {
        switch self {
        case .invoice: String(localized: "Opțional. O păstrez în istoric.")
        case .bill: String(localized: "Opțional. O trec în istoric.")
        case .newDocument: String(localized: "Opțional. Din el iau data la care expiră.")
        case .policy, .certificate: String(localized: "Opțional. Din ea iau data următoare.")
        case .receipt, .result: String(localized: "Opțional. Îl păstrez în dosar.")
        }
    }

    /// The card that asks for the photo, as text.
    var actionWords: String {
        switch self {
        case .invoice, .bill: String(localized: "Fotografiază factura")
        case .newDocument: String(localized: "Fotografiază actul nou")
        case .policy: String(localized: "Fotografiază polița")
        case .certificate: String(localized: "Fotografiază dovada")
        case .receipt: String(localized: "Fotografiază chitanța")
        case .result: String(localized: "Fotografiază rezultatul")
        }
    }

    /// Under the card, as text: which paper is meant.
    var exampleWords: String {
        switch self {
        case .invoice: String(localized: "De la service sau de la cel care a lucrat.")
        case .bill: String(localized: "Cea pe care ai plătit-o.")
        case .newDocument: String(localized: "Partea cu data la care expiră.")
        case .policy: String(localized: "Din ea iau numărul, asigurătorul și data.")
        case .certificate: String(localized: "Raportul, certificatul sau chitanța.")
        case .receipt: String(localized: "Sau dovada plății din aplicația băncii.")
        case .result: String(localized: "Analizele, rețeta sau carnetul de vaccinări.")
        }
    }

    var header: LocalizedStringKey { LocalizedStringKey(headerWords) }
    var purpose: LocalizedStringKey { LocalizedStringKey(purposeWords) }
    var actionTitle: LocalizedStringKey { LocalizedStringKey(actionWords) }
    var example: LocalizedStringKey { LocalizedStringKey(exampleWords) }
}
