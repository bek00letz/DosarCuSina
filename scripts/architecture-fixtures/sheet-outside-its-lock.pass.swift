// path: ios/DosarCuSina/Views/Upcoming/ExampleRecordScreen.swift
// A page that draws its own locked state declares the lock its sheets live behind; a section's
// screen drawn through LockGate puts its sheets behind the gate; a list that only reads a lock
// for its rows and presents nothing needs neither.
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
        .screenLock(record.asset.map { .section($0.id) } ?? .open)
    }
}

struct ExampleSectionPage: View {
    let section: Asset
    @State private var isEditing = false

    var body: some View {
        LockGate(asset: section) {
            Button("Editează") { isEditing = true }
                .dsSheet(isPresented: $isEditing) { Text("Editează") }
        }
    }
}

struct ExampleRows: View {
    let rows: [ObligationSnapshot]
    private var vault: BiometricVaultManager { .shared }

    var body: some View {
        ForEach(rows) { row in
            Text(verbatim: vault.isLocked(sectionIsSensitive: row.isSensitive) ? "O scadență protejată" : row.title)
        }
    }
}
