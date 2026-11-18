// path: ios/DosarCuSina/Views/Example/ExampleForm.swift
// A comment naming ScrollView { } doesn't count.
struct ExampleForm: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DS.Space.xl) {
                DSTextField("Ce", text: $title)
                ScrollView(.horizontal) {
                    HStack { Text("Un chip") }
                }
            }
            .padding(DS.Space.m)
            .dsReadableWidth()
        }
    }
}

struct ExampleBinder: View {
    var body: some View {
        ScrollView { grid.dsReadableWidth(.grid) }
    }
}
