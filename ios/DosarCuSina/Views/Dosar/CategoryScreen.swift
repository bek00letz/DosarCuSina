import SwiftUI
import SwiftData

/// A box that gathers a category: Acte by person, Garanții by whether they still
/// cover, Abonamente with what they cost a month, or any category's assets.
struct CategoryScreen: View {
    let templateKey: String
    @Query private var templates: [CategoryTemplate]
    @Environment(BiometricVaultManager.self) private var vault

    init(templateKey: String) {
        self.templateKey = templateKey
        let key = templateKey
        _templates = Query(filter: #Predicate<CategoryTemplate> { $0.key == key })
    }

    var body: some View {
        if let template = templates.first {
            Group {
                if vault.isLocked(template) {
                    LockedSectionView(title: template.name)
                } else {
                    CategoryContent(template: template)
                }
            }
            .navigationTitle(Text(verbatim: template.name))
        } else {
            MissingRecordView()
        }
    }
}

private struct CategoryContent: View {
    let template: CategoryTemplate

    @Environment(\.modelContext) private var context
    @Environment(ShellRouter.self) private var router
    @Query(sort: \Asset.name) private var assets: [Asset]

    /// One box or one each is arranged where the boxes are: a box's press-and-hold menu and
    /// Setări › Ecranul Dosar (`BoxGrouping.offer`), not on the page the box opens.
    var body: some View {
        content(assets.filter { $0.templateKey == template.key })
    }

    private func content(_ mine: [Asset]) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DS.Space.xl) {
                // What the page lists is the category's own data, so a category of the
                // person's own can be listed by holder, by warranty or by monthly cost too.
                switch template.behavior.listing {
                case .byHolder:
                    documents
                case .byWarranty:
                    warranties(mine)
                case .byMonthlyCost:
                    subscriptions(mine)
                case .plain:
                    plainList(mine)
                }
            }
            .padding(DS.Space.m)
            .frame(maxWidth: 720)
            .frame(maxWidth: .infinity)
        }
        .background(DS.Palette.background)
    }

    // MARK: Acte

    @ViewBuilder
    private var documents: some View {
        let groups = (try? DocumentHolders.groups(in: context, category: template.key)) ?? []
        // One way to add, photo first: capture reads the type, names whose it is and makes the
        // person when they aren't in the binder yet; "Scriu eu" asks whose it is.
        if groups.isEmpty {
            emptyState(
                title: "Niciun act încă",
                message: "Adaugă buletinul, pașaportul sau permisul. Îți spun cu luni înainte când trebuie reînnoite.",
                action: "Adaugă un document"
            ) { addDocument() }
        }
        ForEach(groups) { group in
            VStack(alignment: .leading, spacing: DS.Space.xs) {
                if group.holder == nil {
                    DSSectionHeader(verbatim: group.title, count: group.documents.count)
                }
                DSCard {
                    VStack(spacing: 0) {
                        // The person's own row opens their page; their documents follow.
                        if let holder = group.holder {
                            NavigationLink(value: AppRoute.asset(holder.id)) {
                                DSListRow(title: Text(verbatim: holder.name), systemImage: "person.crop.circle", showsChevron: true) { EmptyView() }
                            }
                            .buttonStyle(.dsPressable)
                        }
                        ForEach(Array(group.documents.enumerated()), id: \.element.id) { index, document in
                            if index > 0 || group.holder != nil { DSRowSeparator() }
                            DocumentRowLink(item: .personal(document))
                        }
                    }
                }
            }
        }
        if !groups.isEmpty {
            DSSecondaryButton(verbatim: PocketWording.addDocument, systemImage: "plus") { addDocument() }
        }
    }

    /// A new personal document, for whoever the photo or "Scriu eu" says.
    private func addDocument() {
        router.present(.addPersonalDocument(holderID: nil))
    }

    // MARK: Garanții

    @ViewBuilder
    private func warranties(_ items: [Asset]) -> some View {
        let definition = template.definition
        let today = CalendarDay(Date())
        let covered = items.filter { AssetFacts.purchase($0.values, template: definition).isUnderWarranty(on: today) ?? true }
            .sorted { (AssetFacts.purchase($0.values, template: definition).warrantyUntil ?? .distantDay) < (AssetFacts.purchase($1.values, template: definition).warrantyUntil ?? .distantDay) }
        let expired = items.filter { AssetFacts.purchase($0.values, template: definition).isUnderWarranty(on: today) == false }
        if items.isEmpty {
            emptyState(
                title: "Nicio garanție încă",
                message: "Adaugă ce ai cumpărat, cu bonul. Când se strică, știi dacă mai e în garanție.",
                action: "Adaugă un produs"
            ) { addTopLevel() }
        } else {
            assetGroup(String(localized: "În garanție", comment: "Group of products still under warranty."), covered, definition: definition)
            assetGroup(String(localized: "Garanție expirată", comment: "Group of products whose warranty ended."), expired, definition: definition)
            DSSecondaryButton("Adaugă un produs", systemImage: "plus") { addTopLevel() }
        }
    }

    // MARK: Abonamente

    @ViewBuilder
    private func subscriptions(_ items: [Asset]) -> some View {
        let total = SubscriptionMath.monthlyTotal(items.map(\.values))
        if items.isEmpty {
            emptyState(
                title: "Niciun abonament încă",
                message: "Adaugă telefonul, internetul sau streamingul. Vezi cât plătești pe lună și îți amintesc înainte de reînnoire.",
                action: "Adaugă un abonament"
            ) { addTopLevel() }
        } else {
            if !total.isEmpty {
                DSMetricTile("Pe lună, în total", systemImage: "creditcard") {
                    Text(verbatim: total.formatted())
                }
            }
            assetGroup(String(localized: "Abonamente", comment: "Section pocket"), items, definition: template.definition)
            DSSecondaryButton("Adaugă un abonament", systemImage: "plus") { addTopLevel() }
        }
    }

    // MARK: Any category

    @ViewBuilder
    private func plainList(_ items: [Asset]) -> some View {
        if items.isEmpty {
            emptyState(title: "Nimic aici încă", message: "Adaugă primul și îl găsești aici.", action: "Adaugă") { addTopLevel() }
        } else {
            assetGroup(template.name, items, definition: template.definition)
            DSSecondaryButton("Adaugă", systemImage: "plus") { addTopLevel() }
        }
    }

    // MARK: Helpers

    @ViewBuilder
    private func assetGroup(_ title: String, _ items: [Asset], definition: TemplateDefinition) -> some View {
        if !items.isEmpty {
            DSPocketCard(title, count: items.count) {
                ForEach(Array(items.enumerated()), id: \.element.id) { index, asset in
                    if index > 0 { DSRowSeparator() }
                    NavigationLink(value: AppRoute.asset(asset.id)) {
                        ChildRow(child: asset, definition: definition)
                    }
                    .buttonStyle(.dsPressable)
                }
            }
        }
    }

    private func emptyState(title: LocalizedStringKey, message: LocalizedStringKey, action: LocalizedStringKey, perform: @escaping () -> Void) -> some View {
        DSEmptyState(title, systemImage: template.symbol, message: message, actionTitle: action, action: perform)
    }

    private func addTopLevel() {
        router.present(.addSection(AddSectionRequest(templateKey: template.key)))
    }
}
