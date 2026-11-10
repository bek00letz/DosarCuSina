// path: ios/DosarCuSinaWidgets/ExampleWidget.swift
// Calendar.current would count in the phone's calendar.
let today = CalendarDay(Date(), calendar: Calendar.dosar)
func due(on day: CalendarDay, calendar: Calendar = .dosar) -> Date { day.startDate(in: calendar) }
let utc = Calendar.dosar(in: .gmt)
let zone = TimeZone.current
let center = UNUserNotificationCenter.current()
let currentCalendar = preferences.currentCalendarName
