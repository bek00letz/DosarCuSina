// path: ios/DosarCuSina/Services/Subscriptions/ExampleMatcher.swift
let code = RomanianText.compact(text)
let letters = ext.lowercased().filter { $0.isLetter || $0.isNumber }.prefix(5)
let count = text.filter { $0.isLetter || $0.isNumber }.count
