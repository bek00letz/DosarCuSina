import Foundation

/// What Settings says about iCloud sync, by its state: what syncs, where it goes, and what
/// turning it off does; and, under the switch, how it is going and what to do when it isn't.
enum SyncWording {
    static func footer(for state: PersistenceController.SyncState) -> String {
        switch state {
        case .waitingForExamples:
            String(localized: "Cât timp sunt exemple în dosar, telefonul nu se sincronizează, ca exemplele să rămână doar aici. Pornește din nou după ce le ștergi.",
                   comment: "Footer of the iCloud sync setting while examples are in the binder.")
        default:
            String(localized: "Dosarul se păstrează în iCloud-ul tău, în spațiul privat al contului, și apare pe celelalte dispozitive ale tale. Nu ai cont la noi și nimic nu trece pe la un server al nostru. Oprită, totul rămâne pe telefon.",
                   comment: "Footer of the iCloud sync setting: what syncs, where, and what turning it off does.")
        }
    }

    /// How a status line reads at a glance.
    enum Tone: Equatable {
        /// All is well.
        case fine
        /// Something is under way; nothing to do.
        case working
        /// The person can do something about it.
        case attention
    }

    /// What the person can do from the status line.
    enum Action: Equatable {
        /// Sync stopped by itself: try again.
        case retry
        /// Another iCloud account: sync with this one, keeping a copy first.
        case syncWithThisAccount
    }

    struct Status: Equatable {
        var title: String
        var detail: String? = nil
        var tone: Tone
        var action: Action? = nil
    }

    /// The line under the switch; nil where there is nothing to say (sync off, not in this build,
    /// examples, which the footer explains).
    static func status(sync: PersistenceController.SyncState, health: SyncHealth?, isStopping: Bool) -> Status? {
        if isStopping {
            return Status(title: String(localized: "Se oprește sincronizarea…", comment: "iCloud sync status while the container that synced is going."), tone: .working)
        }
        switch sync {
        case .notInThisBuild, .off, .waitingForExamples:
            return nil
        case .checkingAccount:
            return Status(
                title: String(localized: "Verific contul iCloud…", comment: "iCloud sync status while the account is being asked about."),
                detail: String(localized: "Între timp, dosarul e întreg pe telefon.", comment: "iCloud sync status detail while the account is being asked about."),
                tone: .working
            )
        case .noAccount:
            return Status(
                title: String(localized: "Nu ești conectat la iCloud", comment: "iCloud sync status: no iCloud account on the phone."),
                detail: String(localized: "Dosarul rămâne pe telefon. Conectează-te la iCloud din Configurări și se sincronizează singur.",
                               comment: "iCloud sync status detail: no iCloud account; what happens and what to do."),
                tone: .attention
            )
        case .otherAccount:
            return Status(
                title: String(localized: "Ești conectat la alt cont iCloud", comment: "iCloud sync status: the phone is signed into another account than the binder synced with."),
                detail: String(localized: "Dosarul de pe telefon s-a sincronizat cu alt cont, așa că rămâne aici și nu se amestecă. Ca să folosești contul acesta, păstrez întâi o copie a dosarului de acum.",
                               comment: "iCloud sync status detail: another account; the binder stays on the phone, and what switching does."),
                tone: .attention,
                action: .syncWithThisAccount
            )
        case .paused(.iCloudFull):
            return Status(
                title: String(localized: "Spațiul din iCloud e plin", comment: "iCloud sync status: the person's iCloud storage is full."),
                detail: String(localized: "Ce schimbi rămâne pe telefon, dar nu mai ajunge pe celelalte dispozitive. Fă loc în iCloud, apoi apasă „Încearcă din nou”.",
                               comment: "iCloud sync status detail: iCloud full; what happens and what to do."),
                tone: .attention,
                action: .retry
            )
        case .paused(.couldNotStart):
            return Status(
                title: String(localized: "Sincronizarea nu a pornit", comment: "iCloud sync status: the store couldn't open with iCloud."),
                detail: String(localized: "Dosarul e întreg pe telefon. Încearcă din nou peste câteva minute.",
                               comment: "iCloud sync status detail: sync couldn't start; the binder is safe, and what to do."),
                tone: .attention,
                action: .retry
            )
        case .on:
            return status(of: health ?? .starting)
        }
    }

    private static func status(of health: SyncHealth) -> Status {
        switch health {
        case .starting:
            Status(title: String(localized: "Pornește sincronizarea…", comment: "iCloud sync status while sync starts."), tone: .working)
        case .downloading:
            Status(
                title: String(localized: "Se aduce dosarul din iCloud…", comment: "iCloud sync status during the first download on this phone."),
                detail: String(localized: "Ce ai pe celelalte dispozitive apare aici pe rând.", comment: "iCloud sync status detail during the first download."),
                tone: .working
            )
        case .upToDate:
            Status(title: String(localized: "Totul e sincronizat", comment: "iCloud sync status: everything went up and came down."), tone: .fine)
        case .waitingForNetwork:
            Status(
                title: String(localized: "Aștept internetul", comment: "iCloud sync status: no network."),
                detail: String(localized: "Ce schimbi rămâne pe telefon și pleacă singur când revine internetul.", comment: "iCloud sync status detail: no network; what happens."),
                tone: .working
            )
        case .retrying:
            Status(
                title: String(localized: "iCloud a cerut o pauză", comment: "iCloud sync status: iCloud is busy; the system tries again."),
                detail: String(localized: "Încerc din nou singur. Ce schimbi rămâne pe telefon între timp.", comment: "iCloud sync status detail: iCloud busy; what happens."),
                tone: .working
            )
        case .iCloudFull:
            Status(title: String(localized: "Spațiul din iCloud e plin", comment: "iCloud sync status: the person's iCloud storage is full."), tone: .attention)
        case .notSignedIn:
            Status(title: String(localized: "Verific contul iCloud…", comment: "iCloud sync status while the account is being asked about."), tone: .working)
        }
    }
}
