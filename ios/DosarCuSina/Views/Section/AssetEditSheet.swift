import SwiftUI
import SwiftData
import PhotosUI

/// Edits a section's name, photo and fields with the design-system controls.
/// "Gata" saves and closes; swiping down with changes asks first, so a draft is
/// never lost by accident.
struct AssetEditSheet: View {
    let asset: Asset
    let definition: TemplateDefinition

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @State private var name: String
    @State private var values: FieldValues
    @State private var notes: String
    @State private var photoData: Data?
    @State private var photoItem: PhotosPickerItem?
    @State private var revealsValidation = false
    @State private var error: UserFacingError?
    @State private var savedCount = 0
    @State private var isMoving = false
    @State private var toast: DSToast?

    private let originalPhoto: Data?

    init(asset: Asset, definition: TemplateDefinition) {
        self.asset = asset
        self.definition = definition
        _name = State(initialValue: asset.name)
        _values = State(initialValue: asset.values)
        _notes = State(initialValue: asset.notes ?? "")
        _photoData = State(initialValue: asset.photoData)
        originalPhoto = asset.photoData
    }

    private var hasChanges: Bool {
        name != asset.name || values != asset.values || notes != (asset.notes ?? "") || photoData != originalPhoto
    }

    private var trimmedName: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: DS.Space.xl) {
                    VStack(alignment: .leading, spacing: DS.Space.m) {
                        DSTextField("Nume", text: $name, isRequired: true)
                        PhotoPickerRow(photoData: $photoData, item: $photoItem)
                        if AssetActions.parentTemplateKey(for: asset) != nil {
                            moveRow
                        }
                    }
                    ForEach(definition.sections) { section in
                        if !section.fields.isEmpty {
                            VStack(alignment: .leading, spacing: DS.Space.m) {
                                DSSectionHeader(verbatim: section.title)
                                ForEach(section.fields.filter { $0.applies(to: values) }) { field in
                                    FieldEditor(field: field, values: $values)
                                }
                            }
                        }
                    }
                    VStack(alignment: .leading, spacing: DS.Space.m) {
                        DSSectionHeader("Note")
                        DSTextField("Note", text: $notes, kind: .longText, prompt: "Orice vrei să ții minte")
                    }
                }
                .padding(DS.Space.m)
                .frame(maxWidth: 640)
                .frame(maxWidth: .infinity)
            }
            .scrollDismissesKeyboard(.interactively)
            .background(DS.Palette.background)
            .environment(\.dsRevealsValidation, revealsValidation)
            .navigationTitle(Text("Editează", comment: "Title of the edit sheet."))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { DSCancelButton() }
                ToolbarItem(placement: .confirmationAction) {
                    Button(action: save) {
                        Text("Gata", comment: "Closes an editor and keeps what was typed.")
                    }
                    .keyboardShortcut(.return, modifiers: .command)
                }
            }
            .userErrorAlert($error)
            .sensoryFeedback(.success, trigger: savedCount)
            .sheet(isPresented: $isMoving) {
                MoveAssetSheet(asset: asset) { receipt in
                    followName(from: receipt.previousName)
                    toast = .undo(receipt.toastTitle) { undoMove(receipt) }
                }
            }
            .dsToast($toast)
        }
        .dsDiscardGuard(hasChanges: hasChanges)
    }

    /// Where it is filed, and "Mută la…".
    private var moveRow: some View {
        Button { isMoving = true } label: {
            DSListRow(
                title: Text("Mută la…", comment: "Menu item that files something under another parent."),
                subtitle: asset.parent.map { Text("Acum e la „\($0.name)”.", comment: "Where the item is filed now, in the move sheet.") },
                systemImage: "arrow.turn.up.right",
                showsChevron: true
            ) { EmptyView() }
        }
        .buttonStyle(.dsPressable)
    }

    /// A move that renamed the document carries the new name into the form, unless
    /// the person had already typed one of their own.
    private func followName(from previousName: String) {
        if name == previousName { name = asset.name }
    }

    private func undoMove(_ receipt: AssetActions.MoveReceipt) {
        do {
            let renamed = asset.name
            try AssetActions(context: context).undoMove(receipt)
            followName(from: renamed)
        } catch {
            self.error = UserFacingError(error)
        }
    }

    private func save() {
        guard hasChanges else { dismiss(); return }
        guard !trimmedName.isEmpty, FieldValuesCheck.canSave(values, fields: definition.allFields) else {
            revealsValidation = true
            return
        }
        do {
            let actions = AssetActions(context: context)
            // The photo and the fields are one change: both are kept, or neither.
            try UnitOfWork.perform(in: context) {
                if photoData != originalPhoto {
                    try actions.setPhoto(asset, photoData)
                }
                if trimmedName != asset.name || values != asset.values || notes != (asset.notes ?? "") {
                    let note = notes.trimmingCharacters(in: .whitespacesAndNewlines)
                    try actions.update(asset, name: trimmedName, values: values, notes: note.isEmpty ? nil : note)
                }
            }
            savedCount += 1
            dismiss()
        } catch {
            self.error = UserFacingError(error)
        }
    }
}

/// Picks a photo from the library (no permission needed) or removes it.
struct PhotoPickerRow: View {
    @Binding var photoData: Data?
    @Binding var item: PhotosPickerItem?

    var body: some View {
        HStack(spacing: DS.Space.m) {
            if let photoData, let image = UIImage(data: photoData) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 64, height: 64)
                    .clipShape(.rect(cornerRadius: DS.Radius.control, style: .continuous))
                    .accessibilityHidden(true)
            }
            VStack(alignment: .leading, spacing: DS.Space.xs) {
                let title = photoData == nil
                    ? Text("Alege o poză", comment: "Button that picks a photo for a section.")
                    : Text("Schimbă poza", comment: "Button that picks a photo for a section.")
                PhotosPicker(selection: $item, matching: .images) {
                    Label {
                        title
                    } icon: {
                        Image(systemName: "photo")
                    }
                    .frame(minHeight: 44)
                }
                if photoData != nil {
                    Button(role: .destructive) {
                        photoData = nil
                        item = nil
                    } label: {
                        Text("Scoate poza", comment: "Button that removes a section's photo.")
                            .frame(minHeight: 44)
                    }
                    .buttonStyle(.borderless)
                }
            }
            Spacer(minLength: 0)
        }
        .onChange(of: item) { _, newItem in
            guard let newItem else { return }
            Task { @MainActor in
                guard let data = try? await newItem.loadTransferable(type: Data.self),
                      let image = UIImage(data: data) else { return }
                // Keep photos small: they show as boxes and heroes, never full screen.
                let side: CGFloat = 1200
                let scale = min(1, side / max(image.size.width, image.size.height))
                let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
                let resized = await image.byPreparingThumbnail(ofSize: size) ?? image
                photoData = resized.jpegData(compressionQuality: 0.8)
            }
        }
    }
}
