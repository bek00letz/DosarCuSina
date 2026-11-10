// path: ios/DosarCuSina/Services/Capture/ExampleReader.swift
// Not a Task.sleep(for: .milliseconds(300)): the wait is named for what it is.
func read(pause: Duration = Self.retryPause) async {
    if failed { try? await Task.sleep(for: pause) }
    try? await Task.sleep(for: Self.typingDebounce)
    try? await Task.sleep(for: DS.Motion.appOpening)
    readAgain()
}
