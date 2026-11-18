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

    /// The page's rows, the latest first. Each entry is one file.
    static func rows(_ entries: [ShareFailureLog.Entry], now: Date = Date(), calendar: Calendar = .dosar) -> [Row] {
        entries.sorted { $0.at > $1.at }.enumerated().map { index, entry in
            Row(id: index,
                when: ShareProblemsWording.when(entry.at, now: now, calendar: calendar),
                title: ShareFailureWording.title(entry.failure),
                advice: ShareFailureWording.advice(entry.failure))
        }
    }

    /// Whether Despre shows the row: only while there is something to explain.
    static func showsRow(_ entries: [ShareFailureLog.Entry]) -> Bool {
        !entries.isEmpty
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

/// The page: the latest failures, or that nothing failed.
struct ShareProblemsScreen: View {
    @Environment(\.scenePhase) private var scenePhase
    /// Read as the page opens, so it shows whole from its first frame; again when the app comes
    /// back, since the share extension writes the log while the app doesn't run.
    @State private var entries = ShareProblems.read()

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
        }
        .navigationTitle(Text(verbatim: ShareProblemsWording.title))
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { entries = ShareProblems.read() }
        }
    }
}
