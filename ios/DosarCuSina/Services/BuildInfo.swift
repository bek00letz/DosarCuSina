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

    /// Whether the app was launched for the App Store's screenshots (`ScreenshotStage`), which
    /// only a development build can be: the binder is a store of its own that never syncs, so a
    /// screenshot run never touches the binder of the phone it runs on.
    public static var isScreenshotRun: Bool { screenshotStoreName != nil }

    /// Whether the app was launched only to write the data layout to iCloud's development
    /// environment (`CloudKitSchemaSetup`), which only a development build can be: the binder
    /// then opens on the phone alone, so its own mirroring never runs beside that step's.
    public static var isCloudKitSchemaRun: Bool {
        #if DEBUG
        CloudKitSchemaSetup.isRequested
        #else
        false
        #endif
    }

    /// The screenshots' own store, one per run of them (`ScreenshotStage.storeName`), so every
    /// run starts from a household made that day; nil in every other launch, and in a release build.
    public static var screenshotStoreName: String? {
        #if DEBUG
        ScreenshotStage.storeName
        #else
        nil
        #endif
    }

    /// "1.0 (build 180) · 7754ec8", or without the commit for builds made outside git.
    public var summary: String {
        let versionAndBuild = String(localized: "\(version) (build \(build))", comment: "About: version and build number, e.g. '1.0 (build 180)'.")
        return [versionAndBuild, commit].compactMap { $0 }.joined(separator: " · ")
    }
}
