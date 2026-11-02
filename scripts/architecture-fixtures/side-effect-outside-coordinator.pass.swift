// path: ios/DosarCuSina/Services/SideEffects/ExampleCoordinator.swift
WidgetCenter.shared.reloadAllTimelines()
try await center.add(UNNotificationRequest(identifier: id, content: content, trigger: trigger))
