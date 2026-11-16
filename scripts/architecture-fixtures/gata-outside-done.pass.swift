// path: ios/DosarCuSina/Views/Example/ExampleViewer.swift
ToolbarItem(placement: .confirmationAction) { Button { close() } label: { Text("Închide", comment: "Closes the viewer.") } }
DSPrimaryButton(shape.actionTitle, systemImage: "checkmark") { start() }
let reply = String(localized: "Gata, am bifat-o.")
