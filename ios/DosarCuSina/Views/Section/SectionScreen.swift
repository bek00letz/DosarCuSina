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
    @State private var isMoving = false
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
                if definition.behavior.role == .personalDocument, (asset.attachments ?? []).isEmpty {
                    DocumentPhotoPrompt(asset: asset, toast: $toast)
                }
                SecretFieldsCard(asset: asset, definition: definition)
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
            if AssetActions.parentTemplateKey(for: asset) != nil {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button {
                            isMoving = true
                        } label: {
                            Label { Text("Mută la…", comment: "Menu item that files something under another parent.") } icon: { Image(systemName: "arrow.turn.up.right") }
                        }
                    } label: {
                        Label { Text("Mai multe", comment: "Toolbar menu with more actions for a section.") } icon: { Image(systemName: "ellipsis.circle") }
                    }
                }
            }
        }
        .sheet(isPresented: $isEditing) {
            AssetEditSheet(asset: asset, definition: definition)
        }
        .sheet(isPresented: $isMoving) {
            MoveAssetSheet(asset: asset) { moved in
                toast = .undo(moved.toastTitle, receipt: moved.receipt)
            }
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
        DSSecondaryButton(verbatim: String(localized: "Șterge „\(asset.name)”", comment: "Button at the bottom of a section page."),
                          systemImage: "trash", role: .destructive) {
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
            ChildrenPocket(asset: asset, pocket: pocket)
        case .products:
            ChildrenPocket(asset: asset, pocket: pocket)
        case .subscriptions:
            ChildrenPocket(asset: asset, pocket: pocket)
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

/// On a document that has no picture yet: "Adaugă poza actului", front and
/// centre. The photo goes through capture, which fills in what it reads.
private struct DocumentPhotoPrompt: View {
    let asset: Asset
    @Binding var toast: DSToast?

    @State private var isChoosingSource = false
    @State private var source: CaptureSource?
    @State private var flow: CaptureFlowInput?
    @State private var errorMessage: String?

    var body: some View {
        DSCard {
            VStack(alignment: .leading, spacing: DS.Space.s) {
                HStack(alignment: .top, spacing: DS.Space.s) {
                    DSIconWell(systemImage: "camera.fill", tint: DS.Palette.accent)
                    VStack(alignment: .leading, spacing: DS.Space.xxs) {
                        Text("Nu are încă poza actului", comment: "Prompt on a document page without a picture.")
                            .dsFont(.headline)
                        Text("Cu poza la îndemână nu mai cauți actul prin casă. Ce citesc din ea completez aici.", comment: "Why to add a picture of a document.")
                            .dsFont(.subheadline)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                DSPrimaryButton("Adaugă poza actului", systemImage: "camera.fill") { isChoosingSource = true }
                if let errorMessage {
                    DSNotice(.error, title: "Nu s-a deschis", message: LocalizedStringKey(errorMessage))
                }
            }
        }
        .confirmationDialog(Text("Adaugă poza actului", comment: "Title of the photo source choice for a document."), isPresented: $isChoosingSource, titleVisibility: .visible) {
            if CaptureSource.isCameraAvailable {
                Button { source = .camera } label: { Text("Fotografiază actul", comment: "Photo source: camera.") }
            }
            Button { source = .photos } label: { Text("Alege din poze", comment: "Photo source: library.") }
            Button { source = .files } label: { Text("Din Fișiere", comment: "Photo source: files.") }
            Button(role: .cancel) {} label: { Text("Renunță", comment: "Cancels a choice.") }
        }
        .captureSourcePicker($source) { payload in
            errorMessage = nil
            flow = CaptureFlowInput(payload: payload, preferredAssetID: asset.id)
        } onError: { error in
            errorMessage = SaveFailure.message(for: error, formKept: false)
        }
        .sheet(item: $flow) { input in
            CaptureFlowView(input: input) { result in
                flow = nil
                switch result {
                case .filed(let message, _), .visitSaved(let message):
                    toast = DSToast(title: message, actionTitle: nil, action: nil)
                case .dismissed:
                    break
                }
            }
        }
    }
}

/// The asset's secret fields (an electronic identity card's PIN codes), masked.
/// Showing or copying one asks for Face ID every time, even with the section open.
private struct SecretFieldsCard: View {
    let asset: Asset
    let definition: TemplateDefinition

    @Environment(BiometricVaultManager.self) private var vault

    var body: some View {
        let fields = SecretFields.fields(in: definition).filter { $0.applies(to: asset.values) }
        if !fields.isEmpty {
            DSPocketCard(String(localized: "Coduri PIN", comment: "Header of the secret codes on a document page.")) {
                ForEach(Array(fields.enumerated()), id: \.element.key) { index, field in
                    if index > 0 { DSRowSeparator() }
                    let sealed = asset.value(field.key)?.textValue
                    DSSecretValueRow(
                        title: Text(verbatim: field.label),
                        footnote: sealed == nil
                            ? Text("Îl poți scrie din Editează. Îl arăt doar după Face ID.", comment: "Footnote of an empty secret code row.")
                            : nil,
                        isSet: sealed != nil
                    ) {
                        guard let sealed else { return .notAuthenticated }
                        return await SecretReveal(vault: vault).open(
                            sealed,
                            reason: String(localized: "Arată \(field.label)", comment: "Face ID reason when showing a secret code.")
                        )
                    }
                }
            }
        }
    }
}
