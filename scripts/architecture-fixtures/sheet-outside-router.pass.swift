// path: ios/DosarCuSina/Views/Example/ExampleScreen.swift
struct ExampleScreen: View {
    @State private var isEditing = false
    @State private var page: ExamplePage?
    var body: some View {
        Text("Exemplu")
            .dsSheet(isPresented: $isEditing) { ExampleEditSheet() }
            .dsFullScreenCover(item: $page) { ExamplePageView(page: $0) }
            // A comment that names .sheet( is not code.
    }
}
