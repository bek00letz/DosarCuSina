import Foundation

/// How the part a section belongs to is said (a home, a car, a person): one place for „Ține de…”
/// in a category of one's own, the add form's choice, „Mută la…” and the suggestion to move
/// sections under the only one. By the part (`CategoryBehavior.Role`), never by a category's name,
/// so a category of one's own that plays a home's part reads as a home. A part that holds no
/// sections reads as a section.
public enum BelongingWording {
    /// Its option in „Ține de…”: „O locuință”, „O mașină”, „O persoană”.
    public static func option(_ role: CategoryBehavior.Role) -> String {
        switch role {
        case .home: String(localized: "O locuință", comment: "„Ține de…” choice of a category of one's own: its sections belong to a home.")
        case .vehicle: String(localized: "O mașină", comment: "„Ține de…” choice of a category of one's own: its sections belong to a car.")
        case .holder: String(localized: "O persoană", comment: "„Ține de…” choice of a category of one's own: its sections belong to a person.")
        case .personalDocument, .subscription: String(localized: "O secțiune", comment: "„Ține de…” choice for a part that holds no sections.")
        }
    }

    /// The add form's choice of which one: „Locuința”, „Mașina”, „Persoana”.
    public static func fieldTitle(_ role: CategoryBehavior.Role) -> String {
        switch role {
        case .home: String(localized: "Locuința", comment: "Add form: the home a new section (a plant) is filed under.")
        case .vehicle: String(localized: "Mașina", comment: "Add form: the car a new section is filed under.")
        case .holder: String(localized: "Persoana", comment: "Add form: the person a new section is filed under.")
        case .personalDocument, .subscription: String(localized: "Secțiunea", comment: "Add form: the section a new one is filed under.")
        }
    }

    /// Under that choice: where it shows, and how to change it.
    public static func fieldFootnote(_ role: CategoryBehavior.Role) -> String {
        switch role {
        case .home: String(localized: "Apare și pe pagina locuinței. Poți schimba oricând, cu „Mută la…”.", comment: "Add form footnote under the home a section is filed under.")
        case .vehicle: String(localized: "Apare și pe pagina mașinii. Poți schimba oricând, cu „Mută la…”.", comment: "Add form footnote under the car a section is filed under.")
        case .holder: String(localized: "Apare și pe pagina persoanei. Poți schimba oricând, cu „Mută la…”.", comment: "Add form footnote under the person a section is filed under.")
        case .personalDocument, .subscription: String(localized: "Apare și pe pagina ei. Poți schimba oricând, cu „Mută la…”.", comment: "Add form footnote under the section a new one is filed under.")
        }
    }

    /// „Mută la…”'s option to stand on its own, in its category's box: „În „Plante”, fără locuință”.
    public static func standingAlone(_ role: CategoryBehavior.Role, in category: String) -> String {
        switch role {
        case .home: String(localized: "În „\(category)”, fără locuință", comment: "Move option: a subscription or a plant stands on its own, in its category's box (Abonamente, Plante).")
        case .vehicle: String(localized: "În „\(category)”, fără mașină", comment: "Move option: a section of a category that belongs to a car stands on its own, in its category's box.")
        case .holder: String(localized: "În „\(category)”, fără persoană", comment: "Move option: a section of a category that belongs to a person stands on its own, in its category's box.")
        case .personalDocument, .subscription: String(localized: "În „\(category)”, pe cont propriu", comment: "Move option: a section stands on its own, in its category's box.")
        }
    }

    /// The suggestion to file a section standing on its own under the household's only one.
    public static func moveSuggestion(_ role: CategoryBehavior.Role, section: String, parent: String, category: String) -> String {
        switch role {
        case .home: String(localized: "Trec „\(section)” la „\(parent)”? Apare pe pagina locuinței și rămâne în „\(category)”.", comment: "Repair: file a section standing on its own (a plant) under the household's only home; it stays in its category's box.")
        case .vehicle: String(localized: "Trec „\(section)” la „\(parent)”? Apare pe pagina mașinii și rămâne în „\(category)”.", comment: "Repair: file a section standing on its own under the household's only car; it stays in its category's box.")
        case .holder: String(localized: "Trec „\(section)” la „\(parent)”? Apare pe pagina persoanei și rămâne în „\(category)”.", comment: "Repair: file a section standing on its own under the household's only person; it stays in its category's box.")
        case .personalDocument, .subscription: String(localized: "Trec „\(section)” la „\(parent)”? Apare pe pagina ei și rămâne în „\(category)”.", comment: "Repair: file a section standing on its own under the only section it can go under.")
        }
    }

    /// With several, the note that says to move them one by one.
    public static func severalNote(_ role: CategoryBehavior.Role, category: String) -> String {
        switch role {
        case .home: String(localized: "„\(category)” pot sta acum și într-o locuință. Ai mai multe, așa că le muți tu, din pagina fiecăreia, cu „Mută la…”.", comment: "Repair note: a category's sections (plants) can now be filed under a home; with several homes the person moves each with 'Mută la…'.")
        case .vehicle: String(localized: "„\(category)” pot sta acum și la o mașină. Ai mai multe, așa că le muți tu, din pagina fiecăreia, cu „Mută la…”.", comment: "Repair note: a category's sections can now be filed under a car; with several cars the person moves each with 'Mută la…'.")
        case .holder: String(localized: "„\(category)” pot sta acum și la o persoană. Ai mai multe, așa că le muți tu, din pagina fiecăreia, cu „Mută la…”.", comment: "Repair note: a category's sections can now be filed under a person; with several people the person moves each with 'Mută la…'.")
        case .personalDocument, .subscription: String(localized: "„\(category)” pot sta acum și în altă secțiune. Le muți tu, din pagina fiecăreia, cu „Mută la…”.", comment: "Repair note: a category's sections can now be filed under another section.")
        }
    }
}
