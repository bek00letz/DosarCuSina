// path: ios/DosarCuSina/Views/Example/ExampleRow.swift
Button("Șterge", action: delete).frame(minWidth: 44, minHeight: 44)
Button(action: close) { Image(systemName: "xmark") }.frame(width: 44, height: 44)
Card().frame(maxWidth: .infinity, minHeight: 168)
Rectangle().fill(DS.Palette.separator).frame(height: 1)
