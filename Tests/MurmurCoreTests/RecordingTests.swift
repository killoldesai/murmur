import XCTest
import SwiftData
@testable import MurmurCore

// MARK: - Test doubles

@MainActor
private final class FakeEngine: RecorderEngine {
    var onInterruption: (@MainActor (Bool) -> Void)?
    var permission = true
    var startError: Error?
    var decibels: Float = -160

    private(set) var startedURL: URL?
    private(set) var pauseCount = 0
    private(set) var resumeCount = 0
    private(set) var stopCount = 0

    func requestPermission() async -> Bool { permission }

    func start(fileURL: URL) throws {
        if let startError { throw startError }
        startedURL = fileURL
        // Behave like the real recorder: the file exists once recording starts.
        FileManager.default.createFile(atPath: fileURL.path, contents: Data([0, 1, 2]))
    }

    func pause() { pauseCount += 1 }
    func resume() { resumeCount += 1 }
    func stop() { stopCount += 1 }
    func averagePowerDecibels() -> Float { decibels }
}

private final class TestClock: @unchecked Sendable {
    var date = Date(timeIntervalSinceReferenceDate: 1_000_000)
    func advance(_ seconds: TimeInterval) { date = date.addingTimeInterval(seconds) }
}

// MARK: - Pure logic

final class MeterLevelTests: XCTestCase {
    func testMapping() {
        XCTAssertEqual(MeterLevel.normalized(decibels: -50), 0)
        XCTAssertEqual(MeterLevel.normalized(decibels: -160), 0)
        XCTAssertEqual(MeterLevel.normalized(decibels: 0), 1)
        XCTAssertEqual(MeterLevel.normalized(decibels: 6), 1)
        XCTAssertEqual(MeterLevel.normalized(decibels: -25), 0.5, accuracy: 1e-6)
    }

    func testBadInputIsZero() {
        XCTAssertEqual(MeterLevel.normalized(decibels: .nan), 0)
        XCTAssertEqual(MeterLevel.normalized(decibels: -.infinity), 0)
    }
}

final class RecordingTimelineTests: XCTestCase {
    func testElapsedAcrossPauses() {
        let t0 = Date(timeIntervalSinceReferenceDate: 0)
        var timeline = RecordingTimeline()
        XCTAssertEqual(timeline.elapsed(at: t0), 0)
        timeline.start(at: t0)
        XCTAssertEqual(timeline.elapsed(at: t0.addingTimeInterval(10)), 10, accuracy: 1e-9)
        timeline.pause(at: t0.addingTimeInterval(10))
        XCTAssertEqual(timeline.elapsed(at: t0.addingTimeInterval(500)), 10, accuracy: 1e-9)
        timeline.resume(at: t0.addingTimeInterval(500))
        XCTAssertEqual(timeline.elapsed(at: t0.addingTimeInterval(503)), 13, accuracy: 1e-9)
    }

    func testStartAndPauseAreIdempotent() {
        let t0 = Date(timeIntervalSinceReferenceDate: 0)
        var timeline = RecordingTimeline()
        timeline.pause(at: t0)                      // pausing before start does nothing
        timeline.start(at: t0)
        timeline.start(at: t0.addingTimeInterval(5)) // second start must not reset the clock
        XCTAssertEqual(timeline.elapsed(at: t0.addingTimeInterval(8)), 8, accuracy: 1e-9)
    }

    func testBookmarks() {
        let t0 = Date(timeIntervalSinceReferenceDate: 0)
        var timeline = RecordingTimeline()
        timeline.start(at: t0)
        XCTAssertEqual(timeline.addBookmark(at: t0.addingTimeInterval(4)), 4, accuracy: 1e-9)
        timeline.pause(at: t0.addingTimeInterval(6))
        timeline.addBookmark(at: t0.addingTimeInterval(60))   // while paused: stays at 6
        XCTAssertEqual(timeline.bookmarks.count, 2)
        XCTAssertEqual(timeline.bookmarks[1], 6, accuracy: 1e-9)
    }
}

final class AudioFileStoreTests: XCTestCase {
    func testNamesAndURLs() {
        let dir = URL(fileURLWithPath: "/tmp/murmur-test", isDirectory: true)
        let store = AudioFileStore(directory: dir)
        let id = UUID()
        let name = store.newFileName(id: id)
        XCTAssertEqual(name, id.uuidString.lowercased() + ".caf")
        XCTAssertEqual(store.url(for: name).deletingLastPathComponent().path, dir.path)
    }

    func testCreateExistsDelete() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let store = AudioFileStore(directory: dir)
        try store.ensureDirectory()
        XCTAssertFalse(store.exists("a.caf"))
        FileManager.default.createFile(atPath: store.url(for: "a.caf").path, contents: Data([1]))
        XCTAssertTrue(store.exists("a.caf"))
        store.delete("a.caf")
        XCTAssertFalse(store.exists("a.caf"))
        try? FileManager.default.removeItem(at: dir)
    }
}

// MARK: - Controller and store

@MainActor
final class RecordingControllerTests: XCTestCase {
    private var container: ModelContainer?
    private var dir: URL?

    override func tearDown() async throws {
        if let dir { try? FileManager.default.removeItem(at: dir) }
        container = nil
        dir = nil
    }

    private struct Rig {
        let controller: RecordingController
        let engine: FakeEngine
        let clock: TestClock
        let context: ModelContext
        let files: AudioFileStore
        let store: RecordingNoteStore
    }

    private func makeRig() throws -> Rig {
        let container = try MurmurSchema.makeContainer(inMemory: true)
        self.container = container
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        self.dir = dir
        let files = AudioFileStore(directory: dir)
        let store = RecordingNoteStore(context: container.mainContext, files: files)
        let engine = FakeEngine()
        let clock = TestClock()
        let controller = RecordingController(engine: engine, store: store, files: files,
                                             now: { clock.date }, autoTick: false)
        return Rig(controller: controller, engine: engine, clock: clock,
                   context: container.mainContext, files: files, store: store)
    }

    private func notes(_ rig: Rig) throws -> [Note] {
        try rig.context.fetch(FetchDescriptor<Note>())
    }

    func testStartCreatesNoteAndStartsEngine() async throws {
        let rig = try makeRig()
        await rig.controller.start()
        XCTAssertEqual(rig.controller.state, .recording)
        XCTAssertNotNil(rig.engine.startedURL)
        let all = try notes(rig)
        XCTAssertEqual(all.count, 1)
        XCTAssertEqual(all[0].status, .recording)
        XCTAssertTrue(all[0].audioFileName?.hasSuffix(".caf") == true)
        XCTAssertTrue(all[0].title.hasPrefix("Recording"))
    }

    func testPermissionDeniedFailsWithoutCreatingNote() async throws {
        let rig = try makeRig()
        rig.engine.permission = false
        await rig.controller.start()
        guard case .failed(let message) = rig.controller.state else {
            return XCTFail("Expected .failed, got \(rig.controller.state)")
        }
        XCTAssertTrue(message.contains("microphone"))
        XCTAssertEqual(try notes(rig).count, 0)
    }

    func testEngineFailureDiscardsTheNote() async throws {
        let rig = try makeRig()
        rig.engine.startError = RecorderError.couldNotStart("boom")
        await rig.controller.start()
        if case .failed = rig.controller.state {} else { XCTFail("Expected .failed") }
        XCTAssertEqual(try notes(rig).count, 0)
    }

    func testElapsedSkipsPausedTime() async throws {
        let rig = try makeRig()
        await rig.controller.start()
        rig.clock.advance(10)
        rig.controller.tick()
        XCTAssertEqual(rig.controller.elapsed, 10, accuracy: 1e-9)

        rig.controller.pause()
        XCTAssertEqual(rig.controller.state, .paused)
        XCTAssertEqual(rig.engine.pauseCount, 1)
        rig.clock.advance(5)
        rig.controller.tick()                       // ignored while paused
        XCTAssertEqual(rig.controller.elapsed, 10, accuracy: 1e-9)

        rig.controller.resume()
        XCTAssertEqual(rig.engine.resumeCount, 1)
        rig.clock.advance(3)
        rig.controller.tick()
        XCTAssertEqual(rig.controller.elapsed, 13, accuracy: 1e-9)
    }

    func testLevelsStayFixedLengthAndFollowTheMic() async throws {
        let rig = try makeRig()
        await rig.controller.start()
        rig.engine.decibels = -25
        for _ in 0..<50 { rig.controller.tick() }
        XCTAssertEqual(rig.controller.levels.count, RecordingController.levelCount)
        XCTAssertEqual(rig.controller.levels.last ?? -1, 0.5, accuracy: 1e-6)
        rig.engine.decibels = -160
        rig.controller.tick()
        XCTAssertEqual(rig.controller.levels.last ?? -1, 0, accuracy: 1e-9)
    }

    func testBookmarksAreSavedImmediately() async throws {
        let rig = try makeRig()
        await rig.controller.start()
        rig.clock.advance(4)
        rig.controller.addBookmark()
        rig.clock.advance(6)
        rig.controller.addBookmark()
        XCTAssertEqual(rig.controller.bookmarkCount, 2)
        XCTAssertEqual(rig.controller.bookmarks.count, 2)
        XCTAssertEqual(rig.controller.bookmarks[1], 10, accuracy: 1e-9)
        let note = try XCTUnwrap(try notes(rig).first)
        XCTAssertEqual(note.bookmarks.count, 2)
        XCTAssertEqual(note.bookmarks[0], 4, accuracy: 1e-9)
        XCTAssertEqual(note.bookmarks[1], 10, accuracy: 1e-9)
    }

    func testStopQueuesNoteWithDuration() async throws {
        let rig = try makeRig()
        await rig.controller.start()
        rig.clock.advance(12)
        rig.controller.addBookmark()
        rig.clock.advance(1)
        let note = try XCTUnwrap(rig.controller.stop())
        XCTAssertEqual(rig.controller.state, .finished)
        XCTAssertEqual(rig.engine.stopCount, 1)
        XCTAssertEqual(note.status, .queued)
        XCTAssertEqual(note.duration, 13, accuracy: 1e-9)
        XCTAssertEqual(note.bookmarks, [12])
        XCTAssertTrue(rig.files.exists(try XCTUnwrap(note.audioFileName)))
    }

    func testStopBeforeStartDoesNothing() throws {
        let rig = try makeRig()
        XCTAssertNil(rig.controller.stop())
        XCTAssertEqual(rig.controller.state, .idle)
    }

    func testCancelDeletesNoteAndAudio() async throws {
        let rig = try makeRig()
        await rig.controller.start()
        let name = try XCTUnwrap(try notes(rig).first?.audioFileName)
        XCTAssertTrue(rig.files.exists(name))
        rig.controller.cancel()
        XCTAssertEqual(rig.controller.state, .idle)
        XCTAssertEqual(try notes(rig).count, 0)
        XCTAssertFalse(rig.files.exists(name))
        XCTAssertEqual(rig.engine.stopCount, 1)
    }

    func testInterruptionPauses() async throws {
        let rig = try makeRig()
        await rig.controller.start()
        rig.engine.onInterruption?(true)
        XCTAssertEqual(rig.controller.state, .paused)
        rig.engine.onInterruption?(false)           // ending an interruption must not auto-resume
        XCTAssertEqual(rig.controller.state, .paused)
    }

    func testRecoveryQueuesNotesWithAudioAndFailsOnesWithout() async throws {
        let rig = try makeRig()

        // A recording that was killed mid-way: note says .recording, audio file exists.
        await rig.controller.start()
        let survivor = try XCTUnwrap(try notes(rig).first)
        XCTAssertEqual(survivor.status, .recording)

        // Another whose audio never reached disk.
        let lost = try rig.store.beginNote()
        XCTAssertEqual(lost.status, .recording)

        // A finished note must be left alone.
        let done = Note(title: "Done", status: .ready)
        rig.context.insert(done)
        try rig.context.save()

        let recovered = try rig.store.recoverInterruptedRecordings()
        XCTAssertEqual(recovered, 1)
        XCTAssertEqual(survivor.status, .queued)
        XCTAssertEqual(lost.status, .failed)
        XCTAssertEqual(done.status, .ready)
    }
}
