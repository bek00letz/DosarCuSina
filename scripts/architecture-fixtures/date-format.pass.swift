// path: ios/Shared/DosarFormat.swift
static func day(_ date: Date, locale: Locale = .dosarDefault) -> String {
    date.formatted(.dateTime.day().month(.abbreviated).year().locale(locale))
}
