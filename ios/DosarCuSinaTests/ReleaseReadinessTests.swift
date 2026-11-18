import Foundation
import ImageIO
import Testing
@testable import DosarCuSina

/// What App Store Connect checks when a build is uploaded, and what review asks of it, pinned
/// against the built bundles (the test's host is the app, with its widgets and share extension
/// inside) and against the code each of them is compiled from:
/// - every bundle that ships carries a privacy manifest that tracks nothing and collects nothing,
///   and declares exactly the kinds of "required reason" APIs its code uses, each with a reason
///   Apple allows an app to give;
/// - every permission the code can ask for has its words in that bundle's Info.plist;
/// - the app icons have no alpha channel, as the upload requires;
/// - the export-compliance answer is in the Info.plist, and every part carries one version.
/// The release build's own bundle is checked on GitHub by `scripts/bundle-check.sh`.
@Suite("Release readiness")
struct ReleaseReadinessTests {
    /// `ios/`, where the targets' folders and the project are.
    static var ios: URL {
        URL(filePath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
    }

    // MARK: The parts that ship

    /// A target that ships in the app: its folder and its product are named after it.
    struct Shipped: Sendable, CustomTestStringConvertible {
        let name: String
        let isApp: Bool

        var testDescription: String { name }

        static let app = Shipped(name: "DosarCuSina", isApp: true)
        static let all = [app, Shipped(name: "DosarCuSinaWidgets", isApp: false), Shipped(name: "DosarCuSinaShare", isApp: false)]

        /// The built bundle, inside the test's host.
        func bundle() throws -> Bundle {
            if isApp { return Bundle.main }
            let plugIns = try #require(Bundle.main.builtInPlugInsURL)
            return try #require(Bundle(url: plugIns.appending(path: "\(name).appex")), "\(name).appex is embedded in the app")
        }

        /// The Swift files its code is compiled from: its own folder and `ios/Shared`, without
        /// what the project leaves out of it (`membershipExceptions`).
        func sources() throws -> [(path: String, text: String)] {
            let project = try String(contentsOf: ReleaseReadinessTests.ios.appending(path: "DosarCuSina.xcodeproj/project.pbxproj"), encoding: .utf8)
            var files: [(path: String, text: String)] = []
            for folder in [name, "Shared"] {
                let left = Self.exceptions(in: project, folder: folder, target: name)
                let base = ReleaseReadinessTests.ios.appending(path: folder)
                let enumerator = FileManager.default.enumerator(at: base, includingPropertiesForKeys: nil)
                while let url = enumerator?.nextObject() as? URL {
                    guard url.pathExtension == "swift" else { continue }
                    let relative = String(url.standardizedFileURL.path().dropFirst(base.standardizedFileURL.path().count)).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
                    guard !left.contains(relative) else { continue }
                    files.append((path: "\(folder)/\(relative)", text: try String(contentsOf: url, encoding: .utf8)))
                }
            }
            return files
        }

        /// The files of `folder` the project keeps out of `target`.
        static func exceptions(in project: String, folder: String, target: String) -> Set<String> {
            let header = "/* Exceptions for \"\(folder)\" folder in \"\(target)\" target */ = {"
            guard let start = project.range(of: header),
                  let list = project.range(of: "membershipExceptions = (", range: start.upperBound..<project.endIndex),
                  let end = project.range(of: ");", range: list.upperBound..<project.endIndex) else { return [] }
            let names = project[list.upperBound..<end.lowerBound].split(whereSeparator: { $0 == "," || $0.isNewline })
            return Set(names.map { $0.trimmingCharacters(in: .whitespaces).trimmingCharacters(in: CharacterSet(charactersIn: "\"")) }.filter { !$0.isEmpty })
        }
    }

    /// Code without its comments, so a comment that names an API doesn't count as using it.
    static func code(_ text: String) -> String {
        var inBlock = false
        return text.split(separator: "\n", omittingEmptySubsequences: false).compactMap { line -> Substring? in
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if inBlock { if trimmed.contains("*/") { inBlock = false }; return nil }
            if trimmed.hasPrefix("/*") { inBlock = !trimmed.contains("*/"); return nil }
            return trimmed.hasPrefix("//") ? nil : line
        }.joined(separator: "\n")
    }

    /// The files of `sources` whose code matches `pattern`.
    static func files(_ sources: [(path: String, text: String)], using pattern: String) throws -> [String] {
        let regex = try NSRegularExpression(pattern: pattern)
        return sources.filter { source in
            let stripped = code(source.text)
            return regex.firstMatch(in: stripped, range: NSRange(stripped.startIndex..., in: stripped)) != nil
        }.map(\.path)
    }

    // MARK: Privacy manifests

    /// Apple's kinds of "required reason" API, the calls that make each one (Apple's list; the
    /// boot time also counts `ContinuousClock`, which the lock's clock reads it through), and the
    /// reasons an app may give for it (the ones only an SDK may give left out).
    enum RequiredReason: String, CaseIterable {
        case userDefaults = "NSPrivacyAccessedAPICategoryUserDefaults"
        case fileTimestamp = "NSPrivacyAccessedAPICategoryFileTimestamp"
        case systemBootTime = "NSPrivacyAccessedAPICategorySystemBootTime"
        case diskSpace = "NSPrivacyAccessedAPICategoryDiskSpace"
        case activeKeyboards = "NSPrivacyAccessedAPICategoryActiveKeyboards"

        var calls: String {
            switch self {
            case .userDefaults: #"\bUserDefaults\b|@AppStorage\b"#
            case .fileTimestamp: #"\.creationDate\b|\.modificationDate\b|\bfileModificationDate\b|\bcontentModificationDate(Key)?\b|\bcreationDateKey\b|\bf?getattrlist(bulk|at)?\s*\(|\b[fl]?stat(at)?\s*\("#
            case .systemBootTime: #"\bsystemUptime\b|\bmach_absolute_time\b|\bContinuousClock\b"#
            case .diskSpace: #"\bvolume(Available|Total)Capacity\w*|\bsystem(Free)?Size\b|\bf?statv?fs\s*\("#
            case .activeKeyboards: #"\bactiveInputModes\b"#
            }
        }

        var allowedReasons: Set<String> {
            switch self {
            case .userDefaults: ["CA92.1", "1C8F.1", "AC6B.1"]
            case .fileTimestamp: ["DDA9.1", "C617.1", "3B52.1"]
            case .systemBootTime: ["35F9.1", "8FFB.1", "3D61.1"]
            case .diskSpace: ["85F4.1", "E174.1", "7D9E.1", "B728.1"]
            case .activeKeyboards: ["3EC4.1", "54BD.1"]
            }
        }
    }

    static func manifest(of target: Shipped) throws -> [String: Any] {
        let url = try #require(try target.bundle().url(forResource: "PrivacyInfo", withExtension: "xcprivacy"), "\(target.name) carries PrivacyInfo.xcprivacy")
        let plist = try PropertyListSerialization.propertyList(from: Data(contentsOf: url), format: nil)
        return try #require(plist as? [String: Any])
    }

    @Test("Every part that ships says it tracks nothing and collects nothing", arguments: Shipped.all)
    func nothingTrackedOrCollected(_ target: Shipped) throws {
        let manifest = try Self.manifest(of: target)
        #expect(manifest["NSPrivacyTracking"] as? Bool == false)
        #expect((manifest["NSPrivacyTrackingDomains"] as? [Any])?.isEmpty == true)
        #expect((manifest["NSPrivacyCollectedDataTypes"] as? [Any])?.isEmpty == true, "No account, analytics or server of ours: nothing is collected")
    }

    @Test("Every part declares exactly the required-reason APIs its code uses, with reasons Apple allows", arguments: Shipped.all)
    func declaredReasonsMatchTheCode(_ target: Shipped) throws {
        let entries = try #require(Self.manifest(of: target)["NSPrivacyAccessedAPITypes"] as? [[String: Any]])
        var declared: [RequiredReason: [String]] = [:]
        for entry in entries {
            let type = try #require(entry["NSPrivacyAccessedAPIType"] as? String)
            let kind = try #require(RequiredReason(rawValue: type), "\(type) is one of Apple's kinds")
            #expect(declared[kind] == nil, "\(type) is declared once")
            declared[kind] = try #require(entry["NSPrivacyAccessedAPITypeReasons"] as? [String])
        }
        let sources = try target.sources()
        #expect(!sources.isEmpty)
        for kind in RequiredReason.allCases {
            let users = try Self.files(sources, using: kind.calls)
            if users.isEmpty {
                #expect(declared[kind] == nil, "\(target.name) declares \(kind.rawValue) but its code no longer uses it: take it out of its PrivacyInfo.xcprivacy")
            } else {
                let reasons = declared[kind] ?? []
                #expect(!reasons.isEmpty, "\(target.name) uses \(kind.rawValue) (\(users.joined(separator: ", "))): declare it in its PrivacyInfo.xcprivacy with the reason that says what for")
                #expect(Set(reasons).isSubset(of: kind.allowedReasons), "\(kind.rawValue): \(reasons) are reasons an app may give")
            }
        }
    }

    // MARK: Permissions

    /// What the code can ask for and the Info.plist words iOS shows when it does. A permission
    /// without its words stops the app the first time it is asked, and fails review.
    static let permissions: [(calls: String, key: String)] = [
        (#"\bVNDocumentCameraViewController\b|\bAVCaptureDevice\b|\bUIImagePickerController\b"#, "NSCameraUsageDescription"),
        (#"\bLAContext\b"#, "NSFaceIDUsageDescription"),
        // The share sheet offers „Salvează imaginea” for a picture, which adds it to Photos.
        (#"\bUIActivityViewController\b|\bShareLink\b|\bPHAssetCreationRequest\b|\bUIImageWriteToSavedPhotosAlbum\b"#, "NSPhotoLibraryAddUsageDescription"),
        (#"\bPHPhotoLibrary\.requestAuthorization\b|\bPHAsset\.fetchAssets\b"#, "NSPhotoLibraryUsageDescription"),
        (#"\bCNContactStore\b"#, "NSContactsUsageDescription"),
        (#"\brequestFullAccessToEvents\b|\brequestFullAccessToReminders\b"#, "NSCalendarsFullAccessUsageDescription"),
        (#"\brequestWriteOnlyAccessToEvents\b"#, "NSCalendarsWriteOnlyAccessUsageDescription"),
        (#"\bCLLocationManager\b"#, "NSLocationWhenInUseUsageDescription"),
        (#"\bAVAudioRecorder\b|\brecordPermission\b"#, "NSMicrophoneUsageDescription"),
        (#"\bSFSpeechRecognizer\b"#, "NSSpeechRecognitionUsageDescription"),
        (#"\bNFC(Tag|NDEF)ReaderSession\b"#, "NFCReaderUsageDescription"),
        // A compatible AI service on the home network (LM Studio, Ollama): iOS asks before the
        // app reaches a device there.
        (#"\bisLocal\(|\bvalidatedBaseURL\("#, "NSLocalNetworkUsageDescription"),
    ]

    @Test("Every permission a part's code can ask for has its words in that part's Info.plist", arguments: Shipped.all)
    func everyPermissionHasItsWords(_ target: Shipped) throws {
        let info = try #require(try target.bundle().infoDictionary)
        let sources = try target.sources()
        for permission in Self.permissions {
            let users = try Self.files(sources, using: permission.calls)
            guard !users.isEmpty else { continue }
            let words = info[permission.key] as? String ?? ""
            #expect(!words.trimmingCharacters(in: .whitespaces).isEmpty, "\(target.name) can ask for \(permission.key) (\(users.joined(separator: ", "))): add its words to the target's INFOPLIST_KEY_\(permission.key)")
        }
    }

    /// What iOS shows when a permission is asked is the app talking, so it speaks as the app
    /// does everywhere (docs/COPY_GUIDE.md): as one, „eu”, to „tu”; never „noi” („Folosim”,
    /// „deschidem”) and never about itself in the third person („Aplicația are nevoie”).
    @Test("Every permission's words speak in the app's one voice", arguments: Shipped.all)
    func permissionWordsSpeakAsTheApp(_ target: Shipped) throws {
        let info = try #require(try target.bundle().infoDictionary)
        let plural = try Regex(#"(?i)\b(noi|folosim|avem|putem|cerem|deschidem|păstrăm|trimitem|citim|salvăm)\b"#)
        for permission in Self.permissions {
            guard let words = info[permission.key] as? String else { continue }
            #expect(!words.contains("Aplicația") && !words.contains("aplicația"), "\(permission.key): „\(words)” speaks of the app in the third person")
            #expect(words.firstMatch(of: plural) == nil, "\(permission.key): „\(words)” speaks as „noi”; the app says „eu”")
            #expect(!words.contains("!"))
        }
    }

    @Test("Saving a page to Photos from „Trimite” says why, in the app's words")
    func savingToPhotosSaysWhy() throws {
        let words = try #require(Bundle.main.infoDictionary?["NSPhotoLibraryAddUsageDescription"] as? String)
        #expect(words == "Ca să salvezi în Poze paginile pe care le trimiți.")
        #expect(!words.contains("!"))
    }

    // MARK: What the upload checks

    @Test("The app icons have no alpha channel, as App Store Connect requires")
    func iconsHaveNoAlpha() throws {
        let set = Self.ios.appending(path: "DosarCuSina/Resources/Assets.xcassets/AppIcon.appiconset")
        let pictures = try FileManager.default.contentsOfDirectory(at: set, includingPropertiesForKeys: nil).filter { $0.pathExtension == "png" }
        #expect(pictures.contains { $0.lastPathComponent == "AppIcon-1024.png" }, "The 1024 pt icon the App Store shows")
        for picture in pictures {
            let source = try #require(CGImageSourceCreateWithURL(picture as CFURL, nil))
            // ImageIO leaves out "has alpha" for a picture without an alpha channel.
            let properties = try #require(CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any])
            let image = try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))
            let opaque: [CGImageAlphaInfo] = [.none, .noneSkipFirst, .noneSkipLast]
            #expect(properties[kCGImagePropertyHasAlpha] as? Bool != true && opaque.contains(image.alphaInfo), "\(picture.lastPathComponent) has an alpha channel: save it without one")
        }
    }

    @Test("Plain http reaches only the home network, as Settings says a local AI service may use")
    func plainHTTPOnlyOnTheHomeNetwork() throws {
        let security = try #require(Bundle.main.infoDictionary?["NSAppTransportSecurity"] as? [String: Any])
        #expect(security["NSAllowsLocalNetworking"] as? Bool == true, "A server at localhost or a .local name, over http")
        #expect(Set(security.keys) == ["NSAllowsLocalNetworking"], "Nothing else is let through in the clear")
        let words = try #require(Bundle.main.infoDictionary?["NSLocalNetworkUsageDescription"] as? String)
        #expect(words == "Ca să citești documente cu serviciul AI de pe rețeaua ta, dacă îl alegi în Setări.")
        #expect(!words.contains("!"))
        #expect(AIProviderSettings.validatedBaseURL("http://studio.local:1234/v1") != nil)
        #expect(AIProviderSettings.validatedBaseURL("http://example.com/v1") == nil, "Never the internet in the clear")
    }

    @Test("The export-compliance answer is in the Info.plist: only the encryption iOS provides")
    func exportCompliance() throws {
        #expect(Bundle.main.infoDictionary?["ITSAppUsesNonExemptEncryption"] as? Bool == false)
    }

    @Test("The app, its widgets and its share extension carry one version and one build number")
    func oneVersionEverywhere() throws {
        let infos = try Shipped.all.map { try #require(try $0.bundle().infoDictionary) }
        for key in ["CFBundleShortVersionString", "CFBundleVersion"] {
            let values = Set(infos.map { $0[key] as? String ?? "" })
            #expect(values.count == 1 && values.first?.isEmpty == false, "\(key) is the same in every part: \(values)")
        }
    }
}
