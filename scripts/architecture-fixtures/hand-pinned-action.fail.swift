// path: ios/DosarCuSina/Views/Example/ExampleSheet.swift
struct ExampleSheet: View {
    var body: some View {
        ScrollView {
            Text("Ce se mută")
        }
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: DS.Space.s) {
                DSPrimaryButton("Mută aici") { move() }
            }
            .padding(DS.Space.m)
            .background(.bar)
        }
    }
}
