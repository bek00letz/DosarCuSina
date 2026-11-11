// path: ios/DosarCuSina/Services/Example/ExampleRepairs.swift
let providers = Dictionary(try context.fetch(FetchDescriptor<Provider>()).map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
// Never Dictionary(uniqueKeysWithValues:): two copies of one record would stop the app.
try RecordsMeet.join(in: context)
