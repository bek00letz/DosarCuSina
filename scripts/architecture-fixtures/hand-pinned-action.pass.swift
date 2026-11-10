// path: ios/DosarCuSina/Views/Example/ExampleSheet.swift
// .safeAreaInset(edge: .bottom) { DSBottomBar { DSPrimaryButton("Mută aici") } } in a comment doesn't count.
struct ExampleSheet: View {
    var body: some View {
        ScrollView {
            Text("Ce se mută")
        }
        .dsPinnedAction {
            DSPrimaryButton("Mută aici") { move() }
        }
    }
}

struct ExampleViewer: View {
    var body: some View {
        TabView {}
            .safeAreaInset(edge: .bottom) {
                if hasActions { pageActions }
            }
    }
}
