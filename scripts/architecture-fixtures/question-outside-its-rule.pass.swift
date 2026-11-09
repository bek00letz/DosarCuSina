// path: ios/DosarCuSina/Views/Capture/Filing/ExampleFiler.swift
@State private var readingQuestion: LowerReadingQuestion?

func file(_ reading: PlannedReading, answer: LowerReadingAnswer?) throws {
    // Asked first, then the unit opens: LowerReadingQuestion(…) is never made here.
    try HouseholdMutations.askAboutReading(reading, answer: answer)
    do {
        try UnitOfWork.perform(in: context) { try record(reading, answer: answer) }
    } catch let question as LowerReadingQuestion {
        readingQuestion = question
    }
}
