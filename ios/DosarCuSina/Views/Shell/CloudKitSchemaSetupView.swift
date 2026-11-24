#if DEBUG
import SwiftUI

/// The only screen of a launch for `CloudKitSchemaSetup`: it writes the layout as it opens and
/// says how it went. Development builds only, so its words are written verbatim.
struct CloudKitSchemaSetupView: View {
    @State private var outcome: CloudKitSchemaSetup.Outcome?
    @State private var isRunning = false

    var body: some View {
        NavigationStack {
            Group {
                switch outcome {
                case nil:
                    VStack(spacing: DS.Space.s) {
                        Text(verbatim: "Scriu în iCloud forma dosarului…")
                            .font(.headline)
                        DSDelayedProgress(label: nil)
                    }
                    .multilineTextAlignment(.center)
                    .padding(DS.Space.xxl)
                case .done:
                    ContentUnavailableView {
                        Label { Text(verbatim: "Forma dosarului e în iCloud") } icon: { Image(systemName: "checkmark.icloud.fill") }
                    } description: {
                        Text(verbatim: "Acum o poți trimite în producție din CloudKit Console (Deploy Schema Changes). Închide aplicația și pornește-o din schema obișnuită.")
                    }
                case .failed(let reason):
                    ContentUnavailableView {
                        Label { Text(verbatim: "Nu am putut scrie în iCloud") } icon: { Image(systemName: "exclamationmark.icloud.fill") }
                    } description: {
                        Text(verbatim: "Verifică că telefonul e conectat la iCloud și are internet, apoi încearcă din nou. (\(reason))")
                    }
                    .dsPinnedAction {
                        DSPrimaryButton(verbatim: "Încearcă din nou") { Task { await run() } }
                    }
                }
            }
            .navigationTitle(Text(verbatim: "Forma pentru iCloud"))
        }
        .task { await run() }
    }

    private func run() async {
        guard !isRunning else { return }
        isRunning = true
        outcome = nil
        outcome = await CloudKitSchemaSetup.run()
        isRunning = false
    }
}
#endif
