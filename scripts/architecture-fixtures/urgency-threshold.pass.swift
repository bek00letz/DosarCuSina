// path: ios/DosarCuSina/Views/Example/ExampleBadge.swift
let urgency = obligation.urgency()
let badge = DSStatusBadge(urgency: urgency, daysRemaining: obligation.daysRemaining())
let tomorrow = days == 1
