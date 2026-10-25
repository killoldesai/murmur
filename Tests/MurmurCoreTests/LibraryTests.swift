import XCTest
import SwiftData
@testable import MurmurCore

private func seg(_ text: String, _ start: Double, _ end: Double, speaker: Int? = nil) -> TranscriptSegment {
    TranscriptSegment(start: start, end: end, text: text, speakerIndex: speaker)
}

// MARK: - Transcript editor

final class TranscriptEditorTests: XCTestCase {
    private func make() -> (TranscriptEditor, [UUID]) {
        let segments = [seg("Hello there friend.", 0, 4, speaker: 0), seg("Second line.", 4, 6, speaker: 1), seg("Third.", 6, 8)]
        return (TranscriptEditor(segments: segments), segments.map(\.id))
    }

    func testSetTextAndUndo() {
        var (editor, ids) = make()
        XCTAssertFalse(editor.hasChanges)
        editor.setText("Hi there.", for: ids[0])
        XCTAssertEqual(editor.segments[0].text, "Hi there.")
        XCTAssertTrue(editor.hasChanges)
        editor.undo()
        XCTAssertEqual(editor.segments[0].text, "Hello there friend.")
        XCTAssertFalse(editor.hasChanges)
        XCTAssertFalse(editor.canUndo)
    }

    func testTypingInOneSegmentIsOneUndoStep() {
        var (editor, ids) = make()
        editor.setText("H", for: ids[0])
        editor.setText("Hi", for: ids[0])
        editor.setText("Hi!", for: ids[0])
        editor.undo()
        XCTAssertEqual(editor.segments[0].text, "Hello there friend.")
        XCTAssertFalse(editor.canUndo)
    }

    func testEditingAnotherSegmentStartsNewUndoStep() {
        var (editor, ids) = make()
        editor.setText("A", for: ids[0])
        editor.setText("B", for: ids[1])
        editor.undo()
        XCTAssertEqual(editor.segments[1].text, "Second line.")
        XCTAssertEqual(editor.segments[0].text, "A")
    }

    func testSetSpeaker() {
        var (editor, ids) = make()
        editor.setSpeaker(1, for: ids[2])
        XCTAssertEqual(editor.segments[2].speakerIndex, 1)
        editor.setSpeaker(nil, for: ids[0])
        XCTAssertNil(editor.segments[0].speakerIndex)
        editor.undo(); editor.undo()
        XCTAssertNil(editor.segments[2].speakerIndex)
        XCTAssertEqual(editor.segments[0].speakerIndex, 0)
    }

    func testSplitInterpolatesTime() {
        var (editor, ids) = make()
        let text = editor.segments[0].text           // "Hello there friend." (19 chars)
        let newID = editor.split(ids[0], atCharacterOffset: 12)   // after "Hello there "
        XCTAssertNotNil(newID)
        XCTAssertEqual(editor.segments.count, 4)
        XCTAssertEqual(editor.segments[0].text, "Hello there")
        XCTAssertEqual(editor.segments[1].text, "friend.")
        XCTAssertEqual(editor.segments[0].end, 4 * 12.0 / Double(text.count), accuracy: 1e-9)
        XCTAssertEqual(editor.segments[1].start, editor.segments[0].end)
        XCTAssertEqual(editor.segments[1].end, 4)
        XCTAssertEqual(editor.segments[1].speakerIndex, 0)
        XCTAssertEqual(editor.segments[1].id, newID)
        editor.undo()
        XCTAssertEqual(editor.segments.count, 3)
        XCTAssertEqual(editor.segments[0].end, 4)
    }

    func testSplitRejectsEdgesAndEmptyHalves() {
        var (editor, ids) = make()
        XCTAssertNil(editor.split(ids[0], atCharacterOffset: 0))
        XCTAssertNil(editor.split(ids[0], atCharacterOffset: 19))
        XCTAssertNil(editor.split(ids[0], atCharacterOffset: 99))
        XCTAssertEqual(editor.segments.count, 3)
        XCTAssertFalse(editor.canUndo)
    }

    func testMergeWithNext() {
        var (editor, ids) = make()
        XCTAssertTrue(editor.merge(ids[0]))
        XCTAssertEqual(editor.segments.count, 2)
        XCTAssertEqual(editor.segments[0].text, "Hello there friend. Second line.")
        XCTAssertEqual(editor.segments[0].end, 6)
        XCTAssertEqual(editor.segments[0].speakerIndex, 0)
        XCTAssertEqual(editor.segments[0].id, ids[0])
        XCTAssertFalse(editor.canMerge(ids[2]))
        XCTAssertFalse(editor.merge(ids[2]))
        editor.undo()
        XCTAssertEqual(editor.segments.count, 3)
    }

    func testDeleteAndUndo() {
        var (editor, ids) = make()
        editor.delete(ids[1])
        XCTAssertEqual(editor.segments.map(\.id), [ids[0], ids[2]])
        editor.undo()
        XCTAssertEqual(editor.segments.map(\.id), ids)
    }

    func testUnknownIDIsIgnored() {
        var (editor, _) = make()
        editor.setText("x", for: UUID())
        editor.delete(UUID())
        XCTAssertFalse(editor.hasChanges)
    }
}

final class SpeakersTests: XCTestCase {
    func testNames() {
        XCTAssertEqual(Speakers.name(at: 0, in: ["Alex"]), "Alex")
        XCTAssertEqual(Speakers.name(at: 1, in: ["Alex"]), "Speaker 2")
        XCTAssertEqual(Speakers.name(at: 0, in: ["  "]), "Speaker 1")
        XCTAssertEqual(Speakers.initial(at: 0, in: ["alex"]), "A")
        XCTAssertEqual(Speakers.initial(at: 2, in: []), "S")
    }

    func testCount() {
        XCTAssertEqual(Speakers.count(names: [], segments: []), 0)
        XCTAssertEqual(Speakers.count(names: ["A", "B"], segments: []), 2)
        XCTAssertEqual(Speakers.count(names: ["A"], segments: [seg("x", 0, 1, speaker: 3)]), 4)
    }
}

// MARK: - Sections and text

@MainActor
final class DaySectionsTests: XCTestCase {
    private var container: ModelContainer!
    private let calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }()
    private let now = Date(timeIntervalSince1970: 1_761_400_000)   // 2025-10-25 14:26 UTC

    override func setUp() async throws { container = try MurmurSchema.makeContainer(inMemory: true) }
    override func tearDown() async throws { container = nil }

    private func note(_ title: String, hoursAgo: Double) -> Note {
        let n = Note(title: title, createdAt: now.addingTimeInterval(-hoursAgo * 3600))
        container.mainContext.insert(n)
        return n
    }

    func testGroupsTodayYesterdayAndOlder() {
        let notes = [note("a", hoursAgo: 1), note("b", hoursAgo: 3), note("c", hoursAgo: 20), note("d", hoursAgo: 24 * 5)]
        let sections = DaySections.make(from: notes, now: now, calendar: calendar)
        XCTAssertEqual(sections.map(\.title).prefix(2), ["Today", "Yesterday"])
        XCTAssertEqual(sections.count, 3)
        XCTAssertEqual(sections[0].notes.map(\.title), ["a", "b"], "newest first inside a day")
        XCTAssertEqual(sections[1].notes.map(\.title), ["c"])
        XCTAssertFalse(["Today", "Yesterday"].contains(sections[2].title))
    }

    func testEmpty() {
        XCTAssertTrue(DaySections.make(from: [], now: now, calendar: calendar).isEmpty)
    }

    func testSnippet() {
        let n = note("x", hoursAgo: 1)
        XCTAssertNil(NoteSummaryText.snippet(for: n))
        n.transcript = "Hello\nthere world."
        XCTAssertEqual(NoteSummaryText.snippet(for: n), "Hello there world.")
        n.transcript = String(repeating: "word ", count: 60)
        let s = NoteSummaryText.snippet(for: n)!
        XCTAssertTrue(s.hasSuffix("…"))
        XCTAssertLessThanOrEqual(s.count, 101)
    }

    func testMetaLine() {
        let n = note("x", hoursAgo: 1)
        n.segments = [seg("a", 0, 1, speaker: 0), seg("b", 1, 2, speaker: 1), seg("c", 2, 3, speaker: 1)]
        XCTAssertTrue(NoteSummaryText.metaLine(for: n).hasPrefix("2 speakers · "))
        let w = Note(title: "w", source: .watch)
        XCTAssertTrue(NoteSummaryText.metaLine(for: w).hasPrefix("From Apple Watch · "))
    }

    func testGreeting() {
        func at(_ hour: Int) -> Date { calendar.date(from: DateComponents(year: 2025, month: 10, day: 25, hour: hour))! }
        XCTAssertEqual(Greeting.text(at: at(8), calendar: calendar), "Good morning")
        XCTAssertEqual(Greeting.text(at: at(12), calendar: calendar), "Good afternoon")
        XCTAssertEqual(Greeting.text(at: at(19), calendar: calendar), "Good evening")
        XCTAssertEqual(Greeting.text(at: at(2), calendar: calendar), "Good evening")
    }

    func testFilterAndHeaderLine() {
        let folder = Folder(name: "Work")
        container.mainContext.insert(folder)
        let a = note("a", hoursAgo: 1)
        let b = note("b", hoursAgo: 2)
        a.folder = folder
        XCTAssertEqual(NoteFilter.filter([a, b], folderID: nil).count, 2)
        XCTAssertEqual(NoteFilter.filter([a, b], folderID: folder.id).map(\.title), ["a"])
        a.duration = 65
        a.segments = [seg("x", 0, 1, speaker: 0)]
        let line = NoteSummaryText.headerLine(for: a)
        XCTAssertTrue(line.contains("01:05"))
        XCTAssertTrue(line.hasSuffix("1 speaker"))
    }

    func testStatusText() {
        XCTAssertNil(NoteSummaryText.statusText(.ready))
        XCTAssertNotNil(NoteSummaryText.statusText(.failed))
    }
}

// MARK: - Library store

@MainActor
final class LibraryStoreTests: XCTestCase {
    private var container: ModelContainer!
    private var directory: URL!
    private var files: AudioFileStore!
    private var store: LibraryStore!

    override func setUp() async throws {
        container = try MurmurSchema.makeContainer(inMemory: true)
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("murmur-lib-\(UUID().uuidString)")
        files = AudioFileStore(directory: directory)
        try files.ensureDirectory()
        store = LibraryStore(context: container.mainContext, files: files)
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: directory)
        store = nil
        container = nil
    }

    private func makeNote(withAudio: Bool = false) -> Note {
        let name = files.newFileName()
        if withAudio { FileManager.default.createFile(atPath: files.url(for: name).path, contents: Data([1])) }
        let n = Note(title: "Old", audioFileName: name)
        container.mainContext.insert(n)
        return n
    }

    func testCreateFolder() {
        XCTAssertNil(store.createFolder(name: "   "))
        let a = store.createFolder(name: " Work ")!
        let b = store.createFolder(name: "Ideas")!
        XCTAssertEqual(a.name, "Work")
        XCTAssertEqual(a.sortOrder, 0)
        XCTAssertEqual(b.sortOrder, 1)
        XCTAssertEqual(b.colorIndex, 1)
    }

    func testRenameIgnoresBlank() {
        let n = makeNote()
        store.rename(n, to: "  ")
        XCTAssertEqual(n.title, "Old")
        store.rename(n, to: " New title ")
        XCTAssertEqual(n.title, "New title")
    }

    func testMoveAndDeleteFolderKeepsNote() {
        let n = makeNote()
        let folder = store.createFolder(name: "Work")!
        store.move(n, to: folder)
        XCTAssertEqual(n.folder?.id, folder.id)
        store.deleteFolder(folder)
        XCTAssertNil(n.folder)
        store.move(n, to: nil)
        XCTAssertNil(n.folder)
    }

    func testDeleteRemovesAudio() {
        let n = makeNote(withAudio: true)
        let name = n.audioFileName!
        XCTAssertTrue(files.exists(name))
        store.delete(n)
        XCTAssertFalse(files.exists(name))
        XCTAssertTrue((try! container.mainContext.fetch(FetchDescriptor<Note>())).isEmpty)
    }

    func testApplyEditUpdatesTranscript() {
        let n = makeNote()
        store.applyEdit([seg("One.", 0, 1), seg("Two.", 1, 2)], to: n)
        XCTAssertEqual(n.segments.count, 2)
        XCTAssertEqual(n.transcript, "One.\nTwo.")
    }

    func testSpeakers() {
        let n = makeNote()
        n.segments = [seg("x", 0, 1, speaker: 1)]
        let index = store.addSpeaker(named: " Priya ", to: n)
        XCTAssertEqual(index, 2, "speakers 0 and 1 already exist implicitly")
        XCTAssertEqual(n.speakerNames, ["", "", "Priya"])
        store.renameSpeaker(at: 0, to: "Alex", in: n)
        XCTAssertEqual(Speakers.name(at: 0, in: n.speakerNames), "Alex")
        XCTAssertEqual(Speakers.name(at: 1, in: n.speakerNames), "Speaker 2")
    }
}

// MARK: - Playback

@MainActor
private final class FakePlayer: PlayerEngine {
    var duration: TimeInterval = 100
    var currentTime: TimeInterval = 0
    var isPlaying = false
    var rate: Float = 1
    var loadError: Error?
    private(set) var loadedURL: URL?

    func load(url: URL) throws {
        if let loadError { throw loadError }
        loadedURL = url
    }
    func play() { isPlaying = true }
    func pause() { isPlaying = false }
}

@MainActor
final class PlaybackControllerTests: XCTestCase {
    private let segments = [seg("a", 0, 10), seg("b", 10, 20), seg("c", 20, 30)]

    private func make(_ player: FakePlayer = FakePlayer()) -> (PlaybackController, FakePlayer) {
        let controller = PlaybackController(engine: player, segments: segments, autoTick: false)
        controller.load(url: URL(fileURLWithPath: "/tmp/x.caf"))
        return (controller, player)
    }

    func testLoadSetsDuration() {
        let (c, p) = make()
        XCTAssertEqual(c.duration, 100)
        XCTAssertEqual(p.loadedURL?.lastPathComponent, "x.caf")
        XCTAssertNil(c.loadError)
    }

    func testLoadFailureDisablesPlayback() {
        let p = FakePlayer()
        p.loadError = NSError(domain: "x", code: 1)
        let c = PlaybackController(engine: p, autoTick: false)
        c.load(url: URL(fileURLWithPath: "/nope"), fallbackDuration: 42)
        XCTAssertNotNil(c.loadError)
        XCTAssertEqual(c.duration, 42)
        c.toggle()
        XCTAssertFalse(p.isPlaying)
    }

    func testToggleAndTick() {
        let (c, p) = make()
        c.toggle()
        XCTAssertTrue(c.isPlaying)
        p.currentTime = 12
        c.tick()
        XCTAssertEqual(c.currentTime, 12)
        XCTAssertEqual(c.playingIndex, 1)
        XCTAssertEqual(c.progress, 0.12, accuracy: 1e-9)
        c.toggle()
        XCTAssertFalse(c.isPlaying)
    }

    func testSeekClampsAndSkips() {
        let (c, _) = make()
        c.seek(to: -5)
        XCTAssertEqual(c.currentTime, 0)
        c.seek(to: 500)
        XCTAssertEqual(c.currentTime, 100)
        c.seek(to: 50)
        c.skip(by: -PlaybackController.skipSeconds)
        XCTAssertEqual(c.currentTime, 35)
        c.skip(by: PlaybackController.skipSeconds)
        XCTAssertEqual(c.currentTime, 50)
        c.seek(toFraction: 0.25)
        XCTAssertEqual(c.currentTime, 25)
    }

    func testPlaySegmentSeeksAndPlays() {
        let (c, p) = make()
        c.play(segment: segments[2])
        XCTAssertEqual(p.currentTime, 20)
        XCTAssertTrue(c.isPlaying)
        c.play(segment: segments[1])
        XCTAssertEqual(p.currentTime, 10)
        XCTAssertTrue(c.isPlaying, "stays playing when jumping between lines")
    }

    func testSpeedCycles() {
        let (c, p) = make()
        XCTAssertEqual(c.speedLabel, "1×")
        c.cycleSpeed(); XCTAssertEqual(c.speedLabel, "1.5×"); XCTAssertEqual(p.rate, 1.5)
        c.cycleSpeed(); XCTAssertEqual(c.speedLabel, "2×")
        c.cycleSpeed(); XCTAssertEqual(c.speedLabel, "1×")
    }

    func testPlayingFromTheEndRestarts() {
        let (c, p) = make()
        p.currentTime = 100
        c.toggle()
        XCTAssertEqual(p.currentTime, 0)
        XCTAssertTrue(c.isPlaying)
    }

    func testNoPlayingLineBeforeFirstSegment() {
        let c = PlaybackController(engine: FakePlayer(), segments: [seg("a", 5, 9)], autoTick: false)
        XCTAssertNil(c.playingIndex)
    }

    func testDemoEngineAdvances() {
        let d = DemoPlayerEngine(duration: 10)
        d.play()
        d.rate = 2
        d.advance(by: 3)
        XCTAssertEqual(d.currentTime, 6)
        d.advance(by: 10)
        XCTAssertEqual(d.currentTime, 10)
        XCTAssertFalse(d.isPlaying)
    }
}
