// path: ios/DosarCuSina/Services/Capture/ExampleReader.swift
let next = RomanianFieldExtractor.labelledDate(profile.labels(for: .nextDoseDate), in: text, window: years)
let labels = profile.labels(for: .claimsPhone)
for index in text.lines(containing: labels) { _ = index }
