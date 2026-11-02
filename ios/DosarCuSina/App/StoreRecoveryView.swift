import SwiftUI

/// Shown instead of crashing when the database can't be opened.
/// Starting fresh keeps the old file next to the new one, renamed.
struct StoreRecoveryView: View {
    let message: String
    let retry: () -> Void
    let startFresh: () -> Void

    @State private var isConfirmingFreshStart = false

    var body: some View {
        ContentUnavailableView {
            Label("Datele nu se deschid", systemImage: "exclamationmark.triangle")
        } description: {
            Text("Încearcă din nou. Dacă nu merge, poți porni cu date noi; copia veche rămâne pe telefon.")
        } actions: {
            Button("Încearcă din nou", action: retry)
                .buttonStyle(.borderedProminent)
            Button("Pornește cu date noi", role: .destructive) {
                isConfirmingFreshStart = true
            }
        }
        .confirmationDialog("Pornești cu date noi?", isPresented: $isConfirmingFreshStart, titleVisibility: .visible) {
            Button("Pornește cu date noi", role: .destructive, action: startFresh)
        } message: {
            Text("Datele de acum nu se șterg; sunt mutate deoparte și pot fi recuperate.")
        }
        .accessibilityHint(Text(verbatim: message))
    }
}
