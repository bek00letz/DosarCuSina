// path: ios/DosarCuSina/Views/Example/ExampleForm.swift
// A comment that names DSPrimaryButton("Salvează") inside a ScrollView { } doesn't count.
struct ExampleForm: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DS.Space.xl) {
                Text("Un } în text nu închide nimic")
                DSTextField("Ce", text: $title)
                DSSecondaryButton("Adaugă o persoană") { add() }
            }
            .padding(DS.Space.m)
            .dsReadableWidth()
        }
        .dsPinnedAction {
            DSPrimaryButton("Salvează", systemImage: "checkmark") { save() }
        } secondary: {
            DSSecondaryButton("Renunță") { cancel() }
        } note: {
            if let errorMessage { DSNotice(.error, title: "Nu s-a salvat", message: LocalizedStringKey(errorMessage)) }
        }
    }
}

struct ExamplePocket: View {
    var body: some View {
        DSPocketCard(String(localized: "Istoric", comment: "Section pocket")) {
            Text("Nimic notat încă.")
        } footer: {
            DSSecondaryButton(verbatim: "Am fost la service", systemImage: "wrench.and.screwdriver") { add() }
        }
        DSPrimaryButton("După card, nu în el") { call() }
    }
}

struct ExampleHero: View {
    var body: some View {
        VStack {
            DSPrimaryButton("Sună", systemImage: "phone.fill") { call() }
        }
    }
}
