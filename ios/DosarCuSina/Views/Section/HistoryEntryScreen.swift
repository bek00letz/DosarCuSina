import SwiftData
import SwiftUI

/// One thing that happened: what was done, the parts and their prices, who did it and how
/// well. The rating feeds the provider's stars.
///
/// A shaped screen: what it shows and in which words is the record's kind laid over its
/// category's visits (`HistoryEntryShape`); it holds no words of its own (`HistoryEntryWording`,
/// the `text-in-shaped-screen` check), and `docs/COPY_MATRIX.md` shows it for every category.
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
    @State private var noteRequest: HistoryNoteRequest?
    @State private var toast: DSToast?

    private var definition: TemplateDefinition? {
        entry.asset.flatMap { asset in (try? TemplateStore(context: context).template(forKey: asset.templateKey)) ?? nil }?.definition
    }

    var body: some View {
        let definition = definition
        let shape = HistoryEntryShape.make(entry.kind, visit: definition?.behavior.visit.shape)
        let people = (entry.providers ?? []).sorted { $0.name < $1.name }
        ScrollView {
            VStack(alignment: .leading, spacing: DS.Space.xl) {
                DSCard(padding: DS.Space.l) {
                    VStack(alignment: .leading, spacing: DS.Space.s) {
                        Text(verbatim: entry.title)
                            .dsFont(.title)
                            .accessibilityAddTraits(.isHeader)
                        Text(verbatim: details(definition))
                            .dsFont(.subheadline, numeric: true)
                        if let reference = entry.reference?.trimmingCharacters(in: .whitespacesAndNewlines), !reference.isEmpty {
                            // The number printed on the paper this records (a bill's invoice number).
                            Text(verbatim: shape.referenceIsInvoice ? HistoryEntryWording.invoiceNumber(reference) : HistoryEntryWording.number(reference))
                                .dsFont(.subheadline, numeric: true)
                                .textSelection(.enabled)
                        }
                        if !entry.effectiveCost.isEmpty {
                            Text(verbatim: entry.effectiveCost.formatted())
                                .dsFont(.display, numeric: true)
                        }
                        if entry.isExample { DSExampleBadge() }
                    }
                }

                let items = (entry.items ?? []).sorted { $0.name < $1.name }
                if !items.isEmpty {
                    DSPocketCard(shape.itemsHeader) {
                        ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                            if index > 0 { DSRowSeparator() }
                            DSReadOnlyValueRow(
                                label: Text(verbatim: [item.name, item.partBrandOrCode].compactMap { $0 }.joined(separator: " · ")),
                                value: Text(verbatim: item.totalCost?.formattedCompact() ?? "")
                            )
                        }
                    }
                }

                if !people.isEmpty {
                    DSPocketCard(shape.providerHeader) {
                        ForEach(Array(people.enumerated()), id: \.element.id) { index, provider in
                            if index > 0 { DSRowSeparator() }
                            ProviderCard(provider: provider)
                        }
                    }
                }

                // How it went: a job's, or a check's someone did; never a bill's or a chore's.
                if shape.asksRating(isCompletion: entry.obligation != nil, hasSomeone: !people.isEmpty) {
                    VStack(alignment: .leading, spacing: DS.Space.xs) {
                        DSSectionHeader(LocalizedStringKey(shape.ratingHeader))
                        DSCard {
                            VStack(alignment: .leading, spacing: DS.Space.xxs) {
                                DSStarRating(rating: entry.rating.map(Double.init)) { rate($0) }
                                if !people.isEmpty {
                                    Text(verbatim: HistoryEntryWording.ratingFootnote)
                                        .dsFont(.footnote)
                                }
                            }
                        }
                    }
                }

                // The record's note, added or changed here too (`HistoryNoteSheet`).
                if let note = entry.note, !note.isEmpty {
                    DSPocketCard(HistoryEntryWording.notes) {
                        Text(verbatim: note).dsFont(.body).textSelection(.enabled)
                            .padding(.bottom, DS.Space.s)
                        DSRowSeparator()
                        Button { noteRequest = HistoryNoteRequest(entryID: entry.id) } label: {
                            DSListRow(LocalizedStringKey(HistoryEntryWording.changeNote), systemImage: "square.and.pencil", showsChevron: true)
                        }
                        .buttonStyle(.plain)
                    }
                } else {
                    DSSecondaryButton(verbatim: HistoryEntryWording.addNote, systemImage: "square.and.pencil") {
                        noteRequest = HistoryNoteRequest(entryID: entry.id)
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

                DSSecondaryButton(verbatim: HistoryEntryWording.delete, systemImage: "trash", role: .destructive) {
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
        .dsToast($toast)
        .historyNoteSheet($noteRequest, toast: $toast)
        .confirmationDialog(Text(verbatim: HistoryEntryWording.deleteQuestion(entry.title)), isPresented: $isConfirmingDelete, titleVisibility: .visible) {
            Button(role: .destructive, action: delete) { Text(verbatim: HistoryEntryWording.confirmDelete) }
            Button(role: .cancel) {} label: { Text(verbatim: HistoryEntryWording.keep) }
        } message: {
            Text(verbatim: deletionMessage(shape: shape, definition: definition))
        }
        .userErrorAlert($error)
    }

    /// What deleting does, as `HistoryDeletion` works it out: the deadline, the reading, the documents.
    private func deletionMessage(shape: HistoryEntryShape, definition: TemplateDefinition?) -> String {
        let effect = HistoryDeletion(of: entry)
        var sentences: [String] = []
        if let reopened = effect.reopensCycle {
            sentences.append(HistoryEntryWording.reopens(on: DosarFormat.longDay(reopened)))
        } else if effect.keepsDeadline {
            sentences.append(HistoryEntryWording.keepsDeadline)
        } else {
            sentences.append(HistoryEntryWording.removesRows(parts: shape.rowsAreParts))
        }
        if let reading = effect.removedReading {
            sentences.append(HistoryEntryWording.removesReading(readingText(reading, definition: definition)))
        }
        if effect.keptDocuments > 0 {
            sentences.append(HistoryEntryWording.keepsDocuments)
        }
        return sentences.joined(separator: " ")
    }

    private func details(_ definition: TemplateDefinition?) -> String {
        var parts = [DosarFormat.longDay(entry.occurredAt)]
        if let reading = entry.metricReading { parts.append(readingText(reading, definition: definition)) }
        if let asset = entry.asset { parts.append(asset.name) }
        return parts.joined(separator: " · ")
    }

    /// "45.724 km": a reading with the unit of the section's counter, written by its unit.
    private func readingText(_ reading: Double, definition: TemplateDefinition?) -> String {
        MeasurementUnit.written(reading, in: definition.flatMap { HouseholdMutations.heroMetricUnit(template: $0) }, fractionDigits: 0...0)
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
            // An older record, not the step just taken: what it does is `HistoryDeletion`.
            try HistoryActions(context: context).delete(entry)
            dismiss()
        } catch {
            self.error = UserFacingError(error)
        }
    }
}
