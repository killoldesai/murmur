import Foundation
import Observation

public enum RecorderState: Equatable, Sendable {
    case idle
    case recording
    case paused
    case finished
    case failed(String)
}

/// Drives one recording: permission, start, pause/resume, bookmarks, live levels, stop.
/// The screen only reads `state`, `elapsed`, `levels` and `bookmarkCount` and calls the methods.
@MainActor
@Observable
public final class RecordingController {
    /// Number of waveform bars on the record screen.
    public static let levelCount = 34

    public private(set) var state: RecorderState = .idle
    public private(set) var elapsed: TimeInterval = 0
    /// Most recent levels, 0...1, oldest first. Always `levelCount` long.
    public private(set) var levels: [Double] = Array(repeating: 0, count: RecordingController.levelCount)
    public private(set) var bookmarkCount = 0

    @ObservationIgnored private let engine: RecorderEngine
    @ObservationIgnored private let store: RecordingNoteStore
    @ObservationIgnored private let files: AudioFileStore
    @ObservationIgnored private let now: () -> Date
    @ObservationIgnored private let autoTick: Bool
    @ObservationIgnored private var timeline = RecordingTimeline()
    @ObservationIgnored private var note: Note?
    @ObservationIgnored private var tickTask: Task<Void, Never>?

    /// - Parameter autoTick: `false` in tests, which call `tick()` themselves.
    public init(
        engine: RecorderEngine,
        store: RecordingNoteStore,
        files: AudioFileStore,
        now: @escaping () -> Date = Date.init,
        autoTick: Bool = true
    ) {
        self.engine = engine
        self.store = store
        self.files = files
        self.now = now
        self.autoTick = autoTick
        engine.onInterruption = { [weak self] began in
            if began { self?.pause() }
        }
    }

    public func start() async {
        guard state == .idle else { return }
        guard await engine.requestPermission() else {
            state = .failed("Murmur needs microphone access to record. You can turn it on in Settings.")
            return
        }
        do {
            try files.ensureDirectory()
            let created = try store.beginNote(now: now())
            note = created
            do {
                try engine.start(fileURL: files.url(for: created.audioFileName ?? files.newFileName()))
            } catch {
                try? store.discard(created)
                note = nil
                throw error
            }
            timeline = RecordingTimeline()
            timeline.start(at: now())
            state = .recording
            if autoTick { startTicking() }
        } catch {
            state = .failed("Recording could not start. \(error.localizedDescription)")
        }
    }

    public func pause() {
        guard state == .recording else { return }
        engine.pause()
        timeline.pause(at: now())
        elapsed = timeline.elapsed(at: now())
        state = .paused
    }

    public func resume() {
        guard state == .paused else { return }
        engine.resume()
        timeline.resume(at: now())
        state = .recording
    }

    public func togglePause() {
        if state == .recording { pause() } else if state == .paused { resume() }
    }

    public func addBookmark() {
        guard state == .recording || state == .paused, let note else { return }
        timeline.addBookmark(at: now())
        bookmarkCount = timeline.bookmarks.count
        try? store.saveBookmarks(timeline.bookmarks, for: note)
    }

    /// Stops recording and queues the note for transcription. Returns the finished note.
    @discardableResult
    public func stop() -> Note? {
        guard state == .recording || state == .paused, let note else { return nil }
        engine.stop()
        timeline.pause(at: now())
        elapsed = timeline.elapsed(at: now())
        stopTicking()
        do {
            try store.finishNote(note, duration: elapsed, bookmarks: timeline.bookmarks)
        } catch {
            state = .failed("The recording was captured but could not be saved. \(error.localizedDescription)")
            return nil
        }
        state = .finished
        return note
    }

    /// Stops and throws the recording away (note and audio file).
    public func cancel() {
        if state == .recording || state == .paused {
            engine.stop()
        }
        stopTicking()
        if let note {
            try? store.discard(note)
        }
        note = nil
        timeline = RecordingTimeline()
        elapsed = 0
        bookmarkCount = 0
        state = .idle
    }

    /// Samples the clock and the microphone level. Runs about 15 times a second while recording.
    public func tick() {
        guard state == .recording else { return }
        elapsed = timeline.elapsed(at: now())
        levels.removeFirst()
        levels.append(MeterLevel.normalized(decibels: engine.averagePowerDecibels()))
    }

    private func startTicking() {
        tickTask?.cancel()
        tickTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 66_000_000)
                self?.tick()
            }
        }
    }

    private func stopTicking() {
        tickTask?.cancel()
        tickTask = nil
    }
}
