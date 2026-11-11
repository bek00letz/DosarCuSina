import Foundation

/// What a form's save writes: only what the person changed in it, laid over what is stored now.
///
/// A form reads a record when it opens and saves a while later. Meanwhile another device may have
/// changed the same record (iCloud writes it under the store), or another screen on this one. A
/// form that wrote back everything it holds would put back the values it read, undoing those
/// changes. So every edit carries what it started from, and saving compares three forms of each
/// value: as the form started (`base`), as the person left it (`edited`) and as stored now
/// (`stored`). A part the person didn't change keeps what is stored now; a part they changed is
/// theirs, even over a newer change to the same part, since the later save is the person's
/// choice. A value stored as JSON (a section's values, the rows under Date importante, a
/// deadline's reminders) is laid part by part, by the rule stored JSON is written by
/// (`JSONValue.laying`): field by field, a row by its id.
enum ThreeWay {
    /// One value, whole: the edit when the person changed it, else what is stored now.
    static func value<Value: Equatable>(_ edited: Value, over stored: Value, startedFrom base: Value) -> Value {
        edited == base ? stored : edited
    }

    /// A value stored as JSON, part by part: each part the person changed, over what is stored now.
    static func laying<Value: Codable & Equatable>(_ edited: Value, over stored: Value, startedFrom base: Value) -> Value {
        if edited == base { return stored }
        if stored == base { return edited }
        guard let made = JSONValue(encoding: edited), let kept = JSONValue(encoding: stored), let read = JSONValue(encoding: base),
              let merged = JSONValue.laying(made, over: kept, readAs: read).decoded(as: Value.self) else { return edited }
        return merged
    }
}
