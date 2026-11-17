import SwiftUI
import SwiftData

// MARK: - Urmează

/// The next few obligations of the asset; each opens its reminder screen. "Vezi tot" lists
/// every one, paused ones too; "Adaugă un termen" opens the one deadline form, over the page.
struct UpcomingPocket: View {
    let asset: Asset
    /// Its line while it holds nothing (`PagePocket.emptyLine`).
    let empty: String
    let add: (PocketAddition) -> Void

    /// Every deadline the section's list shows: the active ones and those paused (a bill
    /// while the bank pays it), soonest first. Whether the pocket shows at all reads it too.
    static func listed(_ asset: Asset) -> [Obligation] {
        (asset.obligations ?? []).filter { $0.status == .active || $0.status == .paused }.sorted { $0.dueDay < $1.dueDay }
    }

    var body: some View {
        let obligations = asset.activeObligations
        let shown = obligations.prefix(SectionPocket.upcomingLimit)
        let listed = Self.listed(asset).count
        DSPocketCard(SectionPocket.upcoming.title, count: obligations.isEmpty ? nil : obligations.count) {
            if listed == 0 {
                PocketEmptyLine(text: empty)
            }
            ForEach(Array(shown.enumerated()), id: \.element.id) { index, obligation in
                if index > 0 { DSRowSeparator() }
                NavigationLink(value: AppRoute.obligation(obligation.id)) {
                    ObligationRow(obligation: obligation)
                }
                .buttonStyle(.dsPressable)
            }
            if listed > shown.count {
                if !shown.isEmpty { DSRowSeparator() }
                NavigationLink(value: SectionListRoute.obligations(asset.id)) {
                    DSSeeAllRow(count: listed)
                }
                .buttonStyle(.dsPressable)
            }
        } footer: {
            PocketAddButton(addition: .deadline, add: add)
        }
    }
}

/// A pocket's own add button, under its rows: the same words and flow as the page's menu.
struct PocketAddButton: View {
    let addition: PocketAddition
    let add: (PocketAddition) -> Void

    var body: some View {
        DSSecondaryButton(verbatim: addition.title, systemImage: addition.systemImage) {
            add(addition)
        }
        .padding(.top, DS.Space.s)
    }
}

/// The page's one row for its empty pockets: "Adaugă…", a menu naming what can be added
/// there, each under the pocket it goes in. A pocket comes back in its usual place as soon
/// as it holds something.
struct PocketAdditionsMenu: View {
    let additions: [PocketAddition]
    let add: (PocketAddition) -> Void

    var body: some View {
        if !additions.isEmpty {
            DSCard(padding: DS.Space.m) {
                Menu {
                    ForEach(additions) { addition in
                        Button {
                            add(addition)
                        } label: {
                            Label {
                                Text(verbatim: addition.title)
                                if let detail = addition.menuDetail { Text(verbatim: detail) }
                            } icon: {
                                Image(systemName: addition.systemImage)
                            }
                        }
                    }
                } label: {
                    DSListRow(
                        title: Text(verbatim: PocketWording.addMenu),
                        systemImage: "plus"
                    ) { EmptyView() }
                }
                .buttonStyle(.dsPressable)
                .accessibilityHint(Text(verbatim: additions.map(\.pocket.title).formatted(.list(type: .or).locale(.dosarDefault))))
            }
        }
    }
}

/// An obligation with its due date and a badge for how far it is.
struct ObligationRow: View {
    let obligation: Obligation

    var body: some View {
        DSListRow(
            title: Text(verbatim: obligation.title),
            subtitle: Text(verbatim: DosarFormat.day(obligation.dueDay)),
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

// MARK: - Chiriași, Produse, Abonamente, Plante, a category's own

/// Assets filed under this one (tenants, products, subscriptions, plants, the sections of a category
/// of one's own that belongs here), with a button that adds one. Which categories a pocket gathers
/// is their own data: the catalog's pocket they show in (`CategoryBehavior.parentPocket`), or, for
/// a category's own pocket (`PagePocket.category`), that category.
struct ChildrenPocket: View {
    let asset: Asset
    let pocket: PagePocket
    /// Its line while it holds nothing (`PagePocket.emptyLine`).
    let empty: String
    let add: (PocketAddition) -> Void

    @Query(sort: \CategoryTemplate.homeOrder) private var templates: [CategoryTemplate]

    /// What a child pocket gathers on a page: the categories it gathers (the built-in one first),
    /// what is filed under the page, the category a new one is made in, and whether the pocket is
    /// offered at all.
    struct Contents {
        var kinds: [CategoryTemplate]
        var children: [Asset]
        var childKey: String? { kinds.first?.key }
        /// Sections that have boxes of their own on the binder (plants) show on a parent only once
        /// the household keeps them: their category is on the binder, or this parent holds some.
        var isOffered: Bool {
            !children.isEmpty || !kinds.allSatisfy { $0.behavior.hasSectionBoxes && !$0.isOnHome }
        }
    }

    @MainActor
    static func contents(of asset: Asset, pocket: PagePocket, templates: [CategoryTemplate]) -> Contents {
        let kinds = templates.filter { template -> Bool in
            switch pocket {
            case .listed(let listed): return template.behavior.parentPocket == listed
            case .category(let key, _): return template.key == key
            }
        }.sorted { $0.isBuiltIn && !$1.isBuiltIn }
        let keys = Set(kinds.map(\.key))
        let children = (asset.children ?? []).filter { keys.contains($0.templateKey) }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        return Contents(kinds: kinds, children: children)
    }

    var body: some View {
        let contents = Self.contents(of: asset, pocket: pocket, templates: templates)
        let children = contents.children
        let definition = contents.kinds.first?.definition
        DSPocketCard(pocket.title, count: children.isEmpty ? nil : children.count) {
            if children.isEmpty {
                PocketEmptyLine(text: empty)
            }
            ForEach(Array(children.prefix(3).enumerated()), id: \.element.id) { index, child in
                if index > 0 { DSRowSeparator() }
                NavigationLink(value: AppRoute.asset(child.id)) {
                    ChildRow(child: child, definition: definition)
                }
                .buttonStyle(.dsPressable)
            }
            if children.count > 3, let childKey = contents.childKey {
                DSRowSeparator()
                NavigationLink(value: SectionListRoute.children(asset.id, templateKey: childKey)) {
                    DSSeeAllRow(count: children.count)
                }
                .buttonStyle(.dsPressable)
            }
        } footer: {
            if let childKey = contents.childKey {
                PocketAddButton(addition: .child(pocket, templateKey: childKey), add: add)
            }
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
            parts.append(PocketWording.until(DosarFormat.day(expiry, locale: locale)))
        } else if let warranty {
            parts.append(PocketWording.warrantyUntil(DosarFormat.day(warranty, locale: locale)))
        }
        return Result(line: parts.isEmpty ? nil : parts.joined(separator: " · "), endDay: expiry ?? warranty)
    }
}

// MARK: - Acte

/// Documents: personal documents filed under this asset (a person's ID, passport),
/// then the section's papers (`SectionPapers`: not a visit's or a bill's, which open from
/// their record in Istoric), each with the date it is valid until when there is one.
struct DocumentsPocket: View {
    let asset: Asset
    /// Its line while it holds nothing (`PagePocket.emptyLine`).
    let empty: String
    let add: (PocketAddition) -> Void
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
        let personal = SectionPapers.personal(asset, templates: templates).sorted { expiry($0) < expiry($1) }
        let papers = SectionPapers.listed(asset)
        let archived = SectionPapers.archived(asset).count
        let rows: [DocumentRowItem] = personal.map { .personal($0) } + papers.map { .paper($0) }
        let isHolder = behavior(asset.templateKey).role == .holder
        // A person's own documents are all listed, each one tap from its page; papers
        // follow, a few at a time like any pocket's. Those kept for reference are behind "Vezi tot".
        let shown = DocumentsPocket.shownCount(personal: personal.count, papers: papers.count, isHolder: isHolder)
        DSPocketCard(SectionPocket.documents.title, count: rows.isEmpty ? nil : rows.count) {
            if rows.isEmpty, archived == 0 {
                PocketEmptyLine(text: empty)
            }
            ForEach(Array(rows.prefix(shown).enumerated()), id: \.element.id) { index, row in
                if index > 0 { DSRowSeparator() }
                DocumentRowLink(item: row, showsPicture: showsPicture(row))
            }
            if rows.count > shown || archived > 0 {
                if !rows.isEmpty { DSRowSeparator() }
                NavigationLink(value: SectionListRoute.documents(asset.id)) {
                    DSSeeAllRow(count: rows.count + archived)
                }
                .buttonStyle(.dsPressable)
            }
        } footer: {
            VStack(spacing: 0) {
                // A person adds one of their own documents; any section a photo of a paper, filed
                // here through capture without leaving the page.
                ForEach(PocketAddition.documentButtons(isHolder: isHolder)) { addition in
                    PocketAddButton(addition: addition, add: add)
                }
            }
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
        return !vault.isLocked(document, template: template) && DocumentPageFacts.showsPicture(in: document.values)
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
                    subtitle: attachment.validityLine().map { Text(verbatim: $0) },
                    systemImage: attachment.kind.systemImage,
                    showsChevron: true
                ) {
                    if let day = attachment.validUntilDay {
                        ExpiryBadge(day: day, rule: attachment.obligation?.urgencyRule ?? DateUrgency.rule(for: day, on: attachment.asset))
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
        if let validUntil { return validUntil }
        return obligation?.dueDay
    }

    /// "Expiră pe …" for a paper that is valid until a day (a policy, as read when it was
    /// filed: last year's policy keeps last year's end), "A expirat pe …" once that day has
    /// passed, else the date printed on it.
    func validityLine(today: CalendarDay = CalendarDay(Date())) -> String? {
        if let day = validUntilDay {
            let date = DosarFormat.day(day)
            return day < today ? PocketWording.expired(date) : PocketWording.expires(date)
        }
        if let documentDay {
            return PocketWording.dated(DosarFormat.day(documentDay))
        }
        return nil
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
    /// Its line while it holds nothing, in the words of the category's visits (`PagePocket.emptyLine`).
    let empty: String
    let add: (PocketAddition) -> Void

    var body: some View {
        let lines = HistoryLines.make(asset: asset, definition: definition)
        DSPocketCard(SectionPocket.history.title) {
            if lines.isEmpty {
                PocketEmptyLine(text: empty)
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
            // A pocket's button, like every other pocket's: the page has no one main action.
            if let addition = PocketAddition.history(of: definition.behavior) { PocketAddButton(addition: addition, add: add) }
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
        // "Acum … km" since the job, counted over every counter (a new dashboard since too).
        let readings = unit.map { HouseholdMutations.readingSeries(of: asset, unit: $0).readings } ?? []
        let names = Dictionary(definition.components.map { ($0.key, $0.name) }, uniquingKeysWith: { first, _ in first })
        let components = MaintenanceLog.trackedComponents(in: items).compactMap { key -> Line? in
            guard let last = MaintenanceLog.lastOccurrence(of: key, in: items, currentMetric: current, readings: readings, now: now) else { return nil }
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
    /// Its line while no one is in it, in the words of the category's visits (`PagePocket.emptyLine`).
    let empty: String
    let add: (PocketAddition) -> Void
    @Environment(\.modelContext) private var context

    var body: some View {
        let people = ProviderDirectory(context: context).providers(for: asset)
        DSPocketCard(SectionPocket.people.title, count: people.isEmpty ? nil : people.count) {
            if people.isEmpty {
                PocketEmptyLine(text: empty)
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
            PocketAddButton(addition: .person, add: add)
        }
    }
}

// MARK: - Bani

/// What the asset has cost, per currency, and what it was bought for.
struct MoneyPocket: View {
    let asset: Asset
    let definition: TemplateDefinition
    /// Its line while it holds nothing (`PagePocket.emptyLine`).
    let empty: String

    /// What the pocket lists, read once: whether it shows at all reads it too (`PocketContents`).
    struct Facts {
        var summary: MoneySummary
        var price: Money?
        var monthly: Money?
        var trend: BillTrend?

        /// Nothing to say: no cost noted, no price, no subscription amount.
        var isEmpty: Bool { summary.allTime.isEmpty && price == nil && monthly == nil && trend == nil }

        @MainActor
        static func make(asset: Asset, definition: TemplateDefinition, now: Date = Date()) -> Facts {
            let isSubscription = definition.behavior.role == .subscription
            return Facts(
                summary: MoneySummary.make(entries: (asset.history ?? []).map { ($0.occurredAt, $0.effectiveCost) }, now: now),
                price: AssetFacts.purchase(asset.values, template: definition).price,
                // A fixed price per month; a contract billed by use shows its bills instead.
                monthly: isSubscription ? SubscriptionMath.monthlyEquivalent(asset.values, usingLastBill: false) : nil,
                trend: isSubscription ? BillHistory.trend(BillHistory.bills(of: asset), today: CalendarDay(now)) : nil
            )
        }
    }

    var body: some View {
        let facts = Facts.make(asset: asset, definition: definition)
        let summary = facts.summary
        let monthly = facts.monthly
        let trend = facts.trend
        DSPocketCard(SectionPocket.money.title) {
            if facts.isEmpty {
                PocketEmptyLine(text: empty)
            }
            if let monthly {
                DSReadOnlyValueRow(label: Text(verbatim: PocketWording.monthly), value: Text(verbatim: monthly.formattedCompact()))
            }
            if let trend, let amount = trend.last.amount {
                DSReadOnlyValueRow(label: Text(verbatim: PocketWording.lastBill), value: Text(verbatim: amount.formattedCompact()))
                if let sentence = BillHistory.changeSentence(trend) {
                    Text(verbatim: sentence)
                        .dsFont(.subheadline)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if !trend.averageLastYear.isEmpty {
                    DSReadOnlyValueRow(label: Text(verbatim: PocketWording.averageBill),
                                       value: Text(verbatim: MoneyTotals(trend.averageLastYear).formatted()))
                }
            }
            if !summary.lastTwelveMonths.isEmpty {
                DSReadOnlyValueRow(label: Text(verbatim: PocketWording.lastYear), value: Text(verbatim: summary.lastTwelveMonths.formatted()))
            }
            if !summary.allTime.isEmpty {
                DSReadOnlyValueRow(label: Text(verbatim: PocketWording.allTime), value: Text(verbatim: summary.allTime.formatted()))
            }
            if let price = facts.price {
                DSReadOnlyValueRow(label: Text(verbatim: PocketWording.purchasePrice), value: Text(verbatim: price.formattedCompact()))
            }
        }
    }
}
