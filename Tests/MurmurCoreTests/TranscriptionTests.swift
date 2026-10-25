import XCTest
import SwiftData
@testable import MurmurCore

// MARK: - Test doubles

private final class FakeDownloader: SpeechModelDownloader, @unchecked Sendable {
    let base: URL
    var delay: TimeInterval = 0
    var error: Error?
    private(set) var callCount = 0

    init(base: URL) { self.base = base }

    func download(_ model: SpeechModel, onProgress: @escaping @Sendable (Double) -> Void) async throws -> URL {
        callCount += 1
        onProgress(0.5)
        if delay > 0 { try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000)) }
        if let error { throw error }
        let folder = base.appendingPathComponent("models/\(model.variant)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        onProgress(1)
        return folder
    }
}

private final class FakeTranscriber: TranscriptionEngine, @unchecked Sendable {
    var result: Result<TranscriptionOutput, Error> = .success(
        TranscriptionOutput(segments: [
            TranscriptSegment(start: 0, end: 2, text: "Hello there."),
            TranscriptSegment(start: 2, end: 5, text: "This is a test."),
        ], language: "en")
    )
    private(set) var receivedOptions: [TranscriptionOptions] = []
    private(set) var receivedURLs: [URL] = []

    func transcribe(
        audioURL: URL,
        duration: TimeInterval,
        options: TranscriptionOptions,
        onProgress: @escaping @Sendable (TranscriptionProgressUpdate) -> Void
    ) async throws -> TranscriptionOutput {
        receivedOptions.append(options)
        receivedURLs.append(audioURL)
        onProgress(TranscriptionProgressUpdate(fraction: 0.5, segments: []))
        return try result.get()
    }
}

private struct Boom: LocalizedError {
    var errorDescription: String? { "boom" }
}

@MainActor
private func waitUntil(_ timeout: TimeInterval = 3, _ condition: @MainActor () -> Bool) async -> Bool {
    let deadline = Date().addingTimeInterval(timeout)
    while Date() < deadline {
        if condition() { return true }
        try? await Task.sleep(nanoseconds: 10_000_000)
    }
    return condition()
}

// MARK: - Pure helpers

final class SpeechModelTests: XCTestCase {
    func testChoicesAndLookup() {
        XCTAssertEqual(SpeechModel.choices.map(\.id), ["large", "small"])
        XCTAssertTrue(SpeechModel.large.isRecommended)
        XCTAssertFalse(SpeechModel.small.isRecommended)
        XCTAssertEqual(SpeechModel.model(withID: "small"), .small)
        XCTAssertNil(SpeechModel.model(withID: "nope"))
    }

    func testByteText() {
        XCTAssertEqual(ByteText.format(632_000_000), "632 MB")
        XCTAssertEqual(ByteText.format(1_600_000_000), "1.60 GB")
        XCTAssertEqual(ByteText.format(80_000_000), "80 MB")
        XCTAssertEqual(ByteText.format(-5), "0 MB")
    }

    func testETA() {
        let t0 = Date(timeIntervalSinceReferenceDate: 0)
        let eta = ETAEstimator(start: t0)
        XCTAssertNil(eta.remaining(fraction: 0.01, at: t0.addingTimeInterval(5)))
        XCTAssertEqual(eta.remaining(fraction: 0.5, at: t0.addingTimeInterval(10))!, 10, accuracy: 1e-6)
        XCTAssertEqual(eta.remaining(fraction: 1, at: t0.addingTimeInterval(10)), 0)
    }

    func testETAText() {
        XCTAssertEqual(ETAEstimator.text(for: nil), "Estimating…")
        XCTAssertEqual(ETAEstimator.text(for: 0.2), "Almost done")
        XCTAssertEqual(ETAEstimator.text(for: 12), "About 12s left")
        XCTAssertEqual(ETAEstimator.text(for: 61), "About 2 min left")
    }
}

// MARK: - Model manager

@MainActor
final class SpeechModelManagerTests: XCTestCase {
    private var base: URL!
    private var defaults: UserDefaults!
    private var suite: String!

    override func setUp() async throws {
        base = FileManager.default.temporaryDirectory.appendingPathComponent("murmur-models-\(UUID().uuidString)")
        suite = "murmur-tests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suite)
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: base)
        defaults.removePersistentDomain(forName: suite)
    }

    private func makeManager(_ downloader: FakeDownloader, expensive: Bool = false) -> SpeechModelManager {
        SpeechModelManager(
            downloader: downloader, baseDirectory: base, defaults: defaults,
            isOnExpensiveNetwork: { expensive }
        )
    }

    func testDefaults() {
        let manager = makeManager(FakeDownloader(base: base))
        XCTAssertEqual(manager.selected, .large)
        XCTAssertTrue(manager.wifiOnly)
        XCTAssertEqual(manager.state, .notDownloaded)
        XCTAssertNil(manager.readyFolder)
    }

    func testDownloadBecomesReady() async {
        let manager = makeManager(FakeDownloader(base: base))
        manager.start()
        XCTAssertTrue(manager.isDownloading)
        let ok = await waitUntil { manager.isReady }
        XCTAssertTrue(ok)
        XCTAssertNotNil(manager.readyFolder)
    }

    func testReadyStatePersistsAcrossLaunches() async {
        let first = makeManager(FakeDownloader(base: base))
        first.start()
        _ = await waitUntil { first.isReady }
        let second = makeManager(FakeDownloader(base: base))
        XCTAssertEqual(second.state, .ready)
        XCTAssertEqual(second.readyFolder?.resolvingSymlinksInPath(), first.readyFolder?.resolvingSymlinksInPath())
    }

    func testWifiOnlyBlocksMobileData() {
        let downloader = FakeDownloader(base: base)
        let manager = makeManager(downloader, expensive: true)
        manager.start()
        if case .failed = manager.state {} else { XCTFail("expected failure, got \(manager.state)") }
        XCTAssertEqual(downloader.callCount, 0)
    }

    func testMobileDataAllowedWhenToggleOff() async {
        let downloader = FakeDownloader(base: base)
        let manager = makeManager(downloader, expensive: true)
        manager.wifiOnly = false
        manager.start()
        let ok = await waitUntil { manager.isReady }
        XCTAssertTrue(ok)
        XCTAssertFalse(defaults.bool(forKey: "model.wifiOnly"))
    }

    func testFailureShowsMessageAndCanRetry() async {
        let downloader = FakeDownloader(base: base)
        downloader.error = Boom()
        let manager = makeManager(downloader)
        manager.start()
        let failed = await waitUntil { if case .failed = manager.state { return true } else { return false } }
        XCTAssertTrue(failed)
        downloader.error = nil
        manager.start()
        let ok = await waitUntil { manager.isReady }
        XCTAssertTrue(ok)
    }

    func testCancelIgnoresLateResult() async {
        let downloader = FakeDownloader(base: base)
        downloader.delay = 0.2
        let manager = makeManager(downloader)
        manager.start()
        manager.cancel()
        XCTAssertEqual(manager.state, .notDownloaded)
        try? await Task.sleep(nanoseconds: 450_000_000)
        XCTAssertEqual(manager.state, .notDownloaded)
        XCTAssertNil(defaults.string(forKey: "model.folder.large"))
    }

    func testSelectionPersistsAndIsBlockedWhileDownloading() async {
        let downloader = FakeDownloader(base: base)
        downloader.delay = 0.2
        let manager = makeManager(downloader)
        manager.select(.small)
        XCTAssertEqual(makeManager(downloader).selected, .small)
        manager.start()
        manager.select(.large)
        XCTAssertEqual(manager.selected, .small)
        manager.cancel()
    }

    func testDeleteRemovesModel() async {
        let manager = makeManager(FakeDownloader(base: base))
        manager.start()
        _ = await waitUntil { manager.isReady }
        let folder = manager.readyFolder!
        manager.deleteSelected()
        XCTAssertEqual(manager.state, .notDownloaded)
        XCTAssertFalse(FileManager.default.fileExists(atPath: folder.path))
    }
}

// MARK: - Transcription queue

@MainActor
final class TranscriptionQueueTests: XCTestCase {
    private var container: ModelContainer!
    private var files: AudioFileStore!
    private var directory: URL!

    override func setUp() async throws {
        container = try MurmurSchema.makeContainer(inMemory: true)
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("murmur-queue-\(UUID().uuidString)")
        files = AudioFileStore(directory: directory)
        try files.ensureDirectory()
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: directory)
        container = nil
    }

    private var context: ModelContext { container.mainContext }

    @discardableResult
    private func addNote(title: String = "Note", status: NoteStatus = .queued, withAudio: Bool = true, age: TimeInterval = 0) -> Note {
        let name = files.newFileName()
        if withAudio { FileManager.default.createFile(atPath: files.url(for: name).path, contents: Data([1, 2, 3])) }
        let note = Note(
            title: title,
            createdAt: Date(timeIntervalSinceNow: -age),
            duration: 5,
            audioFileName: name,
            source: .recording,
            status: status
        )
        context.insert(note)
        try! context.save()
        return note
    }

    private func makeQueue(_ engine: TranscriptionEngine?) -> TranscriptionQueue {
        TranscriptionQueue(context: context, files: files, engineProvider: { engine })
    }

    func testQueuedNoteBecomesReady() async {
        let note = addNote()
        let engine = FakeTranscriber()
        let queue = makeQueue(engine)
        await queue.processQueued()
        XCTAssertEqual(note.status, .ready)
        XCTAssertEqual(note.segments.count, 2)
        XCTAssertEqual(note.transcript, "Hello there.\nThis is a test.")
        XCTAssertEqual(note.language, "en")
        XCTAssertEqual(queue.fraction, 1)
        XCTAssertNil(queue.currentNoteID)
        XCTAssertEqual(engine.receivedURLs.first, files.url(for: note.audioFileName!))
    }

    func testWithoutEngineNotesStayQueued() async {
        let note = addNote()
        await makeQueue(nil).processQueued()
        XCTAssertEqual(note.status, .queued)
    }

    func testEngineFailureMarksFailed() async {
        let note = addNote()
        let engine = FakeTranscriber()
        engine.result = .failure(Boom())
        let queue = makeQueue(engine)
        await queue.processQueued()
        XCTAssertEqual(note.status, .failed)
        XCTAssertEqual(queue.lastFailure, "boom")
    }

    func testMissingAudioMarksFailed() async {
        let note = addNote(withAudio: false)
        await makeQueue(FakeTranscriber()).processQueued()
        XCTAssertEqual(note.status, .failed)
    }

    func testCancellationReturnsNoteToQueueAndStops() async {
        let first = addNote(title: "A", age: 20)
        let second = addNote(title: "B", age: 10)
        let engine = FakeTranscriber()
        engine.result = .failure(CancellationError())
        await makeQueue(engine).processQueued()
        XCTAssertEqual(first.status, .queued)
        XCTAssertEqual(second.status, .queued)
        XCTAssertEqual(engine.receivedURLs.count, 1, "queue stops after a cancellation")
    }

    func testOldestFirstAndOnlyQueuedNotes() async {
        let old = addNote(title: "old", age: 100)
        let new = addNote(title: "new", age: 10)
        let done = addNote(title: "done", status: .ready, age: 200)
        let engine = FakeTranscriber()
        await makeQueue(engine).processQueued()
        XCTAssertEqual(engine.receivedURLs, [files.url(for: old.audioFileName!), files.url(for: new.audioFileName!)])
        XCTAssertEqual(done.status, .ready)
        XCTAssertTrue(done.segments.isEmpty)
    }

    func testStaleTranscribingNoteIsRequeuedAndFinished() async {
        let note = addNote(status: .transcribing)
        await makeQueue(FakeTranscriber()).processQueued()
        XCTAssertEqual(note.status, .ready)
    }

    func testDictionaryTermsArePassedAsVocabulary() async {
        context.insert(DictionaryWord(term: "Murmur", createdAt: Date(timeIntervalSinceNow: -10)))
        context.insert(DictionaryWord(term: "Kubernetes", createdAt: Date()))
        try! context.save()
        addNote()
        let engine = FakeTranscriber()
        await makeQueue(engine).processQueued()
        XCTAssertEqual(engine.receivedOptions.first?.vocabulary, ["Murmur", "Kubernetes"])
        XCTAssertNil(engine.receivedOptions.first?.language)
    }

    func testStartRunsInBackground() async {
        let note = addNote()
        let queue = makeQueue(FakeTranscriber())
        queue.start()
        let ok = await waitUntil { note.status == .ready && !queue.isRunning }
        XCTAssertTrue(ok)
    }
}
