// path: ios/Shared/ExampleNotice.swift
static func body(_ count: Int) -> String {
    count > 1
        ? String(localized: "Deschide aplicația ca să le pui la locul lor.", comment: "Several documents.")
        : String(localized: "Deschide aplicația ca să-l pui la locul lui.", comment: "One document.")
}
