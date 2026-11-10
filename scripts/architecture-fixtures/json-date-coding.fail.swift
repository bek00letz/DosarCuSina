// path: ios/DosarCuSina/Services/Example/ExampleStore.swift
let encoder = JSONEncoder()
encoder.dateEncodingStrategy = .iso8601
let decoder = JSONDecoder()
decoder.dateDecodingStrategy = .secondsSince1970
