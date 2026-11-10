import Foundation
import Testing
@testable import DosarCuSina

/// One JSON coder for machine text: what the app, its widgets and its share extension keep
/// and hand each other, and archives. Pinned against what earlier versions wrote, byte for
/// byte where the bytes matter. Placeholder data only.
@Suite("Machine JSON")
struct MachineJSONTests {
    private struct Stamped: Codable, Equatable {
        var at: Date
        var link: String
    }

    private let moment = Date(timeIntervalSince1970: 1_793_606_400) // 2026-11-02T08:00:00Z

    // MARK: Writing

    @Test func aMomentIsWrittenInUTCToTheSecond() throws {
        let fraction = moment.addingTimeInterval(0.75)
        let json = String(decoding: try MachineText.jsonEncoder().encode(Stamped(at: fraction, link: "a/b")), as: UTF8.self)
        #expect(json == #"{"at":"2026-11-02T08:00:00Z","link":"a\/b"}"#)
    }

    /// What the widget snapshot, the share inbox, a widget's completions and outside failures
    /// were written with before the shared coder.
    @Test func compactIsWhatTheSharedFilesWereWrittenWith() throws {
        let before = JSONEncoder()
        before.dateEncodingStrategy = .iso8601
        before.outputFormatting = [.sortedKeys]
        let value = Stamped(at: moment, link: "dosarcusina://obligation/1")
        #expect(try MachineText.jsonEncoder().encode(value) == before.encode(value))
    }

    /// What `.dosar` archives were written with before the shared coder: the archive's
    /// checksums are of these bytes.
    @Test func readableIsWhatArchivesWereWrittenWith() throws {
        let before = JSONEncoder()
        before.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        before.dateEncodingStrategy = .custom { date, encoder in
            var container = encoder.singleValueContainer()
            try container.encode(date.formatted(Date.ISO8601FormatStyle()))
        }
        for date in [moment, moment.addingTimeInterval(0.999), Date(timeIntervalSince1970: 0), Date(timeIntervalSinceReferenceDate: -1e10)] {
            let value = Stamped(at: date, link: "vault/6b7c8d9e.txt")
            #expect(try MachineText.jsonEncoder(.readable).encode(value) == before.encode(value))
            #expect(try DossierV3.encoder().encode(value) == before.encode(value))
        }
    }

    // MARK: Reading

    @Test(arguments: [
        ("2026-11-02T08:00:00Z", 0.0),
        ("2026-11-02T10:00:00+02:00", 0.0),
        ("2026-11-02T08:00:00.000Z", 0.0),
        ("2026-11-02", -8 * 3600.0),
    ])
    func everyFormEarlierWritersUsedIsRead(raw: String, offset: Double) throws {
        let json = Data(#"{"at":"\#(raw)","link":""}"#.utf8)
        let read = try MachineText.jsonDecoder().decode(Stamped.self, from: json)
        #expect(abs(read.at.timeIntervalSince(moment.addingTimeInterval(offset))) < 0.001)
    }

    @Test func somethingElseIsNotAMoment() {
        let json = Data(#"{"at":"2 noiembrie 2026","link":""}"#.utf8)
        #expect(throws: DecodingError.self) { try MachineText.jsonDecoder().decode(Stamped.self, from: json) }
        #expect(MachineText.moment("2026-11-02T08:00") == nil)
    }

    @Test func whatTheCoderWritesItReads() throws {
        let value = Stamped(at: moment, link: "x")
        for layout in [MachineText.JSONLayout.compact, .readable] {
            #expect(try MachineText.jsonDecoder().decode(Stamped.self, from: MachineText.jsonEncoder(layout).encode(value)) == value)
        }
    }

    @Test func theGoldenArchivesStillRead() throws {
        let v3 = try Data(contentsOf: Fixtures.root.appending(path: "dosar-v3/household/manifest.json"))
        let manifest = try DossierV3.decoder().decode(DossierV3.Manifest.self, from: v3)
        #expect(manifest.exportedAt == MachineText.moment("2026-03-02T08:00:00Z"))

        let v2 = try Data(contentsOf: Fixtures.root.appending(path: "dosar-v2/ios-export/manifest.json"))
        let old = try MachineText.jsonDecoder().decode(DossierManifestV2.self, from: v2)
        #expect(old.schemaVersion == 2)
    }

    // MARK: What the app and its extensions hand each other

    /// A snapshot exactly as the app wrote it before the widget and the app shared one type.
    @Test func aSnapshotTheAppWroteBeforeStillReads() throws {
        let written = #"{"generatedAt":"2026-11-02T08:00:00Z","items":[{"assetId":"6F1D2C3B-0000-4000-8000-000000000002","assetName":"VW Golf","deepLink":"dosarcusina:\/\/obligation\/6f1d2c3b-0000-4000-8000-000000000001","dueDate":"2026-11-15","isSensitive":false,"kind":"legal","obligationId":"6F1D2C3B-0000-4000-8000-000000000001","symbol":"car.fill","tint":"blue","title":"ITP","urgency":{"firstLeadDays":30,"graceDays":0,"maxWindowDays":30,"travelMarginDays":0}}],"needsActionCount":2,"version":1}"#
        let feed = try #require(WidgetFeed.decode(Data(written.utf8)))
        #expect(feed.generatedAt == moment)
        #expect(feed.needsActionCount == 2)
        let item = try #require(feed.items.first)
        #expect(item.title == "ITP")
        #expect(item.dueDate == CalendarDay("2026-11-15"))
        #expect(item.tint == TemplateTint.blue.rawValue)
        #expect(item.kind == ObligationKind.legal.rawValue)
        #expect(item.urgency == UrgencyRule(graceDays: 0, firstLeadDays: 30, maxWindowDays: 30))
        #expect(try WidgetFeed.encode(feed) == Data(written.utf8), "Written again, it is the same file")
    }

    @Test func aSnapshotWithoutItsUrgencyRuleStillReads() throws {
        let written = #"{"generatedAt":"2026-11-02T08:00:00Z","items":[{"deepLink":"dosarcusina:\/\/obligation\/6f1d2c3b-0000-4000-8000-000000000001","dueDate":"2026-11-15","isSensitive":true,"kind":"health","obligationId":"6F1D2C3B-0000-4000-8000-000000000001","symbol":"lock.fill","tint":"red","title":"Scadență protejată"}],"needsActionCount":0,"version":1}"#
        let feed = try #require(WidgetFeed.decode(Data(written.utf8)))
        #expect(feed.items.first?.urgency == nil)
        #expect(feed.items.first?.assetId == nil)
    }

    @Test func aSnapshotFromANewerVersionIsLeftForTheAppToRewrite() {
        let newer = #"{"generatedAt":"2026-11-02T08:00:00Z","items":[],"needsActionCount":0,"version":2}"#
        #expect(WidgetFeed.decode(Data(newer.utf8)) == nil)
    }

    @Test func aWidgetsCompletionsWrittenBeforeStillRead() throws {
        let folder = URL.temporaryDirectory.appending(path: "completions-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appending(path: WidgetCompletionQueue.fileName)
        let written = #"[{"dueDay":"2026-11-15","obligationId":"6F1D2C3B-0000-4000-8000-000000000001","requestedAt":"2026-11-02T08:00:00Z"}]"#
        try Data(written.utf8).write(to: url)
        let queue = WidgetCompletionQueue(fileURL: url)
        #expect(queue.pending().map(\.dueDay) == ["2026-11-15"])
    }
}
