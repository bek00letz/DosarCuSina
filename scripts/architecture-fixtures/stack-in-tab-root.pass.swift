// path: ios/DosarCuSina/Views/Example/ExampleRoot.swift
struct ExampleRoot: View {
    @State private var isAdding = false

    var body: some View {
        List {}
            .sheet(isPresented: $isAdding) {
                // A sheet has a stack of its own; that's fine.
                NavigationStack { AddSheet() }
            }
    }
}

struct AddSheet: View {
    var body: some View {
        NavigationStack { Form {} }
    }
}
