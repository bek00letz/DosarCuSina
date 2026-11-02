import SwiftUI
import SwiftData

/// Full lists behind a pocket's "Vezi tot".
enum SectionListRoute: Hashable {
    case obligations(UUID)
    case history(UUID)
    case people(UUID)
    case documents(UUID)
    case children(UUID, templateKey: String)
}

/// The page of one asset: a hero, then the category's pockets in the global
/// order, all in one vertical scroll. Locked categories show a calm locked state
/// until Face ID opens them.
struct SectionScreen: View {
    let assetID: UUID
    @Query private var matches: [Asset]

    init(assetID: UUID) {
        self.assetID = assetID
        let id = assetID
        _matches = Query(filter: #Predicate<Asset> { $0.id == id })
    }

    var body: some View {
        if let asset = matches.first {
            SectionContent(asset: asset)
        } else {
            MissingRecordView()
        }
    }
}

/// Shown when a link points at something that was deleted.
struct MissingRecordView: View {
    var body: some View {
        DSEmptyState(
            "Nu mai e aici",
            systemImage: "questionmark.folder",
            message: "A fost șters sau mutat. Găsești restul în Dosar."
        )
        .background(DS.Palette.background)
    }
}

private struct SectionContent: View {
    let asset: Asset

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(BiometricVaultManager.self) private var vault
    @Query private var templates: [CategoryTemplate]

    @State private var isEditing = false
    @State private var isConfirmingDelete = false
    @State private var error: UserFacingError?
    @State private var toast: DSToast?

    init(asset: Asset) {
        self.asset = asset
        let key = asset.templateKey
        _templates = Query(filter: #Predicate<CategoryTemplate> { $0.key == key })
    }

    private var template: CategoryTemplate? { templates.first }

    var body: some View {
        Group {
            if let template, vault.isLocked(template) {
                LockedSectionView(title: asset.name)
            } else {
                page
            }
        }
        .navigationTitle(Text(verbatim: asset.name))
        .navigationBarTitleDisplayMode(.inline)
    }

    private var page: some View {
        let definition = template?.definition ?? BuiltInTemplates.definition(for: asset.templateKey) ?? BuiltInTemplates.other
        return ScrollView {
            VStack(alignment: .leading, spacing: DS.Space.xl) {
                SectionHero(asset: asset, definition: definition)
                ForEach(definition.pockets, id: \.self) { pocket in
                    PocketView(pocket: pocket, asset: asset, definition: definition, toast: $toast, error: $error)
                }
                deleteButton
            }
            .padding(.horizontal, DS.Space.m)
            .padding(.bottom, DS.Space.xxl)
            .frame(maxWidth: 720)
            .frame(maxWidth: .infinity)
        }
        .background(DS.Palette.background)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    isEditing = true
                } label: {
                    Text("Editează", comment: "Toolbar button that edits a section's details.")
                }
                .keyboardShortcut("e", modifiers: .command)
            }
        }
        .sheet(isPresented: $isEditing) {
            AssetEditSheet(asset: asset, definition: definition)
        }
        .confirmationDialog(deleteTitle, isPresented: $isConfirmingDelete, titleVisibility: .visible) {
            deleteActions
        } message: {
            deleteMessage
        }
        .dsToast($toast)
        .userErrorAlert($error)
    }

    // MARK: Delete

    private var deleteButton: some View {
        DSWideButton(verbatim: String(localized: "Șterge „\(asset.name)”", comment: "Button at the bottom of a section page."),
                     systemImage: "trash", isProminent: false, role: .destructive) {
            isConfirmingDelete = true
        }
        .padding(.top, DS.Space.l)
    }

    private var deleteTitle: Text {
        Text("Ștergi „\(asset.name)”?", comment: "Title of the delete confirmation for a section.")
    }

    @ViewBuilder
    private var deleteActions: some View {
        if asset.childCount > 0 {
            Button(role: .destructive) { delete(children: .delete) } label: {
                Text("Șterge tot, cu ce e în el", comment: "Delete an asset and everything filed under it.")
            }
            Button { delete(children: .keep) } label: {
                Text("Șterge doar „\(asset.name)”", comment: "Delete an asset but keep what is filed under it.")
            }
        } else {
            Button(role: .destructive) { delete(children: .keep) } label: {
                Text("Șterge", comment: "Confirm deleting.")
            }
        }
        Button(role: .cancel) {} label: { Text("Păstrează", comment: "Cancel a delete.") }
    }

    private var deleteMessage: Text {
        if asset.childCount > 0 {
            return Text("Are lucruri trecute sub el, de exemplu chiriași, produse sau acte. Dacă le păstrezi, rămân în dosar fără să fie sub „\(asset.name)”. Termenele, istoricul și documentele lui se șterg de pe acest telefon.", comment: "Delete confirmation when the asset has children.")
        }
        return Text("Termenele, istoricul și documentele lui se șterg de pe acest telefon.", comment: "Delete confirmation message.")
    }

    private func delete(children: AssetActions.ChildrenOnDelete) {
        do {
            try AssetActions(context: context).delete(asset, children: children)
            dismiss()
        } catch {
            self.error = UserFacingError(error)
        }
    }
}

/// One pocket of a section page.
private struct PocketView: View {
    let pocket: SectionPocket
    let asset: Asset
    let definition: TemplateDefinition
    @Binding var toast: DSToast?
    @Binding var error: UserFacingError?

    var body: some View {
        switch pocket {
        case .upcoming:
            UpcomingPocket(asset: asset)
        case .tenants:
            ChildrenPocket(asset: asset, pocket: pocket, childKey: BuiltInTemplates.Key.tenancy)
        case .products:
            ChildrenPocket(asset: asset, pocket: pocket, childKey: BuiltInTemplates.Key.purchase)
        case .subscriptions:
            ChildrenPocket(asset: asset, pocket: pocket, childKey: BuiltInTemplates.Key.subscription)
        case .documents:
            DocumentsPocket(asset: asset)
        case .history:
            HistoryPocket(asset: asset, definition: definition)
        case .people:
            PeoplePocket(asset: asset)
        case .money:
            MoneyPocket(asset: asset, definition: definition)
        case .keyFacts:
            KeyFactsPocket(asset: asset, definition: definition, toast: $toast, error: $error)
        }
    }
}
