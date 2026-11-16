// path: ios/DosarCuSina/Services/Obligations/CycleReminders.swift
extension DosarSchemaV14.Obligation {
    var cycleReminders: ReminderProfile { reminders }
}
extension DosarSchemaV15 {
    static var everyModel: Int { models.count }
}
let schema = Schema(versionedSchema: DosarSchemaV15.self)
let asset = context.first(#Predicate<DosarSchemaV15.Asset> { $0.id == id })
