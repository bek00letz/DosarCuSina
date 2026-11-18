// path: ios/DosarCuSina/Views/Example/ExamplePage.swift
struct ExamplePage: View {
    var body: some View {
        ScrollView {
            content
                .frame(maxWidth: 720)
                .frame(maxWidth: .infinity)
                .dsReadableWidth()
        }
    }
}
