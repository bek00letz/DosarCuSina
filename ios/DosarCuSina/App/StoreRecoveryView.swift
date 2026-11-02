import SwiftUI

/// Shown instead of crashing when the database can't be opened. It promises
/// only what it does: trying again, or starting with an empty binder while the
/// old file stays aside, untouched, on the phone. A backup can then be put back
/// from Settings. The system's error text is never shown or read out.
struct StoreRecoveryView: View {
    let failure: PersistenceController.StoreFailure
    let retry: () -> Void
    let startFresh: () -> Void

    @State private var isConfirmingFreshStart = false

    var body: some View {
        ContentUnavailableView {
            Label {
                Text("Dosarul nu se deschide", comment: "Title when the database can't be opened.")
            } icon: {
                Image(systemName: failure == .outOfSpace ? "externaldrive.badge.exclamationmark" : "exclamationmark.triangle")
            }
        } description: {
            switch failure {
            case .outOfSpace:
                Text("Telefonul nu mai are spațiu liber. Eliberează puțin spațiu, apoi încearcă din nou.", comment: "The database can't be opened because the phone is full.")
            case .unreadable:
                Text("Încearcă din nou. Dacă tot nu merge, poți porni cu un dosar gol și pune înapoi o copie de siguranță din Setări.", comment: "The database can't be opened.")
            }
        } actions: {
            Button(action: retry) {
                Text("Încearcă din nou", comment: "Tries to open the database again.")
                    .frame(minHeight: 44)
            }
            .buttonStyle(.borderedProminent)
            if failure == .unreadable {
                Button(role: .destructive) {
                    isConfirmingFreshStart = true
                } label: {
                    Text("Pornește cu un dosar gol", comment: "Starts with an empty database.")
                        .frame(minHeight: 44)
                }
            }
        }
        .confirmationDialog(
            Text("Pornești cu un dosar gol?", comment: "Confirmation before starting with an empty database."),
            isPresented: $isConfirmingFreshStart,
            titleVisibility: .visible
        ) {
            Button(role: .destructive, action: startFresh) {
                Text("Pornește cu un dosar gol", comment: "Starts with an empty database.")
            }
        } message: {
            Text("Dosarul de acum nu se șterge: rămâne deoparte pe telefon, neatins. Aplicația pornește goală; dacă ai o copie de siguranță, o pui înapoi din Setări.", comment: "What starting with an empty database does.")
        }
    }
}

/// Shown in the rare moment the database waits for the phone to be unlocked
/// after a restart. It opens by itself; a progress line appears only if it takes a while.
struct StoreWaitingView: View {
    var body: some View {
        ZStack {
            DS.Palette.background.ignoresSafeArea()
            DSDelayedProgress(label: "Se deschide dosarul…", delay: .seconds(1))
        }
    }
}
