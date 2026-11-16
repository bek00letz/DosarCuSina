import SwiftUI

/// How "Am rezolvat" puts what a kind asks (`CompletionShape`), in the app's words.

extension CompletionShape {
    /// The deadline page's main button and Urmează's swipe: "Gata" for a chore done in one tap,
    /// else "Am rezolvat", which opens the sheet (`CompletionEntry`).
    var actionTitle: LocalizedStringKey {
        isOneTap ? "Gata" : "Am rezolvat"
    }

    /// The same words in a menu and as VoiceOver's action: one that opens the sheet ends with
    /// "…", since it asks something before anything is done.
    var menuTitle: LocalizedStringKey {
        isOneTap ? "Gata" : "Am rezolvat…"
    }
}

extension CompletionShape.Cost {
    /// The money field's title.
    var title: LocalizedStringKey {
        switch self {
        case .cost: "Cât a costat"
        case .paid: "Cât ai plătit"
        }
    }
}

extension CompletionShape.Paper {
    /// The section's header in the sheet.
    var header: LocalizedStringKey {
        switch self {
        case .invoice, .bill: "Factura"
        case .newDocument: "Actul nou"
        case .policy: "Polița nouă"
        case .certificate: "Dovada"
        case .receipt: "Chitanța"
        case .result: "Rezultatul"
        }
    }

    /// Under the header: that it is optional, and what the photo is for.
    var purpose: LocalizedStringKey {
        switch self {
        case .invoice: "Opțional. O păstrez în istoric."
        case .bill: "Opțional. O trec în istoric."
        case .newDocument: "Opțional. Din el iau data la care expiră."
        case .policy, .certificate: "Opțional. Din ea iau data următoare."
        case .receipt, .result: "Opțional. Îl păstrez în dosar."
        }
    }

    /// The card that asks for the photo.
    var actionTitle: LocalizedStringKey {
        switch self {
        case .invoice, .bill: "Fotografiază factura"
        case .newDocument: "Fotografiază actul nou"
        case .policy: "Fotografiază polița"
        case .certificate: "Fotografiază dovada"
        case .receipt: "Fotografiază chitanța"
        case .result: "Fotografiază rezultatul"
        }
    }

    /// Under the card: which paper is meant.
    var example: LocalizedStringKey {
        switch self {
        case .invoice: "De la service sau de la cel care a lucrat."
        case .bill: "Cea pe care ai plătit-o."
        case .newDocument: "Partea cu data la care expiră."
        case .policy: "Din ea iau numărul, asigurătorul și data."
        case .certificate: "Raportul, certificatul sau chitanța."
        case .receipt: "Sau dovada plății din aplicația băncii."
        case .result: "Analizele, rețeta sau carnetul de vaccinări."
        }
    }
}
