// path: ios/DosarCuSina/Views/Example/ExampleSheet.swift
ToolbarItem(placement: .cancellationAction) { DSCancelButton() }
DSSecondaryButton("Anulează vizita", systemImage: "arrow.uturn.backward", role: .destructive, action: onUndo)
// "Anulează" in a comment never counts.
