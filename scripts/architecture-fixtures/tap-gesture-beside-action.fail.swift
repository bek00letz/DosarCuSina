// path: ios/DosarCuSina/Views/Example/ExampleList.swift
NavigationLink(value: route) { Text("Rând") }
    .simultaneousGesture(TapGesture().onEnded { remember() })
