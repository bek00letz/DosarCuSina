// path: ios/DosarCuSina/Services/Obligations/CycleReminders.swift
// Never extension DosarSchemaV14.Obligation: the current model is Obligation.
extension Obligation {
    var cycleReminders: ReminderProfile { reminders }
}
let schema = Schema(versionedSchema: CurrentSchema.self)
let asset = context.first(#Predicate<Asset> { $0.id == id })
let models = CurrentSchema.models.count
