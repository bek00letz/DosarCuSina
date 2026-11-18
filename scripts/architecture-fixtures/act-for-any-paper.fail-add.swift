// path: ios/DosarCuSina/Views/Add/ExampleAdd.swift
struct ExampleAdd: View {
    var body: some View {
        DSActionCard("Fotografiază un act", subtitle: "O poză cu actul.", systemImage: "camera.fill") { open() }
    }
}
