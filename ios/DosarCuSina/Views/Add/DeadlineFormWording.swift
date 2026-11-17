import Foundation

/// The words the deadline form (`DeadlineForm`) says for every category alike: what varies by
/// category is the category's own (its usual deadlines, their notes and reminders), and a
/// deadline of one's own is asked the same everywhere, so its example fits any section.
/// `docs/COPY_MATRIX.md` lists them (`CopyMatrixTests`).
enum DeadlineFormWording {
    static var title: String { String(localized: "Un termen") }
    static var which: String { String(localized: "Ce termen") }
    static var own: String { String(localized: "Alt termen") }
    static var ownHint: String { String(localized: "Scrii tu ce e.") }
    static var ownTitle: String { String(localized: "Ce trebuie făcut") }
    /// An example that fits a deadline of one's own in any category.
    static var ownTitleExample: String {
        String(localized: "O verificare, o plată, o programare", comment: "Deadline form: example of a deadline of one's own, for any section.")
    }
    static var importance: String { String(localized: "Cât de important e") }
    static var repeats: String { String(localized: "Se repetă") }
    static var when: String { String(localized: "Când e termenul") }
    static var date: String { String(localized: "Data") }
    static var save: String { String(localized: "Salvează termenul") }
    static var notSaved: String { String(localized: "Nu s-a salvat") }

    /// The confirmation once it is saved, with how it will remind: „Am adăugat termenul „Udat”.”
    /// The deadline's title is the person's or its category's words, quoted, so it reads as a
    /// name whatever it is („ITP”, „Udat”, „Schimb filtru de apă”).
    static func added(_ deadline: String, reminders: String) -> LocalizedStringResource {
        LocalizedStringResource("Am adăugat termenul „\(deadline)”. \(reminders)",
                                comment: "Deadline form: saved. The first argument is the deadline's title, the second how it reminds („Te anunț cu 7 zile înainte.”).")
    }
}
