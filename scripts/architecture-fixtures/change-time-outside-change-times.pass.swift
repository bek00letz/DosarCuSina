// path: ios/DosarCuSina/Models/Schema/ExampleModel.swift
public var updatedAt: Date = Date.distantPast
init() {
    self.updatedAt = Date()
}
let newer = record.updatedAt > other.updatedAt
let same = record.updatedAt == stored.updatedAt
// A comment that says obligation.updatedAt = now() never counts.
try UnitOfWork.perform(in: context, origin: .app, now: now()) { obligation.snoozedUntil = nil }
