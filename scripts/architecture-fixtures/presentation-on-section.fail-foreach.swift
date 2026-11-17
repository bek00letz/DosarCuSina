// path: ios/DosarCuSina/Views/Settings/ExampleCategoryList.swift
// A dialog on a ForEach is one dialog for each row, all asked by the same switch.
struct ExampleCategoryList: View {
    let names: [String]
    @State private var isConfirming = false

    var body: some View {
        List {
            ForEach(names, id: \.self) { name in
                Button { isConfirming = true } label: { Text(verbatim: name) }
            }
            .confirmationDialog(Text("Ștergi categoria?"), isPresented: $isConfirming) {
                Button(role: .destructive) { } label: { Text("Șterge") }
            }
        }
    }
}
