import Foundation

/// A question a step asks the person before it can be kept: a counter lower than before
/// (`LowerReadingQuestion`), something of theirs going into an example
/// (`ExampleSectionQuestion`). Nothing is saved: the screen asks, and saves again with the
/// answer.
///
/// A step asks its questions before its unit of work writes anything. Each question is
/// worked out by its one rule without changing anything (`HouseholdMutations.askAboutReading`
/// with the step's `PlannedReading`, `ExampleOwnership.requireReal`), so the action, and any
/// flow that wraps it in a larger unit (`CaptureFiler`), asks first and opens its unit only
/// once every answer is in. A unit taken back after it wrote leaves the records it touched
/// unreadable to SwiftData until they are fetched again, and a screen drawing that section
/// next would stop the app. `UnitOfWork` stops a debug build where a question comes too late.
public protocol StepQuestion: LocalizedError {}
