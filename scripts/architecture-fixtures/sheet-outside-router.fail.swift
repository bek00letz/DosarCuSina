// path: ios/DosarCuSina/Views/Example/ExampleScreen.swift
struct ExampleScreen: View {
    @State private var isEditing = false
    var body: some View {
        Text("Exemplu")
            .sheet(isPresented: $isEditing) { ExampleEditSheet() }
    }
}
