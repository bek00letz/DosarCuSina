import SwiftUI

/// Setări › Despre › „Probleme la primire”: why the latest files shared from other apps didn't
/// arrive, in plain words, each with when and what to do, so a „Nu s-a trimis” can be explained
/// without a developer. Read from the share log (`ShareFailureLog`, written by the share
/// extension), which keeps kinds only: never a file's name or path, so none is ever shown.
/// Its row in Despre shows only while the log holds something.
enum ShareProblems {
    /// One file that didn't arrive, as the page says it.
    struct Row: Hashable, Identifiable {
        let id: Int
        /// „Azi la 14:05”, „Ieri la 09:30”, „Pe 12 noiembrie la 14:05”.
        let when: String
        /// What happened, in the share sheet's words for one file (`ShareFailureWording.title`).
        let title: String
        /// What to do next, in the same words (`ShareFailureWording.advice`).
        let advice: String
    }

    /// The log as this phone has it now: empty when there is none or it can't be read.
    static func read(_ inbox: ShareInbox? = ShareInbox.shared()) -> [ShareFailureLog.Entry] {
        inbox?.failureLog() ?? []
    }

    /// The page's rows, the latest first. Each entry is one item, worded for the files it held
    /// (photos sorted into one document, the files past the limit).
    static func rows(_ entries: [ShareFailureLog.Entry], now: Date = Date(), calendar: Calendar = .dosar) -> [Row] {
        entries.sorted { $0.at > $1.at }.enumerated().map { index, entry in
            Row(id: index,
                when: ShareProblemsWording.when(entry.at, now: now, calendar: calendar),
                title: ShareFailureWording.title(entry.failure, count: entry.files),
                advice: ShareFailureWording.advice(entry.failure, count: entry.files))
        }
    }

    /// How many files didn't arrive, for Despre's row: every entry's files.
    static func files(_ entries: [ShareFailureLog.Entry]) -> Int {
        entries.reduce(0) { $0 + $1.files }
    }

    /// Whether Despre shows the row: only while there is something to explain.
    static func showsRow(_ entries: [ShareFailureLog.Entry]) -> Bool {
        !entries.isEmpty
    }

    /// „Golește lista”: empties the log and returns what it held, for the toast's "Anulează". An
    /// undo toast rather than a question first: what goes is a few small entries, kept in memory
    /// and put back whole (`ShareFailureLog.putBack`), beside any the share kept meanwhile.
    static func clear(_ inbox: ShareInbox? = ShareInbox.shared()) throws -> [ShareFailureLog.Entry] {
        guard let inbox else { return [] }
        return try ShareFailureLog.clear(in: inbox)
    }

    /// "Anulează" after „Golește lista”: what the list held comes back.
    static func putBack(_ entries: [ShareFailureLog.Entry], in inbox: ShareInbox? = ShareInbox.shared()) throws {
        guard let inbox, !entries.isEmpty else { return }
        try ShareFailureLog.putBack(entries, in: inbox)
    }
}

/// The page's own words; each failure's are `ShareFailureWording`'s.
enum ShareProblemsWording {
    static var title: String {
        String(localized: "Probleme la primire", comment: "Settings › Despre: the row and page that list the files shared from other apps that didn't arrive, and why.")
    }

    static var empty: String {
        String(localized: "Nicio problemă la primire.", comment: "Settings › Probleme la primire: every file shared from other apps arrived.")
    }

    static var footer: String {
        String(localized: "Când un fișier trimis din altă aplicație nu ajunge, scriu aici de ce, fără numele lui.",
               comment: "Footer of Probleme la primire: what the list is, and that no file's name is kept.")
    }

    /// The button that empties the list, a destructive action under it.
    static var clear: String {
        String(localized: "Golește lista", comment: "Settings › Probleme la primire: button that empties the list of files that didn't arrive. Undone from its toast.")
    }

    /// What VoiceOver reads for the button: the list it empties, said whole.
    static var clearLabel: String {
        String(localized: "Golește lista de probleme la primire", comment: "VoiceOver label of the button that empties Settings › Probleme la primire.")
    }

    /// The toast after the list was emptied, with "Anulează".
    static var cleared: LocalizedStringResource {
        LocalizedStringResource("Am golit lista.", comment: "Toast after emptying Settings › Probleme la primire; „Anulează” puts the list back.")
    }

    static var couldNotClear: String {
        String(localized: "Nu am putut goli lista. Încearcă din nou.", comment: "Error: the list of files that didn't arrive couldn't be emptied.")
    }

    static var couldNotPutBack: String {
        String(localized: "Nu am putut pune lista înapoi. Ce nu ajunge de acum apare aici, ca de obicei.", comment: "Error: „Anulează” couldn't bring back the list of files that didn't arrive; new problems are still listed.")
    }

    /// When a file didn't arrive: „Azi la 14:05”, „Ieri la 09:30”, „Pe 12 noiembrie la 14:05”,
    /// with the year when it was another year.
    static func when(_ date: Date, now: Date = Date(), calendar: Calendar = .dosar) -> String {
        let time = DosarFormat.time(date, calendar: calendar)
        if calendar.isDate(date, inSameDayAs: now) {
            return String(localized: "Azi la \(time)", comment: "Probleme la primire: a file that didn't arrive today, at a time.")
        }
        if let yesterday = calendar.date(byAdding: .day, value: -1, to: now), calendar.isDate(date, inSameDayAs: yesterday) {
            return String(localized: "Ieri la \(time)", comment: "Probleme la primire: a file that didn't arrive yesterday, at a time.")
        }
        let day = calendar.isDate(date, equalTo: now, toGranularity: .year)
            ? DosarFormat.dayMonth(date, calendar: calendar)
            : DosarFormat.longDay(date, calendar: calendar)
        return String(localized: "Pe \(day) la \(time)", comment: "Probleme la primire: a file that didn't arrive on a day („12 noiembrie”), at a time.")
    }
}

/// The page: the latest failures, or that nothing failed; „Golește lista” under them, undone from
/// its toast.
struct ShareProblemsScreen: View {
    @Environment(\.scenePhase) private var scenePhase
    /// Read as the page opens, so it shows whole from its first frame; again when the app comes
    /// back, since the share extension writes the log while the app doesn't run, and whenever
    /// the app empties it or puts it back (`ShareFailureLog.didChangeNotification`).
    @State private var entries = ShareProblems.read()
    /// „Am golit lista.” with "Anulează", which puts back what the list held.
    @State private var toast: DSToast?
    @State private var error: UserFacingError?

    var body: some View {
        let rows = ShareProblems.rows(entries)
        List {
            Section {
                if rows.isEmpty {
                    Text(verbatim: ShareProblemsWording.empty)
                        .dsFont(.subheadline)
                        .frame(minHeight: DS.Control.minimumHitTarget, alignment: .leading)
                }
                ForEach(rows) { row in
                    VStack(alignment: .leading, spacing: DS.Space.xs) {
                        Text(verbatim: row.title)
                            .dsFont(.headline)
                        Text(verbatim: row.when)
                            .dsFont(.subheadline)
                            .foregroundStyle(.secondary)
                        Text(verbatim: row.advice)
                            .dsFont(.subheadline)
                    }
                    .padding(.vertical, DS.Space.xs)
                    .frame(minHeight: DS.Control.minimumHitTarget, alignment: .leading)
                    .accessibilityElement(children: .combine)
                }
            } footer: {
                Text(verbatim: ShareProblemsWording.footer)
            }
            if !rows.isEmpty {
                Section {
                    // Asks nothing first: the toast's "Anulează" puts the list back whole.
                    Button(role: .destructive, action: clear) {
                        Label { Text(verbatim: ShareProblemsWording.clear) } icon: { Image(systemName: "trash") }
                            .frame(maxWidth: .infinity, minHeight: DS.Control.minimumHitTarget, alignment: .leading)
                            .contentShape(.rect)
                    }
                    .accessibilityLabel(Text(verbatim: ShareProblemsWording.clearLabel))
                }
            }
        }
        .dsAnimation(value: entries)
        .dsToast($toast)
        .userErrorAlert($error)
        .navigationTitle(Text(verbatim: ShareProblemsWording.title))
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { entries = ShareProblems.read() }
        }
        .onReceive(NotificationCenter.default.publisher(for: ShareFailureLog.didChangeNotification)) { _ in
            entries = ShareProblems.read()
        }
    }

    private func clear() {
        do {
            let removed = try ShareProblems.clear()
            entries = ShareProblems.read()
            guard !removed.isEmpty else { return }
            // The toast brings its own haptic; its button puts back what the list held.
            toast = DSToast(title: ShareProblemsWording.cleared, systemImage: "trash.fill", tint: DS.Palette.secondaryLabel,
                            action: { putBack(removed) }, duration: DSToast.deletionDuration)
        } catch {
            self.error = UserFacingError(message: ShareProblemsWording.couldNotClear)
        }
    }

    private func putBack(_ removed: [ShareFailureLog.Entry]) {
        do {
            try ShareProblems.putBack(removed)
        } catch {
            self.error = UserFacingError(message: ShareProblemsWording.couldNotPutBack)
        }
        entries = ShareProblems.read()
    }
}
