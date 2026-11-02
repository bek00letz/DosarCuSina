import Foundation

/// How a personal document is named: "<document> – <Surname Given names>", the
/// way the household says it ("Carte de identitate – Manole Corina"). Capture,
/// "Scriu eu" and moving a document to another person all name it here.
public enum DocumentNaming {
    /// The en dash with a space on each side, between the document and its holder.
    public static let separator = " – "

    /// "Carte de identitate – Manole Corina", or just the document when there is no holder.
    public static func name(document: String, holder: String?) -> String {
        let document = document.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let holder = holder?.trimmingCharacters(in: .whitespacesAndNewlines), !holder.isEmpty else { return document }
        return document + separator + holder
    }

    /// The name with the holder swapped, when the name ends with the old holder's
    /// name (ignoring case and diacritics). Nil when the name isn't the holder's,
    /// so a name the person chose ("Buletinul vechi") is never rewritten.
    public static func renamed(_ name: String, from oldHolder: String?, to newHolder: String) -> String? {
        let newHolder = newHolder.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let oldHolder = oldHolder?.trimmingCharacters(in: .whitespacesAndNewlines), !oldHolder.isEmpty, !newHolder.isEmpty,
              let range = name.range(of: separator, options: .backwards) else { return nil }
        let document = String(name[..<range.lowerBound])
        let holder = String(name[range.upperBound...])
        guard !document.trimmingCharacters(in: .whitespaces).isEmpty,
              ChoiceOption.fold(holder) == ChoiceOption.fold(oldHolder),
              ChoiceOption.fold(holder) != ChoiceOption.fold(newHolder) else { return nil }
        return self.name(document: document, holder: newHolder)
    }
}
