// path: ios/DosarCuSina/Services/Example/ExampleProtection.swift
try FileManager.default.setAttributes([.protectionKey: FileProtectionType.complete], ofItemAtPath: item.path())
