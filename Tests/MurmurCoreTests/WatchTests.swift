import XCTest
import SwiftData
@testable import MurmurCore

@MainActor
private final class WatchFakeEngine: RecorderEngine {
    var onInterruption: (@MainActor (Bool) -> Void)?
    var permission = true
    func requestPermission() async -> Bool { permission }
    func start(fileURL: URL) throws {
        FileManager.default.createFile(atPath: fileURL.path, contents: Data([1, 2, 3]))
    }
    func pause() {}
    func resume() {}
    func stop() {}
    func averagePowerDecibels() -> Float { -20 }
}

private final class WatchClock: @unchecked Sendable {
    var date = Date(timeIntervalSinceReferenceDate: 2_000_000)
    func advance(_ seconds: TimeInterval) { date = date.addingTimeInterval(seconds) }
}

private struct CopyConverter: AudioConverting {
    var fails = false
    func convert(from source: URL, to destination: URL, onProgress: @escaping @Sendable (Double) -> Void) async throws -> TimeInterval {
        if fails { throw CocoaError(.fileReadCorruptFile) }
        try FileManager.default.copyItem(at: source, to: destination)
        return 58
    }
}

private func tempDirectory() -> URL {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("murmur-watch-\(UUID().uuidString)", isDirectory: true)
    try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

final class WatchTransferTests: XCTestCase {
    func testMetadataRoundTrip() {
        let transfer = WatchTransfer(createdAt: Date(timeIntervalSince1970: 1_700_000_000), duration: 58.5)
        let back = WatchTransfer(metadata: transfer.metadata)
        XCTAssertEqual(back, transfer)
    }

    func testBadMetadataIsRejected() {
        XCTAssertNil(WatchTransfer(metadata: nil))
        XCTAssertNil(WatchTransfer(metadata: ["id": "nope"]))
    }

    func testMetaLine() {
        let now = Date()
        let today = WatchRecordingEntry(transfer: WatchTransfer(createdAt: now, duration: 84))
        XCTAssertEqual(today.meta(now: now), "Today · 1:24")
        let old = WatchRecordingEntry(transfer: WatchTransfer(createdAt: now.addingTimeInterval(-86_400), duration: 5))
        XCTAssertEqual(old.meta(now: now), "Yesterday · 0:05")
    }
}

@MainActor
final class WatchOutboxTests: XCTestCase {
    func testAddPersistsAndReloads() {
        let dir = tempDirectory()
        let outbox = WatchOutbox(directory: dir)
        let a = WatchTransfer(createdAt: Date(timeIntervalSinceReferenceDate: 100), duration: 10)
        let b = WatchTransfer(createdAt: Date(timeIntervalSinceReferenceDate: 200), duration: 20)
        outbox.add(a)
        outbox.add(b)
        outbox.add(b)   // same id: ignored
        XCTAssertEqual(outbox.entries.map(\.id), [b.id, a.id])
        XCTAssertEqual(WatchOutbox(directory: dir).entries.map(\.id), [b.id, a.id])
    }

    func testWaitingCountAndDelivery() {
        let outbox = WatchOutbox(directory: tempDirectory())
        let a = WatchTransfer(duration: 10)
        outbox.add(a)
        XCTAssertEqual(outbox.waitingCount, 1)
        outbox.setDelivery(.sending, for: a.id)
        XCTAssertEqual(outbox.waitingCount, 1)
        outbox.setDelivery(.delivered, for: a.id)
        XCTAssertEqual(outbox.waitingCount, 0)
    }

    func testDeleteRemovesAudio() throws {
        let outbox = WatchOutbox(directory: tempDirectory())
        let a = WatchTransfer(duration: 10)
        let url = outbox.directory.appendingPathComponent(a.fileName)
        try Data([1]).write(to: url)
        outbox.add(a)
        outbox.delete(id: a.id)
        XCTAssertTrue(outbox.entries.isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
    }

    func testOldDeliveredRecordingsAreTrimmed() throws {
        let outbox = WatchOutbox(directory: tempDirectory(), keepDelivered: 2)
        var ids: [UUID] = []
        for i in 0..<4 {
            let t = WatchTransfer(createdAt: Date(timeIntervalSinceReferenceDate: Double(i)), duration: 5)
            try Data([1]).write(to: outbox.directory.appendingPathComponent(t.fileName))
            outbox.add(t)
            ids.append(t.id)
        }
        ids.forEach { outbox.setDelivery(.delivered, for: $0) }
        XCTAssertEqual(outbox.entries.count, 2)
        XCTAssertEqual(Set(outbox.entries.map(\.id)), Set(ids.suffix(2)))
    }

    func testNotesTodayAndSnapshot() {
        let outbox = WatchOutbox(directory: tempDirectory())
        let now = Date()
        outbox.add(WatchTransfer(createdAt: now, duration: 58))
        outbox.add(WatchTransfer(createdAt: now.addingTimeInterval(-3 * 86_400), duration: 12))
        XCTAssertEqual(outbox.notesToday(now: now), 1)
        let snapshot = WatchSnapshot.make(from: outbox, now: now)
        XCTAssertEqual(snapshot.notesToday, 1)
        XCTAssertEqual(snapshot.waitingCount, 2)
        XCTAssertEqual(snapshot.lastMemoText, "Last memo 0:58 · waiting for iphone")
        XCTAssertEqual(snapshot.recent.count, 2)
    }

    func testSnapshotSaveAndLoad() {
        let defaults = UserDefaults(suiteName: "murmur-snap-\(UUID().uuidString)")
        let snapshot = WatchSnapshot(notesToday: 3, waitingCount: 1, lastMemoText: "x", recent: [.init(title: "Memo", detail: "Sent")])
        snapshot.save(to: defaults)
        XCTAssertEqual(WatchSnapshot.load(from: defaults), snapshot)
        XCTAssertEqual(WatchSnapshot.load(from: UserDefaults(suiteName: "murmur-snap-\(UUID().uuidString)")), .empty)
    }

    func testChangeCallback() {
        let outbox = WatchOutbox(directory: tempDirectory())
        var calls = 0
        outbox.onChange = { calls += 1 }
        outbox.add(WatchTransfer(duration: 3))
        XCTAssertEqual(calls, 1)
    }
}

@MainActor
final class WatchRecordingControllerTests: XCTestCase {
    private func make(clock: WatchClock) -> (WatchRecordingController, WatchOutbox) {
        let outbox = WatchOutbox(directory: tempDirectory())
        let controller = WatchRecordingController(engine: WatchFakeEngine(), outbox: outbox, now: { clock.date }, autoTick: false)
        return (controller, outbox)
    }

    func testRecordAndStopSavesToOutbox() async {
        let clock = WatchClock()
        let (controller, outbox) = make(clock: clock)
        await controller.start()
        XCTAssertEqual(controller.state, .recording)
        clock.advance(30)
        controller.tick()
        XCTAssertEqual(controller.elapsed, 30, accuracy: 0.01)
        let saved = controller.stop()
        XCTAssertEqual(saved?.duration ?? 0, 30, accuracy: 0.01)
        XCTAssertEqual(outbox.entries.count, 1)
        XCTAssertTrue(FileManager.default.fileExists(atPath: outbox.directory.appendingPathComponent(saved!.fileName).path))
        XCTAssertEqual(controller.state, .finished)
    }

    func testPauseDoesNotCountTowardsDuration() async {
        let clock = WatchClock()
        let (controller, _) = make(clock: clock)
        await controller.start()
        clock.advance(10)
        controller.pause()
        clock.advance(100)
        controller.resume()
        clock.advance(5)
        XCTAssertEqual(controller.stop()?.duration ?? 0, 15, accuracy: 0.01)
    }

    func testTooShortIsDiscarded() async {
        let clock = WatchClock()
        let (controller, outbox) = make(clock: clock)
        await controller.start()
        clock.advance(0.4)
        XCTAssertNil(controller.stop())
        XCTAssertTrue(outbox.entries.isEmpty)
        XCTAssertEqual(controller.state, .idle)
    }

    func testPermissionDenied() async {
        let engine = WatchFakeEngine()
        engine.permission = false
        let controller = WatchRecordingController(engine: engine, outbox: WatchOutbox(directory: tempDirectory()), autoTick: false)
        await controller.start()
        if case .failed = controller.state {} else { XCTFail("expected failure") }
    }

    func testCancelRemovesFile() async {
        let clock = WatchClock()
        let (controller, outbox) = make(clock: clock)
        await controller.start()
        controller.cancel()
        XCTAssertEqual(controller.state, .idle)
        let files = (try? FileManager.default.contentsOfDirectory(atPath: outbox.directory.path)) ?? []
        XCTAssertTrue(files.filter { $0.hasSuffix(".m4a") }.isEmpty)
    }
}

@MainActor
final class WatchInboxTests: XCTestCase {
    private var keep: ModelContainer?

    private func make(fails: Bool = false) throws -> (WatchInbox, ModelContext, AudioFileStore) {
        let container = try MurmurSchema.makeContainer(inMemory: true)
        keep = container
        let files = AudioFileStore(directory: tempDirectory())
        let defaults = UserDefaults(suiteName: "murmur-inbox-\(UUID().uuidString)")!
        let inbox = WatchInbox(context: container.mainContext, files: files, converter: CopyConverter(fails: fails), defaults: defaults)
        return (inbox, container.mainContext, files)
    }

    private func audioFile() throws -> URL {
        let url = tempDirectory().appendingPathComponent("memo.m4a")
        try Data([1, 2, 3]).write(to: url)
        return url
    }

    func testReceiveCreatesQueuedWatchNote() async throws {
        let (inbox, context, files) = try make()
        let transfer = WatchTransfer(createdAt: Date(), duration: 60)
        let note = await inbox.receive(fileURL: try audioFile(), transfer: transfer)
        XCTAssertEqual(note?.source, .watch)
        XCTAssertEqual(note?.status, .queued)
        XCTAssertEqual(note?.duration ?? 0, 58, accuracy: 0.01)
        XCTAssertTrue(files.exists(note!.audioFileName!))
        XCTAssertEqual(try context.fetch(FetchDescriptor<Note>()).count, 1)
        XCTAssertTrue(inbox.hasReceived(transfer.id))
    }

    func testSameIdTwiceMakesOneNote() async throws {
        let (inbox, context, _) = try make()
        let transfer = WatchTransfer(duration: 60)
        let url = try audioFile()
        _ = await inbox.receive(fileURL: url, transfer: transfer)
        let second = await inbox.receive(fileURL: url, transfer: transfer)
        XCTAssertNil(second)
        XCTAssertEqual(try context.fetch(FetchDescriptor<Note>()).count, 1)
    }

    func testFailedConversionCanBeRetried() async throws {
        let (inbox, context, _) = try make(fails: true)
        let transfer = WatchTransfer(duration: 60)
        let note = await inbox.receive(fileURL: try audioFile(), transfer: transfer)
        XCTAssertNil(note)
        XCTAssertFalse(inbox.hasReceived(transfer.id))
        XCTAssertEqual(try context.fetch(FetchDescriptor<Note>()).count, 0)
    }
}
