// path: ios/DosarCuSina/Services/Subscriptions/ExampleMeter.swift
let index = RomanianNumber.double(reading.value)
let digits = NSDecimalNumber(decimal: reading.value).stringValue
let months = NSDecimalNumber(decimal: count).intValue
// NSDecimalNumber(decimal: value).doubleValue misses by a step: a comment never counts.
