// path: ios/DosarCuSina/Views/Settings/ExampleSettingsSection.swift
// A sheet on the Section reaches both buttons, the header and the footer: it is presented four
// times, and the copies that can't present close Settings with it.
struct ExampleSettingsSection: View {
    @State private var isChoosing = false
    @State private var error: UserFacingError?

    var body: some View {
        Section {
            Button { isChoosing = true } label: { Text("Fă o copie") }
            Button { isChoosing = true } label: { Text("Pune înapoi o copie") }
        } header: {
            Text("Copie de siguranță")
        } footer: {
            Text("Copia e un singur fișier.")
        }
        .onAppear { }
        .alert(
            Text("Copia are parolă"),
            isPresented: $isChoosing
        ) {
            Button("Deschide") { }
        }
        .sheet(isPresented: $isChoosing) {
            Text("Parolă")
        }
        .userErrorAlert($error)
    }
}
