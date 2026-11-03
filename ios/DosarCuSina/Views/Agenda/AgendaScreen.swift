import SwiftUI
import SwiftData

/// Everyone the household relies on, grouped by trade or by section, best first.
struct AgendaScreen: View {
    @Query(sort: \Provider.name) private var providers: [Provider]
    @AppStorage("agenda.grouping") private var grouping: AgendaGrouping = .trade
    @State private var isAdding = false

    var body: some View {
        let byID = Dictionary(providers.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let groups = AgendaGroups.make(providers.map(\.agendaPerson), by: grouping)
        ScrollView {
            VStack(alignment: .leading, spacing: DS.Space.xl) {
                if providers.isEmpty {
                    DSEmptyState(
                        "Nimeni în agendă",
                        systemImage: "person.crop.rectangle.stack",
                        message: "Adaugă mecanicul, instalatorul sau veterinarul. Îi găsești aici cu notele tale și ce au lucrat.",
                        actionTitle: "Adaugă o persoană",
                        action: { isAdding = true }
                    )
                } else {
                    Picker(selection: $grouping) {
                        ForEach(AgendaGrouping.allCases, id: \.self) { option in
                            Text(verbatim: option.title).tag(option)
                        }
                    } label: {
                        Text("Grupează", comment: "Label of the agenda grouping control.")
                    }
                    .pickerStyle(.segmented)
                    .controlSize(.large)

                    ForEach(groups) { group in
                        VStack(alignment: .leading, spacing: DS.Space.xs) {
                            DSSectionHeader(verbatim: group.title, count: group.providerIDs.count)
                            DSCard {
                                VStack(spacing: 0) {
                                    ForEach(Array(group.providerIDs.enumerated()), id: \.element) { index, id in
                                        if let provider = byID[id] {
                                            if index > 0 { DSRowSeparator() }
                                            ProviderCard(provider: provider)
                                        }
                                    }
                                }
                            }
                        }
                    }
                    DSSecondaryButton("Adaugă o persoană", systemImage: "person.badge.plus") { isAdding = true }
                }
            }
            .padding(DS.Space.m)
            .frame(maxWidth: 720)
            .frame(maxWidth: .infinity)
            .dsAnimation(value: grouping)
        }
        .background(DS.Palette.background)
        .navigationTitle(Text("Agendă", comment: "Box with people and firms."))
        .sheet(isPresented: $isAdding) {
            ProviderEditSheet(provider: nil, linkTo: nil)
        }
    }
}

extension Provider {
    var agendaPerson: AgendaGroups.Person {
        let sections = Set((assets ?? []).map(\.name) + (historyEntries ?? []).compactMap { $0.asset?.name })
        return AgendaGroups.Person(id: id, name: name, trades: trades, sections: Array(sections), wouldCallAgain: wouldCallAgain, rating: rating)
    }

    /// Trades in words: "Mecanic, Vulcanizare".
    var tradeLine: String? {
        let titles = trades.map { ProviderTrade(rawValue: $0)?.title ?? $0 }.filter { !$0.isEmpty }
        return titles.isEmpty ? nil : titles.formatted(.list(type: .and).locale(.dosarDefault))
    }

    /// "Schimb ulei · 14 mar. 2025 · 420 lei": the latest job and its price.
    var lastJobLine: String? {
        guard let last = (historyEntries ?? []).max(by: { $0.occurredAt < $1.occurredAt }) else { return nil }
        var parts = [last.title, DosarFormat.day(last.occurredAt)]
        if !last.effectiveCost.isEmpty { parts.append(last.effectiveCost.formatted()) }
        return parts.joined(separator: " · ")
    }
}

/// A provider in a list: who, what they do, stars, "would call again", their last
/// job, and real buttons to call or message.
struct ProviderCard: View {
    let provider: Provider
    @Environment(\.openURL) private var openURL
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.xs) {
            NavigationLink(value: AppRoute.provider(provider.id)) {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: DS.Space.xxs) {
                        Text(verbatim: provider.name).dsFont(.headline)
                        if let trades = provider.tradeLine {
                            Text(verbatim: trades).dsFont(.subheadline)
                        }
                        HStack(spacing: DS.Space.xs) {
                            if provider.rating != nil { DSStarRating(rating: provider.rating) }
                            if provider.wouldCallAgain == true {
                                Label {
                                    Text("Aș chema din nou", comment: "The person would call this provider again.")
                                } icon: {
                                    Image(systemName: "hand.thumbsup.fill").foregroundStyle(DSStatus.done.color)
                                }
                                .labelStyle(DSLeadingIconLabelStyle())
                                .dsFont(.caption)
                            }
                        }
                        if let last = provider.lastJobLine {
                            Text(verbatim: last).dsFont(.footnote, numeric: true)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    Image(systemName: "chevron.forward")
                        .font(.system(.footnote, weight: .semibold))
                        .foregroundStyle(DS.Palette.tertiaryLabel)
                        .accessibilityHidden(true)
                }
                .padding(.vertical, DS.Space.xs)
                .frame(minHeight: 44)
                .contentShape(.rect)
            }
            .buttonStyle(.dsPressable)
            .accessibilityElement(children: .combine)

            if let phone = provider.phone {
                let layout = dynamicTypeSize.isAccessibilitySize ? AnyLayout(VStackLayout(spacing: DS.Space.xs)) : AnyLayout(HStackLayout(spacing: DS.Space.xs))
                layout {
                    contactButton(String(localized: "Sună", comment: "Call a phone number."), systemImage: "phone.fill", url: PhoneLinks.call(phone))
                    contactButton(String(localized: "Mesaj", comment: "Send a text message."), systemImage: "message.fill", url: PhoneLinks.message(phone))
                }
                .padding(.bottom, DS.Space.xs)
            }
        }
    }

    private func contactButton(_ title: String, systemImage: String, url: URL?) -> some View {
        DSSecondaryButton(verbatim: title, systemImage: systemImage) {
            if let url { openURL(url) }
        }
        .disabled(url == nil)
        .accessibilityLabel(Text(verbatim: "\(title), \(provider.name)"))
    }
}
