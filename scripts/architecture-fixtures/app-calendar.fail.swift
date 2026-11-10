// path: ios/DosarCuSinaWidgets/ExampleWidget.swift
let today = CalendarDay(Date(), calendar: Calendar.current)
let later = Calendar.autoupdatingCurrent.date(byAdding: .month, value: 1, to: Date())
func due(on day: CalendarDay, calendar: Calendar = .current) -> Date { day.startDate(in: calendar) }
let start = CalendarDay(year: 2026, month: 3, day: 31).startDate(in: .current)
let month = CalendarDay(year: 2026, month: 3, day: 31).adding(months: 1, calendar: .autoupdatingCurrent)
let gregorian = Calendar(identifier: .gregorian)
