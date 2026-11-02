// path: ios/DosarCuSina/Views/Example/ExampleRow.swift
let label = String(localized: "\(days) zile", comment: "Plural variations in the catalog.")
let only = items.count == 1 ? items[0].id : nil
let title = pages.count > 1 ? Text("Pagina 1") : Text(verbatim: "")
