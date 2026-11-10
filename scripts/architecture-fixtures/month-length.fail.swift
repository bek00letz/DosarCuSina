// path: ios/DosarCuSina/Services/Obligations/ExampleCadence.swift
let lengths = [31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31]
let shortFirst = [0, 31, 29, 31, 30]
func isLeapYear(_ year: Int) -> Bool { (year % 4 == 0 && year % 100 != 0) || year % 400 == 0 }
func days(in month: Int) -> Int {
    switch month {
    case 4, 6, 9, 11: 30
    case 1, 3, 5, 7, 8, 10, 12: 31
    default: 28
    }
}
let length = calendar.range(of: .day, in: .month, for: date)?.count ?? 30
