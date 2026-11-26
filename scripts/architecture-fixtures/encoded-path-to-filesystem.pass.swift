// path: ios/Shared/ExampleFolder.swift
let names = try FileManager.default.contentsOfDirectory(atPath: folder.path(percentEncoded: false))
let image = UIImage(contentsOfFile: url.path(percentEncoded: false))
try FileManager.default.setAttributes([.protectionKey: FileProtectionType.complete], ofItemAtPath: item.path(percentEncoded: false))
