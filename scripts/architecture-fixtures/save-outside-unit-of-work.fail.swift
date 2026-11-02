// path: ios/DosarCuSina/Services/Example/ExampleActions.swift
func rename(_ asset: Asset, to name: String) throws {
    asset.name = name
    try context.save()
}
