// path: ios/DosarCuSina/Services/Example/ExampleActions.swift
/// Saves once; never call context.save() here.
func rename(_ asset: Asset, to name: String) throws {
    asset.name = name
    try UnitOfWork.save(context) // not context.save()
    request.save()
}
