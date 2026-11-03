import SwiftUI
import SwiftData
import UniformTypeIdentifiers

/// A box opened from the grid. Kept apart from `AppRoute` so only boxes opened
/// here zoom out of their box; the same screens pushed from elsewhere slide in.
struct BoxDestination: Hashable {
    let route: AppRoute
}

/// The Dosar tab: one big box per thing the household looks after, plus Acte,
/// Garanții, Abonamente and Agenda, and a last dashed box that adds a section.
struct DosarHomeView: View {
    @Environment(\.modelContext) private var context
    @Environment(ShellRouter.self) private var router
    @Environment(BiometricVaultManager.self) private var vault
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @Query(sort: [SortDescriptor(\CategoryTemplate.homeOrder), SortDescriptor(\CategoryTemplate.createdAt)]) private var templates: [CategoryTemplate]
    @Query(sort: \Asset.createdAt) private var assets: [Asset]
    @Query private var obligations: [Obligation]
    @Query private var providers: [Provider]

    @State private var layout = BinderLayoutStore.shared
    @State private var dragging: BinderBoxID?
    @State private var isLoadingExamples = false
    @State private var error: UserFacingError?
    @State private var toast: DSToast?
    @Namespace private var zoom

    var body: some View {
        ScrollView {
            if assets.isEmpty {
                DosarEmptyState(isLoading: isLoadingExamples, addFirst: addSection, loadExamples: loadExamples)
                    .padding(.horizontal, DS.Space.m)
                    .transition(.opacity)
            } else {
                grid
                    .padding(.horizontal, DS.Space.m)
                    .padding(.bottom, DS.Space.xl)
            }
        }
        .background(DS.Palette.background)
        .navigationTitle(Text("Dosar", comment: "Title of the home tab."))
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    router.present(.settings(nil))
                } label: {
                    Text("Setări", comment: "Toolbar button that opens settings.")
                }
                .keyboardShortcut(",", modifiers: .command)
            }
        }
        .navigationDestination(for: BoxDestination.self) { destination in
            RouteScreen(route: destination.route)
                .navigationTransition(.zoom(sourceID: destination.route, in: zoom))
        }
        .dsAnimation(value: assets.isEmpty)
        .dsToast($toast)
        .userErrorAlert($error)
    }

    // MARK: Grid

    private var columns: [GridItem] {
        if dynamicTypeSize.isAccessibilitySize {
            return [GridItem(.flexible(), spacing: DS.Space.s)]
        }
        if horizontalSizeClass == .regular {
            return [GridItem(.adaptive(minimum: 220, maximum: 360), spacing: DS.Space.s)]
        }
        return Array(repeating: GridItem(.flexible(), spacing: DS.Space.s), count: 2)
    }

    private var grid: some View {
        let model = BinderBoxes(templates: templates, assets: assets, providerCount: providers.count, vault: vault, context: context)
        let order = layout.order(defaults: model.defaultOrder)
        return LazyVGrid(columns: columns, spacing: DS.Space.s) {
            ForEach(order, id: \.self) { id in
                if let box = model.box(for: id) {
                    boxView(box, order: order)
                }
            }
            Button(action: addSection) {
                DSAddBox(title: "Adaugă o secțiune")
            }
            .buttonStyle(.dsPressable)
            .accessibilityHint(Text("Alegi ce vrei să ții în dosar: o mașină, o casă, un animal.", comment: "VoiceOver hint of the add-section box."))
        }
        .padding(.top, DS.Space.xs)
        .animation(DS.Motion.animation(DS.Motion.standard, reduceMotion: reduceMotion), value: order)
    }

    private func boxView(_ box: BinderBox, order: [BinderBoxID]) -> some View {
        NavigationLink(value: BoxDestination(route: box.id.route)) {
            DSBox(
                title: box.title,
                systemImage: box.symbol,
                tint: box.tint,
                photo: box.photo,
                statusText: box.statusText,
                tone: box.tone,
                isExample: box.isExample,
                isLocked: box.isLocked
            )
        }
        .buttonStyle(.dsPressable)
        .matchedTransitionSource(id: box.id.route, in: zoom)
        .opacity(dragging == box.id ? 0.4 : 1)
        .onDrag {
            dragging = box.id
            return NSItemProvider(object: box.id.storageKey as NSString)
        }
        .onDrop(of: [.text], delegate: BoxDropDelegate(target: box.id, dragging: $dragging, layout: layout, order: order, reduceMotion: reduceMotion))
        .contextMenu {
            Button {
                move(box.id, by: -1, in: order)
            } label: {
                Label { Text("Mută mai în față", comment: "Context menu: move a box earlier.") } icon: { Image(systemName: "arrow.backward") }
            }
            .disabled(order.first == box.id)
            Button {
                move(box.id, by: 1, in: order)
            } label: {
                Label { Text("Mută mai în spate", comment: "Context menu: move a box later.") } icon: { Image(systemName: "arrow.forward") }
            }
            .disabled(order.last == box.id)
        }
        .accessibilityAction(named: Text("Mută mai în față", comment: "Context menu: move a box earlier.")) { move(box.id, by: -1, in: order) }
        .accessibilityAction(named: Text("Mută mai în spate", comment: "Context menu: move a box later.")) { move(box.id, by: 1, in: order) }
        .sensoryFeedback(.impact(weight: .medium), trigger: dragging == box.id) { _, isDragging in isDragging }
    }

    // MARK: Actions

    private func move(_ id: BinderBoxID, by offset: Int, in order: [BinderBoxID]) {
        layout.update(BinderLayout.move(id, by: offset, in: order))
        layout.persist()
    }

    private func addSection() {
        router.present(.addSection(.topLevel))
    }

    private func loadExamples() {
        isLoadingExamples = true
        defer { isLoadingExamples = false }
        do {
            try ExampleDataService(context: context).loadExamples()
            toast = DSToast(
                title: LocalizedStringResource("Am pus exemplele. Le ștergi oricând din Setări.", comment: "Toast after loading example data."),
                actionTitle: nil
            )
        } catch {
            self.error = UserFacingError(error)
        }
    }
}

// MARK: - Drag to reorder

/// Moves the dragged box into the place of the box under the finger, live, and
/// saves the order when the finger lifts.
private struct BoxDropDelegate: DropDelegate {
    let target: BinderBoxID
    @Binding var dragging: BinderBoxID?
    let layout: BinderLayoutStore
    let order: [BinderBoxID]
    let reduceMotion: Bool

    func dropEntered(info: DropInfo) {
        guard let dragging, dragging != target else { return }
        withAnimation(DS.Motion.animation(DS.Motion.standard, reduceMotion: reduceMotion)) {
            layout.update(BinderLayout.move(dragging, onto: target, in: order))
        }
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: .move)
    }

    func performDrop(info: DropInfo) -> Bool {
        layout.persist()
        dragging = nil
        return true
    }

    func dropExited(info: DropInfo) {}
}

// MARK: - Box model

/// A box ready to draw.
struct BinderBox: Identifiable {
    let id: BinderBoxID
    let title: String
    let symbol: String
    let tint: Color
    let photo: Image?
    let statusText: String
    let tone: DSBoxTone
    let isExample: Bool
    let isLocked: Bool
}

/// Builds the boxes from the data for one render.
@MainActor
struct BinderBoxes {
    let defaultOrder: [BinderBoxID]
    private let templatesByKey: [String: CategoryTemplate]
    private let assetsByID: [UUID: Asset]
    private let assets: [Asset]
    private let snapshots: [ObligationSnapshot]
    private let providerCount: Int
    private let vault: BiometricVaultManager

    init(templates: [CategoryTemplate], assets: [Asset], providerCount: Int, vault: BiometricVaultManager, context: ModelContext) {
        var byKey: [String: CategoryTemplate] = [:]
        for template in templates where byKey[template.key] == nil { byKey[template.key] = template }
        templatesByKey = byKey
        assetsByID = Dictionary(assets.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        self.assets = assets
        self.providerCount = providerCount
        self.vault = vault
        snapshots = (try? ObligationSnapshot.fetchAll(in: context)) ?? []
        defaultOrder = BinderLayout.defaultOrder(
            templates: byKey.values.map { .init(key: $0.key, homeOrder: $0.homeOrder, isOnHome: $0.isOnHome, box: $0.behavior.box) },
            assets: assets.map { .init(id: $0.id, templateKey: $0.templateKey, isTopLevel: $0.parent == nil, createdAt: $0.createdAt) }
        )
    }

    func box(for id: BinderBoxID) -> BinderBox? {
        switch id {
        case .asset(let assetID):
            guard let asset = assetsByID[assetID] else { return nil }
            let template = templatesByKey[asset.templateKey]
            let isLocked = template.map(vault.isLocked) ?? false
            let descendants = Set(AssetActions.descendants(of: asset).map(\.id))
            let status = BoxStatus.make(forAsset: asset.id, descendants: descendants, in: snapshots)
            return BinderBox(
                id: id,
                title: asset.name,
                symbol: asset.symbol(template: template),
                tint: asset.tintColor(template: template),
                photo: isLocked ? nil : asset.thumbnail(),
                statusText: status.line(isSensitive: isLocked),
                tone: status.tone,
                isExample: asset.isExample,
                isLocked: isLocked
            )
        case .category(let key):
            guard let template = templatesByKey[key] else { return nil }
            let isLocked = vault.isLocked(template)
            let members = Set(assets.filter { $0.templateKey == key || belongsToCategory($0, key) }.map(\.id))
            let status = BoxStatus.make(snapshots.filter { $0.assetId.map(members.contains) ?? false })
            let all = assets.filter { $0.templateKey == key }
            return BinderBox(
                id: id,
                title: template.name,
                symbol: template.symbol,
                tint: template.tintColor,
                photo: nil,
                statusText: all.isEmpty ? String(localized: "Gol deocamdată", comment: "Box status when a category box holds nothing yet.") : status.line(isSensitive: isLocked),
                tone: all.isEmpty ? .neutral : status.tone,
                isExample: !all.isEmpty && all.allSatisfy(\.isExample),
                isLocked: isLocked
            )
        case .agenda:
            return BinderBox(
                id: id,
                title: String(localized: "Agendă", comment: "Box with people and firms."),
                symbol: "person.crop.rectangle.stack.fill",
                tint: TemplateTint.teal.color,
                photo: nil,
                statusText: providerCount == 0
                    ? String(localized: "Nimeni încă", comment: "Agenda box when no people are saved.")
                    : String(localized: "\(providerCount) contacte", comment: "Agenda box: how many people and firms are saved."),
                tone: .neutral,
                isExample: false,
                isLocked: false
            )
        }
    }

    /// A person's own deadlines count towards the box their personal documents live in (Acte).
    private func belongsToCategory(_ asset: Asset, _ key: String) -> Bool {
        templatesByKey[key]?.behavior.role == .personalDocument && templatesByKey[asset.templateKey]?.behavior.role == .holder
    }
}

// MARK: - Empty

/// The first run, before anything is in the binder.
struct DosarEmptyState: View {
    let isLoading: Bool
    let addFirst: () -> Void
    let loadExamples: () -> Void

    var body: some View {
        VStack(spacing: DS.Space.xl) {
            Image(systemName: "folder.fill.badge.plus")
                .font(.system(size: 56))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(DS.Palette.accent)
                .padding(.top, DS.Space.xxl)
                .accessibilityHidden(true)
            VStack(spacing: DS.Space.xs) {
                Text("Dosarul e gol", comment: "Empty home title.")
                    .dsFont(.title)
                    .multilineTextAlignment(.center)
                    .accessibilityAddTraits(.isHeader)
                Text("Pune aici mașina, casa, actele sau pisica. Îți spunem din timp când expiră ceva și ții minte cine a reparat ce.", comment: "Empty home message.")
                    .dsFont(.body)
                    .foregroundStyle(DS.Palette.secondaryLabel)
                    .multilineTextAlignment(.center)
            }
            VStack(spacing: DS.Space.s) {
                DSPrimaryButton("Adaugă primul lucru", systemImage: "plus", action: addFirst)
                DSSecondaryButton("Încarcă exemple", systemImage: "sparkles", action: loadExamples)
                    .disabled(isLoading)
                Text("Exemplele sunt marcate și le ștergi dintr-o atingere, din Setări.", comment: "Footnote under the load examples button.")
                    .dsFont(.footnote)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: 520)
        .frame(maxWidth: .infinity)
    }
}
