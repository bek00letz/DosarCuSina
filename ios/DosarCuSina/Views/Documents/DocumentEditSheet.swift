import SwiftData
import SwiftUI

/// "Editează" on a personal document's page: correct its values, add its back when only
/// the front is kept, or read it again. Reading puts what it found into the form and says
/// which values changed, with "Păstrează ce era"; nothing is kept until "Gata", which saves
/// everything as one step the page's toast can take back (`AssetActions.editDocument`).
/// Swiping down with changes asks first.
struct DocumentEditSheet: View {
    let document: Asset
    let definition: TemplateDefinition
    /// The document's own picture, if it has one.
    let picture: Attachment?
    /// The page's toast, with the step's "Anulează".
    let announce: (DSToast) -> Void

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var name: String
    @State private var values: FieldValues
    @State private var notes: String
    @State private var addedPages: AddedPages?
    @State private var readText: String?
    @State private var reading: ReadingState = .idle
    @State private var readTask: Task<Void, Never>?
    @State private var isChoosingBackSource = false
    @State private var backSource: CaptureSource?
    @State private var revealsValidation = false
    @State private var error: UserFacingError?
    @State private var savedCount = 0
    @State private var exampleQuestion: ExampleSectionQuestion?

    /// Where reading the document again stands.
    enum ReadingState: Equatable {
        case idle
        case reading
        /// Read: the values it changed, and the form's values before, for "Păstrează ce era".
        case read(changes: [DocumentReading.Change], before: FieldValues)
        case failed(String)
    }

    init(document: Asset, definition: TemplateDefinition, picture: Attachment?, announce: @escaping (DSToast) -> Void) {
        self.document = document
        self.definition = definition
        self.picture = picture
        self.announce = announce
        _name = State(initialValue: document.name)
        _values = State(initialValue: document.values)
        _notes = State(initialValue: document.notes ?? "")
        start = AssetActions.SectionEditStart(document)
    }

    /// What the form started from: saving writes only what changed from it.
    private let start: AssetActions.SectionEditStart

    private var trimmedName: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }

    private var hasChanges: Bool {
        name != start.name || values != start.values || notes != (start.notes ?? "") || addedPages != nil || readText != nil
    }

    private var isReading: Bool { reading == .reading }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: DS.Space.xl) {
                    if let picture {
                        pictureSection(picture)
                    }
                    DSTextField("Nume", text: $name, isRequired: true)
                    SectionFieldsForm(asset: document, definition: definition, values: $values)
                    VStack(alignment: .leading, spacing: DS.Space.m) {
                        DSSectionHeader("Note")
                        DSTextField("Note", text: $notes, kind: .longText, prompt: "Orice vrei să ții minte")
                    }
                }
                .padding(DS.Space.m)
                .frame(maxWidth: 640)
                .frame(maxWidth: .infinity)
                .animation(DS.Motion.animation(DS.Motion.standard, reduceMotion: reduceMotion), value: reading)
            }
            .scrollDismissesKeyboard(.interactively)
            .background(DS.Palette.background)
            .environment(\.dsRevealsValidation, revealsValidation)
            .navigationTitle(Text("Editează actul", comment: "Title of a document's edit sheet."))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { DSCancelButton() }
                ToolbarItem(placement: .confirmationAction) {
                    Button { save() } label: {
                        Text("Gata", comment: "Closes an editor and keeps what was typed.")
                    }
                    .disabled(isReading)
                    .keyboardShortcut(.return, modifiers: .command)
                }
            }
            .userErrorAlert($error)
            .examplePrompt($exampleQuestion) { save() }
            .sensoryFeedback(.success, trigger: savedCount)
            .confirmationDialog(Text("Adaugă spatele", comment: "Title of the photo source choice for a document's back."),
                                isPresented: $isChoosingBackSource, titleVisibility: .visible) {
                if CaptureSource.isCameraAvailable {
                    Button { backSource = .camera } label: { Text("Fotografiază spatele", comment: "Back source: camera.") }
                }
                Button { backSource = .photos } label: { Text("Alege din poze", comment: "Photo source: library.") }
                Button { backSource = .files } label: { Text("Din Fișiere", comment: "Photo source: files.") }
                Button(role: .cancel) {} label: { Text("Renunță", comment: "Cancels a choice.") }
            }
            .captureSourcePicker($backSource) { payload in
                addBack(payload)
            } onError: { error in
                reading = .failed(SaveFailure.message(for: error, formKept: true))
            }
        }
        .dsDiscardGuard(hasChanges: hasChanges)
        .onDisappear { readTask?.cancel() }
    }

    // MARK: The picture

    private func pictureSection(_ picture: Attachment) -> some View {
        let kept = DocumentPages.sources(of: picture)
        let added = (addedPages?.images ?? []).enumerated().map { offset, data in
            DocumentPageSource(index: kept.count + offset, content: .image(data), framing: addedPages?.framing[safe: offset] ?? .plain)
        }
        let pages = kept + added
        let names = DocumentPageFacts.pageNames(count: pages.count)
        return VStack(alignment: .leading, spacing: DS.Space.s) {
            DSSectionHeader("Poza actului")
            DSCard {
                VStack(alignment: .leading, spacing: DS.Space.m) {
                    HStack(alignment: .top, spacing: DS.Space.s) {
                        ForEach(pages) { page in
                            VStack(spacing: DS.Space.xxs) {
                                DocumentPageImage(source: page, maxLongEdge: 480)
                                    .frame(height: 72)
                                    .clipShape(.rect(cornerRadius: DS.Radius.badge, style: .continuous))
                                    .dsHairlineBorder(RoundedRectangle(cornerRadius: DS.Radius.badge, style: .continuous))
                                Text(verbatim: names?[safe: page.index] ?? String(localized: "Pagina \(page.index + 1)", comment: "A page's number under its picture."))
                                    .dsFont(.footnote)
                            }
                            .accessibilityElement(children: .combine)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    if addedPages == nil, DocumentPageFacts.canAddBack(values, picture: picture) {
                        DSSecondaryButton("Adaugă spatele", systemImage: "rectangle.on.rectangle") { isChoosingBackSource = true }
                            .disabled(isReading)
                            .accessibilityHint(Text("Fotografiezi spatele actului sau îl alegi din poze ori din Fișiere. Îl citesc împreună cu fața.", comment: "VoiceOver hint of adding a document's back."))
                    }
                    if addedPages == nil {
                        DSSecondaryButton("Citește din nou", systemImage: "text.viewfinder") { read(adding: []) }
                            .disabled(isReading)
                            .accessibilityHint(Text("Citesc din nou poza actului, pe telefon, și completez mai jos ce găsesc.", comment: "VoiceOver hint of reading a document again."))
                    }
                    readingStatus
                }
            }
        }
    }

    /// While reading, what reading found, or why it couldn't. The progress keeps its space,
    /// so nothing moves when it shows.
    @ViewBuilder private var readingStatus: some View {
        switch reading {
        case .idle:
            EmptyView()
        case .reading:
            DSDelayedProgress(label: "Citesc actul…")
                .frame(maxWidth: .infinity, minHeight: 44)
        case .read(let changes, let before):
            if changes.isEmpty {
                DSNotice(.success, title: "Am citit din nou actul", message: "Ce e scris aici se potrivește cu ce scrie pe act.")
                    .transition(.opacity)
            } else {
                DSNotice(.info, title: "Am citit din nou actul",
                         message: LocalizedStringKey(Self.changedLine(changes)),
                         actionTitle: "Păstrează ce era") {
                    values = before
                    reading = .idle
                }
                .transition(.opacity)
            }
        case .failed(let message):
            DSNotice(.error, title: "Nu am putut citi actul", message: LocalizedStringKey(message))
                .transition(.opacity)
        }
    }

    /// "Am schimbat: CNP, Valabil până la. Verifică-le mai jos înainte să salvezi."
    static func changedLine(_ changes: [DocumentReading.Change]) -> String {
        let labels = changes.map(\.label).formatted(.list(type: .and).locale(.dosarDefault))
        return String(localized: "Am schimbat: \(labels). Verifică-le mai jos înainte să salvezi.", comment: "After reading a document again: the values it changed in the form.")
    }

    /// The back the person picked: read with the front as one document.
    private func addBack(_ payload: CaptureRequest.Payload) {
        guard case .images(let images) = payload, let back = images.first else {
            reading = .failed(String(localized: "Alege o poză a spatelui. Un PDF rămâne act separat.", comment: "A PDF was picked as a document's back."))
            return
        }
        read(adding: [back])
    }

    /// Reads the picture again (with `adding`, the back) and puts what it found into the form.
    private func read(adding: [CaptureImage]) {
        guard let picture, !isReading else { return }
        let before = values
        reading = .reading
        readTask = Task {
            do {
                let outcome = try await DocumentReading(context: context).read(document, picture: picture, adding: adding,
                                                                               into: before, definition: definition)
                guard !Task.isCancelled else { return }
                values = outcome.values
                if let pages = outcome.addedPages { addedPages = pages }
                if let text = outcome.readText { readText = text }
                reading = .read(changes: outcome.changes, before: before)
            } catch is CancellationError {
                reading = .idle
            } catch {
                guard !Task.isCancelled else { return }
                reading = .failed(SaveFailure.message(for: error, formKept: true))
            }
        }
    }

    // MARK: Saving

    private func save() {
        guard hasChanges else { dismiss(); return }
        guard !trimmedName.isEmpty, FieldValuesCheck.canSave(values, fields: definition.allFields) else {
            revealsValidation = true
            return
        }
        do {
            let note = notes.trimmingCharacters(in: .whitespacesAndNewlines)
            let edit = AssetActions.DocumentEdit(name: trimmedName, values: values, notes: note.isEmpty ? nil : note,
                                                 addedPages: addedPages, readText: readText, startedFrom: start)
            let saved = try AssetActions(context: context).editDocument(document, edit, picture: picture)
            savedCount += 1
            announce(.undo(addedPages == nil
                ? LocalizedStringResource("Actul e la zi", comment: "Toast after saving a document's edit.")
                : LocalizedStringResource("Am adăugat spatele actului", comment: "Toast after saving a document's edit with its back."),
                receipt: saved.receipt))
            dismiss()
        } catch let question as ExampleSectionQuestion {
            // The back is the person's own photo: an example becomes theirs first, if they say so.
            exampleQuestion = question
        } catch {
            self.error = UserFacingError(error)
        }
    }
}

fileprivate extension Array {
    /// The element at `index`, or nil past the end.
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
