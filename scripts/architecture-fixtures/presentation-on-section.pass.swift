// path: ios/DosarCuSina/Views/Settings/ExampleSettingsSection.swift
// Each presentation hangs on one view that stays while it is up: the row that opens it, or the
// section's header. What isn't a presentation may sit on the Section, and a List or a
// NavigationStack holds its own sheets.
struct ExampleSettingsSection: View {
    @State private var isChoosing = false
    @State private var isEditing: String?
    @State private var error: UserFacingError?
    let names: [String]

    var body: some View {
        List {
            Section {
                Button { isChoosing = true } label: { Text("Fă o copie") }
                    .dsSheet(isPresented: $isChoosing) {
                        Text("Parolă")
                    }
                ForEach(names, id: \.self) { name in
                    Button { isEditing = name } label: { Text(verbatim: name) }
                }
            } header: {
                Text("Copie de siguranță")
                    .userErrorAlert($error)
                    .dsSheet(item: $isEditing) { name in Text(verbatim: name) }
            } footer: {
                Text("Copia e un singur fișier.")
            }
            .listSectionSpacing(.compact)
        }
        .alert(Text("Copia are parolă"), isPresented: $isChoosing) {
            Button("Deschide") { }
        }
    }
}
