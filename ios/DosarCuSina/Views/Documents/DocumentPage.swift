import SwiftData
import SwiftUI

/// Whether a document opens as one page: its picture first, with "Trimite" and "Rotește"
/// beside it, its values with "Copiază", and "Editează". The pages from before (a personal
/// document's section page, the old document screen) are kept switched off as the way back
/// until the owner has used the new one.
enum DocumentPageLayout {
    static let isOn = true

    /// Whether a section of a category playing `role` opens as a document's page.
    static func opensAsDocumentPage(role: CategoryBehavior.Role?) -> Bool {
        isOn && role == .personalDocument
    }
}

// MARK: - A personal document

/// The page of a personal document (an identity card, a passport, a licence): the
/// document's own picture, front and back; what was read off it, each value one tap from
/// the clipboard; its PIN codes behind Face ID; when it must be renewed. Behind its
/// category's lock, like any section.
struct PersonalDocumentPage: View {
    let document: Asset

    var body: some View {
        LockGate(asset: document) { PersonalDocumentContent(document: document) }
            .navigationTitle(Text(verbatim: document.name))
            .navigationBarTitleDisplayMode(.inline)
    }
}

private struct PersonalDocumentContent: View {
    let document: Asset

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(\.announce) private var announce
    @Query private var templates: [CategoryTemplate]

    @State private var isEditing = false
    @State private var isMoving = false
    @State private var isConfirmingDelete = false
    @State private var toast: DSToast?
    @State private var error: UserFacingError?

    init(document: Asset) {
        self.document = document
        let key = document.templateKey
        _templates = Query(filter: #Predicate<CategoryTemplate> { $0.key == key })
    }

    private var definition: TemplateDefinition {
        templates.first?.definition ?? BuiltInTemplates.definition(for: document.templateKey) ?? BuiltInTemplates.other
    }

    var body: some View {
        let definition = self.definition
        let picture = DocumentPageFacts.currentPicture(of: document)
        ScrollView {
            VStack(alignment: .leading, spacing: DS.Space.xl) {
                if let picture {
                    DocumentPictureSection(attachment: picture, toast: $toast)
                } else {
                    DocumentPhotoPrompt(asset: document, toast: $toast)
                }
                DocumentValuesCard(document: document, definition: definition)
                SecretFieldsCard(asset: document, definition: definition)
                // The category's other pockets (when it must be renewed, Date importante):
                // its documents are the picture above and the older ones below.
                ForEach(definition.pockets.filter { $0 != .documents }, id: \.self) { pocket in
                    PocketView(pocket: pocket, asset: document, definition: definition, toast: $toast, error: $error)
                }
                OlderPicturesCard(pictures: DocumentPageFacts.olderPictures(of: document))
                DSSecondaryButton(Text("Șterge actul", comment: "Deletes a personal document from its page."), systemImage: "trash", role: .destructive) {
                    isConfirmingDelete = true
                }
                .padding(.top, DS.Space.l)
            }
            .padding(.horizontal, DS.Space.m)
            .padding(.top, DS.Space.s)
            .padding(.bottom, DS.Space.xxl)
            .frame(maxWidth: 720)
            .frame(maxWidth: .infinity)
        }
        .background(DS.Palette.background)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { isEditing = true } label: {
                    Text("Editează", comment: "Toolbar button that edits a document: its values, its back, reading it again.")
                }
                .keyboardShortcut("e", modifiers: .command)
            }
            if AssetActions.parentTemplateKey(for: document) != nil {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button { isMoving = true } label: {
                            Label { Text("Mută la…", comment: "Menu item that files something under another parent.") } icon: { Image(systemName: "arrow.turn.up.right") }
                        }
                    } label: {
                        Label { Text("Mai multe", comment: "Toolbar menu with more actions for a section.") } icon: { Image(systemName: "ellipsis.circle") }
                    }
                }
            }
        }
        .sheet(isPresented: $isEditing) {
            DocumentEditSheet(document: document, definition: definition, picture: picture) { toast = $0 }
        }
        .sheet(isPresented: $isMoving) {
            MoveAssetSheet(asset: document) { moved in
                toast = .undo(moved.toastTitle, receipt: moved.receipt)
            }
        }
        .confirmationDialog(Text("Ștergi „\(document.name)”?", comment: "Title of the delete confirmation for a section."),
                            isPresented: $isConfirmingDelete, titleVisibility: .visible) {
            Button(role: .destructive, action: delete) { Text("Șterge", comment: "Confirm deleting.") }
            Button(role: .cancel) {} label: { Text("Păstrează", comment: "Cancel a delete.") }
        } message: {
            Text("Poza actului, ce ai scris despre el și reînnoirea lui se șterg de pe acest telefon.", comment: "Delete confirmation message for a personal document.")
        }
        .dsToast($toast)
        .userErrorAlert($error)
    }

    private func delete() {
        let name = document.name
        do {
            let receipt = try AssetActions(context: context).delete(document)
            announce(.undoDeletion(LocalizedStringResource("Am șters „\(name)”.", comment: "Toast after deleting a personal document."), receipt: receipt))
            dismiss()
        } catch {
            self.error = UserFacingError(error)
        }
    }
}

/// What was read off the document or typed in, under its picture: each value that a form
/// asks for has "Copiază", kept on this phone only and gone after a minute (`.personal`);
/// the date it stops being valid says how urgent that is.
struct DocumentValuesCard: View {
    let document: Asset
    let definition: TemplateDefinition

    @Environment(\.calendar) private var calendar

    var body: some View {
        let rows = DocumentPageFacts.rows(document.values, definition: definition)
        VStack(alignment: .leading, spacing: DS.Space.xs) {
            DSSectionHeader("Date de pe act")
            DSCard {
                VStack(alignment: .leading, spacing: 0) {
                    if document.isExample {
                        DSExampleBadge().padding(.bottom, DS.Space.xs)
                    }
                    if rows.isEmpty {
                        Text("Nu am încă date de pe act. Le poți scrie din Editează sau din poza actului.", comment: "Empty values on a document's page.")
                            .dsFont(.subheadline)
                            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                    }
                    ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                        if index > 0 { DSRowSeparator() }
                        valueRow(row).padding(.vertical, DS.Space.xs)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func valueRow(_ row: DocumentPageFacts.ValueRow) -> some View {
        if row.copies {
            let expiry = row.isExpiry ? document.values[row.key]?.dateValue : nil
            // Read off a personal document: personal, so it stays on this phone and expires.
            DSActionValueRow(title: Text(verbatim: row.label), value: row.text, action: .copy,
                             copies: DocumentPageFacts.copyKind(isPersonalDocument: true, isLockedCategory: false),
                             note: expiry.flatMap(travelLine).map { Text(verbatim: $0) },
                             status: expiry.map(badge))
        } else {
            DSReadOnlyValueRow(label: Text(verbatim: row.label), value: Text(verbatim: row.text))
        }
    }

    /// How urgent the day it stops being valid is, by the rule of the deadline it drives.
    private func badge(_ day: CalendarDay) -> DSStatusBadge {
        let today = CalendarDay(Date(), calendar: calendar)
        let rule = DateUrgency.rule(for: day, on: document)
        return DSStatusBadge(expiry: rule.urgency(of: day, today: today, calendar: calendar), daysRemaining: today.days(to: day, calendar: calendar))
    }

    /// A passport's "Bun de călătorit până pe …" (its type's margin), under its expiry.
    private func travelLine(_ day: CalendarDay) -> String? {
        let today = CalendarDay(Date(), calendar: calendar)
        return DueWording.travelLines(due: day, rule: DateUrgency.rule(for: day, on: document), today: today, calendar: calendar)?.dropFirst().first
    }
}

/// The document's older pictures (last year's card, kept when it was renewed): each opens
/// its own page.
private struct OlderPicturesCard: View {
    let pictures: [Attachment]

    var body: some View {
        if !pictures.isEmpty {
            DSPocketCard(String(localized: "Poze mai vechi", comment: "Header of a document's older pictures."), count: pictures.count) {
                ForEach(Array(pictures.enumerated()), id: \.element.id) { index, picture in
                    if index > 0 { DSRowSeparator() }
                    DocumentRowLink(item: .paper(picture))
                }
            }
        }
    }
}

// MARK: - The picture

/// A document's picture on its page, with its own actions right by it: "Trimite", the
/// page's main action, and "Rotește" for the side shown. A tap opens it full screen, where
/// it can be zoomed, turned, shown whole or cut out, and sent.
struct DocumentPictureSection: View {
    let attachment: Attachment
    @Binding var toast: DSToast?

    @Environment(\.modelContext) private var context
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var selection = 0
    @State private var openPage: OpenPage?
    @State private var isTurning = false
    @State private var turns = 0

    private struct OpenPage: Identifiable {
        let index: Int
        var id: Int { index }
    }

    var body: some View {
        let pages = DocumentPages.sources(of: attachment)
        VStack(spacing: DS.Space.m) {
            DocumentPicturePager(pages: pages, selection: $selection) { index in
                DocumentPagesViewer.present(reduceMotion: reduceMotion) { openPage = OpenPage(index: index) }
            }
            DSAdaptiveStack(spacing: DS.Space.s) {
                DocumentShareButton(attachment: attachment, prominent: true)
                DSSecondaryButton(Text("Rotește", comment: "Turns the page shown a quarter turn clockwise."), systemImage: "rotate.right") {
                    turn(pages)
                }
                .disabled(isTurning)
                .accessibilityLabel(turnLabel(pageCount: pages.count))
                .accessibilityHint(Text("Întoarce pagina un sfert de tură spre dreapta.", comment: "VoiceOver hint of the turn button."))
            }
        }
        .sensoryFeedback(.selection, trigger: turns)
        .onChange(of: pages.count) { _, count in
            if selection >= count { selection = max(count - 1, 0) }
        }
        .fullScreenCover(item: $openPage) { page in
            DocumentPagesViewer(
                pages: DocumentPages.sources(of: attachment),
                startAt: page.index,
                editing: .document(attachment, actions: AttachmentActions(context: context)),
                share: DocumentShareRequest(attachment: attachment, context: context)
            )
        }
    }

    /// "Rotește fața", "Rotește spatele", "Rotește pagina 2", for VoiceOver.
    private func turnLabel(pageCount: Int) -> Text {
        if let names = DocumentPageFacts.pageNames(count: pageCount), names.indices.contains(selection) {
            return Text("Rotește \(names[selection].lowercased())", comment: "VoiceOver label of the turn button: the side it turns.")
        }
        if pageCount > 1 {
            return Text("Rotește pagina \(selection + 1)", comment: "VoiceOver label of the turn button: the page it turns.")
        }
        return Text("Rotește", comment: "Turns the page shown a quarter turn clockwise.")
    }

    /// One turn at a time, kept as the person's own (it wins over the app's guess).
    private func turn(_ pages: [DocumentPageSource]) {
        guard !isTurning, let page = pages.first(where: { $0.index == selection }) ?? pages.first else { return }
        isTurning = true
        Task {
            defer { isTurning = false }
            do {
                _ = try await AttachmentActions(context: context).turnPage(attachment, page: page.index)
                turns += 1
            } catch {
                toast = .failure(error)
            }
        }
    }
}

/// A document's pages, one at a time, as they are shown: swiped, or picked with "Fața" and
/// "Spatele" for a card's two sides; a page's number under the pages of a longer one. Its
/// height comes from the pages' shapes from the start, so nothing moves when they are drawn.
struct DocumentPicturePager: View {
    let pages: [DocumentPageSource]
    @Binding var selection: Int
    let open: (Int) -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// The tallest page sets the height, so every page fits without the pager changing size.
    private var aspect: CGFloat {
        let ratios = pages.compactMap { DocumentPicture.shownSize(of: $0) }.filter { $0.height > 0 }.map { $0.width / $0.height }
        return ratios.min() ?? (85.6 / 53.98)
    }

    var body: some View {
        let names = DocumentPageFacts.pageNames(count: pages.count)
        VStack(spacing: DS.Space.s) {
            if let names {
                Picker(selection: $selection) {
                    ForEach(Array(names.enumerated()), id: \.offset) { index, name in
                        Text(verbatim: name).tag(index)
                    }
                } label: {
                    Text("Partea arătată", comment: "VoiceOver label of the front and back choice above a document's picture.")
                }
                .pickerStyle(.segmented)
                .controlSize(.large)
            }
            TabView(selection: $selection) {
                ForEach(pages) { page in
                    Button { open(page.index) } label: {
                        DocumentPageImage(source: page)
                            .clipShape(.rect(cornerRadius: DS.Radius.control, style: .continuous))
                            .dsHairlineBorder(RoundedRectangle(cornerRadius: DS.Radius.control, style: .continuous))
                            .shadow(color: .black.opacity(0.08), radius: 10, y: 3)
                            .padding(.horizontal, DS.Space.xxs)
                            .padding(.bottom, pages.count > 2 ? DS.Space.xl : DS.Space.xs)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                    .buttonStyle(.dsPressable)
                    .accessibilityLabel(pageLabel(page, names: names))
                    .accessibilityHint(Text("Se deschide pe tot ecranul. Poți mări, roti sau trimite pagina.", comment: "VoiceOver hint of a page that opens full screen."))
                    .tag(page.index)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: pages.count > 2 ? .always : .never))
            .indexViewStyle(.page(backgroundDisplayMode: .always))
            .aspectRatio(aspect, contentMode: .fit)
            .frame(maxHeight: 560)
            .dsAnimation(DS.Motion.standard, value: aspect)
        }
        .animation(DS.Motion.animation(DS.Motion.quick, reduceMotion: reduceMotion), value: selection)
    }

    private func pageLabel(_ page: DocumentPageSource, names: [String]?) -> Text {
        if let names, names.indices.contains(page.index) {
            return Text("Poza actului, \(names[page.index].lowercased())", comment: "VoiceOver label of a document's front or back picture.")
        }
        if pages.count > 1 {
            return Text("Pagina \(page.index + 1) din \(pages.count)", comment: "VoiceOver label of a page in the full-screen viewer.")
        }
        return Text("Poza actului", comment: "VoiceOver label of a document's picture.")
    }
}

// MARK: - Any other paper

/// A paper filed on a section (a policy, an invoice, a report) or a personal document's
/// older picture: its picture first, with "Trimite" and "Rotește", then what it is, until
/// when it is valid and where it is filed.
struct PaperPage: View {
    let attachment: Attachment

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(\.announce) private var announce
    @State private var isConfirmingDelete = false
    @State private var isShowingText = false
    @State private var error: UserFacingError?
    @State private var toast: DSToast?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DS.Space.xl) {
                if DocumentPages.sources(of: attachment).isEmpty {
                    DSNotice(.info, title: "Nu am o previzualizare", message: "Documentul e păstrat, dar nu îl pot arăta aici.")
                } else {
                    DocumentPictureSection(attachment: attachment, toast: $toast)
                }
                facts
                if let text = attachment.extractedText, !text.isEmpty {
                    DisclosureGroup(isExpanded: $isShowingText) {
                        Text(verbatim: text)
                            .dsFont(.footnote)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.top, DS.Space.xs)
                    } label: {
                        Text("Textul citit din document", comment: "Disclosure with the OCR text of a document.")
                            .dsFont(.headline)
                            .frame(minHeight: 44)
                    }
                    .padding(.horizontal, DS.Space.m)
                    .background(DS.Palette.surface, in: .rect(cornerRadius: DS.Radius.card, style: .continuous))
                }
                VStack(spacing: DS.Space.s) {
                    DSSecondaryButton(attachment.isArchived ? "Scoate din arhivă" : "Mută în arhivă",
                                      systemImage: attachment.isArchived ? "tray.and.arrow.up" : "archivebox") {
                        setArchived(!attachment.isArchived)
                    }
                    DSSecondaryButton("Șterge documentul", systemImage: "trash", role: .destructive) {
                        isConfirmingDelete = true
                    }
                }
                .padding(.top, DS.Space.l)
            }
            .padding(.horizontal, DS.Space.m)
            .padding(.top, DS.Space.s)
            .padding(.bottom, DS.Space.xxl)
            .frame(maxWidth: 720)
            .frame(maxWidth: .infinity)
        }
        .background(DS.Palette.background)
        .navigationTitle(Text(verbatim: attachment.displayTitle))
        .navigationBarTitleDisplayMode(.inline)
        .confirmationDialog(Text("Ștergi documentul?", comment: "Delete confirmation for a document."), isPresented: $isConfirmingDelete, titleVisibility: .visible) {
            Button(role: .destructive, action: delete) { Text("Șterge", comment: "Confirm deleting.") }
            Button(role: .cancel) {} label: { Text("Păstrează", comment: "Cancel a delete.") }
        } message: {
            Text("Fișierul se șterge de pe acest telefon. Dacă vrei doar să nu-l mai vezi, mută-l în arhivă.", comment: "Delete confirmation message for a document.")
        }
        .dsToast($toast)
        .userErrorAlert($error)
    }

    /// What it is, until when it is valid, the date on it, and where it is filed.
    private var facts: some View {
        DSCard {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: DS.Space.xs) {
                    Text(verbatim: attachment.kind.title).dsFont(.headline)
                    if attachment.isArchived {
                        DSStatusBadge(.later, text: Text("Arhivat", comment: "Badge on an archived document."))
                    }
                    if attachment.isExample { DSExampleBadge() }
                }
                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                if let day = attachment.validUntilDay {
                    DSRowSeparator()
                    DSReadOnlyValueRow(label: Text("Valabil până la", comment: "A paper's last valid day."), value: Text(verbatim: DosarFormat.longDay(day)))
                    ExpiryBadge(day: day, rule: attachment.obligation?.reminders.urgencyRule ?? DateUrgency.rule(for: day, on: attachment.asset))
                        .padding(.bottom, DS.Space.xs)
                }
                if let date = attachment.documentDay {
                    DSRowSeparator()
                    DSReadOnlyValueRow(label: Text("Data de pe act", comment: "The date printed on a paper."), value: Text(verbatim: DosarFormat.day(date)))
                }
                if let asset = attachment.asset {
                    DSRowSeparator()
                    NavigationLink(value: AppRoute.asset(asset.id)) {
                        DSListRow(title: Text(verbatim: asset.name),
                                  subtitle: Text("Unde e păstrat", comment: "Row that opens the section a paper is filed in."),
                                  systemImage: "folder", showsChevron: true) { EmptyView() }
                    }
                    .buttonStyle(.dsPressable)
                }
            }
        }
    }

    private func setArchived(_ value: Bool) {
        do {
            let receipt = try AttachmentActions(context: context).setArchived(attachment, value)
            toast = .undo(value
                ? LocalizedStringResource("Mutat în arhivă", comment: "Toast after archiving a document.")
                : LocalizedStringResource("Scos din arhivă", comment: "Toast after unarchiving a document."), receipt: receipt)
        } catch {
            self.error = UserFacingError(error)
        }
    }

    private func delete() {
        let title = attachment.displayTitle
        do {
            let receipt = try AttachmentActions(context: context).delete(attachment)
            announce(.undoDeletion(LocalizedStringResource("Am șters „\(title)”.", comment: "Toast after deleting a document."), receipt: receipt))
            dismiss()
        } catch {
            self.error = UserFacingError(error)
        }
    }
}
