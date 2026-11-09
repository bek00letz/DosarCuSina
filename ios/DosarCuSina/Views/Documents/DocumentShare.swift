import SwiftData
import SwiftUI

/// What "Trimite" sends: a document's pages as they are shown, a neutral name for the
/// files, and what decides how it is asked (a locked category, a bank card).
struct DocumentShareRequest: Identifiable, Sendable {
    let id = UUID()
    let pages: [DocumentPageSource]
    /// The document's type or kind ("Carte de identitate", "Poliță"), never its holder or number.
    let name: String
    /// The document's category is locked: Face ID or the passcode first, every time.
    let isFromLockedCategory: Bool
    /// The document came as a PDF: it goes as one PDF unless the person chooses pictures.
    let isPDF: Bool
    /// Its picture shows what is sent only to someone the person trusts (a bank card's number).
    let needsCare: Bool

    @MainActor
    init(attachment: Attachment, context: ModelContext) {
        pages = DocumentPages.sources(of: attachment)
        name = DocumentShareFiles.name(for: attachment)
        let template = attachment.asset.flatMap { asset in (try? TemplateStore(context: context).template(forKey: asset.templateKey)) ?? nil }
        isFromLockedCategory = template?.isSensitive ?? false
        isPDF = pages.first?.isPDF ?? false
        needsCare = DocumentType.isSharedWithCare(attachment.asset?.values[DocumentType.typeFieldKey]?.textValue)
    }

    init(pages: [DocumentPageSource], name: String, isFromLockedCategory: Bool = false, needsCare: Bool = false) {
        self.pages = pages
        self.name = name
        self.isFromLockedCategory = isFromLockedCategory
        self.isPDF = pages.first?.isPDF ?? false
        self.needsCare = needsCare
    }

    /// What is chosen when the sheet opens: every page, as the document came.
    var defaultChoice: DocumentShareChoice {
        DocumentShareChoice(pages: .all, format: isPDF ? .pdf : .pictures)
    }
}

extension DocumentShareFiles {
    /// The neutral name a shared document's files take: its type ("Carte de identitate")
    /// for a personal document, else what kind of paper it is ("Poliță"), else "Act".
    @MainActor
    static func name(for attachment: Attachment) -> String {
        if let stored = attachment.asset?.values[DocumentType.typeFieldKey]?.textValue,
           let key = DocumentType.options.option(for: stored)?.key, key != DocumentType.other,
           let label = DocumentType.label(for: key) {
            return label
        }
        return attachment.kind == .other ? String(localized: "Act", comment: "Neutral name of a shared document.") : attachment.kind.title
    }
}

extension View {
    /// "Trimite" for the document in `request`: the choice (which pages, pictures or one
    /// PDF), Face ID first for a locked category, then the system share sheet. The files are
    /// made for this share only and removed when it ends.
    func documentShare(_ request: Binding<DocumentShareRequest?>) -> some View {
        sheet(item: request) { request in
            DocumentShareSheet(request: request)
        }
    }
}

/// "Trimite" as a full-width button, for a document's page: filled when it is the page's
/// main action (the picture's own, beside it), bordered otherwise.
struct DocumentShareButton: View {
    let attachment: Attachment
    var prominent = false
    @Environment(\.modelContext) private var context
    @State private var request: DocumentShareRequest?

    var body: some View {
        Group {
            if prominent {
                DSPrimaryButton(title, systemImage: "square.and.arrow.up", action: share)
            } else {
                DSSecondaryButton(title, systemImage: "square.and.arrow.up", action: share)
            }
        }
        .accessibilityHint(Text("Alegi ce pagini trimiți, ca poze sau ca PDF.", comment: "VoiceOver hint of the share button."))
        .documentShare($request)
    }

    private var title: Text { Text("Trimite", comment: "Sends a copy of a document's pictures to someone.") }

    private func share() {
        request = DocumentShareRequest(attachment: attachment, context: context)
    }
}

/// The small choice before the share sheet: which pages, and how.
struct DocumentShareSheet: View {
    let request: DocumentShareRequest

    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(BiometricVaultManager.self) private var vault
    @State private var choice: DocumentShareChoice
    @State private var files: SharedFiles?
    /// Every file this sheet wrote and hasn't removed yet, whatever way the share sheet closes.
    @State private var written: [URL] = []
    @State private var isPreparing = false
    @State private var failure: String?
    @State private var sentCount = 0

    /// The files of one share, while the share sheet shows them.
    private struct SharedFiles: Identifiable {
        let id = UUID()
        let urls: [URL]
    }

    init(request: DocumentShareRequest) {
        self.request = request
        _choice = State(initialValue: request.defaultChoice)
    }

    private var pageOptions: [DocumentSharePages] { DocumentSharePages.options(pageCount: request.pages.count) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: DS.Space.l) {
                    if pageOptions.count > 1 {
                        VStack(alignment: .leading, spacing: DS.Space.xs) {
                            DSSectionHeader("Ce trimiți")
                            DSCard {
                                VStack(spacing: 0) {
                                    ForEach(Array(pageOptions.enumerated()), id: \.element) { index, option in
                                        if index > 0 { DSRowSeparator() }
                                        DSCheckRow(title: Text(verbatim: option.title(pageCount: request.pages.count)),
                                                   isOn: choice.pages == option) { choice.pages = option }
                                    }
                                }
                            }
                        }
                    }
                    VStack(alignment: .leading, spacing: DS.Space.xs) {
                        DSSectionHeader("Cum")
                        DSCard {
                            VStack(spacing: 0) {
                                DSCheckRow(title: picturesTitle,
                                           subtitle: Text("Bune pentru WhatsApp sau mesaje.", comment: "Why someone sends a document as pictures."),
                                           isOn: choice.format == .pictures) { choice.format = .pictures }
                                DSRowSeparator()
                                DSCheckRow(title: Text("Ca un singur PDF", comment: "Share a document as one PDF file."),
                                           subtitle: Text("Bun pentru e-mail sau formulare pe internet.", comment: "Why someone sends a document as a PDF."),
                                           isOn: choice.format == .pdf) { choice.format = .pdf }
                            }
                        }
                    }
                    if request.needsCare {
                        DSNotice(.warning, title: "Poza arată numărul întreg al cardului",
                                 message: "Trimite-o doar cuiva în care ai încredere. Banca nu îți cere niciodată poza cardului.")
                    }
                    Label {
                        Text("Pleacă doar poza actului, fără ce am citit de pe el.", comment: "What a shared document contains.")
                    } icon: {
                        Image(systemName: "info.circle").foregroundStyle(DS.Palette.secondaryLabel)
                    }
                    .dsFont(.footnote)
                    if let failure {
                        DSNotice(.error, title: "Nu s-a putut pregăti", message: LocalizedStringKey(failure))
                            .transition(DS.Motion.transition(reduceMotion: reduceMotion))
                    }
                    // Its space is kept, so nothing moves when it shows.
                    DSDelayedProgress(label: "Pregătesc actul…")
                        .frame(maxWidth: .infinity)
                        .opacity(isPreparing ? 1 : 0)
                        .accessibilityHidden(!isPreparing)
                        .id(isPreparing)
                }
                .padding(DS.Space.m)
                .animation(DS.Motion.animation(DS.Motion.standard, reduceMotion: reduceMotion), value: failure)
            }
            .dsPinnedAction {
                DSPrimaryButton(Text("Trimite", comment: "Opens the share sheet with the chosen pages."), systemImage: "square.and.arrow.up") {
                    send()
                }
                .disabled(isPreparing || request.pages.isEmpty)
            }
            .background(DS.Palette.background)
            .navigationTitle(Text("Trimite actul", comment: "Title of the sheet that shares a document."))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button { dismiss() } label: { Text("Anulează", comment: "Cancels.") }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .sensoryFeedback(.success, trigger: sentCount)
        .sheet(item: $files, onDismiss: removeFiles) { files in
            SystemShareSheet(urls: files.urls) { completed in
                finished(completed)
            }
            .ignoresSafeArea()
        }
    }

    private var picturesTitle: Text {
        choice.pages.indices(pageCount: request.pages.count).count > 1
            ? Text("Ca poze", comment: "Share a document's pages as pictures.")
            : Text("Ca poză", comment: "Share one page of a document as a picture.")
    }

    /// Face ID first for a locked category, then the files, then the share sheet.
    private func send() {
        guard !isPreparing else { return }
        failure = nil
        isPreparing = true
        let request = request
        let choice = choice
        Task {
            defer { isPreparing = false }
            let reason = String(localized: "Confirmă că vrei să trimiți actul.", comment: "Face ID reason before a document from a locked category is shared.")
            // A cancelled or failed Face ID leaves the choice as it was, to try again.
            guard await vault.confirmSharing(fromLockedCategory: request.isFromLockedCategory, reason: reason) == .success else { return }
            do {
                let urls = try await Task.detached(priority: .userInitiated) {
                    DocumentShareFiles.removeLeftovers()
                    return try DocumentShareFiles.write(request.pages, choice: choice, name: request.name)
                }.value
                written = urls
                files = SharedFiles(urls: urls)
            } catch {
                CaptureLog.documents.error("Share failed: \(String(describing: type(of: error)), privacy: .public)")
                failure = String(localized: "Încearcă din nou. Dacă nu merge, verifică dacă telefonul mai are spațiu liber.", comment: "A document's share couldn't be prepared.")
            }
        }
    }

    /// The share sheet closed: sent (the choice closes too) or not (the choice stays, to try another way).
    private func finished(_ completed: Bool) {
        files = nil
        removeFiles()
        if completed {
            sentCount += 1
            dismiss()
        }
    }

    /// Whatever way the share sheet went, its files go with it.
    private func removeFiles() {
        DocumentShareFiles.remove(written)
        written = []
    }
}
