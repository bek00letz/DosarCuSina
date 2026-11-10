// path: ios/DosarCuSina/Services/Capture/ExampleReader.swift
let next = RomanianFieldExtractor.labelledDate(profile.labels(for: .nextDoseDate), in: text, window: years)
let labels = profile.labels(for: .claimsPhone)
for index in text.lines(containing: labels) { _ = index }
let words = RomanianText.words(line)
static var labels: [(Label, [LabelWording])] { CaptureKindProfile.policyLabels.map { ($0.0, $0.1.map(LabelWording.words)) } }
let nonItems = CaptureLexicon.nonItemWords.map { RomanianText.Keyword($0) }
