# Legacy tests

The first test harness (a hand-rolled runner compiled with `swiftc`) and its
suites, kept as a way back. They test code that now lives in `ios/Legacy/`
and are not run. The cadence and utility-parser suites were ported to the
`DosarCuSinaTests` target; everything else there replaces these.

`ios/RomanianUtilityParserSuite.swift` is the Swift Testing suite of the first bill
reader, moved here with the reader. Its fixtures now run against the label tables
that replaced it, in `ios/DosarCuSinaTests/Capture/BillReaderTests.swift`.
