import Foundation

// Reads JSON-encoded keys, one per line, and prints them back in the order Xcode writes a
// String Catalog's entries: Finder's order (localizedStandardCompare) in English.
let english = Locale(identifier: "en_US")
var keys: [String] = []
while let line = readLine(strippingNewline: true) {
    keys.append(try JSONDecoder().decode(String.self, from: Data(line.utf8)))
}
let sorted = keys.sorted {
    $0.compare($1, options: [.caseInsensitive, .numeric, .widthInsensitive, .forcedOrdering], range: nil, locale: english) == .orderedAscending
}
let encoder = JSONEncoder()
for key in sorted {
    print(String(decoding: try encoder.encode(key), as: UTF8.self))
}
