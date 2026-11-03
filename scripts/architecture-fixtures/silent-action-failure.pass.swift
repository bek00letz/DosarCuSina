// path: ios/DosarCuSina/Views/Example/ExampleScreen.swift
do {
    try ObligationActions(context: context).undo(entry)
} catch {
    toast = DSToast(title: SaveFailure.message(for: error, formKept: false), actionTitle: nil, action: nil)
}
try? await Task.sleep(for: .milliseconds(250))
