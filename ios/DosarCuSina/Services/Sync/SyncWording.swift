import Foundation

/// What Settings says about iCloud sync, by its state: what syncs, where it goes, and what
/// turning it off does.
enum SyncWording {
    static func footer(for state: PersistenceController.SyncState) -> String {
        switch state {
        case .on, .off, .notInThisBuild:
            String(localized: "Dosarul se păstrează în iCloud-ul tău, în spațiul privat al contului, și apare pe celelalte dispozitive ale tale. Nu ai cont la noi și nimic nu trece pe la un server al nostru. Oprită, totul rămâne pe telefon.",
                   comment: "Footer of the iCloud sync setting: what syncs, where, and what turning it off does.")
        case .waitingForExamples:
            String(localized: "Cât timp sunt exemple în dosar, telefonul nu se sincronizează, ca exemplele să rămână doar aici. Pornește din nou după ce le ștergi.",
                   comment: "Footer of the iCloud sync setting while examples are in the binder.")
        }
    }
}
