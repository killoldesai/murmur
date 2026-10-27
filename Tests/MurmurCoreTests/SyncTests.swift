import XCTest
import SwiftData
@testable import MurmurCore

final class SyncStateTests: XCTestCase {
    func testDecide() {
        XCTAssertEqual(ICloudSync.decide(enabled: false, signedIn: true), .off)
        XCTAssertEqual(ICloudSync.decide(enabled: false, signedIn: false), .off)
        XCTAssertEqual(ICloudSync.decide(enabled: true, signedIn: true), .active)
        XCTAssertEqual(ICloudSync.decide(enabled: true, signedIn: false), .needsSignIn)
    }

    func testMessages() {
        XCTAssertTrue(ICloudSync.message(enabled: false, state: .off).contains("Audio stays on the device"))
        XCTAssertTrue(ICloudSync.message(enabled: true, state: .off).contains("next time you open"))
        XCTAssertTrue(ICloudSync.message(enabled: false, state: .active).contains("turns off"))
        XCTAssertTrue(ICloudSync.message(enabled: true, state: .active).contains("private iCloud"))
        XCTAssertTrue(ICloudSync.message(enabled: true, state: .needsSignIn).contains("Sign in"))
        XCTAssertTrue(ICloudSync.message(enabled: true, state: .unavailable("No account.")).contains("No account."))
    }

    func testBackupCopiesStoreAndSideFiles() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("murmur-backup-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let store = root.appendingPathComponent("default.store")
        try Data([1, 2, 3]).write(to: store)
        try Data([4]).write(to: URL(fileURLWithPath: store.path + "-wal"))

        let folder = try StoreBackup.copyStore(at: store, into: root.appendingPathComponent("Backups"))
        let copied = try XCTUnwrap(folder)
        XCTAssertTrue(copied.lastPathComponent.hasPrefix("before-icloud-"))
        XCTAssertEqual(try Data(contentsOf: copied.appendingPathComponent("default.store")), Data([1, 2, 3]))
        XCTAssertEqual(try Data(contentsOf: copied.appendingPathComponent("default.store-wal")), Data([4]))
        XCTAssertFalse(FileManager.default.fileExists(atPath: copied.appendingPathComponent("default.store-shm").path))
    }

    func testBackupWithNoStoreDoesNothing() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("murmur-backup-\(UUID().uuidString)")
        let result = try StoreBackup.copyStore(at: root.appendingPathComponent("none.store"), into: root)
        XCTAssertNil(result)
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.path))
    }

    @MainActor
    func testSettingPersistsAndTakesEffectOnRestart() {
        let suite = "murmur-sync-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let settings = AppSettings(defaults: defaults)
        XCTAssertFalse(settings.iCloudSyncEnabled)
        XCTAssertFalse(settings.isSyncActive)
        settings.setICloudSyncEnabled(true)
        XCTAssertTrue(ICloudSync.isEnabled(defaults))
        XCTAssertFalse(settings.isSyncActive, "turning it on does not change this run")
        XCTAssertTrue(settings.syncMessage.contains("next time you open"))
        XCTAssertTrue(AppSettings(defaults: defaults).iCloudSyncEnabled)
        settings.syncState = .active
        XCTAssertTrue(settings.isSyncActive)
    }
}

private final class SyncFakeEngine: TranscriptionEngine, @unchecked Sendable {
    func transcribe(
        audioURL: URL,
        duration: TimeInterval,
        options: TranscriptionOptions,
        onProgress: @escaping @Sendable (TranscriptionProgressUpdate) -> Void
    ) async throws -> TranscriptionOutput {
        TranscriptionOutput(segments: [TranscriptSegment(start: 0, end: 2, text: "Hello there.")], language: "en")
    }
}

@MainActor
final class SyncGuardTests: XCTestCase {
    private var container: ModelContainer!
    private var files: AudioFileStore!
    private var directory: URL!
    private var defaults: UserDefaults!
    private var suite = ""

    override func setUp() async throws {
        container = try MurmurSchema.makeContainer(inMemory: true)
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("murmur-syncguard-\(UUID().uuidString)")
        files = AudioFileStore(directory: directory)
        try files.ensureDirectory()
        suite = "murmur-syncguard-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suite)
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: directory)
        defaults.removePersistentDomain(forName: suite)
        container = nil
    }

    private var context: ModelContext { container.mainContext }

    @discardableResult
    private func addNote(status: NoteStatus, withAudio: Bool, age: TimeInterval = 0) -> Note {
        let name = files.newFileName()
        if withAudio { FileManager.default.createFile(atPath: files.url(for: name).path, contents: Data([1, 2, 3])) }
        let note = Note(title: "N", createdAt: Date(timeIntervalSinceNow: -age), duration: 5,
                        audioFileName: name, source: .recording, status: status)
        context.insert(note)
        try! context.save()
        return note
    }

    private func syncedQueue(active: Bool) -> TranscriptionQueue {
        let settings = AppSettings(defaults: defaults)
        settings.syncState = active ? .active : .off
        let queue = TranscriptionQueue(context: context, files: files, engineProvider: { SyncFakeEngine() })
        queue.settings = settings
        return queue
    }

    func testSyncedQueuedNoteFromAnotherDeviceIsLeftAlone() async {
        let remote = addNote(status: .queued, withAudio: false)
        let local = addNote(status: .queued, withAudio: true, age: -5)
        await syncedQueue(active: true).processQueued()
        XCTAssertEqual(remote.status, .queued, "not failed, not transcribed: another device owns it")
        XCTAssertEqual(local.status, .ready)
    }

    func testWithoutSyncMissingAudioStillFails() async {
        let note = addNote(status: .queued, withAudio: false)
        await syncedQueue(active: false).processQueued()
        XCTAssertEqual(note.status, .failed)
    }

    func testStaleTranscribingNoteFromAnotherDeviceIsNotRequeued() async {
        let remote = addNote(status: .transcribing, withAudio: false)
        let local = addNote(status: .transcribing, withAudio: true)
        await syncedQueue(active: true).processQueued()
        XCTAssertEqual(remote.status, .transcribing)
        XCTAssertEqual(local.status, .ready, "the local one was requeued and then finished")
    }

    func testRecoveryLeavesRemoteRecordingAlone() throws {
        let remote = addNote(status: .recording, withAudio: false)
        let local = addNote(status: .recording, withAudio: true)
        let store = RecordingNoteStore(context: context, files: files)
        XCTAssertEqual(try store.recoverInterruptedRecordings(skippingRemote: true), 1)
        XCTAssertEqual(remote.status, .recording)
        XCTAssertEqual(local.status, .queued)
    }

    func testRecoveryWithoutSyncFailsMissingAudio() throws {
        let note = addNote(status: .recording, withAudio: false)
        _ = try RecordingNoteStore(context: context, files: files).recoverInterruptedRecordings()
        XCTAssertEqual(note.status, .failed)
    }

    func testAudioAvailability() {
        let here = addNote(status: .ready, withAudio: true)
        let elsewhere = addNote(status: .ready, withAudio: false)
        let deleted = addNote(status: .ready, withAudio: true)
        deleted.audioFileName = nil
        XCTAssertEqual(AudioAvailability.of(here, files: files, syncActive: true), .here)
        XCTAssertEqual(AudioAvailability.of(elsewhere, files: files, syncActive: true), .onAnotherDevice)
        XCTAssertEqual(AudioAvailability.of(elsewhere, files: files, syncActive: false), .here, "unchanged when sync is off")
        XCTAssertEqual(AudioAvailability.of(deleted, files: files, syncActive: true), .deleted)
    }

    func testOrphanedAudioIsRemovedOnlyWhenOldAndUnused() throws {
        let used = addNote(status: .ready, withAudio: true)
        let oldOrphan = files.newFileName()
        let freshOrphan = files.newFileName()
        for name in [oldOrphan, freshOrphan] {
            FileManager.default.createFile(atPath: files.url(for: name).path, contents: Data([9]))
        }
        let old = Date(timeIntervalSinceNow: -3 * 86_400)
        try FileManager.default.setAttributes([.modificationDate: old], ofItemAtPath: files.url(for: oldOrphan).path)

        let removed = LibraryStore(context: context, files: files).removeOrphanedAudio()
        XCTAssertEqual(removed, 1)
        XCTAssertFalse(files.exists(oldOrphan))
        XCTAssertTrue(files.exists(freshOrphan), "a file from the last day may still be mid-import")
        XCTAssertTrue(files.exists(used.audioFileName!))
    }
}
