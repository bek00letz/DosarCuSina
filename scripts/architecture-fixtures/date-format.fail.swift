// path: ios/DosarCuSina/Views/Example/ExampleRow.swift
Text(date, format: .dateTime.day().month(.wide).year())
let text = date.formatted(date: .abbreviated, time: .omitted)
let formatter = DateFormatter()
