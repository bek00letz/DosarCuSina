// path: ios/DosarCuSina/Views/Upcoming/ExampleRecordScreen.swift
// A record's page that draws its own locked state and presents a sheet without saying which lock
// it lives behind: the sheet would stay up, open, after the lock comes back.
struct ExampleRecordPage: View {
    let record: Obligation
    @State private var isEditing = false
    private var vault: BiometricVaultManager { .shared }

    private var isLocked: Bool { record.asset.map { vault.isLocked($0, template: nil) } ?? false }

    var body: some View {
        ScrollView {
            if isLocked {
                Text("Secțiunea e protejată")
            } else {
                Button("Editează") { isEditing = true }
            }
        }
        .dsSheet(isPresented: $isEditing) {
            Text("Editează")
        }
    }
}
