// path: ios/DosarCuSina/Views/Capture/Filing/ExampleFiler.swift
func askAboutTheMeter(_ last: MeasurementLog, value: Double) throws {
    if value < last.value {
        throw LowerReadingQuestion(previous: last.value, previousDate: last.recordedAt, value: value, unit: last.measurementUnit)
    }
}
