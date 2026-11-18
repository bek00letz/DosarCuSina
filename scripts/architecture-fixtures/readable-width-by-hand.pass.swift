// path: ios/DosarCuSina/Views/Example/ExamplePage.swift
// .frame(maxWidth: 720) in a comment doesn't count.
struct ExamplePage: View {
    var body: some View {
        ScrollView {
            content
                .frame(maxWidth: .infinity, alignment: .leading)
                .dsReadableWidth()
        }
    }
}

struct ExampleEmptyState: View {
    var body: some View {
        Text("Nimic încă").frame(maxWidth: 480)
    }
}
