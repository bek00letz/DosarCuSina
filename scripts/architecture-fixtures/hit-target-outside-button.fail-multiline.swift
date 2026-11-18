// path: ios/DosarCuSina/Views/Example/ExampleRow.swift
struct ExampleRow: View {
    var body: some View {
        Button(role: .destructive) {
            remove()
        } label: {
            Text("Scoate rândul")
        }
        .frame(minHeight: 44)
    }
}
