import SwiftData
import SwiftUI

/// The Urmează tab: a calm, short list built on `AttentionModel`, so it stays
/// short however much is tracked.
/// - "Acum": the few things that need you, most consequential first.
/// - "Curând": the rest of the next month, one collapsed row per section.
/// - "Mai târziu": a count you can open.
///
/// It lives in the shell's navigation stack for this tab: obligations push as
/// `AppRoute.obligation`, the longer lists as `UpcomingDestination`.
struct UpcomingRoot: View {
    @Environment(\.modelContext) private var context
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Query private var obligations: [Obligation]
    /// The sections, so a bill filed or a subscription changed refreshes the missing-bill notes.
    /// Which of them are subscriptions is the categories' to say (`keys(playing: .subscription)`),
    /// the same set `BillWatchSnapshot.fetchAll` reads; a query's predicate can't ask a behaviour.
    @Query private var sections: [Asset]
    @Query private var templates: [CategoryTemplate]

    @State private var snapshots: [ObligationSnapshot] = []
    @State private var digest: AttentionDigest?
    /// Calm notes with nothing due: a bill that hasn't come.
    @State private var notes: [AttentionNote] = []
    /// Reminder buttons and widget taps that couldn't be saved, while their cycle is still open.
    @State private var unsaved: [OutsideActionFailures.Failure] = []
    @State private var today = CalendarDay(Date())
    @State private var expanded: Set<String> = []
    @State private var toast: DSToast?
    @State private var snoozing: AttentionEntry?

    @Environment(ShellRouter.self) private var router

    private var vault: BiometricVaultManager { .shared }

    var body: some View {
        content
            .navigationTitle("Urmează")
            .navigationDestination(for: UpcomingDestination.self) { destination in
                switch destination {
                case .later: UpcomingFullList(mode: .later)
                case .hidden: UpcomingFullList(mode: .hidden)
                }
            }
        .dsToast($toast)
        .task(id: changeToken) { reload() }
        .onReceive(NotificationCenter.default.publisher(for: .NSCalendarDayChanged)) { _ in reload() }
        .onReceive(NotificationCenter.default.publisher(for: OutsideActionFailures.didChange)) { _ in reload() }
        .confirmationDialog(
            Text("Amâni până când?"),
            isPresented: Binding(get: { snoozing != nil }, set: { if !$0 { snoozing = nil } }),
            titleVisibility: .visible,
            presenting: snoozing
        ) { entry in
            ForEach(UpcomingActions.snoozeChoices, id: \.self) { days in
                Button(UpcomingActions.snoozeTitle(days: days)) { snooze(entry, days: days) }
            }
            Button("Renunță", role: .cancel) {}
        }
    }

    /// Changes whenever anything the list shows changes.
    private var changeToken: Int {
        var hasher = Hasher()
        for obligation in obligations {
            hasher.combine(obligation.id)
            hasher.combine(obligation.updatedAt)
            hasher.combine(obligation.dueDate)
            hasher.combine(obligation.statusRaw)
            hasher.combine(obligation.snoozedUntil)
            hasher.combine(obligation.asset?.name)
        }
        let subscriptionKeys = templates.keys(playing: .subscription)
        for subscription in sections where subscriptionKeys.contains(subscription.templateKey) {
            hasher.combine(subscription.id)
            hasher.combine(subscription.updatedAt)
            hasher.combine(subscription.history?.count)
        }
        return hasher.finalize()
    }

    private func reload() {
        today = CalendarDay(Date())
        snapshots = (try? ObligationSnapshot.fetchAll(in: context)) ?? []
        digest = AttentionModel.digest(snapshots)
        notes = AttentionModel.missingBills((try? BillWatchSnapshot.fetchAll(in: context)) ?? [])
        unsaved = OutsideActionFailures.shared.current(in: snapshots).map(\.failure)
    }

    // MARK: Content

    @ViewBuilder private var content: some View {
        if let digest {
            List {
                if !unsaved.isEmpty {
                    Section {
                        ForEach(unsaved) { failure in unsavedRow(failure) }
                    } header: {
                        sectionHeader("Nu s-a salvat", subtitle: "Fă-o din nou de aici.")
                    }
                }
                if digest.now.isEmpty && digest.soon.isEmpty {
                    Section { allClear(digest) }
                        .listRowBackground(Color.clear)
                        .listRowInsets(EdgeInsets())
                }
                if !digest.now.isEmpty {
                    Section {
                        ForEach(digest.now) { entry in row(entry) }
                    } header: {
                        sectionHeader("Acum", subtitle: digest.overflowCount > 0 ? "Încă \(digest.overflowCount) sunt mai jos, la Curând." : nil)
                    }
                }
                if !digest.soon.isEmpty {
                    Section {
                        ForEach(digest.soon) { group in soonGroup(group) }
                    } header: {
                        sectionHeader("Curând", subtitle: "În următoarele 30 de zile")
                    }
                }
                if !notes.isEmpty {
                    Section {
                        ForEach(notes) { note in noteRow(note) }
                    } header: {
                        sectionHeader("Din timp", subtitle: "Nimic de plătit acum, doar de știut.")
                    }
                }
                if digest.later.count > 0 || digest.hiddenCount > 0 {
                    Section {
                        if digest.later.count > 0 { laterRow(digest.later) }
                        if digest.hiddenCount > 0 { hiddenRow(digest.hiddenCount) }
                    } header: {
                        sectionHeader("Mai târziu", subtitle: nil)
                    }
                }
                Section {
                    // The situations that are about the whole household, from the one list of them.
                    ForEach(ReadinessSituation.allCases.filter(\.isHouseholdWide)) { situation in
                        if let route = situation.route(for: nil) {
                            SituationLink(situation: situation, route: route, inList: true)
                        }
                    }
                } header: {
                    sectionHeader("Pregătește-te", subtitle: nil)
                }
                if snapshots.contains(where: \.isExample) {
                    Section {
                        Text("Unele termene sunt date de exemplu, marcate „Exemplu”. Le ștergi din Setări › Exemple.")
                            .dsFont(.footnote)
                            .listRowBackground(Color.clear)
                    }
                }
            }
            .listStyle(.insetGrouped)
            .dsAnimation(value: digest)
        } else {
            // First load is instant; this only reserves the space.
            Color.clear
        }
    }

    private func sectionHeader(_ title: LocalizedStringKey, subtitle: LocalizedStringKey?) -> some View {
        DSSectionHeader(title, subtitle: subtitle)
            .textCase(nil)
    }

    // MARK: Rows

    private func row(_ entry: AttentionEntry) -> some View {
        let isLocked = vault.isLocked(sectionIsSensitive: entry.obligation.isSensitive)
        return NavigationLink(value: AppRoute.obligation(entry.id)) {
            UpcomingRow(entry: entry, today: today, isLocked: isLocked)
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            Button { complete(entry) } label: { Label("Gata", systemImage: "checkmark") }
                .tint(DSStatus.done.color)
            Button { snoozing = entry } label: { Label("Amână", systemImage: "clock.arrow.circlepath") }
                .tint(DSStatus.soon.color)
        }
        .swipeActions(edge: .leading) {
            Button { router.push(.obligation(entry.id)) } label: { Label("Editează", systemImage: "slider.horizontal.3") }
                .tint(DS.Palette.accent)
        }
        .contextMenu {
            Button("Am rezolvat", systemImage: "checkmark") { complete(entry) }
            Button("Amână", systemImage: "clock.arrow.circlepath") { snoozing = entry }
            Button("Deschide", systemImage: "slider.horizontal.3") { router.push(.obligation(entry.id)) }
        }
        .accessibilityAction(named: Text("Am rezolvat")) { complete(entry) }
        .accessibilityAction(named: Text("Amână")) { snoozing = entry }
    }

    private func soonGroup(_ group: AttentionAssetGroup) -> some View {
        let isOpen = Binding(
            get: { expanded.contains(group.id) },
            set: { open in
                if open { expanded.insert(group.id) } else { expanded.remove(group.id) }
            }
        )
        let isLocked = group.entries.first.map { vault.isLocked(sectionIsSensitive: $0.obligation.isSensitive) } ?? false
        return DisclosureGroup(isExpanded: isOpen) {
            ForEach(group.entries) { entry in row(entry) }
        } label: {
            HStack(spacing: DS.Space.s) {
                DSIconWell(systemImage: isLocked ? "lock.fill" : group.symbol, tint: group.tint.color)
                VStack(alignment: .leading, spacing: 2) {
                    Text(verbatim: group.assetId == nil ? String(localized: "Pentru toată casa") : group.assetName)
                        .dsFont(.headline)
                    Text(groupSummary(group))
                        .dsFont(.subheadline, numeric: true)
                }
            }
            .frame(minHeight: 44)
            .contentShape(.rect)
        }
        .sensoryFeedback(.selection, trigger: isOpen.wrappedValue)
    }

    /// A group with one deadline names it; a bigger one counts them.
    private func groupSummary(_ group: AttentionAssetGroup) -> String {
        let first = group.nextDay.map { DueWording.date($0, today: today) } ?? ""
        if let only = group.entries.first, group.entries.count == 1 {
            let title = vault.isLocked(sectionIsSensitive: only.obligation.isSensitive) ? String(localized: "O scadență") : only.obligation.title
            return "\(title) · \(first)"
        }
        let count = String(localized: "\(group.entries.count) termene", comment: "How many deadlines a section has coming up")
        return String(localized: "\(count), primul pe \(first)", comment: "Deadlines in a section, and the date of the first")
    }

    /// A calm note: no badge, no alarm colour, opens the subscription.
    private func noteRow(_ note: AttentionNote) -> some View {
        NavigationLink(value: AppRoute.asset(note.assetId)) {
            DSListRow(
                title: Text(verbatim: note.title),
                subtitle: Text(verbatim: note.detail),
                systemImage: "envelope.open",
                trailing: { EmptyView() }
            )
        }
        .accessibilityHint(Text("Deschide abonamentul.", comment: "VoiceOver hint of a missing-bill note."))
    }

    /// A reminder button or widget tap that couldn't be saved: says which and where,
    /// and opens the deadline so it can be done again. It goes once that cycle is
    /// done, or with a swipe.
    private func unsavedRow(_ failure: OutsideActionFailures.Failure) -> some View {
        let obligation = snapshots.first { $0.id == failure.obligationId }
        let isLocked = vault.isLocked(sectionIsSensitive: obligation?.isSensitive ?? false)
        let name = isLocked ? String(localized: "O scadență protejată") : (obligation?.title ?? "")
        let title: String
        switch failure.action {
        case .complete: title = String(localized: "„\(name)” nu s-a bifat", comment: "Urmează: a reminder button or widget tap for this deadline couldn't be saved")
        case .snooze: title = String(localized: "„\(name)” nu s-a amânat", comment: "Urmează: a snooze from a reminder couldn't be saved")
        }
        let when = DueWording.date(CalendarDay(failure.failedAt), today: today)
        let detail: String
        switch failure.surface {
        case .widget: detail = String(localized: "Din widget, \(when)", comment: "Where and when an unsaved tap came from")
        case .notification, .shortcut: detail = String(localized: "Din notificare, \(when)", comment: "Where and when an unsaved tap came from")
        }
        return NavigationLink(value: AppRoute.obligation(failure.obligationId)) {
            DSListRow(
                title: Text(verbatim: title),
                subtitle: Text(verbatim: detail),
                systemImage: "arrow.clockwise.circle",
                trailing: { EmptyView() }
            )
        }
        .swipeActions(edge: .trailing) {
            Button { OutsideActionFailures.shared.dismiss(failure.obligationId) } label: { Label("Ascunde", systemImage: "eye.slash") }
                .tint(DS.Palette.secondaryLabel)
        }
        .accessibilityAction(named: Text("Ascunde")) { OutsideActionFailures.shared.dismiss(failure.obligationId) }
        .accessibilityHint(Text("Deschide termenul ca să-l faci din nou.", comment: "VoiceOver hint of an unsaved tap in Urmează."))
    }

    private func laterRow(_ later: AttentionLaterSummary) -> some View {
        NavigationLink(value: UpcomingDestination.later) {
            DSListRow(
                title: Text("\(later.count) termene mai departe", comment: "Deadlines more than a month away"),
                subtitle: later.nextDay.map { Text("Primul pe \(DueWording.date($0, today: today))") },
                systemImage: "calendar",
                trailing: { EmptyView() }
            )
        }
    }

    private func hiddenRow(_ count: Int) -> some View {
        NavigationLink(value: UpcomingDestination.hidden) {
            DSListRow(
                title: Text("\(count) amânate sau pe pauză", comment: "Deadlines snoozed or paused"),
                subtitle: Text("Nu te anunț despre ele până atunci."),
                systemImage: "moon.zzz",
                tint: DS.Palette.secondaryLabel,
                trailing: { EmptyView() }
            )
        }
    }

    // MARK: Empty

    @ViewBuilder private func allClear(_ digest: AttentionDigest) -> some View {
        let next = snapshots
            .filter { $0.status == .active && !($0.snoozedUntil.map { $0 > Date() } ?? false) }
            .min { $0.dueDay < $1.dueDay }
        VStack(spacing: DS.Space.s) {
            Image(systemName: "checkmark.circle")
                .font(.system(.largeTitle))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(DSStatus.done.color)
                .accessibilityHidden(true)
            Text("Nimic de făcut acum")
                .dsFont(.title)
                .multilineTextAlignment(.center)
            if let next {
                let title = vault.isLocked(sectionIsSensitive: next.isSensitive) ? String(localized: "o scadență protejată") : next.title
                Text("Următorul: \(title), pe \(DueWording.date(next.dueDay, today: today)).")
                    .dsFont(.body)
                    .foregroundStyle(DS.Palette.secondaryLabel)
                    .multilineTextAlignment(.center)
            } else {
                Text("Adaugă un act, o mașină sau o factură și îți spun din timp ce urmează.")
                    .dsFont(.body)
                    .foregroundStyle(DS.Palette.secondaryLabel)
                    .multilineTextAlignment(.center)
                DSPrimaryButton("Adaugă ceva", systemImage: "plus") {
                    AppNavigator.shared.open(.intake)
                }
                .padding(.top, DS.Space.xs)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, DS.Space.xxl)
        .padding(.horizontal, DS.Space.m)
        .accessibilityElement(children: .contain)
    }

    // MARK: Actions

    private func complete(_ entry: AttentionEntry) {
        Task {
            if entry.obligation.isSensitive, vault.isLocked(sectionIsSensitive: true) {
                guard await vault.unlock(reason: String(localized: "Deschide secțiunea protejată ca să bifezi termenul.")) == .success else { return }
            }
            let actions = UpcomingActions(context: context)
            guard let obligation = actions.obligation(entry.id) else { return }
            do {
                toast = try actions.complete(obligation, title: obligation.title)
            } catch {
                toast = UpcomingActions.failureToast(error)
            }
        }
    }

    private func snooze(_ entry: AttentionEntry, days: Int) {
        let actions = UpcomingActions(context: context)
        guard let obligation = actions.obligation(entry.id) else { return }
        let title = vault.isLocked(sectionIsSensitive: entry.obligation.isSensitive) ? String(localized: "termenul") : obligation.title
        do {
            toast = try actions.snooze(obligation, days: days, title: title)
        } catch {
            toast = UpcomingActions.failureToast(error)
        }
    }
}

/// The longer Urmează lists; single obligations push as `AppRoute.obligation`.
enum UpcomingDestination: Hashable {
    case later
    case hidden
}

/// One obligation in Urmează: the section it belongs to, what it is, and when in plain words.
struct UpcomingRow: View {
    let entry: AttentionEntry
    let today: CalendarDay
    let isLocked: Bool

    var body: some View {
        let obligation = entry.obligation
        HStack(alignment: .top, spacing: DS.Space.s) {
            DSIconWell(systemImage: isLocked ? "lock.fill" : obligation.symbol, tint: obligation.tint.color)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: DS.Space.xs) {
                    Text(verbatim: isLocked ? String(localized: "O scadență protejată") : obligation.title)
                        .dsFont(.headline)
                    if obligation.isExample { DSExampleBadge() }
                }
                if !isLocked {
                    Text(verbatim: obligation.assetName ?? String(localized: "Pentru toată casa"))
                        .dsFont(.subheadline)
                }
                Text(verbatim: DueWording.line(kind: obligation.kind, due: obligation.dueDay, today: today))
                    .dsFont(.subheadline, numeric: true)
                    .foregroundStyle(statusColor)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, DS.Space.xxs)
        .frame(minHeight: 44)
        .accessibilityElement(children: .combine)
        .accessibilityHint(Text("Glisează pentru Gata sau Amână."))
    }

    /// The tone of its urgency, the same one its badge and box use.
    private var statusColor: Color {
        DSStatus.urgent(entry.urgency.tone)?.textColor ?? DS.Palette.secondaryLabel
    }
}
