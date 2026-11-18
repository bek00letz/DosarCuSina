// path: ios/DosarCuSina/Views/Example/ExampleNotice.swift
// A comment about Button("x").frame(minHeight: 44) doesn't count.
struct ExampleNotice: View {
    var body: some View {
        VStack(alignment: .leading) {
            Text("Factura nu s-a citit")
            DSLinkButton("Alege altă poză") { choose() }
            Button(action: retry) {
                Text("Încearcă din nou")
                    .frame(minHeight: DS.Control.minimumHitTarget)
                    .contentShape(.rect)
            }
            .buttonStyle(.borderless)
            HStack {
                Text("Ora amintirilor")
            }
            .frame(minHeight: 44)
        }
        .frame(minHeight: 44)
    }
}
