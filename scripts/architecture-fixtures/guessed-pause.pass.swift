// path: ios/DosarCuSina/Views/Example/ExampleScreen.swift
// Not a Task.sleep(for: .milliseconds(400)): the wait ends with what it waits for.
.task(id: query) {
    try? await Task.sleep(for: Self.typingDebounce)
    try? await Task.sleep(for: DS.Motion.appOpening)
    runSearch()
}
