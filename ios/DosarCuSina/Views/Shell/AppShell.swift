import SwiftUI
import SwiftData

/// The app once the store is open: four labelled tabs, every route through one
/// router, onboarding once, and the app lock over everything when it is on, in
/// a window of its own above every sheet (`LockWindowHost`). Links and opened
/// files wait until the app is unlocked. Coming back with something new shared from
/// another app opens De verificat once (`InboxLanding`). A toast that must outlive its
/// screen (a deleted section's, the review's after "Salvează") is shown here, above the
/// tab bar of whichever tab is open (`DSToastCenter`, reached with `\.announce`).
///
/// Each tab is wrapped in a `NavigationStack` here, with every `AppRoute`
/// registered as a destination, so any screen can push with
/// `NavigationLink(value: AppRoute…)`. Tab roots must not add a stack of their own.
struct AppShell: View {
    @Environment(AppNavigator.self) private var navigator
    @Environment(AppPreferences.self) private var preferences
    @Environment(BiometricVaultManager.self) private var vault
    @Environment(\.scenePhase) private var scenePhase

    @State private var router = ShellRouter()
    @State private var search = SearchQuery()
    @State private var toasts = DSToastCenter()
    /// How far each tab's content keeps from the bottom edge (the tab bar), and the shell's own.
    @State private var tabInsets: [AppTab: CGFloat] = [:]
    @State private var shellInset: CGFloat = 0
    @Query(filter: #Predicate<CategoryTemplate> { $0.isSensitive }) private var lockedCategories: [CategoryTemplate]

    private var cover: LockCover? {
        LockCover.decide(
            appLockEnabled: preferences.appLockEnabled,
            anySectionLocked: !lockedCategories.isEmpty,
            isSessionUnlocked: vault.isSessionUnlocked,
            isActive: scenePhase == .active,
            isAuthenticating: vault.isAuthenticating
        )
    }

    var body: some View {
        TabView(selection: Binding(get: { router.tab }, set: { router.select($0) })) {
            Tab(value: AppTab.dosar) {
                NavigationStack(path: $router.dosarPath) {
                    DosarHomeView().shellDestinations()
                }
                .measuringToastInset { tabInsets[.dosar] = $0 }
            } label: {
                Label { Text("Dosar", comment: "Tab: the binder.") } icon: { Image(systemName: "square.grid.2x2.fill") }
            }
            Tab(value: AppTab.upcoming) {
                NavigationStack(path: $router.upcomingPath) {
                    UpcomingRoot().shellDestinations()
                }
                .measuringToastInset { tabInsets[.upcoming] = $0 }
            } label: {
                Label { Text("Urmează", comment: "Tab: what comes up next.") } icon: { Image(systemName: "clock.fill") }
            }
            Tab(value: AppTab.add) {
                NavigationStack(path: $router.addPath) {
                    AddRoot().shellDestinations()
                }
                .measuringToastInset { tabInsets[.add] = $0 }
            } label: {
                Label { Text("Adaugă", comment: "Tab: scan or add something.") } icon: { Image(systemName: "plus.circle.fill") }
            }
            .badge(IntakeInbox.shared.count)
            Tab(value: AppTab.search, role: .search) {
                NavigationStack(path: $router.searchPath) {
                    SearchScreen().shellDestinations()
                }
                .measuringToastInset { tabInsets[.search] = $0 }
                // The search field belongs to this tab alone; iOS draws it in the tab bar.
                .shellSearch(search)
            } label: {
                Label { Text("Caută", comment: "Tab: search.") } icon: { Image(systemName: "magnifyingglass") }
            }
        }
        .measuringToastInset { shellInset = $0 }
        // Above the tab bar, wherever the person is; under the sheets, which have their own.
        .dsToastHost(toasts, bottomInset: max(0, (tabInsets[router.tab] ?? shellInset) - shellInset))
        .environment(router)
        .intakeHandoff()
        .sheet(item: $router.sheet) { sheet in
            sheetContent(sheet)
                .environment(router)
        }
        .fullScreenCover(isPresented: Binding(get: { !preferences.hasCompletedOnboarding && !vault.isAppLocked }, set: { _ in })) {
            OnboardingFlow {
                preferences.hasCompletedOnboarding = true
            }
            .environment(router)
        }
        // The shell's sheets announce through it too, once they close.
        .environment(\.dsToastCenter, toasts)
        .dataRepairPrompt(isAllowed: router.sheet == nil && preferences.hasCompletedOnboarding && !vault.isAppLocked) {
            router.open(.settings(.repairs))
        }
        .background(LockWindowHost(cover: cover, scenePhase: scenePhase, vault: vault))
        .task { consumeRoute() }
        .onChange(of: navigator.pendingRoute) { _, _ in consumeRoute() }
        .onChange(of: vault.isAppLocked) { _, _ in consumeRoute() }
        // Opening the app with something new from another app lands on De verificat, once.
        .task(id: scenePhase) {
            guard scenePhase == .active else { return }
            await InboxLanding.shared.didBecomeActive(
                waiting: {
                    IntakeInbox.shared.refresh()
                    return IntakeInbox.shared.waiting
                },
                navigator: navigator,
                isBusy: { !preferences.hasCompletedOnboarding || router.sheet != nil || InboxLanding.isShowingSomethingOverTheTabs() }
            )
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .background { InboxLanding.shared.didEnterBackground(navigator: navigator) }
        }
    }

    @ViewBuilder
    private func sheetContent(_ sheet: ShellSheet) -> some View {
        switch sheet {
        case .settings(let section):
            SettingsScreen(initialSection: section)
        case .addVisit(let assetID):
            AddVisitFlow(assetID: assetID)
        case .addPersonalDocument(let holderID):
            AddPersonalDocumentFlow(holderID: holderID) { documentID in
                // Land on the document's own page, over the person it was added for.
                router.push(.asset(documentID))
            }
        case .addSection(let request):
            AddSectionFlow(request: request) { asset in
                // A new top-level section opens right away; a child shows up in its parent's pocket.
                if request.parentID == nil, asset.parent == nil {
                    router.tab = .dosar
                    router.dosarPath.append(AppRoute.asset(asset.id))
                }
            }
        }
    }

    private func consumeRoute() {
        guard let route = navigator.consume() else { return }
        router.open(route)
    }
}

private extension View {
    /// Reports how far this view's content keeps from its bottom edge (the tab bar, the home
    /// indicator), so the shell's toast sits where a screen's own would.
    func measuringToastInset(_ report: @escaping (CGFloat) -> Void) -> some View {
        onGeometryChange(for: CGFloat.self) { $0.safeAreaInsets.bottom } action: { report($0) }
    }
}

extension View {
    /// Registers every screen a tab can push: app routes and full pocket lists.
    func shellDestinations() -> some View {
        navigationDestination(for: AppRoute.self) { RouteScreen(route: $0) }
            .navigationDestination(for: SectionListRoute.self) { SectionListScreen(route: $0) }
    }
}

/// The screen for a pushed route.
struct RouteScreen: View {
    let route: AppRoute
    @Environment(ShellRouter.self) private var router

    var body: some View {
        switch route {
        case .asset(let id): SectionScreen(assetID: id)
        case .obligation(let id): ObligationScreen(obligationID: id)
        case .historyEntry(let id): HistoryEntryScreen(entryID: id)
        case .provider(let id): ProviderScreen(providerID: id)
        case .document(let id): DocumentScreen(attachmentID: id)
        case .agenda: AgendaScreen()
        case .category(let key): CategoryScreen(templateKey: key)
        case .addVisit(let id): AddVisitFlow(assetID: id)
        case .readiness(let readiness): ReadinessScreen(route: readiness)
        case .home, .upcoming, .search, .intake, .settings:
            // Tabs and sheets aren't pushed; hand them to the router instead.
            Color.clear.task { router.open(route) }
        }
    }
}
