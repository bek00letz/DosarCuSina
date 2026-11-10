// path: ios/DosarCuSina/Views/Example/ExampleForm.swift
struct ExampleForm: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DS.Space.xl) {
                DSTextField("Ce", text: $title)
                DSPrimaryButton("Salvează", systemImage: "checkmark") { save() }
            }
            .padding(DS.Space.m)
        }
    }
}
