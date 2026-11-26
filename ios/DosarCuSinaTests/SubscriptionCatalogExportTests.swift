import Foundation
import Testing
@testable import DosarCuSina

/// What a subscription can be, written to `shared/catalog/subscriptions/` as data, so the Android
/// app reads the same services and never keeps a list of its own (docs/ANDROID_PLAN.md, "How parity
/// is kept", item 1). One file, `subscriptions.json`, which `shared/catalog/README.md` describes:
///
/// - the services (`ServiceKind.services`): each one's key, name and older spellings, its group,
///   its codes, whether it lives under a home, whether it bills on a rhythm, its meter and what a
///   language model is told it is; and the service that says nothing about a contract (`other`);
/// - the codes (`SubscriptionCode`), in the edit form's order: the field that keeps each, its
///   family, what capture reads it as, its weight, whether it names one point, the home's fields
///   for the same code, how it is compared, and the edit form's condition;
/// - the groups (`SubscriptionGroup`), in their order, and the one for what isn't known;
/// - the billing cycles (`BillingCycle`): each one's key, name, spellings and interval, and the
///   interval of an unknown one.
///
/// Fresh or failing, as `CatalogExportTests` keeps the built-in catalog, and written by the same
/// switch (`CATALOG_WRITE=1`): a run that finds the file out of date leaves it made afresh in
/// `TEST_RUNNER_CATALOG_OUT`'s `subscriptions/` folder.
@Suite("Subscription catalog export")
struct SubscriptionCatalogExportTests {
    static var folder: URL { CatalogExportTests.folder.appending(path: "subscriptions") }

    static let writtenBy = "ios/DosarCuSinaTests/SubscriptionCatalogExportTests.swift"

    static let regenerate = """
    is out of date with what a subscription can be (ServiceKind, SubscriptionCode, SubscriptionGroup, \
    BillingCycle). Bring shared/catalog/subscriptions up to date: a failed run on GitHub keeps the file \
    made afresh in its test-results artifact, catalog/subscriptions/ (copy it over), or \
    TEST_RUNNER_CATALOG_WRITE=1 ./tests/run_tests.sh (or run SubscriptionCatalogExportTests in Xcode with \
    CATALOG_WRITE=1 in the scheme's environment); review the diff and commit it, then run the Android \
    tests (./gradlew :core:test in android/), which read the same file.
    """

    @Test("shared/catalog/subscriptions is up to date with what a subscription can be")
    func catalogIsUpToDate() throws {
        let files = try Self.files()
        let manager = FileManager.default
        if CatalogExportTests.writes { try manager.createDirectory(at: Self.folder, withIntermediateDirectories: true) }
        var outOfDate: [String] = []
        for (name, fresh) in files.sorted(by: { $0.key < $1.key }) {
            let url = Self.folder.appending(path: name)
            if CatalogExportTests.writes {
                try fresh.write(to: url, atomically: true, encoding: .utf8)
                continue
            }
            let committed = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
            if committed != fresh { outOfDate.append(name) }
        }
        // A file nothing writes any more goes, so Android never reads an old list.
        let present = (try? manager.contentsOfDirectory(atPath: Self.folder.path(percentEncoded: false))) ?? []
        for stale in present where stale.hasSuffix(".json") && files[stale] == nil {
            if CatalogExportTests.writes {
                try manager.removeItem(at: Self.folder.appending(path: stale))
            } else {
                Issue.record(Comment(rawValue: "\(stale) is written by nothing any more and " + Self.regenerate))
            }
        }
        if !outOfDate.isEmpty, let out = CatalogExportTests.outOfDateGoesTo?.appending(path: "subscriptions") {
            try manager.createDirectory(at: out, withIntermediateDirectories: true)
            for (name, fresh) in files { try fresh.write(to: out.appending(path: name), atomically: true, encoding: .utf8) }
        }
        for name in outOfDate {
            Issue.record(Comment(rawValue: "shared/catalog/subscriptions/\(name) " + Self.regenerate))
        }
    }

    @Test("Every code a service names is declared, and the unspecified service and group are real ones")
    func theFileHoldsTogether() {
        let codes = Set(SubscriptionCode.allCases)
        for service in ServiceKind.services {
            #expect(Set(service.codes).isSubset(of: codes), "\(service.key)")
        }
        #expect(ServiceKind.service(ServiceKind.other) != nil)
        #expect(ServiceKind.codes(of: nil) == ServiceKind.codes(of: ServiceKind.other), "What any contract has is the unspecified service's")
        #expect(SubscriptionGroup.of(service: nil) == Subscriptions.unspecifiedGroup)
        #expect(BillingCycle.interval(nil) == Subscriptions.unknownCycle)
    }

    // MARK: The file

    static func files() throws -> [String: String] {
        ["subscriptions.json": try CatalogExportTests.render(Subscriptions())]
    }

    /// Everything a subscription can be, as data.
    struct Subscriptions: Encodable {
        /// The group of a service that isn't known (`SubscriptionGroup.of(service:)`).
        static let unspecifiedGroup = SubscriptionGroup.other
        /// What a cycle that isn't known lasts (`BillingCycle.interval(_:)`).
        static let unknownCycle = RecurrenceInterval.months(1)

        struct Service: Encodable {
            var key: String
            var label: String
            var aliases: [String]
            var group: String
            var codes: [String]
            var isTiedToHome: Bool
            var sendsRegularBills: Bool
            var meter: String?
            var modelDescription: String

            init(_ service: ServiceKind.Service) {
                key = service.key
                label = service.label
                aliases = service.aliases
                group = service.group.rawValue
                codes = service.codes.map(\.rawValue)
                isTiedToHome = service.isTiedToHome
                sendsRegularBills = service.sendsRegularBills
                meter = service.meter?.rawValue
                modelDescription = service.modelDescription
            }

            // Written with `meter` as null when there is none, so every service has the same keys.
            func encode(to encoder: Encoder) throws {
                var container = encoder.container(keyedBy: CodingKeys.self)
                try container.encode(key, forKey: .key)
                try container.encode(label, forKey: .label)
                try container.encode(aliases, forKey: .aliases)
                try container.encode(group, forKey: .group)
                try container.encode(codes, forKey: .codes)
                try container.encode(isTiedToHome, forKey: .isTiedToHome)
                try container.encode(sendsRegularBills, forKey: .sendsRegularBills)
                try container.encode(meter, forKey: .meter)
                try container.encode(modelDescription, forKey: .modelDescription)
            }

            private enum CodingKeys: String, CodingKey {
                case key, label, aliases, group, codes, isTiedToHome, sendsRegularBills, meter, modelDescription
            }
        }

        struct Code: Encodable {
            var name: String
            var family: String
            var fieldKey: String
            var captureKey: String
            var weight: Int
            var namesOnePoint: Bool
            var homeFieldKeys: [String]
            /// How a kept and a read value are compared: `nationalPhoneNumber` (a phone number in
            /// its national form) or `compact` (`RomanianText.compact`).
            var comparedAs: String
            var editFormCondition: BlueprintCondition

            init(_ code: SubscriptionCode) {
                name = code.rawValue
                family = "\(code.family)"
                fieldKey = code.fieldKey
                captureKey = code.captureKey.rawValue
                weight = code.weight
                namesOnePoint = code.namesOnePoint
                homeFieldKeys = code.homeFieldKeys
                // The one code the matcher reads another way (`SubscriptionMatcher.normalized`).
                comparedAs = code == .phoneNumber ? "nationalPhoneNumber" : "compact"
                editFormCondition = code.fieldCondition
            }
        }

        struct Group: Encodable {
            var key: String
            var label: String
        }

        struct Cycle: Encodable {
            var key: String
            var label: String
            var aliases: [String]
            var interval: RecurrenceInterval
        }

        /// In the order they are offered.
        var services = ServiceKind.services.map(Service.init)
        /// The service that says nothing about which contract a paper is (`ServiceKind.other`): its
        /// codes are what any contract has, and it is never told apart from another service.
        var unspecifiedService = ServiceKind.other
        /// In the edit form's order.
        var codes = SubscriptionCode.allCases.map(Code.init)
        /// In the order they are listed.
        var groups = SubscriptionGroup.allCases.map { Group(key: $0.rawValue, label: $0.label) }
        var unspecifiedGroup = Subscriptions.unspecifiedGroup.rawValue
        /// In the order they are offered.
        var billingCycles = BillingCycle.options.map { option in
            Cycle(key: option.key, label: option.label, aliases: option.aliases, interval: BillingCycle.interval(option.key))
        }
        var unknownCycle = Subscriptions.unknownCycle
        var writtenBy = SubscriptionCatalogExportTests.writtenBy
    }
}
