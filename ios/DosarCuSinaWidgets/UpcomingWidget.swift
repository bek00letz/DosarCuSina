import AppIntents
import SwiftUI
import WidgetKit

@main
struct DosarWidgets: WidgetBundle {
    var body: some Widget {
        UpcomingWidget()
    }
}

/// What's next in the binder: Home Screen (small, medium) and Lock Screen
/// (inline, rectangular). Content comes from the snapshot the app writes after
/// every change; examples never reach it, and protected sections only show a
/// generic title.
struct UpcomingWidget: Widget {
    static let kind = "DosarUpcoming"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: Self.kind, provider: UpcomingProvider()) { entry in
            UpcomingWidgetView(entry: entry)
        }
        .configurationDisplayName(Text("Urmează"))
        .description(Text("Ce ai de rezolvat în curând, din Dosar cu Șină."))
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryInline, .accessoryRectangular])
    }
}

// MARK: - Timeline

struct UpcomingEntry: TimelineEntry {
    let date: Date
    /// Nil until the app has written its first snapshot.
    let rows: [WidgetRow]?

    static let placeholder = UpcomingEntry(date: .now, rows: [
        WidgetRow(id: UUID(), title: String(localized: "ITP"), subtitle: "VW Golf", symbol: "car.fill", daysRemaining: 5,
                  dueDate: .now.addingTimeInterval(5 * 86_400), dueKey: "", deepLink: URL(string: "dosarcusina://upcoming")!, canComplete: false),
        WidgetRow(id: UUID(), title: String(localized: "Vaccin anual"), subtitle: "PawPaw", symbol: "pawprint.fill", daysRemaining: 12,
                  dueDate: .now.addingTimeInterval(12 * 86_400), dueKey: "", deepLink: URL(string: "dosarcusina://upcoming")!, canComplete: false),
    ])
}

struct UpcomingProvider: TimelineProvider {
    /// Rows kept per entry; the medium widget shows the most.
    static let rowLimit = 3

    func placeholder(in context: Context) -> UpcomingEntry { .placeholder }

    func getSnapshot(in context: Context, completion: @escaping @Sendable (UpcomingEntry) -> Void) {
        completion(context.isPreview ? .placeholder : entry(at: .now))
    }

    /// One entry now and one at each of the next midnights, so "în 5 zile"
    /// counts down without the app running. The app reloads it after every change.
    func getTimeline(in context: Context, completion: @escaping @Sendable (Timeline<UpcomingEntry>) -> Void) {
        let calendar = Calendar.current
        let now = Date.now
        var entries = [entry(at: now)]
        var midnight = calendar.startOfDay(for: now)
        for _ in 0..<7 {
            guard let next = calendar.date(byAdding: .day, value: 1, to: midnight) else { break }
            midnight = next
            entries.append(entry(at: midnight))
        }
        completion(Timeline(entries: entries, policy: .atEnd))
    }

    private func entry(at date: Date) -> UpcomingEntry {
        let feed = WidgetFeed.load()
        guard feed != nil else { return UpcomingEntry(date: date, rows: nil) }
        let rows = WidgetContent.rows(
            feed: feed,
            completed: WidgetCompletionQueue.shared()?.pending() ?? [],
            now: date,
            protectedTitle: String(localized: "Scadență protejată"),
            limit: Self.rowLimit
        )
        return UpcomingEntry(date: date, rows: rows)
    }
}

// MARK: - Wording

enum WidgetWording {
    /// "Azi", "Mâine", "În 5 zile", "Întârziat cu 3 zile".
    static func when(_ days: Int) -> String {
        switch days {
        case ..<0: return String(localized: "Întârziat cu \(-days) zile", comment: "Widget: how many days late")
        case 0: return String(localized: "Azi", comment: "Widget: due today")
        case 1: return String(localized: "Mâine", comment: "Widget: due tomorrow")
        default: return String(localized: "În \(days) zile", comment: "Widget: due in N days")
        }
    }

    static func date(_ date: Date) -> String {
        date.formatted(.dateTime.day().month(.wide).locale(Locale(identifier: "ro_RO")))
    }

    static func color(_ days: Int) -> Color {
        days < 0 ? .red : (days == 0 ? .orange : .secondary)
    }
}

// MARK: - Views

struct UpcomingWidgetView: View {
    let entry: UpcomingEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        Group {
            switch family {
            case .accessoryInline: inline
            case .accessoryRectangular: rectangular
            case .systemMedium: medium
            default: small
            }
        }
        .containerBackground(.background, for: .widget)
    }

    private var rows: [WidgetRow] { entry.rows ?? [] }

    // Lock Screen

    @ViewBuilder private var inline: some View {
        if let first = rows.first {
            ViewThatFits {
                Text(verbatim: "\(first.title) · \(WidgetWording.when(first.daysRemaining))")
                Text(verbatim: first.title)
            }
            .widgetURL(first.deepLink)
        } else {
            Text("Nimic de făcut acum")
        }
    }

    @ViewBuilder private var rectangular: some View {
        if let first = rows.first {
            VStack(alignment: .leading, spacing: 1) {
                Label { Text(verbatim: first.title).font(.headline) } icon: { Image(systemName: first.symbol) }
                    .lineLimit(1)
                Text(verbatim: WidgetWording.when(first.daysRemaining))
                    .monospacedDigit()
                if let subtitle = first.subtitle {
                    Text(verbatim: subtitle).foregroundStyle(.secondary).lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .widgetURL(first.deepLink)
        } else {
            emptyLabel
        }
    }

    // Home Screen

    @ViewBuilder private var small: some View {
        if let first = rows.first {
            VStack(alignment: .leading, spacing: 4) {
                Image(systemName: first.symbol)
                    .font(.title3)
                    .foregroundStyle(.tint)
                    .accessibilityHidden(true)
                Text(verbatim: first.title)
                    .font(.headline)
                    .lineLimit(2)
                if let subtitle = first.subtitle {
                    Text(verbatim: subtitle).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer(minLength: 0)
                Text(verbatim: WidgetWording.when(first.daysRemaining))
                    .font(.subheadline.weight(.semibold))
                    .monospacedDigit()
                    .foregroundStyle(WidgetWording.color(first.daysRemaining))
                if first.canComplete {
                    doneButton(first)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            .widgetURL(first.deepLink)
        } else {
            emptyState
        }
    }

    @ViewBuilder private var medium: some View {
        if rows.isEmpty {
            emptyState
        } else {
            VStack(alignment: .leading, spacing: 6) {
                Text("Urmează")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                ForEach(rows) { row in
                    HStack(spacing: 8) {
                        Link(destination: row.deepLink) {
                            HStack(spacing: 8) {
                                Image(systemName: row.symbol)
                                    .foregroundStyle(.tint)
                                    .frame(width: 22)
                                    .accessibilityHidden(true)
                                VStack(alignment: .leading, spacing: 0) {
                                    Text(verbatim: row.title).font(.subheadline.weight(.semibold)).lineLimit(1)
                                    Text(verbatim: [row.subtitle, WidgetWording.when(row.daysRemaining)].compactMap { $0 }.joined(separator: " · "))
                                        .font(.caption)
                                        .monospacedDigit()
                                        .foregroundStyle(WidgetWording.color(row.daysRemaining))
                                        .lineLimit(1)
                                }
                                Spacer(minLength: 0)
                            }
                        }
                        if row.canComplete {
                            doneButton(row)
                        }
                    }
                    .frame(maxHeight: .infinity)
                }
                if rows.count < UpcomingProvider.rowLimit { Spacer(minLength: 0) }
            }
        }
    }

    private func doneButton(_ row: WidgetRow) -> some View {
        Button(intent: CompleteFromWidgetIntent(obligationID: row.id, dueDay: row.dueKey)) {
            Label("Gata", systemImage: "checkmark")
                .font(.caption.weight(.semibold))
        }
        .buttonStyle(.bordered)
        .buttonBorderShape(.capsule)
        .tint(.accentColor)
        .accessibilityLabel(Text("Marchează \(row.title) ca rezolvat"))
    }

    @ViewBuilder private var emptyState: some View {
        VStack(alignment: .leading, spacing: 4) {
            Image(systemName: entry.rows == nil ? "folder" : "checkmark.circle")
                .font(.title3)
                .foregroundStyle(.tint)
                .accessibilityHidden(true)
            Spacer(minLength: 0)
            emptyLabel
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .widgetURL(URL(string: "dosarcusina://upcoming"))
    }

    @ViewBuilder private var emptyLabel: some View {
        if entry.rows == nil {
            Text("Deschide Dosar cu Șină o dată ca să apară aici.")
                .font(.footnote)
        } else {
            VStack(alignment: .leading, spacing: 2) {
                Text("Nimic de făcut acum").font(.headline)
                Text("Te anunț din timp.").font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}

#Preview(as: .systemMedium) {
    UpcomingWidget()
} timeline: {
    UpcomingEntry.placeholder
    UpcomingEntry(date: .now, rows: [])
}
