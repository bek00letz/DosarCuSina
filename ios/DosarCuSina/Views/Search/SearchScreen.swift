import SwiftUI
import SwiftData

/// What is typed in Caută's search field. The field belongs to the search tab's own
/// navigation stack: there iOS draws it in the tab bar when Caută is chosen, and only
/// there (on the whole tab view it would reach every tab). The search screen reads it
/// from here.
@MainActor
@Observable
final class SearchQuery {
    var text = ""
    /// Goes up each time the person submits the field.
    private(set) var submissions = 0

    func submit() { submissions += 1 }
}

extension View {
    /// The search tab's field, on the search tab's navigation stack, with the screen's prompt.
    func shellSearch(_ query: SearchQuery) -> some View {
        @Bindable var query = query
        // Always shown under the title: the field is the whole point of Caută, so it never
        // hides on scroll or waits to be pulled down.
        return searchable(text: $query.text, placement: .navigationBarDrawer(displayMode: .always),
                          prompt: Text("Nume, număr, piesă, meseriaș…", comment: "Search field prompt."))
            .onSubmit(of: .search) { query.submit() }
            .environment(query)
    }
}

/// Caută: one field over the whole binder (sections, deadlines, history, people
/// and the text of scanned documents), ignoring diacritics. Results are grouped,
/// matching words are highlighted, and locked sections show only titles.
struct SearchScreen: View {
    @Environment(\.modelContext) private var context
    @Environment(BiometricVaultManager.self) private var vault
    @Environment(SearchQuery.self) private var search
    @Environment(ShellRouter.self) private var router

    @State private var store: SearchIndexStore?
    @State private var results: [SearchResult] = []
    @State private var recent = RecentSearches.shared
    @State private var searchTask: Task<Void, Never>?

    /// How long typing pauses before the results follow, so each letter doesn't search alone.
    static let typingDebounce: Duration = .milliseconds(120)

    var body: some View {
        List {
            if trimmedQuery.isEmpty {
                recentSection
            } else if results.isEmpty, index != nil {
                Section {
                    noResults
                        .listRowBackground(Color.clear)
                }
            } else {
                ForEach(SearchGroups.make(results)) { group in
                    Section {
                        ForEach(group.results) { result in
                            NavigationLink(value: result.document.route) {
                                SearchResultRow(result: result, query: trimmedQuery, isLocked: vault.isLocked(sectionIsSensitive: result.document.isSensitive))
                            }
                        }
                    } header: {
                        Label { Text(verbatim: group.kind.groupTitle) } icon: { Image(systemName: group.kind.systemImage) }
                    }
                }
            }
        }
        .navigationTitle(Text("Caută", comment: "Title of the search tab."))
        .onChange(of: search.submissions) { _, _ in recent.add(trimmedQuery, results: index?.search(trimmedQuery) ?? []) }
        .onChange(of: search.text) { _, _ in scheduleSearch() }
        // A result opened from here is worth remembering. Read from the navigation, not from
        // a gesture on each row: a gesture beside the link makes every tap wait to be told
        // apart from a hold.
        .onChange(of: router.searchPath.count) { before, after in
            if after > before, !trimmedQuery.isEmpty { recent.add(trimmedQuery, results: results) }
        }
        .task {
            // One index per database, kept up to date off the main thread after every save.
            let shared = SearchIndexStore.shared(for: context.container)
            shared.start()
            store = shared
        }
        .onChange(of: store?.generation) { _, _ in runSearch() }
    }

    private var index: SearchIndex? { store?.index }

    private var trimmedQuery: String { search.text.trimmingCharacters(in: .whitespacesAndNewlines) }

    @ViewBuilder
    private var recentSection: some View {
        if recent.items.isEmpty {
            Section {
                VStack(alignment: .leading, spacing: DS.Space.xs) {
                    Text("Caută orice din dosar", comment: "Search empty state title.")
                        .dsFont(.headline)
                    Text("De exemplu „RCA”, „B 123”, „plăcuțe”, „instalator” sau un cuvânt de pe o factură scanată.", comment: "Search empty state hint.")
                        .dsFont(.subheadline)
                }
                .padding(.vertical, DS.Space.xs)
            }
        } else {
            Section {
                ForEach(recent.items, id: \.self) { item in
                    Button {
                        search.text = item
                    } label: {
                        Label { Text(verbatim: item).foregroundStyle(DS.Palette.label) } icon: { Image(systemName: "clock.arrow.circlepath") }
                            .frame(minHeight: 44)
                    }
                    .swipeActions {
                        Button(role: .destructive) { recent.remove(item) } label: {
                            Text("Șterge", comment: "Confirm deleting.")
                        }
                    }
                }
                Button(role: .destructive) {
                    recent.clear()
                } label: {
                    Text("Șterge căutările recente", comment: "Clears recent searches.")
                        .frame(minHeight: 44)
                }
            } header: {
                Text("Căutări recente", comment: "Header of recent searches.")
            } footer: {
                Text("Rămân doar pe acest telefon.", comment: "Footer: recent searches are kept on device.")
            }
        }
    }

    private var noResults: some View {
        VStack(spacing: DS.Space.xs) {
            Image(systemName: "magnifyingglass")
                .font(.largeTitle)
                .foregroundStyle(DS.Palette.secondaryLabel)
                .accessibilityHidden(true)
            Text("Nimic pentru „\(trimmedQuery)”", comment: "Search with no results.")
                .dsFont(.headline)
                .multilineTextAlignment(.center)
            Text("Încearcă un cuvânt mai scurt sau doar începutul lui.", comment: "Hint when a search finds nothing.")
                .dsFont(.subheadline)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, DS.Space.xl)
    }

    private func scheduleSearch() {
        searchTask?.cancel()
        searchTask = Task {
            try? await Task.sleep(for: Self.typingDebounce)
            guard !Task.isCancelled else { return }
            runSearch()
        }
    }

    private func runSearch() {
        results = index?.search(trimmedQuery) ?? []
    }
}

/// A result: title, and unless its section is locked, the subtitle and the best
/// matching line, with the matching words highlighted.
private struct SearchResultRow: View {
    let result: SearchResult
    let query: String
    let isLocked: Bool

    var body: some View {
        HStack(spacing: DS.Space.s) {
            VStack(alignment: .leading, spacing: 2) {
                Text(SearchHighlighter.attributed(result.document.title, query: query))
                    .dsFont(.headline)
                if isLocked {
                    Label {
                        Text("Deblochează secțiunea ca să vezi mai mult.", comment: "Search result in a locked section.")
                    } icon: {
                        Image(systemName: "lock.fill")
                    }
                    .labelStyle(DSLeadingIconLabelStyle())
                    .dsFont(.footnote)
                } else {
                    if let subtitle = result.document.subtitle, !subtitle.isEmpty {
                        Text(verbatim: subtitle).dsFont(.subheadline)
                    }
                    if let snippet = result.snippet, snippet != result.document.title, !snippet.isEmpty {
                        Text(SearchHighlighter.attributed(snippet, query: query))
                            .dsFont(.footnote)
                            .lineLimit(2)
                    }
                }
            }
        }
        .padding(.vertical, DS.Space.xxs)
        .frame(minHeight: 44)
        .accessibilityElement(children: .combine)
    }
}
