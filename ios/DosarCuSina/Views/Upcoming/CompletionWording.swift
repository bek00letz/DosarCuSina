import SwiftUI

/// How "Am rezolvat" puts what a deadline asks (`CompletionShape`, from its `CompletionKind`), in
/// the app's words. Each word is written once, as text (`…Words`, which `docs/COPY_MATRIX.md`
/// lists, `CopyMatrixTests`), and drawn through the key made from it. The sheet
/// (`ObligationCompleteSheet`) is a shaped screen: it holds no words of its own, only these,
/// its kind's and the words every kind shares (`CompletionWording`).

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

extension CompletionShape.NewEnd {
    /// The date field's title.
    var label: String {
        switch self {
        case .expires: String(localized: "Expiră pe")
        case .ends: String(localized: "Se termină pe", comment: "Am rezolvat: the day a renewed contract ends.")
        }
    }

    /// Said once the date was read off the photo and written above.
    var filledFromPhoto: String {
        switch self {
        case .expires: String(localized: "Am trecut mai sus data la care expiră. Verifică-o.")
        case .ends: String(localized: "Am trecut mai sus data la care se termină. Verifică-o.", comment: "Am rezolvat: the new contract's end was read off its photo.")
        }
    }
}

extension CompletionShape.Paper {
    /// The section's header in the sheet: the paper's name.
    var headerWords: String { name }

    /// The name inside a sentence: „Am citit raportul ITP”.
    private var inSentence: String {
        String(name.prefix(1)).lowercased(with: Locale.dosarDefault) + name.dropFirst()
    }

    /// Under the header: that it is optional, and what the photo is for, agreeing with the
    /// paper's noun („O păstrez” for „Chitanța”, „Îl păstrez” for „Rezultatul”).
    var purposeWords: String {
        switch (use, gender) {
        case (.keep, .masculine): String(localized: "Opțional. Îl păstrez în dosar.")
        case (.keep, .feminine): String(localized: "Opțional. O păstrez în dosar.", comment: "Am rezolvat: a paper named by a feminine noun is kept in the binder.")
        case (.keep, .plural): String(localized: "Opțional. Le păstrez în dosar.", comment: "Am rezolvat: papers named by a plural noun are kept in the binder.")
        case (.history, .masculine): String(localized: "Opțional. Îl păstrez în istoric.", comment: "Am rezolvat: a paper named by a masculine noun is kept with the job.")
        case (.history, .feminine): String(localized: "Opțional. O păstrez în istoric.")
        case (.history, .plural): String(localized: "Opțional. Le păstrez în istoric.", comment: "Am rezolvat: papers named by a plural noun are kept with the job.")
        case (.logged, .masculine): String(localized: "Opțional. Îl trec în istoric.", comment: "Am rezolvat: a paper named by a masculine noun is logged in Istoric.")
        case (.logged, .feminine): String(localized: "Opțional. O trec în istoric.")
        case (.logged, .plural): String(localized: "Opțional. Le trec în istoric.", comment: "Am rezolvat: papers named by a plural noun are logged in Istoric.")
        case (.nextDate, .masculine): String(localized: "Opțional. Din el iau data următoare.", comment: "Am rezolvat: the next due day is read off a paper named by a masculine noun.")
        case (.nextDate, .feminine): String(localized: "Opțional. Din ea iau data următoare.")
        case (.nextDate, .plural): String(localized: "Opțional. Din ele iau data următoare.", comment: "Am rezolvat: the next due day is read off papers named by a plural noun.")
        case (.expiry, .masculine): String(localized: "Opțional. Din el iau data la care expiră.")
        case (.expiry, .feminine): String(localized: "Opțional. Din ea iau data la care expiră.", comment: "Am rezolvat: the new expiry is read off a paper named by a feminine noun.")
        case (.expiry, .plural): String(localized: "Opțional. Din ele iau data la care expiră.", comment: "Am rezolvat: the new expiry is read off papers named by a plural noun.")
        case (.end, .masculine): String(localized: "Opțional. Din el iau data la care se termină.", comment: "Am rezolvat: the new end is read off a paper named by a masculine noun.")
        case (.end, .feminine): String(localized: "Opțional. Din ea iau data la care se termină.", comment: "Am rezolvat: the new end is read off a paper named by a feminine noun.")
        case (.end, .plural): String(localized: "Opțional. Din ele iau data la care se termină.", comment: "Am rezolvat: the new end is read off papers named by a plural noun.")
        }
    }

    /// The card that asks for the photo, as text.
    var actionWords: String { action }

    /// Under the card, as text: which paper is meant.
    var exampleWords: String { example }

    /// While the photo is read: „Citesc raportul ITP…”.
    var readingWords: String {
        String(localized: "Citesc \(inSentence)…", comment: "Am rezolvat: the paper's photo is being read. The argument is the paper's name, e.g. „raportul ITP”.")
    }

    /// Once it is read: „Am citit raportul ITP”.
    var readWords: String {
        String(localized: "Am citit \(inSentence)", comment: "Am rezolvat: the paper's photo was read. The argument is the paper's name, e.g. „raportul ITP”.")
    }

    /// When it couldn't be read: „Raportul ITP nu s-a citit”.
    var unreadWords: String {
        switch gender {
        case .masculine, .feminine:
            String(localized: "\(name) nu s-a citit", comment: "Am rezolvat: the paper's photo couldn't be read. The argument is the paper's name, e.g. „Raportul ITP”.")
        case .plural:
            String(localized: "\(name) nu s-au citit", comment: "Am rezolvat: the photo of papers named by a plural noun couldn't be read, e.g. „Rezultatele”.")
        }
    }

    /// Whether the paper carries a date the sheet looks for (the next one, a new expiry or
    /// end): only then does reading it say that none was found.
    var readsADate: Bool {
        switch use {
        case .nextDate, .expiry, .end: true
        case .keep, .history, .logged: false
        }
    }

    /// Read, with no new date on it, its photo kept only on request: „Nu am găsit o dată nouă pe el.”
    var noDateWords: String {
        switch gender {
        case .masculine: String(localized: "Nu am găsit o dată nouă pe el.")
        case .feminine: String(localized: "Nu am găsit o dată nouă pe ea.", comment: "Am rezolvat: no new date on a paper named by a feminine noun.")
        case .plural: String(localized: "Nu am găsit o dată nouă pe ele.", comment: "Am rezolvat: no new date on papers named by a plural noun.")
        }
    }

    /// Read, with no new date on it, its photo kept: „… Îl păstrez oricum.”
    var noDateKeptWords: String {
        switch gender {
        case .masculine: String(localized: "Nu am găsit o dată nouă pe el. Îl păstrez oricum.", comment: "Am rezolvat: no new date on a paper named by a masculine noun; its photo is kept.")
        case .feminine: String(localized: "Nu am găsit o dată nouă pe ea. O păstrez oricum.", comment: "Am rezolvat: no new date on a paper named by a feminine noun; its photo is kept.")
        case .plural: String(localized: "Nu am găsit o dată nouă pe ele. Le păstrez oricum.", comment: "Am rezolvat: no new date on papers named by a plural noun; their photo is kept.")
        }
    }

    var header: LocalizedStringKey { LocalizedStringKey(headerWords) }
    var purpose: LocalizedStringKey { LocalizedStringKey(purposeWords) }
    var actionTitle: LocalizedStringKey { LocalizedStringKey(actionWords) }
    var exampleTitle: LocalizedStringKey { LocalizedStringKey(exampleWords) }
}

/// The words "Am rezolvat" says for every kind alike.
enum CompletionWording {
    static var save: String { String(localized: "Salvează", comment: "Am rezolvat: saves the completion.") }
    static var notSaved: String { String(localized: "Nu s-a salvat") }
    static var when: String { String(localized: "Când") }
    static var note: String { String(localized: "Notă") }
    static var newEndFootnote: String { String(localized: "De aici încep să-ți amintesc din nou.") }
    static var photos: String { String(localized: "Alege din poze") }
    static var files: String { String(localized: "Din Fișiere") }
    static var cancel: String { String(localized: "Renunță", comment: "Cancels a choice.") }
    static var anotherPhoto: String { String(localized: "Alege altă poză", comment: "Am rezolvat: picks another photo of the paper.") }
    static var photoDidNotOpen: String { String(localized: "Poza nu s-a putut deschide. Încearcă din nou.") }
    static var unreadMessage: String {
        String(localized: "Încearcă o poză mai clară, de aproape și fără umbre.", comment: "Am rezolvat: a paper's photo couldn't be read.")
    }
    static var billRead: String { String(localized: "Am citit factura") }
    /// Under the new end, when it isn't after today: saving waits for another day.
    static var newDayHasPassed: String { ObligationActionError.newDayHasPassed.errorDescription ?? "" }
    /// Above the button, when the cycle the sheet opened for was closed meanwhile (a reminder,
    /// the widget, another device): nothing is filed.
    static var closedMeanwhile: String { ObligationActionError.cycleClosed.errorDescription ?? "" }

    /// The sheet's title: „Am rezolvat: ITP”.
    static func title(_ deadline: String) -> String {
        String(localized: "Am rezolvat: \(deadline)")
    }

    /// Under the money field: what it cost the last time.
    static func lastCost(_ cost: String) -> String {
        String(localized: "Data trecută: \(cost).")
    }

    /// A paper read with a next date on it.
    static func nextDeadline(_ day: String) -> String {
        String(localized: "Următorul termen: \(day).")
    }

    /// A photo of the bill being paid, logged in its subscription's history.
    static func billLogged(in section: String) -> String {
        String(localized: "O trec în istoricul „\(section)”.", comment: "Am rezolvat: a photo of the bill being paid is logged in its subscription's history.")
    }

    /// The toast once it is saved, with its next due day.
    static func done(_ deadline: String, next day: String) -> LocalizedStringResource {
        "\(deadline): gata. Următorul termen e pe \(day)."
    }

    /// The toast once it is saved, with nothing next.
    static func done(_ deadline: String) -> LocalizedStringResource {
        "\(deadline): gata."
    }
}
