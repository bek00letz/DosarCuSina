import Foundation

/// Which build this is, so a person can tell whether their phone has the latest
/// code. Stamped into each target's Info.plist at build time by
/// `scripts/stamp-build-info.sh`: the build number (commits so far, so it only
/// goes up) and the commit it was built from.
public struct BuildInfo: Equatable, Sendable {
    public let version: String
    public let build: String
    public let commit: String?

    public init(info: [String: Any]) {
        version = info["CFBundleShortVersionString"] as? String ?? "1.0"
        build = info["CFBundleVersion"] as? String ?? "1"
        commit = (info["DosarCommit"] as? String).flatMap { $0.isEmpty ? nil : $0 }
    }

    public static let current = BuildInfo(info: Bundle.main.infoDictionary ?? [:])

    /// Whether the app is hosting a test run (xcodebuild test sets this): the tests' own
    /// containers are in memory, and the host app's binder reaches no iCloud.
    public static var isTestHost: Bool {
        ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
    }

    /// "1.0 (build 180) · 7754ec8", or without the commit for builds made outside git.
    public var summary: String {
        let versionAndBuild = String(localized: "\(version) (build \(build))", comment: "About: version and build number, e.g. '1.0 (build 180)'.")
        return [versionAndBuild, commit].compactMap { $0 }.joined(separator: " · ")
    }
}
