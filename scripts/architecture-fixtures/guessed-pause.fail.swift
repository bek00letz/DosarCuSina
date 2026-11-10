// path: ios/DosarCuSina/Services/Capture/ExampleReader.swift
func read() async {
    if failed { try? await Task.sleep(for: .milliseconds(300)) }
    readAgain()
}
