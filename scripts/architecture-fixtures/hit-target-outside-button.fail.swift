// path: ios/DosarCuSina/Views/Example/ExampleNotice.swift
struct ExampleNotice: View {
    var body: some View {
        VStack(alignment: .leading) {
            Text("Factura nu s-a citit")
            Button("Alege altă poză") { choose() }
                .buttonStyle(.borderless)
                .frame(minHeight: DS.Control.minimumHitTarget)
        }
    }
}
