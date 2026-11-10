// path: ios/DosarCuSina/Services/Obligations/ExampleCadence.swift
// A table such as [31, 28, 31, …] or a leap-year rule would be a second calendar.
let next = due.adding(months: 1, dayOfMonth: 31)
let length = due.daysInMonth()
let column = index % 4 == 0
let weekday = calendar.range(of: .weekday, in: .weekOfYear, for: date)
let row = items.count % 100
let year = CalendarDay(Date()).year
