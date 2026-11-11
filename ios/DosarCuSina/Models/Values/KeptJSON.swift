import Foundation

/// The one rule for writing again a stored JSON value a newer build may have written: what this
/// build changed goes in, and everything else stays exactly as it was stored, keys and values this
/// build doesn't know included, at any depth. `KeptObject` (one object) and `KeptList` (a list's
/// entries) write through it.
///
/// It works on three forms of the same value: as stored; as read (what this build made of it,
/// written again); and as edited. Where the edit left a part as read, the stored part stays: a key
/// this build doesn't know, or a value it read as something else (an unknown consequence read as
/// the loudest). Where the edit changed a part, the edit wins. Two rules say when a part is still
/// the same thing:
/// - an object with a `type` is another value once its type is another: a rule that became
///   another kind of rule, or a field that became another type, keeps nothing of the old one;
/// - a list's entries pair by their `key` or `id`, else by being unchanged, else by their place
///   when the list kept its length; an entry the edit took out goes, with what it kept.
///
/// The same rule lays a form's edit over what is stored now (`ThreeWay`): read as the form opened
/// it, edited by the person, stored as it is when they save, perhaps changed since on another
/// device. So what the stored value has that the form never read stays (a key, or a list entry
/// with a `key` or `id`, added on the other device), and what the form left as it read it and the
/// stored value no longer has stays gone (removed on the other device).
extension JSONValue {
    /// What `edited` writes over `stored`, which this build read as `asRead`.
    static func laying(_ edited: JSONValue, over stored: JSONValue, readAs asRead: JSONValue) -> JSONValue {
        if edited == asRead { return stored }
        switch (stored, asRead, edited) {
        case (.object(let kept), .object(let read), .object(let made)):
            guard kept["type"] == made["type"] else { return edited }
            var merged: [String: JSONValue] = [:]
            for (key, value) in made {
                if let wasRead = read[key], let wasKept = kept[key] {
                    merged[key] = laying(value, over: wasKept, readAs: wasRead)
                } else if let wasRead = read[key], value == wasRead {
                    // Left as read, and no longer stored: it was taken out since, and stays out.
                    continue
                } else {
                    merged[key] = value
                }
            }
            // What this build didn't read, and the edit didn't set.
            for (key, value) in kept where read[key] == nil && made[key] == nil {
                merged[key] = value
            }
            return .object(merged)
        case (.array(let kept), .array(let read), .array(let made)):
            let origins = Self.storedIndices(of: read, in: kept)
            var taken = Set<Int>()
            var merged: [JSONValue] = []
            for (index, value) in made.enumerated() {
                guard let match = Self.readEntry(pairing: value, at: index, of: made.count, in: read, taken: taken) else {
                    merged.append(value)
                    continue
                }
                taken.insert(match)
                guard let origin = origins[match] else {
                    // An entry known by its key or id, left as read, and no longer stored: taken
                    // out since, it stays out.
                    if read[match].keptIdentity == nil || value != read[match] { merged.append(value) }
                    continue
                }
                merged.append(laying(value, over: kept[origin], readAs: read[match]))
            }
            // Entries stored with a key or id this build never read, and the edit didn't make:
            // added since, they stay.
            let known = Set((read + made).compactMap(\.keptIdentity))
            merged += kept.filter { entry in entry.keptIdentity.map { !known.contains($0) } ?? false }
            return .array(merged)
        default:
            return edited
        }
    }

    /// The same value as stored with every part this build doesn't read (a part `asRead` lacks, or
    /// holds otherwise) changed by `transform`: the rules every exit applies (secrets, card numbers)
    /// reach what a newer build wrote. A part `transform` gives nil for is left out; one this build
    /// also reads, otherwise, is then kept as this build reads it.
    func mappingKept(readAs asRead: JSONValue, _ transform: (JSONValue) -> JSONValue?) -> JSONValue {
        if self == asRead { return self }
        switch (self, asRead) {
        case (.object(let kept), .object(let read)) where kept["type"] == read["type"]:
            var result: [String: JSONValue] = [:]
            for (key, value) in kept {
                if let wasRead = read[key] {
                    result[key] = value.mappingKept(readAs: wasRead, transform)
                } else if let changed = transform(value) {
                    result[key] = changed
                }
            }
            return .object(result)
        case (.array(let kept), .array(let read)):
            var readFor: [Int: Int] = [:]
            for (match, origin) in Self.storedIndices(of: read, in: kept).enumerated() {
                if let origin, readFor[origin] == nil { readFor[origin] = match }
            }
            var result: [JSONValue] = []
            for (index, value) in kept.enumerated() {
                if let match = readFor[index] {
                    result.append(value.mappingKept(readAs: read[match], transform))
                } else if let changed = transform(value) {
                    result.append(changed)
                }
            }
            return .array(result)
        default:
            return transform(self) ?? asRead
        }
    }

    /// The key or id an entry of a stored list is known by, when it has one.
    var keptIdentity: String? {
        (self["key"]?.string ?? self["id"]?.string)?.lowercased()
    }

    /// The JSON a value writes, as plain JSON (no dates in these values, so no strategy to agree on).
    init?<Value: Encodable>(encoding value: Value) {
        guard let data = try? JSONEncoder().encode(value),
              let json = try? JSONDecoder().decode(JSONValue.self, from: data) else { return nil }
        self = json
    }

    /// This JSON read as `Value`, or nil when this build can't.
    func decoded<Value: Decodable>(as type: Value.Type) -> Value? {
        guard let data = try? JSONEncoder().encode(self) else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }

    // MARK: Pairing a list's entries

    /// For each entry as read, the place of the stored entry it was read from: the one with the
    /// same key or id, else the same place when nothing was left out in reading.
    private static func storedIndices(of read: [JSONValue], in kept: [JSONValue]) -> [Int?] {
        read.enumerated().map { index, entry in
            if let id = entry.keptIdentity { return kept.firstIndex { $0.keptIdentity == id } }
            return kept.count == read.count ? index : nil
        }
    }

    /// The entry as read that `value` (at `index` of `count` edited entries) is: the same key or
    /// id, else one left as it was, else the one in its place when the list kept its length.
    private static func readEntry(pairing value: JSONValue, at index: Int, of count: Int, in read: [JSONValue], taken: Set<Int>) -> Int? {
        let free = read.indices.filter { !taken.contains($0) }
        if let id = value.keptIdentity {
            return free.first { read[$0].keptIdentity == id }
        }
        if let same = free.first(where: { read[$0] == value }) { return same }
        if count == read.count, free.contains(index), read[index].keptIdentity == nil { return index }
        return nil
    }
}
