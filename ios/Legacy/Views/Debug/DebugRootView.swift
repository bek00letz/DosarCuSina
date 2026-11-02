import SwiftUI
import SwiftData

/// Temporary root screen between the foundation and the real screens.
/// It lists what the engine sees and exercises it; wave 2 replaces it.
struct DebugRootView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \CategoryTemplate.homeOrder) private var templates: [CategoryTemplate]
    @Query(sort: \Asset.name) private var assets: [Asset]
    @Query(sort: \Obligation.dueDate) private var obligations: [Obligation]

    @State private var errorMessage: String?

    private var digest: AttentionDigest {
        AttentionModel.digest((try? ObligationSnapshot.fetchAll(in: context)) ?? [])
    }

    var body: some View {
        NavigationStack {
            List {
                let digest = digest
                Section("Acum") {
                    if digest.now.isEmpty {
                        Text("Nimic urgent")
                            .foregroundStyle(.secondary)
                    }
                    ForEach(digest.now) { entry in
                        obligationRow(entry)
                    }
                }
                Section("Curând") {
                    ForEach(digest.soon) { group in
                        LabeledContent(group.assetName, value: "\(group.entries.count)")
                    }
                    LabeledContent("Mai târziu", value: "\(digest.later.count)")
                    LabeledContent("Ascunse", value: "\(digest.hiddenCount)")
                }
                Section("Active") {
                    ForEach(assets) { asset in
                        LabeledContent(asset.name, value: templateName(asset.templateKey))
                    }
                }
                Section("Categorii") {
                    ForEach(templates) { template in
                        Label(template.name, systemImage: template.symbol)
                            .foregroundStyle(template.isOnHome ? .primary : .secondary)
                    }
                }
            }
            .navigationTitle("Dosar cu Șină")
            .toolbar {
                #if DEBUG
                ToolbarItem(placement: .topBarLeading) {
                    NavigationLink("Galerie", destination: DesignSystemGallery())
                }
                #endif
                ToolbarItem(placement: .topBarTrailing) {
                    Menu("Exemple", systemImage: "ellipsis.circle") {
                        Button("Încarcă exemple", systemImage: "sparkles") { run { try ExampleDataService(context: context).loadExamples() } }
                        Button("Șterge exemplele", systemImage: "trash", role: .destructive) { run { try ExampleDataService(context: context).removeExamples() } }
                    }
                }
            }
            .alert("Nu a mers", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(errorMessage ?? "")
            }
        }
    }

    private func obligationRow(_ entry: AttentionEntry) -> some View {
        HStack {
            VStack(alignment: .leading) {
                Text(entry.obligation.title)
                Text(entry.obligation.assetName ?? "")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button("Rezolvă") {
                run {
                    let id = entry.obligation.id
                    guard let obligation = obligations.first(where: { $0.id == id }) else { return }
                    try ObligationActions(context: context).complete(obligation)
                }
            }
            .buttonStyle(.bordered)
        }
    }

    private func templateName(_ key: String) -> String {
        templates.first { $0.key == key }?.name ?? key
    }

    private func run(_ action: () throws -> Void) {
        do {
            try action()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
