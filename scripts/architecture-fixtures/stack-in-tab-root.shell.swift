// The shell the tab-root fixtures run beside: ExampleRoot is a tab root.
struct AppShell: View {
    var body: some View {
        TabView {
            Tab(value: AppTab.dosar) {
                NavigationStack(path: $router.dosarPath) {
                    ExampleRoot().shellDestinations()
                }
            }
        }
    }
}
