// path: ios/DosarCuSina/Views/Example/ExampleScreen.swift
do {
    try ObligationActions(context: context).undo(entry)
} catch {
    toast = DSToast(title: SaveFailure.message(for: error, formKept: false), actionTitle: nil, action: nil)
}
try? await Task.sleep(for: Self.toastDwell)
let template = try? TemplateStore(context: context).template(forKey: asset.templateKey)
let templates = (try? TemplateStore(context: context).templatesByKey()) ?? [:]
PersistenceLog.attempt("Refreshing the repair list") { try repairs.refresh(in: context, announce: true) }
