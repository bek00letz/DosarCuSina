import SwiftUI
import SwiftData
import PDFKit

// MARK: - History entry

/// One thing that happened: what was done, the parts and their prices, who did
/// it and how well. The rating feeds the provider's stars.
struct HistoryEntryScreen: View {
    let entryID: UUID
    @Query private var matches: [HistoryEntry]

    init(entryID: UUID) {
        self.entryID = entryID
        let id = entryID
        _matches = Query(filter: #Predicate<HistoryEntry> { $0.id == id })
    }

    var body: some View {
        if let entry = matches.first {
            if let asset = entry.asset {
                LockGate(asset: asset) { HistoryEntryContent(entry: entry) }
            } else {
                HistoryEntryContent(entry: entry)
            }
        } else {
            MissingRecordView()
        }
    }
}

private struct HistoryEntryContent: View {
    let entry: HistoryEntry
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var isConfirmingDelete = false
    @State private var error: UserFacingError?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DS.Space.xl) {
                DSCard(padding: DS.Space.l) {
                    VStack(alignment: .leading, spacing: DS.Space.s) {
                        Text(verbatim: entry.title)
                            .dsFont(.title)
                            .accessibilityAddTraits(.isHeader)
                        Text(verbatim: details)
                            .dsFont(.subheadline, numeric: true)
                        if !entry.effectiveCost.isEmpty {
                            Text(verbatim: entry.effectiveCost.formatted())
                                .dsFont(.display, numeric: true)
                        }
                        if entry.isExample { DSExampleBadge() }
                    }
                }

                let items = (entry.items ?? []).sorted { $0.name < $1.name }
                if !items.isEmpty {
                    DSPocketCard(String(localized: "Ce s-a făcut", comment: "Header: the jobs and parts of a visit.")) {
                        ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                            if index > 0 { DSRowSeparator() }
                            DSReadOnlyValueRow(
                                label: Text(verbatim: [item.name, item.partBrandOrCode].compactMap { $0 }.joined(separator: " · ")),
                                value: Text(verbatim: item.totalCost?.formattedCompact() ?? "")
                            )
                        }
                    }
                }

                let people = (entry.providers ?? []).sorted { $0.name < $1.name }
                if !people.isEmpty {
                    DSPocketCard(String(localized: "Cine a lucrat", comment: "Header: who did the job.")) {
                        ForEach(Array(people.enumerated()), id: \.element.id) { index, provider in
                            if index > 0 { DSRowSeparator() }
                            ProviderCard(provider: provider)
                        }
                    }
                }

                VStack(alignment: .leading, spacing: DS.Space.xs) {
                    DSSectionHeader("Cum a fost")
                    DSCard {
                        VStack(alignment: .leading, spacing: DS.Space.xxs) {
                            DSStarRating(rating: entry.rating.map(Double.init)) { rate($0) }
                            Text("Nota intră în stelele celui care a lucrat.", comment: "Footnote under a job rating.")
                                .dsFont(.footnote)
                        }
                    }
                }

                if let note = entry.note, !note.isEmpty {
                    DSPocketCard(String(localized: "Note", comment: "Header: notes.")) {
                        Text(verbatim: note).dsFont(.body).textSelection(.enabled)
                    }
                }

                let papers = entry.attachments ?? []
                if !papers.isEmpty {
                    DSPocketCard(SectionPocket.documents.title) {
                        ForEach(Array(papers.enumerated()), id: \.element.id) { index, attachment in
                            if index > 0 { DSRowSeparator() }
                            DocumentRowLink(item: .paper(attachment))
                        }
                    }
                }

                DSSecondaryButton("Șterge din istoric", systemImage: "trash", role: .destructive) {
                    isConfirmingDelete = true
                }
            }
            .padding(DS.Space.m)
            .frame(maxWidth: 720)
            .frame(maxWidth: .infinity)
        }
        .background(DS.Palette.background)
        .navigationTitle(Text(verbatim: entry.asset?.name ?? entry.title))
        .navigationBarTitleDisplayMode(.inline)
        .confirmationDialog(Text("Ștergi „\(entry.title)” din istoric?", comment: "Delete confirmation for a history entry."), isPresented: $isConfirmingDelete, titleVisibility: .visible) {
            Button(role: .destructive, action: delete) { Text("Șterge", comment: "Confirm deleting.") }
            Button(role: .cancel) {} label: { Text("Păstrează", comment: "Cancel a delete.") }
        } message: {
            if entry.isCompletion {
                Text("Termenul revine la data de dinainte, ca și cum nu l-ai fi rezolvat.", comment: "Deleting a completion moves the obligation back.")
            } else {
                Text("Piesele și prețurile notate aici se șterg de pe acest telefon.", comment: "Delete confirmation for a history entry.")
            }
        }
        .userErrorAlert($error)
    }

    private var details: String {
        var parts = [DosarFormat.longDay(entry.occurredAt)]
        if let reading = entry.metricReading {
            let template = entry.asset.flatMap { asset in (try? TemplateStore(context: context).template(forKey: asset.templateKey)) ?? nil }
            let unit = template.flatMap { HouseholdMutations.heroMetricUnit(template: $0.definition) } ?? ""
            let number = reading.formatted(.number.locale(.dosarDefault).precision(.fractionLength(0)))
            parts.append(unit.isEmpty ? number : "\(number) \(unit)")
        }
        if let asset = entry.asset { parts.append(asset.name) }
        return parts.joined(separator: " · ")
    }

    private func rate(_ value: Int?) {
        do {
            try HistoryActions(context: context).rate(entry, value)
        } catch {
            self.error = UserFacingError(error)
        }
    }

    private func delete() {
        do {
            // A completion is undone through the obligation engine so its due date moves back.
            if entry.isCompletion, entry.obligation != nil {
                try ObligationActions(context: context).undo(entry)
            } else {
                try HistoryActions(context: context).delete(entry)
            }
            dismiss()
        } catch {
            self.error = UserFacingError(error)
        }
    }
}

// MARK: - Document

/// A document in the binder: the pages or the PDF, what it is, and where it is filed.
struct DocumentScreen: View {
    let attachmentID: UUID
    @Query private var matches: [Attachment]

    init(attachmentID: UUID) {
        self.attachmentID = attachmentID
        let id = attachmentID
        _matches = Query(filter: #Predicate<Attachment> { $0.id == id })
    }

    var body: some View {
        if let attachment = matches.first {
            if let asset = attachment.asset {
                LockGate(asset: asset) { DocumentContent(attachment: attachment) }
            } else {
                DocumentContent(attachment: attachment)
            }
        } else {
            MissingRecordView()
        }
    }
}

private struct DocumentContent: View {
    let attachment: Attachment
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var isConfirmingDelete = false
    @State private var isShowingText = false
    @State private var error: UserFacingError?
    @State private var toast: DSToast?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DS.Space.xl) {
                VStack(alignment: .leading, spacing: DS.Space.xs) {
                    Text(verbatim: attachment.displayTitle)
                        .dsFont(.title)
                        .accessibilityAddTraits(.isHeader)
                    Text(verbatim: [attachment.kind.title, attachment.validityLine, attachment.asset?.name].compactMap { $0 }.joined(separator: " · "))
                        .dsFont(.subheadline)
                    if attachment.isArchived {
                        DSStatusBadge(.later, text: Text("Arhivat", comment: "Badge on an archived document."))
                    }
                }

                DocumentPreview(attachment: attachment)

                if attachment.kind == .identity, let asset = attachment.asset {
                    DocumentFacts(asset: asset)
                }

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
            }
            .padding(DS.Space.m)
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

    private func setArchived(_ value: Bool) {
        do {
            try AttachmentActions(context: context).setArchived(attachment, value)
            toast = .undo(value
                ? LocalizedStringResource("Mutat în arhivă", comment: "Toast after archiving a document.")
                : LocalizedStringResource("Scos din arhivă", comment: "Toast after unarchiving a document.")) {
                try? AttachmentActions(context: context).setArchived(attachment, !value)
            }
        } catch {
            self.error = UserFacingError(error)
        }
    }

    private func delete() {
        do {
            try AttachmentActions(context: context).delete(attachment)
            dismiss()
        } catch {
            self.error = UserFacingError(error)
        }
    }
}

/// The document itself: a PDF, scanned pages, or the original image.
private struct DocumentPreview: View {
    let attachment: Attachment

    /// The page opened full screen, with pinch and double-tap to zoom.
    @State private var openPage: OpenPage?

    private struct OpenPage: Identifiable {
        let index: Int
        var id: Int { index }
    }

    var body: some View {
        let pages = attachment.orderedPages.compactMap { $0.imageData.flatMap(UIImage.init(data:)) }
        let images = pages.isEmpty ? [(attachment.fileData ?? attachment.thumbnailData).flatMap(UIImage.init(data:))].compactMap { $0 } : pages
        Group {
            if attachment.contentType == "com.adobe.pdf", let data = attachment.fileData {
                PDFPreview(data: data)
                    .frame(height: 520)
                    .clipShape(.rect(cornerRadius: DS.Radius.card, style: .continuous))
                    .dsHairlineBorder(RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous))
                    .accessibilityLabel(Text("Documentul PDF", comment: "VoiceOver label of a PDF preview."))
            } else if !images.isEmpty {
                VStack(spacing: DS.Space.s) {
                    ForEach(Array(images.enumerated()), id: \.offset) { index, page in
                        pageImage(page, index: index)
                    }
                }
            } else {
                DSNotice(.info, title: "Nu am o previzualizare", message: "Documentul e păstrat, dar nu îl pot arăta aici.")
            }
        }
        .fullScreenCover(item: $openPage) { page in
            DocumentPagesViewer(pages: images, startAt: page.index)
        }
    }

    private func pageImage(_ image: UIImage, index: Int) -> some View {
        Button { openPage = OpenPage(index: index) } label: {
            Image(uiImage: image)
                .resizable()
                .scaledToFit()
                .clipShape(.rect(cornerRadius: DS.Radius.control, style: .continuous))
                .dsHairlineBorder(RoundedRectangle(cornerRadius: DS.Radius.control, style: .continuous))
        }
        .buttonStyle(.dsPressable)
        .accessibilityLabel(Text("Pagina \(index + 1)", comment: "VoiceOver label of a scanned page."))
        .accessibilityHint(Text("Se deschide pe tot ecranul. Poți mări cu două degete.", comment: "VoiceOver hint of a page that opens full screen."))
    }
}

/// What was read off an identity document, one tap from the clipboard for filling in
/// forms: CNP, birth date, series and number, dates. The page sits behind Face ID.
private struct DocumentFacts: View {
    let asset: Asset
    @Query private var templates: [CategoryTemplate]

    init(asset: Asset) {
        self.asset = asset
        let key = asset.templateKey
        _templates = Query(filter: #Predicate<CategoryTemplate> { $0.key == key })
    }

    var body: some View {
        let rows = Self.rows(asset.values, definition: templates.first?.definition)
        if !rows.isEmpty {
            DSCard {
                VStack(spacing: 0) {
                    ForEach(Array(rows.enumerated()), id: \.element.key) { index, row in
                        if index > 0 { DSRowSeparator() }
                        DSActionValueRow(title: Text(verbatim: row.label), value: row.text, action: .copy)
                            .padding(.vertical, DS.Space.xs)
                    }
                }
            }
        }
    }

    /// Every filled field of the document's template except its type, in template order.
    static func rows(_ values: FieldValues, definition: TemplateDefinition?) -> [(key: String, label: String, text: String)] {
        guard let definition else { return [] }
        return definition.allFields.compactMap { field in
            guard field.type != .choice, let value = values[field.key] else { return nil }
            let text = FieldFormatter.display(value, field: field, locale: .dosarDefault)
            return text.isEmpty ? nil : (field.key, field.label, text)
        }
    }
}

private struct PDFPreview: UIViewRepresentable {
    let data: Data

    func makeUIView(context: Context) -> PDFView {
        let view = PDFView()
        view.autoScales = true
        view.document = PDFDocument(data: data)
        return view
    }

    func updateUIView(_ view: PDFView, context: Context) {}
}
