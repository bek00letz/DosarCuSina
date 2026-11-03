import SwiftData
import SwiftUI

/// What Urmează only counts: everything further than a month away, by month,
/// or what is snoozed or paused, with a way to bring it back.
struct UpcomingFullList: View {
    enum Mode: Hashable {
        case later
        case hidden
    }

    let mode: Mode

    @Environment(\.modelContext) private var context
    @Query private var obligations: [Obligation]
    @State private var toast: DSToast?

    private var vault: BiometricVaultManager { .shared }

    var body: some View {
        let today = CalendarDay(Date())
        let snapshots = (try? ObligationSnapshot.fetchAll(in: context)) ?? []
        List {
            switch mode {
            case .later:
                let window = AttentionModel.Limits.standard.soonWindowDays
                let later = snapshots
                    .filter { $0.status == .active && !isSnoozed($0) && today.days(to: $0.dueDay) > window }
                    .sorted { $0.dueDay < $1.dueDay }
                if later.isEmpty {
                    Text("Nimic mai departe de o lună.").dsFont(.body)
                }
                ForEach(months(of: later), id: \.title) { month in
                    Section {
                        ForEach(month.items) { item in row(item, today: today) }
                    } header: {
                        Text(verbatim: month.title).textCase(nil)
                    }
                }
            case .hidden:
                let hidden = snapshots.filter { $0.status == .paused || ($0.status == .active && isSnoozed($0)) }
                if hidden.isEmpty {
                    Text("Nimic amânat sau pe pauză.").dsFont(.body)
                }
                ForEach(hidden) { item in
                    VStack(alignment: .leading, spacing: DS.Space.xs) {
                        row(item, today: today)
                        Button(item.status == .paused ? "Pornește din nou" : "Anulează amânarea") { bringBack(item) }
                            .buttonStyle(.bordered)
                            .frame(minHeight: 44)
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle(mode == .later ? Text("Mai târziu") : Text("Amânate"))
        .navigationBarTitleDisplayMode(.inline)
        .dsToast($toast)
    }

    private func isSnoozed(_ item: ObligationSnapshot) -> Bool {
        item.snoozedUntil.map { $0 > Date() } ?? false
    }

    private func row(_ item: ObligationSnapshot, today: CalendarDay) -> some View {
        let days = today.days(to: item.dueDay)
        let entry = AttentionEntry(
            obligation: item,
            daysRemaining: days,
            urgency: AttentionModel.urgency(daysRemaining: days, profile: item.reminders),
            score: 0
        )
        return NavigationLink(value: AppRoute.obligation(item.id)) {
            UpcomingRow(entry: entry, today: today, isLocked: vault.isLocked(sectionIsSensitive: item.isSensitive))
        }
    }

    private struct Month {
        var title: String
        var items: [ObligationSnapshot]
    }

    private func months(of items: [ObligationSnapshot]) -> [Month] {
        var result: [Month] = []
        for item in items {
            let title = DosarFormat.monthYear(item.dueDay).capitalized(with: .dosarDefault)
            if result.last?.title == title {
                result[result.count - 1].items.append(item)
            } else {
                result.append(Month(title: title, items: [item]))
            }
        }
        return result
    }

    private func bringBack(_ item: ObligationSnapshot) {
        let actions = UpcomingActions(context: context)
        guard let obligation = actions.obligation(item.id) else { return }
        do {
            let engine = ObligationActions(context: context)
            if obligation.status == .paused {
                try engine.resume(obligation)
            } else {
                try engine.clearSnooze(obligation)
            }
            toast = DSToast(title: "Am readus \(obligation.title) în Urmează.", actionTitle: nil, action: nil)
        } catch {
            toast = UpcomingActions.failureToast(error)
        }
    }
}
