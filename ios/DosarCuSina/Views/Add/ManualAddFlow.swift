import SwiftData
import SwiftUI

/// "Scriu eu": pick the section, then what to add to it: a deadline, a visit,
/// or a document. Everything saves through the engine's actions.
struct ManualAddFlow: View {
    /// Called when the flow closes, with a confirmation to show, if anything was saved.
    let onClose: (LocalizedStringResource?) -> Void

    @Query(sort: \CategoryTemplate.homeOrder) private var templates: [CategoryTemplate]
    @Query(sort: \Asset.name) private var assets: [Asset]

    @State private var path: [ManualStep] = []
    @State private var isCreatingSection = false
    @Environment(\.announce) private var announce

    var body: some View {
        NavigationStack(path: $path) {
            List {
                if assets.isEmpty {
                    Text("Nu ai încă nicio secțiune. Fă una nouă mai jos.")
                        .dsFont(.subheadline)
                }
                ForEach(templates.filter { template in assets.contains { $0.templateKey == template.key } }) { template in
                    Section {
                        ForEach(assets.filter { $0.templateKey == template.key }) { asset in
                            NavigationLink(value: ManualStep.what(asset.id)) {
                                DSListRow(
                                    title: Text(verbatim: asset.name),
                                    subtitle: asset.isExample ? Text("Exemplu") : nil,
                                    systemImage: asset.symbolOverride ?? template.symbol,
                                    tint: (asset.tintOverride ?? template.tint).color,
                                    trailing: { EmptyView() }
                                )
                            }
                        }
                    } header: {
                        Text(verbatim: template.name).textCase(nil)
                    }
                }
                Section {
                    Button { isCreatingSection = true } label: {
                        DSListRow("Secțiune nouă", subtitle: "O mașină, o casă, un animal, un act…", systemImage: "folder.badge.plus", showsChevron: true)
                    }
                    .buttonStyle(.plain)
                }
            }
            .navigationTitle("Unde adaugi?")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Închide") { onClose(nil) } }
            }
            .navigationDestination(for: ManualStep.self) { step in
                switch step {
                case .what(let id):
                    ManualWhatView(assetID: id, path: $path, onClose: onClose)
                case .deadline(let id):
                    DeadlineForm(assetID: id) { message in onClose(message) }
                case .visit(let id):
                    AddVisitFlow(assetID: id, prefill: nil) { receipt in
                        // This sheet closes: the shell shows the toast, with its "Anulează".
                        if let receipt, let toast = CaptureFlowResult.visit(receipt: receipt).toast { announce(toast) }
                        onClose(nil)
                    }
                }
            }
            .sheet(isPresented: $isCreatingSection) {
                // The same flow as "Adaugă o secțiune" on the binder: category, details, deadlines.
                AddSectionFlow(request: .topLevel) { asset in
                    isCreatingSection = false
                    path.append(.what(asset.id))
                }
            }
        }
    }
}

enum ManualStep: Hashable {
    case what(UUID)
    case deadline(UUID)
    case visit(UUID)
}

/// What to add to the chosen section.
private struct ManualWhatView: View {
    let assetID: UUID
    @Binding var path: [ManualStep]
    let onClose: (LocalizedStringResource?) -> Void

    @Environment(\.announce) private var announce
    @Query private var assets: [Asset]
    @State private var source: CaptureSource?
    @State private var isChoosingSource = false
    @State private var flow: CaptureFlowInput?
    @State private var errorMessage: String?

    var body: some View {
        let asset = assets.first { $0.id == assetID }
        ScrollView {
            VStack(alignment: .leading, spacing: DS.Space.s) {
                if let asset {
                    Text(verbatim: asset.name).dsFont(.title).padding(.bottom, DS.Space.xs)
                }
                DSActionCard("Un termen", subtitle: "ITP, o asigurare, un vaccin, o plată.", systemImage: "calendar.badge.clock") {
                    path.append(.deadline(assetID))
                }
                DSActionCard("O vizită sau o reparație", subtitle: "Ce s-a făcut, cât a costat, cine a lucrat.", systemImage: "wrench.and.screwdriver") {
                    path.append(.visit(assetID))
                }
                DSActionCard("Un act", subtitle: "Poză, PDF sau scanare. Îl citesc și ți-l arăt.", systemImage: "doc.viewfinder") {
                    isChoosingSource = true
                }
                if let errorMessage {
                    DSNotice(.error, title: "Nu s-a deschis", message: LocalizedStringKey(errorMessage))
                }
            }
            .padding(DS.Space.m)
        }
        .background(DS.Palette.background)
        .navigationTitle("Ce adaugi?")
        .navigationBarTitleDisplayMode(.inline)
        .confirmationDialog("Un act", isPresented: $isChoosingSource, titleVisibility: .visible) {
            if CaptureSource.isCameraAvailable { Button("Fotografiază actul") { source = .camera } }
            Button("Alege din poze") { source = .photos }
            Button("Din Fișiere") { source = .files }
            Button("Renunță", role: .cancel) {}
        }
        .captureSourcePicker($source) { payload in
            flow = CaptureFlowInput(payload: payload, preferredAssetID: assetID)
        } onError: { error in
            errorMessage = SaveFailure.message(for: error, formKept: true)
        }
        .sheet(item: $flow) { input in
            CaptureFlowView(input: input) { result in
                flow = nil
                switch result {
                case .filed(let toast, _), .visitSaved(let toast):
                    // This sheet closes: the shell shows the toast, with its "Anulează".
                    announce(toast)
                    onClose(nil)
                case .dismissed: break
                }
            }
        }
    }
}
