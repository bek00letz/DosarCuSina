// path: ios/DosarCuSina/Views/Example/ExampleRow.swift
let label = String(localized: "\(days) zile", comment: "Plural variations in the catalog.")
let only = items.count == 1 ? items[0].id : nil
let title = pages.count > 1 ? Text("Pagina 1") : Text(verbatim: "")
let pages = pageCount > 1 ? String(localized: "\(pageCount) pagini", comment: "Only for two or more.") : nil
let rest = findings.count > 1
    ? String(localized: "Mai sunt și alte lucruri în listă.", comment: "Only for several.")
    : ""
let padding = boxes.count >= 2 ? 0.8 : 1.8
