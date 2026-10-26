import XCTest
import SwiftData
@testable import MurmurCore

final class TalkTimeTests: XCTestCase {
    func testSharesAddUpAndSortLongestFirst() {
        let segments = [
            TranscriptSegment(start: 0, end: 10, text: "a", speakerIndex: 0),
            TranscriptSegment(start: 10, end: 40, text: "b", speakerIndex: 1),
            TranscriptSegment(start: 40, end: 50, text: "c", speakerIndex: 0),
        ]
        let shares = TalkTime.shares(segments: segments, names: ["Alex", "Priya"])
        XCTAssertEqual(shares.map(\.name), ["Priya", "Alex"])
        XCTAssertEqual(shares.map(\.percent), [60, 40])
        XCTAssertEqual(shares.map(\.fraction).reduce(0, +), 1, accuracy: 0.0001)
    }

    func testUnnamedSpeakersGetDefaultNames() {
        let segments = [TranscriptSegment(start: 0, end: 5, text: "a", speakerIndex: 2)]
        XCTAssertEqual(TalkTime.shares(segments: segments, names: []).first?.name, "Speaker 3")
    }

    func testNoSpeakersGivesNoShares() {
        let segments = [TranscriptSegment(start: 0, end: 5, text: "a", speakerIndex: nil)]
        XCTAssertTrue(TalkTime.shares(segments: segments, names: []).isEmpty)
        XCTAssertTrue(TalkTime.shares(segments: [], names: []).isEmpty)
    }
}

final class RealtimeFactorTests: XCTestCase {
    func testFactorIsAudioOverElapsed() {
        XCTAssertEqual(RealtimeFactor.value(audioSeconds: 600, elapsed: 30) ?? 0, 20, accuracy: 0.0001)
    }

    func testNoFactorUntilThereIsSomethingToMeasure() {
        XCTAssertNil(RealtimeFactor.value(audioSeconds: 0, elapsed: 10))
        XCTAssertNil(RealtimeFactor.value(audioSeconds: 10, elapsed: 0.2))
    }

    func testText() {
        XCTAssertEqual(RealtimeFactor.text(17.4), "17× real time")
        XCTAssertEqual(RealtimeFactor.text(2.34), "2.3× real time")
        XCTAssertEqual(RealtimeFactor.text(nil), "—")
    }
}

final class MarkdownExportTests: XCTestCase {
    func testMarkdownHasSummaryTasksAndTranscript() {
        let segments = [
            TranscriptSegment(start: 4, end: 9, text: "Ship Watch first.", speakerIndex: 0),
            TranscriptSegment(start: 10, end: 15, text: "Agreed.", speakerIndex: 1),
        ]
        let summary = NoteSummary(
            template: .meeting,
            text: "Watch ships first.",
            actionItems: [ActionItem(text: "Update timeline", owner: "Priya", due: "Friday", done: true),
                          ActionItem(text: "Start spike")]
        )
        let md = Exporter.markdown(title: "Sync", segments: segments, speakerNames: ["Alex", "Priya"],
                                   summary: summary, options: ExportOptions(speakerLabels: true, timestamps: true, summary: true))
        XCTAssertTrue(md.hasPrefix("# Sync\n"))
        XCTAssertTrue(md.contains("## Summary\n\nWatch ships first."))
        XCTAssertTrue(md.contains("- [x] Update timeline (Priya · Friday)"))
        XCTAssertTrue(md.contains("- [ ] Start spike"))
        XCTAssertTrue(md.contains("`00:04` **Alex:** Ship Watch first."))
        XCTAssertTrue(md.contains("**Priya:** Agreed."))
    }

    func testMarkdownOptionsOff() {
        let segments = [TranscriptSegment(start: 4, end: 9, text: "Hello.", speakerIndex: 0)]
        let md = Exporter.markdown(title: "T", segments: segments, speakerNames: ["Alex"], summary: NoteSummary(template: .meeting, text: "S"),
                                   options: ExportOptions(speakerLabels: false, timestamps: false, summary: false))
        XCTAssertFalse(md.contains("Summary"))
        XCTAssertFalse(md.contains("Alex"))
        XCTAssertTrue(md.contains("## Transcript\n\nHello."))
    }
}

@MainActor
final class MacLibraryLogicTests: XCTestCase {
    private var keep: ModelContainer?

    private func note(_ title: String, ageDays: Double = 0, source: NoteSource = .recording, status: NoteStatus = .ready, duration: Double = 60) throws -> Note {
        if keep == nil { keep = try MurmurSchema.makeContainer(inMemory: true) }
        let n = Note(title: title, createdAt: Date().addingTimeInterval(-ageDays * 86_400), duration: duration, source: source, status: status)
        keep!.mainContext.insert(n)
        return n
    }

    func testRecentAndFromWatch() throws {
        let notes = [try note("new"), try note("old", ageDays: 20), try note("watch", ageDays: 30, source: .watch)]
        XCTAssertEqual(NoteFilter.recent(notes).map(\.title), ["new"])
        XCTAssertEqual(NoteFilter.fromWatch(notes).map(\.title), ["watch"])
    }

    func testQueueStats() throws {
        let notes = [
            try note("a", status: .ready),
            try note("b", status: .transcribing, duration: 600),
            try note("c", status: .queued, duration: 1200),
            try note("d", status: .queued, duration: 600),
        ]
        let stats = QueueStats.make(notes: notes, currentETA: 30, speed: 20)
        XCTAssertEqual(stats.done, 1)
        XCTAssertEqual(stats.working, 1)
        XCTAssertEqual(stats.waiting, 2)
        XCTAssertEqual(stats.secondsLeft ?? 0, 30 + 1800.0 / 20, accuracy: 0.001)
        XCTAssertNil(QueueStats.make(notes: notes, currentETA: nil, speed: nil).secondsLeft)
        XCTAssertEqual(QueueStats.make(notes: [notes[0]], currentETA: nil, speed: nil).secondsLeft, 0)
    }

    func testDictionaryImportExport() throws {
        let container = try MurmurSchema.makeContainer(inMemory: true)
        keep = container
        let store = DictionaryStore(context: container.mainContext)
        XCTAssertEqual(store.importList("Priya\n\n  Jordan \npriya\nCloudKit\n"), 3)
        XCTAssertEqual(Set(store.words().map(\.term)), ["Priya", "Jordan", "CloudKit"])
        let exported = store.exportList()
        XCTAssertEqual(Set(exported.split(separator: "\n").map(String.init)), ["Priya", "Jordan", "CloudKit"])
    }

    func testMacSettings() {
        let defaults = UserDefaults(suiteName: "murmur-mac-\(UUID().uuidString)")!
        let settings = AppSettings(defaults: defaults)
        XCTAssertTrue(settings.showMenuBarIcon)
        XCTAssertFalse(settings.hideDockIcon)
        settings.setShowMenuBarIcon(false)
        settings.setHideDockIcon(true)
        let again = AppSettings(defaults: defaults)
        XCTAssertFalse(again.showMenuBarIcon)
        XCTAssertTrue(again.hideDockIcon)
    }
}

@MainActor
final class RecordShortcutTests: XCTestCase {
    func testDefaultDisplay() {
        XCTAssertEqual(RecordShortcut.default.display, "⌃⌥R")
        XCTAssertTrue(RecordShortcut.default.isValid)
    }

    func testNeedsAModifier() {
        XCTAssertFalse(RecordShortcut(keyCode: 15, carbonModifiers: 0, key: "r").isValid)
        XCTAssertFalse(RecordShortcut(keyCode: 15, carbonModifiers: RecordShortcut.shift, key: "r").isValid)
        XCTAssertEqual(RecordShortcut(keyCode: 1, carbonModifiers: RecordShortcut.command | RecordShortcut.shift, key: "s").display, "⇧⌘S")
    }

    func testSettingsSaveAndIgnoreInvalid() {
        let defaults = UserDefaults(suiteName: "murmur-sc-\(UUID().uuidString)")!
        let settings = AppSettings(defaults: defaults)
        XCTAssertEqual(settings.recordShortcut, .default)
        settings.setRecordShortcut(RecordShortcut(keyCode: 1, carbonModifiers: RecordShortcut.command | RecordShortcut.shift, key: "s"))
        settings.setRecordShortcut(RecordShortcut(keyCode: 2, carbonModifiers: 0, key: "d"))
        XCTAssertEqual(AppSettings(defaults: defaults).recordShortcut.display, "⇧⌘S")
    }
}
