// path: ios/DosarCuSina/Views/Section/ExamplePocket.swift
// A pocket's card is part of a scrolling page wherever it is written: a primary button in it is
// at the end of content, though no ScrollView is in this file.
struct ExamplePocket: View {
    var body: some View {
        DSPocketCard(String(localized: "Istoric", comment: "Section pocket")) {
            Text("Nimic notat încă.")
        } footer: {
            DSPrimaryButton(verbatim: "Am fost la service", systemImage: "wrench.and.screwdriver.fill") { add() }
        }
    }
}
