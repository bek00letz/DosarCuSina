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
            subtitle: Text(verbatim: DosarFormat.day(obligation.dueDay())),
            showsChevron: true
        ) {
            DSStatusBadge(urgency: obligation.urgency(), daysRemaining: obligation.daysRemaining())
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
/// Which categories a pocket gathers is their own data (`CategoryBehavior.parentPocket`).
struct ChildrenPocket: View {
    let asset: Asset
    let pocket: SectionPocket

    @Environment(ShellRouter.self) private var router
    @Query(sort: \CategoryTemplate.homeOrder) private var templates: [CategoryTemplate]

    /// The categories this pocket gathers, the built-in one first.
    private var childTemplates: [CategoryTemplate] {
        templates.filter { $0.behavior.parentPocket == pocket }.sorted { $0.isBuiltIn && !$1.isBuiltIn }
    }

    var body: some View {
        let kinds = childTemplates
        let keys = Set(kinds.map(\.key))
        let childKey = kinds.first?.key ?? ""
        let children = (asset.children ?? []).filter { keys.contains($0.templateKey) }.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        let definition = kinds.first?.definition
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
                ExpiryBadge(day: day, rule: DateUrgency.rule(for: day, on: child))
            }
        }
    }
}

/// A small badge for an end date, shown once the deadline it drives needs the person
/// (the same moment it joins Urmează) or once it has passed.
struct ExpiryBadge: View {
    let day: CalendarDay
    let rule: UrgencyRule
    @Environment(\.calendar) private var calendar

    var body: some View {
        let today = CalendarDay(Date(), calendar: calendar)
        let urgency = rule.urgency(of: day, today: today, calendar: calendar)
        if urgency.tone != .calm {
            DSStatusBadge(expiry: urgency, daysRemaining: today.days(to: day, calendar: calendar))
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

    static func make(_ values: FieldValues, definition: TemplateDefinition, locale: Locale = .dosarDefault) -> Result {
        var parts: [String] = []
        if let subtitle = HeroFacts.subtitle(values, definition: definition, locale: locale) { parts.append(subtitle) }
        if let field = definition.fields(withRole: .heroMetric).first, let value = values[field.key] {
            parts.append(FieldFormatter.display(value, field: field, locale: locale))
        }
        let expiry = AssetFacts.expiry(values, template: definition)
        let warranty = AssetFacts.purchase(values, template: definition).warrantyUntil
        if let expiry {
            parts.append(String(localized: "până la \(DosarFormat.day(expiry, locale: locale))", comment: "Child summary: valid or contracted until a date."))
        } else if let warranty {
            parts.append(String(localized: "garanție până la \(DosarFormat.day(warranty, locale: locale))", comment: "Child summary: warranty until a date."))
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
    @Environment(BiometricVaultManager.self) private var vault
    @Query private var templates: [CategoryTemplate]

    /// What a category does, by key.
    private func behavior(_ key: String) -> CategoryBehavior {
        templates.first { $0.key == key }?.behavior ?? .standard
    }

    /// When a personal document stops being valid, by its category's expiry field.
    private func expiry(_ document: Asset) -> CalendarDay {
        templates.first { $0.key == document.templateKey }.flatMap { AssetFacts.expiry(document.values, template: $0.definition) } ?? .distantDay
    }

    var body: some View {
        let personal = (asset.children ?? []).filter { behavior($0.templateKey).role == .personalDocument }
            .sorted { expiry($0) < expiry($1) }
        let papers = (asset.attachments ?? []).filter { !$0.isArchived }.sorted { $0.createdAt > $1.createdAt }
        let rows: [DocumentRowItem] = personal.map { .personal($0) } + papers.map { .paper($0) }
        // A person's own documents are all listed, each one tap from its page; papers
        // follow, a few at a time like any pocket's.
        let shown = DocumentsPocket.shownCount(personal: personal.count, papers: papers.count, isHolder: behavior(asset.templateKey).role == .holder)
        DSPocketCard(SectionPocket.documents.title, count: rows.isEmpty ? nil : rows.count) {
            if rows.isEmpty {
                PocketEmptyLine(text: String(localized: "Niciun document. Scanează polița, factura sau certificatul și le găsești aici.", comment: "Empty Acte pocket."))
            }
            ForEach(Array(rows.prefix(shown).enumerated()), id: \.element.id) { index, row in
                if index > 0 { DSRowSeparator() }
                DocumentRowLink(item: row, showsPicture: showsPicture(row))
            }
            if rows.count > shown {
                DSRowSeparator()
                NavigationLink(value: SectionListRoute.documents(asset.id)) {
                    DSSeeAllRow(count: rows.count)
                }
                .buttonStyle(.dsPressable)
            }
        } footer: {
            VStack(spacing: DS.Space.s) {
                if behavior(asset.templateKey).role == .holder {
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

extension DocumentsPocket {
    /// How many rows the pocket lists before "Vezi tot": every one of a person's own
    /// documents, then at most three papers; three in all on any other page.
    static func shownCount(personal: Int, papers: Int, isHolder: Bool) -> Int {
        isHolder ? personal + min(papers, 3) : min(personal + papers, 3)
    }

    /// A personal document's row shows its own picture while its category is open, and
    /// never a bank card's (its picture shows the whole number).
    private func showsPicture(_ row: DocumentRowItem) -> Bool {
        guard case .personal(let document) = row else { return false }
        let template = templates.first { $0.key == document.templateKey }
        return !(template.map(vault.isLocked) ?? false) && DocumentPageFacts.showsPicture(in: document.values)
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
    /// A personal document's row shows its own picture in place of the symbol (only where
    /// its category is open, and never for a bank card: `DocumentsPocket.showsPicture`).
    var showsPicture = false

    var body: some View {
        switch item {
        case .personal(let document):
            // One tap: the document's own page, picture first.
            NavigationLink(value: AppRoute.asset(document.id)) {
                DSListRow(
                    title: Text(verbatim: document.name),
                    subtitle: DocumentSummary.line(document.values).map { Text(verbatim: $0) },
                    systemImage: "person.text.rectangle",
                    thumbnail: showsPicture ? DSThumbnailWell(image: picture(of: document), systemImage: "person.text.rectangle") : nil,
                    showsChevron: true
                ) {
                    if let day = document.value(DocumentFields.expiry)?.dateValue { ExpiryBadge(day: day, rule: DateUrgency.rule(for: day, on: document)) }
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
                    if let day = attachment.validUntilDay {
                        ExpiryBadge(day: day, rule: attachment.obligation?.reminders.urgencyRule ?? DateUrgency.rule(for: day, on: attachment.asset))
                    }
                }
            }
            .buttonStyle(.dsPressable)
        }
    }

    /// The small picture of the document's own first page, as it is shown.
    private func picture(of document: Asset) -> Image? {
        DocumentPageFacts.currentPicture(of: document)?.thumbnailData
            .flatMap(UIImage.init(data:))
            .map { Image(uiImage: $0) }
    }
}

extension Attachment {
    /// The title the person gave it, else its file name.
    var displayTitle: String {
        if let title, !title.trimmingCharacters(in: .whitespaces).isEmpty { return title }
        return fileName.isEmpty ? kind.title : fileName
    }

    /// The last day the paper itself is valid: as read when it was filed. A paper filed
    /// before that was kept (version 3) falls back to its deadline's day.
    var validUntilDay: CalendarDay? {
        if let validUntil { return CalendarDay(validUntil) }
        return obligation?.dueDay()
    }

    /// "Valabil până la …" for a paper that is valid until a day (a policy, as read when
    /// it was filed: last year's policy keeps last year's end), else the date printed on it.
    var validityLine: String? {
        if let day = validUntilDay {
            return String(localized: "Valabil până la \(DosarFormat.day(day))", comment: "Document row: valid until.")
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
        let isSubscription = definition.behavior.role == .subscription
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
