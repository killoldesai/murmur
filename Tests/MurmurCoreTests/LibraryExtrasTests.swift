import XCTest
import SwiftData
@testable import MurmurCore

final class FolderTextTests: XCTestCase {
    func testDuration() {
        XCTAssertEqual(FolderOverview.duration(0), "0m")
        XCTAssertEqual(FolderOverview.duration(30), "under 1m")
        XCTAssertEqual(FolderOverview.duration(4 * 60 + 20), "4m")
        XCTAssertEqual(FolderOverview.duration(5 * 3600 + 12 * 60), "5h 12m")
        XCTAssertEqual(FolderOverview.duration(3600 + 5 * 60), "1h 05m")
    }

    func testMeta() {
        XCTAssertEqual(FolderOverview.meta(count: 0, seconds: 0), "Empty")
        XCTAssertEqual(FolderOverview.meta(count: 1, seconds: 240), "1 note · 4m")
        XCTAssertEqual(FolderOverview.meta(count: 8, seconds: 5 * 3600 + 720), "8 notes · 5h 12m")
    }

    func testSubtitle() {
        XCTAssertEqual(FolderOverview.subtitle(folderCount: 1, noteCount: 1), "1 folder · 1 note")
        XCTAssertEqual(FolderOverview.subtitle(folderCount: 6, noteCount: 21), "6 folders · 21 notes")
    }

    func testWatchBannerText() {
        XCTAssertEqual(WatchBanner.text(count: 1), "1 new recording from your Apple Watch")
        XCTAssertEqual(WatchBanner.text(count: 3), "3 new recordings from your Apple Watch")
    }
}

final class SwipeRevealTests: XCTestCase {
    func testOffsetFollowsFingerAndStopsAtClosed() {
        XCTAssertEqual(SwipeReveal.offset(revealed: false, translation: -40, buttonWidth: 84), -40)
        XCTAssertEqual(SwipeReveal.offset(revealed: false, translation: 50, buttonWidth: 84), 0, "no slide to the right")
        XCTAssertEqual(SwipeReveal.offset(revealed: true, translation: 30, buttonWidth: 84), -54)
        XCTAssertEqual(SwipeReveal.offset(revealed: true, translation: 200, buttonWidth: 84), 0)
    }

    func testOffsetResistsPastFullyOpen() {
        let value = SwipeReveal.offset(revealed: false, translation: -184, buttonWidth: 84)
        XCTAssertLessThan(value, -84)
        XCTAssertGreaterThan(value, -184, "moves less than the finger")
    }

    func testSettle() {
        XCTAssertTrue(SwipeReveal.settle(revealed: false, predictedEnd: -90, buttonWidth: 84))
        XCTAssertFalse(SwipeReveal.settle(revealed: false, predictedEnd: -25, buttonWidth: 84))
        XCTAssertFalse(SwipeReveal.settle(revealed: true, predictedEnd: 80, buttonWidth: 84))
        XCTAssertTrue(SwipeReveal.settle(revealed: true, predictedEnd: 10, buttonWidth: 84))
    }
}

@MainActor
final class LibraryExtrasTests: XCTestCase {
    private var container: ModelContainer!
    private var directory: URL!
    private var files: AudioFileStore!
    private var defaults: UserDefaults!
    private var suite = ""

    override func setUp() async throws {
        container = try MurmurSchema.makeContainer(inMemory: true)
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("murmur-extras-\(UUID().uuidString)")
        files = AudioFileStore(directory: directory)
        try files.ensureDirectory()
        suite = "murmur-extras-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suite)
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: directory)
        defaults.removePersistentDomain(forName: suite)
        container = nil
    }

    private var context: ModelContext { container.mainContext }

    func testFolderCards() throws {
        let work = Folder(name: "Work", colorIndex: 0, sortOrder: 1)
        let ideas = Folder(name: "Ideas", colorIndex: 1, sortOrder: 0)
        context.insert(work)
        context.insert(ideas)
        let a = Note(title: "a", duration: 600)
        let b = Note(title: "b", duration: 1200)
        let c = Note(title: "c", duration: 60, source: .watch)
        [a, b, c].forEach(context.insert)
        a.folder = work
        b.folder = work
        let cards = FolderOverview.cards(folders: [work, ideas], notes: [a, b, c])
        XCTAssertEqual(cards.map(\.name), ["Ideas", "Work", "From Watch"], "saved order, then the smart folder")
        XCTAssertEqual(cards[0].meta, "Empty")
        XCTAssertEqual(cards[1].meta, "2 notes · 30m")
        XCTAssertEqual(cards[2].kind, .fromWatch)
        XCTAssertEqual(cards[1].id, work.id.uuidString)
    }

    func testNoWatchCardWithoutWatchNotes() {
        let n = Note(title: "x")
        context.insert(n)
        XCTAssertTrue(FolderOverview.cards(folders: [], notes: [n]).isEmpty)
    }

    func testRenameFolder() {
        let store = LibraryStore(context: context, files: files)
        let folder = store.createFolder(name: "Old")!
        store.renameFolder(folder, to: "  New name ")
        XCTAssertEqual(folder.name, "New name")
        store.renameFolder(folder, to: "   ")
        XCTAssertEqual(folder.name, "New name", "blank names are ignored")
    }

    func testAudioFormatAndWatchCounterPersist() {
        let settings = AppSettings(defaults: defaults)
        XCTAssertEqual(settings.audioFormat, .m4a, "M4A is the default, as in the design")
        settings.setAudioFormat(.original)
        XCTAssertEqual(AppSettings(defaults: defaults).audioFormat, .original)
        XCTAssertEqual(settings.newWatchRecordings, 0)
        settings.noteWatchRecordingReceived()
        settings.noteWatchRecordingReceived()
        XCTAssertEqual(AppSettings(defaults: defaults).newWatchRecordings, 2)
        settings.clearNewWatchRecordings()
        XCTAssertEqual(AppSettings(defaults: defaults).newWatchRecordings, 0)
    }

    // MARK: M4A conversion after transcribing

    private final class OneLineEngine: TranscriptionEngine, @unchecked Sendable {
        func transcribe(audioURL: URL, duration: TimeInterval, options: TranscriptionOptions,
                        onProgress: @escaping @Sendable (TranscriptionProgressUpdate) -> Void) async throws -> TranscriptionOutput {
            TranscriptionOutput(segments: [TranscriptSegment(start: 0, end: 1, text: "Hi.")], language: "en")
        }
    }

    private struct Boom: Error {}

    private final class Flag: @unchecked Sendable { var raised = false }

    private func queuedNote() -> Note {
        let name = files.newFileName()
        FileManager.default.createFile(atPath: files.url(for: name).path, contents: Data(repeating: 7, count: 400))
        let note = Note(title: "n", duration: 5, audioFileName: name, source: .recording, status: .queued)
        context.insert(note)
        try! context.save()
        return note
    }

    private func queue(format: AudioFormat, compactor: (@Sendable (URL, URL) async throws -> Void)?) -> TranscriptionQueue {
        let settings = AppSettings(defaults: defaults)
        settings.setAudioFormat(format)
        let queue = TranscriptionQueue(context: context, files: files, engineProvider: { OneLineEngine() })
        queue.settings = settings
        queue.audioCompactor = compactor
        return queue
    }

    func testAudioIsReplacedByM4A() async {
        let note = queuedNote()
        let original = note.audioFileName!
        let q = queue(format: .m4a) { _, destination in
            FileManager.default.createFile(atPath: destination.path, contents: Data(repeating: 1, count: 40))
        }
        await q.processQueued()
        XCTAssertEqual(note.status, .ready)
        XCTAssertTrue(note.audioFileName!.hasSuffix(".m4a"))
        XCTAssertTrue(files.exists(note.audioFileName!))
        XCTAssertFalse(files.exists(original), "the large original is removed")
    }

    func testFailedConversionKeepsOriginalAudio() async {
        let note = queuedNote()
        let original = note.audioFileName!
        let q = queue(format: .m4a) { _, _ in throw Boom() }
        await q.processQueued()
        XCTAssertEqual(note.status, .ready)
        XCTAssertEqual(note.audioFileName, original)
        XCTAssertTrue(files.exists(original))
        XCTAssertEqual(files.allFiles().count, 1, "no half-written m4a left behind")
    }

    func testEmptyConversionOutputKeepsOriginalAudio() async {
        let note = queuedNote()
        let original = note.audioFileName!
        let q = queue(format: .m4a) { _, destination in
            FileManager.default.createFile(atPath: destination.path, contents: Data())
        }
        await q.processQueued()
        XCTAssertEqual(note.audioFileName, original)
        XCTAssertEqual(files.allFiles().count, 1)
    }

    func testOriginalFormatIsLeftAlone() async {
        let note = queuedNote()
        let original = note.audioFileName!
        let flag = Flag()
        let q = queue(format: .original) { _, _ in flag.raised = true }
        await q.processQueued()
        XCTAssertEqual(note.audioFileName, original)
        XCTAssertFalse(flag.raised)
    }
}
