import SwiftUI
import SwiftData

// MARK: - Urmează

/// The next few obligations of the asset; each opens its reminder screen.
struct UpcomingPocket: View {
    let asset: Asset

    var body: some View {
        let obligations = asset.activeObligations
        DSPocketCard(SectionPocket.upcoming.title, count: obligations.isEmpty ? nil : obligations.count) {
            if obligations.isEmpty {
                PocketEmptyLine(text: String(localized: "Niciun termen. Adaugă unul ca să îți amintim la timp.", comment: "Empty Urmează pocket."))
            }
            ForEach(Array(obligations.prefix(SectionPocket.upcomingLimit).enumerated()), id: \.element.id) { index, obligation in
                if index > 0 { DSRowSeparator() }
                NavigationLink(value: AppRoute.obligation(obligation.id)) {
                    ObligationRow(obligation: obligation)
                }
                .buttonStyle(.dsPressable)
            }
        } footer: {
            DSRowSeparator()
            NavigationLink(value: SectionListRoute.obligations(asset.id)) {
                DSSeeAllRow(title: obligations.isEmpty ? "Adaugă un termen" : "Vezi tot și adaugă", count: nil)
            }
            .buttonStyle(.dsPressable)
        }
    }
}

/// An obligation with its due date and a badge for how far it is.
struct ObligationRow: View {
    let obligation: Obligation

    var body: some View {
        DSListRow(
            title: Text(verbatim: obligation.title),
            subtitle: Text(verbatim: DosarFormat.day(obligation.dueDate)),
            showsChevron: true
        ) {
            DSStatusBadge(daysRemaining: obligation.daysRemaining())
        }
    }
}

/// One quiet line inside an empty pocket.
struct PocketEmptyLine: View {
    let text: String

    var body: some View {
        Text(verbatim: text)
            .dsFont(.subheadline)
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            .fixedSize(horizontal: false, vertical: true)
    }
}

// MARK: - Chiriași, Produse, Abonamente

/// Assets filed under this one (tenants, products, subscriptions), with a button that adds one.
struct ChildrenPocket: View {
    let asset: Asset
    let pocket: SectionPocket
    let childKey: String

    @Environment(ShellRouter.self) private var router
    @Query private var templates: [CategoryTemplate]

    var body: some View {
        let children = (asset.children ?? []).filter { $0.templateKey == childKey }.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        let definition = templates.first { $0.key == childKey }?.definition ?? BuiltInTemplates.definition(for: childKey)
        DSPocketCard(pocket.title, count: children.isEmpty ? nil : children.count) {
            if children.isEmpty {
                PocketEmptyLine(text: emptyText)
            }
            ForEach(Array(children.prefix(3).enumerated()), id: \.element.id) { index, child in
                if index > 0 { DSRowSeparator() }
                NavigationLink(value: AppRoute.asset(child.id)) {
                    ChildRow(child: child, definition: definition)
                }
                .buttonStyle(.dsPressable)
            }
            if children.count > 3 {
                DSRowSeparator()
                NavigationLink(value: SectionListRoute.children(asset.id, templateKey: childKey)) {
                    DSSeeAllRow(count: children.count)
                }
                .buttonStyle(.dsPressable)
            }
        } footer: {
            DSSecondaryButton(verbatim: addTitle, systemImage: "plus") {
                router.present(.addSection(AddSectionRequest(parentID: asset.id, templateKey: childKey)))
            }
            .padding(.top, DS.Space.s)
        }
    }

    private var emptyText: String {
        switch pocket {
        case .tenants: String(localized: "Niciun chiriaș. Adaugă contractul și îți spunem când se termină.", comment: "Empty Chiriași pocket.")
        case .products: String(localized: "Niciun produs. Adaugă aragazul sau centrala și ții minte garanția.", comment: "Empty Produse pocket.")
        default: String(localized: "Niciun abonament trecut aici.", comment: "Empty Abonamente pocket.")
        }
    }

    private var addTitle: String {
        switch pocket {
        case .tenants: String(localized: "Adaugă un chiriaș", comment: "Button in the Chiriași pocket.")
        case .products: String(localized: "Adaugă un produs", comment: "Button in the Produse pocket.")
        default: String(localized: "Adaugă un abonament", comment: "Button in the Abonamente pocket.")
        }
    }
}

/// A child asset: its name and one line of what matters (contract end and rent,
/// warranty end, price), with a badge when a date is near or past.
struct ChildRow: View {
    let child: Asset
    let definition: TemplateDefinition?

    var body: some View {
        let summary = definition.map { ChildSummary.make(child.values, definition: $0) }
        DSListRow(
            title: Text(verbatim: child.name),
            subtitle: summary?.line.map { Text(verbatim: $0) },
            showsChevron: true
        ) {
            if let day = summary?.endDay {
                ExpiryBadge(day: day)
            }
        }
    }
}

/// A small badge for an end date: only shown when it is within two months or past.
struct ExpiryBadge: View {
    let day: CalendarDay
    @Environment(\.calendar) private var calendar

    var body: some View {
        let days = DSDayMath.daysRemaining(until: day.startDate(in: calendar), calendar: calendar)
        if days <= 60 {
            DSStatusBadge(days < 0 ? .overdue : .soon, text: Text(DSDueText.expiryText(daysRemaining: days, soonWithinDays: 60)))
        }
    }
}

/// The one-line summary of a child asset, read from field roles.
enum ChildSummary {
    struct Result: Equatable {
        var line: String?
        /// The date it ends: contract end, expiry or warranty end.
        var endDay: CalendarDay?
    }

    static func make(_ values: FieldValues, definition: TemplateDefinition, locale: Locale = .dosarDefault, calendar: Calendar = .current) -> Result {
        var parts: [String] = []
        if let subtitle = HeroFacts.subtitle(values, definition: definition, locale: locale) { parts.append(subtitle) }
        if let field = definition.fields(withRole: .heroMetric).first, let value = values[field.key] {
            parts.append(FieldFormatter.display(value, field: field, locale: locale))
        }
        let expiry = AssetFacts.expiry(values, template: definition)
        let warranty = AssetFacts.purchase(values, template: definition).warrantyUntil
        if let expiry {
            parts.append(String(localized: "până la \(DosarFormat.day(expiry, locale: locale, calendar: calendar))", comment: "Child summary: valid or contracted until a date."))
        } else if let warranty {
            parts.append(String(localized: "garanție până la \(DosarFormat.day(warranty, locale: locale, calendar: calendar))", comment: "Child summary: warranty until a date."))
        }
        return Result(line: parts.isEmpty ? nil : parts.joined(separator: " · "), endDay: expiry ?? warranty)
    }
}

// MARK: - Acte

/// Documents: personal documents filed under this asset (a person's ID, passport),
/// then scanned papers, each with the date it is valid until when there is one.
struct DocumentsPocket: View {
    let asset: Asset
    @Environment(ShellRouter.self) private var router

    var body: some View {
        let personal = (asset.children ?? []).filter { $0.templateKey == BuiltInTemplates.Key.documents }
            .sorted { ($0.value("document.expiry")?.dateValue ?? .distantDay) < ($1.value("document.expiry")?.dateValue ?? .distantDay) }
        let papers = (asset.attachments ?? []).filter { !$0.isArchived }.sorted { $0.createdAt > $1.createdAt }
        let rows: [DocumentRowItem] = personal.map { .personal($0) } + papers.map { .paper($0) }
        DSPocketCard(SectionPocket.documents.title, count: rows.isEmpty ? nil : rows.count) {
            if rows.isEmpty {
                PocketEmptyLine(text: String(localized: "Niciun document. Scanează polița, factura sau certificatul și le găsești aici.", comment: "Empty Acte pocket."))
            }
            ForEach(Array(rows.prefix(3).enumerated()), id: \.element.id) { index, row in
                if index > 0 { DSRowSeparator() }
                DocumentRowLink(item: row)
            }
            if rows.count > 3 {
                DSRowSeparator()
                NavigationLink(value: SectionListRoute.documents(asset.id)) {
                    DSSeeAllRow(count: rows.count)
                }
                .buttonStyle(.dsPressable)
            }
        } footer: {
            VStack(spacing: DS.Space.s) {
                if asset.templateKey == BuiltInTemplates.Key.member {
                    DSSecondaryButton("Adaugă un act", systemImage: "plus") {
                        router.present(.addPersonalDocument(holderID: asset.id))
                    }
                }
                DSSecondaryButton("Scanează un document", systemImage: "doc.viewfinder") {
                    router.open(.intake)
                }
            }
            .padding(.top, DS.Space.s)
        }
    }
}

/// A personal document (an asset) or a scanned paper (an attachment).
enum DocumentRowItem: Identifiable {
    case personal(Asset)
    case paper(Attachment)

    var id: UUID {
        switch self {
        case .personal(let asset): asset.id
        case .paper(let attachment): attachment.id
        }
    }
}

struct DocumentRowLink: View {
    let item: DocumentRowItem

    var body: some View {
        switch item {
        case .personal(let document):
            NavigationLink(value: AppRoute.asset(document.id)) {
                DSListRow(
                    title: Text(verbatim: document.name),
                    subtitle: document.value("document.expiry")?.dateValue.map {
                        Text(verbatim: String(localized: "Valabil până la \(DosarFormat.day($0))", comment: "Document row: valid until."))
                    },
                    systemImage: "person.text.rectangle",
                    showsChevron: true
                ) {
                    if let day = document.value("document.expiry")?.dateValue { ExpiryBadge(day: day) }
                }
            }
            .buttonStyle(.dsPressable)
        case .paper(let attachment):
            NavigationLink(value: AppRoute.document(attachment.id)) {
                DSListRow(
                    title: Text(verbatim: attachment.displayTitle),
                    subtitle: attachment.validityLine.map { Text(verbatim: $0) },
                    systemImage: attachment.kind.systemImage,
                    showsChevron: true
                ) {
                    if let day = attachment.obligation?.dueDay() { ExpiryBadge(day: day) }
                }
            }
            .buttonStyle(.dsPressable)
        }
    }
}

extension Attachment {
    /// The title the person gave it, else its file name.
    var displayTitle: String {
        if let title, !title.trimmingCharacters(in: .whitespaces).isEmpty { return title }
        return fileName.isEmpty ? kind.title : fileName
    }

    /// "Valabil până la …" when it belongs to an obligation (a policy valid until
    /// the renewal), else the date printed on it.
    var validityLine: String? {
        if let obligation {
            return String(localized: "Valabil până la \(DosarFormat.day(obligation.dueDate))", comment: "Document row: valid until.")
        }
        if let documentDate {
            return String(localized: "Din \(DosarFormat.day(documentDate))", comment: "Document row: the date on the document.")
        }
        return nil
    }
}

extension DocumentKind {
    var title: String {
        switch self {
        case .invoice: String(localized: "Factură")
        case .receipt: String(localized: "Bon")
        case .policy: String(localized: "Poliță")
        case .contract: String(localized: "Contract")
        case .certificate: String(localized: "Certificat")
        case .report: String(localized: "Raport")
        case .identity: String(localized: "Act de identitate")
        case .warranty: String(localized: "Certificat de garanție")
        case .manual: String(localized: "Manual")
        case .prescription: String(localized: "Rețetă")
        case .photo: String(localized: "Poză")
        case .other: String(localized: "Document")
        }
    }

    var systemImage: String {
        switch self {
        case .invoice, .receipt: "doc.text"
        case .policy, .contract: "doc.richtext"
        case .certificate, .warranty: "checkmark.seal"
        case .report: "doc.plaintext"
        case .identity: "person.text.rectangle"
        case .manual: "book"
        case .prescription: "cross.case"
        case .photo: "photo"
        case .other: "doc"
        }
    }
}

extension CalendarDay {
    /// Sorts after every real date.
    static let distantDay = CalendarDay(year: 9999, month: 12, day: 31)
}

// MARK: - Istoric

/// "Last time" for each part or job, from the maintenance log, and the button
/// that logs a visit.
struct HistoryPocket: View {
    let asset: Asset
    let definition: TemplateDefinition
    @Environment(ShellRouter.self) private var router

    var body: some View {
        let lines = HistoryLines.make(asset: asset, definition: definition)
        DSPocketCard(SectionPocket.history.title) {
            if lines.isEmpty {
                PocketEmptyLine(text: String(localized: "Nimic notat încă. Când se face ceva, notează aici: ce, cât a costat și cine a lucrat.", comment: "Empty Istoric pocket."))
            }
            ForEach(Array(lines.prefix(3).enumerated()), id: \.element.id) { index, line in
                if index > 0 { DSRowSeparator() }
                NavigationLink(value: AppRoute.historyEntry(line.entryID)) {
                    DSListRow(title: Text(verbatim: line.title), subtitle: Text(verbatim: line.detail), showsChevron: true) { EmptyView() }
                }
                .buttonStyle(.dsPressable)
            }
            if !(asset.history ?? []).isEmpty {
                DSRowSeparator()
                NavigationLink(value: SectionListRoute.history(asset.id)) {
                    DSSeeAllRow(count: asset.history?.count)
                }
                .buttonStyle(.dsPressable)
            }
        } footer: {
            DSPrimaryButton(verbatim: VisitWording.forTemplate(key: definition.key, heroStyle: definition.heroStyle).title, systemImage: "wrench.and.screwdriver.fill") {
                router.present(.addVisit(asset.id))
            }
            .padding(.top, DS.Space.s)
        }
    }
}

/// Lines for the Istoric pocket: the last time of each tracked part, or the
/// latest entries when nothing is tracked by part.
struct HistoryLines {
    struct Line: Identifiable, Equatable {
        var id: String
        var entryID: UUID
        var title: String
        var detail: String
    }

    @MainActor
    static func make(asset: Asset, definition: TemplateDefinition, now: Date = Date()) -> [Line] {
        let items = HistoryItemSnapshot.items(of: asset)
        let current = HouseholdMutations.currentMetric(of: asset)
        let unit = HouseholdMutations.heroMetricUnit(template: definition)
        let names = Dictionary(definition.components.map { ($0.key, $0.name) }, uniquingKeysWith: { first, _ in first })
        let components = MaintenanceLog.trackedComponents(in: items).compactMap { key -> Line? in
            guard let last = MaintenanceLog.lastOccurrence(of: key, in: items, currentMetric: current, now: now) else { return nil }
            return Line(id: key, entryID: last.entryId, title: names[key] ?? last.name, detail: ComponentLine.detail(last, unit: unit))
        }
        if !components.isEmpty { return components }
        return asset.timeline.map { entry in
            var parts = [DosarFormat.day(entry.occurredAt)]
            if !entry.effectiveCost.isEmpty { parts.append(entry.effectiveCost.formatted()) }
            return Line(id: entry.id.uuidString, entryID: entry.id, title: entry.title, detail: parts.joined(separator: " · "))
        }
    }
}

// MARK: - Oameni

/// People and firms who look after the asset or worked on it.
struct PeoplePocket: View {
    let asset: Asset
    @Environment(\.modelContext) private var context
    @State private var isAdding = false

    var body: some View {
        let people = ProviderDirectory(context: context).providers(for: asset)
        DSPocketCard(SectionPocket.people.title, count: people.isEmpty ? nil : people.count) {
            if people.isEmpty {
                PocketEmptyLine(text: String(localized: "Nimeni încă. Adaugă mecanicul, instalatorul sau medicul și îi suni de aici.", comment: "Empty Oameni pocket."))
            }
            ForEach(Array(people.prefix(3).enumerated()), id: \.element.id) { index, provider in
                if index > 0 { DSRowSeparator() }
                ProviderCard(provider: provider)
            }
            if people.count > 3 {
                DSRowSeparator()
                NavigationLink(value: SectionListRoute.people(asset.id)) {
                    DSSeeAllRow(count: people.count)
                }
                .buttonStyle(.dsPressable)
            }
        } footer: {
            DSSecondaryButton("Adaugă o persoană", systemImage: "person.badge.plus") {
                isAdding = true
            }
            .padding(.top, DS.Space.s)
        }
        .sheet(isPresented: $isAdding) {
            ProviderEditSheet(provider: nil, linkTo: asset)
        }
    }
}

// MARK: - Bani

/// What the asset has cost, per currency, and what it was bought for.
struct MoneyPocket: View {
    let asset: Asset
    let definition: TemplateDefinition

    var body: some View {
        let summary = MoneySummary.make(entries: (asset.history ?? []).map { ($0.occurredAt, $0.effectiveCost) }, now: Date())
        let purchase = AssetFacts.purchase(asset.values, template: definition)
        let isSubscription = asset.templateKey == BuiltInTemplates.Key.subscription
        // A fixed price per month; a contract billed by use shows its bills instead.
        let monthly = isSubscription ? SubscriptionMath.monthlyEquivalent(asset.values, usingLastBill: false) : nil
        let trend = isSubscription ? BillHistory.trend(BillHistory.bills(of: asset), today: CalendarDay(Date())) : nil
        DSPocketCard(SectionPocket.money.title) {
            if summary.allTime.isEmpty && purchase.price == nil && monthly == nil && trend == nil {
                PocketEmptyLine(text: String(localized: "Nicio sumă notată încă. Când notezi o lucrare cu preț, apare aici.", comment: "Empty Bani pocket."))
            }
            if let monthly {
                DSReadOnlyValueRow(label: Text("Pe lună", comment: "Money row: monthly equivalent of a subscription."), value: Text(verbatim: monthly.formattedCompact()))
            }
            if let trend, let amount = trend.last.amount {
                DSReadOnlyValueRow(label: Text("Ultima factură", comment: "Money row: a subscription's newest bill."), value: Text(verbatim: amount.formattedCompact()))
                if let sentence = BillHistory.changeSentence(trend) {
                    Text(verbatim: sentence)
                        .dsFont(.subheadline)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if !trend.averageLastYear.isEmpty {
                    DSReadOnlyValueRow(label: Text("În medie, pe factură", comment: "Money row: a subscription's average bill over the last year."),
                                       value: Text(verbatim: MoneyTotals(trend.averageLastYear).formatted()))
                }
            }
            if !summary.lastTwelveMonths.isEmpty {
                DSReadOnlyValueRow(label: Text("În ultimul an", comment: "Money row: spent in the last 12 months."), value: Text(verbatim: summary.lastTwelveMonths.formatted()))
            }
            if !summary.allTime.isEmpty {
                DSReadOnlyValueRow(label: Text("De când îl ai", comment: "Money row: spent in total."), value: Text(verbatim: summary.allTime.formatted()))
            }
            if let price = purchase.price {
                DSReadOnlyValueRow(label: Text("Preț de cumpărare", comment: "Money row: purchase price."), value: Text(verbatim: price.formattedCompact()))
            }
        }
    }
}

// MARK: - Formatting

/// Dates the way the binder writes them, in Romanian whatever the phone's language.
enum DosarFormat {
    /// "14 mar. 2025"
    static func day(_ date: Date, locale: Locale = .dosarDefault) -> String {
        date.formatted(.dateTime.day().month(.abbreviated).year().locale(locale))
    }

    static func day(_ day: CalendarDay, locale: Locale = .dosarDefault, calendar: Calendar = .current) -> String {
        self.day(day.startDate(in: calendar), locale: locale)
    }

    /// "14 martie 2025"
    static func longDay(_ date: Date, locale: Locale = .dosarDefault) -> String {
        date.formatted(.dateTime.day().month(.wide).year().locale(locale))
    }
}
