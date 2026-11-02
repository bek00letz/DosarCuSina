import Foundation
import Testing
@testable import DosarCuSina

@Suite("Build info")
struct BuildInfoTests {

    @Test func showsVersionBuildAndCommit() {
        let info = BuildInfo(info: ["CFBundleShortVersionString": "1.0", "CFBundleVersion": "180", "DosarCommit": "7754ec8"])
        #expect(info.summary == "1.0 (build 180) · 7754ec8")
    }

    @Test func aBuildMadeOutsideGitShowsNoCommit() {
        let info = BuildInfo(info: ["CFBundleShortVersionString": "1.0", "CFBundleVersion": "1"])
        #expect(info.summary == "1.0 (build 1)")
    }
}
