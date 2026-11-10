// path: ios/DosarCuSina/Services/Subscriptions/ExampleMatcher.swift
let code = text.uppercased().filter { $0.isLetter || $0.isNumber }
let plate = raw.uppercased().filter({ $0.isLetter || $0.isNumber })
