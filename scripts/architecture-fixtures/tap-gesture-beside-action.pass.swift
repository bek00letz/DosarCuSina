// path: ios/DosarCuSina/Views/Example/ExampleList.swift
NavigationLink(value: route) { Text("Rând") }
.onChange(of: path.count) { _, _ in remember() }
