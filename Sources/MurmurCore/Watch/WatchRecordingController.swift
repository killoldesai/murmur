import Foundation
import Observation

/// Drives one recording on the watch: permission, timer, levels, pause, stop. Stopping saves the
/// recording to the outbox so it can be sent to the iPhone.
@MainActor
@Observable
public final class WatchRecordingController {
    public static let levelCount = 12

    public private(set) var state: RecorderState = .idle
    public private(set) var elapsed: TimeInterval = 0
    public private(set) var levels: [Double] = Array(repeating: 0, count: WatchRecordingController.levelCount)
    /// The recording made by the last `stop()`.
    public private(set) var lastSaved: WatchTransfer?

    @ObservationIgnored private let engine: RecorderEngine
    @ObservationIgnored private let outbox: WatchOutbox
    @ObservationIgnored private let now: () -> Date
    @ObservationIgnored private let autoTick: Bool
    @ObservationIgnored private var timeline = RecordingTimeline()
    @ObservationIgnored private var current: WatchTransfer?
    @ObservationIgnored private var startedAt = Date()
    @ObservationIgnored private var tickTask: Task<Void, Never>?

    public init(engine: RecorderEngine, outbox: WatchOutbox, now: @escaping () -> Date = Date.init, autoTick: Bool = true) {
        self.engine = engine
        self.outbox = outbox
        self.now = now
        self.autoTick = autoTick
        engine.onInterruption = { [weak self] began in
            if began { self?.pause() }
        }
    }

    public var isRecording: Bool { state == .recording || state == .paused }

    public func start() async {
        guard !isRecording else { return }
        state = .idle
        guard await engine.requestPermission() else {
            state = .failed("Allow the microphone for Murmur in Settings on your iPhone.")
            return
        }
        do {
            try FileManager.default.createDirectory(at: outbox.directory, withIntermediateDirectories: true)
            let transfer = WatchTransfer(createdAt: now(), duration: 0)
            try engine.start(fileURL: outbox.directory.appendingPathComponent(transfer.fileName))
            current = transfer
            startedAt = now()
            timeline = RecordingTimeline()
            timeline.start(at: now())
            elapsed = 0
            levels = Array(repeating: 0, count: Self.levelCount)
            state = .recording
            if autoTick { startTicking() }
        } catch {
            state = .failed("Recording could not start.")
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

    /// Stops, saves to the outbox and returns the saved recording.
    @discardableResult
    public func stop() -> WatchTransfer? {
        guard isRecording, var transfer = current else { return nil }
        engine.stop()
        timeline.pause(at: now())
        elapsed = timeline.elapsed(at: now())
        stopTicking()
        transfer.duration = elapsed
        current = nil
        guard elapsed >= 1 else {
            // Too short to be a memo: throw it away.
            try? FileManager.default.removeItem(at: outbox.directory.appendingPathComponent(transfer.fileName))
            state = .idle
            elapsed = 0
            return nil
        }
        outbox.add(transfer)
        lastSaved = transfer
        state = .finished
        return transfer
    }

    public func cancel() {
        guard isRecording else { return }
        engine.stop()
        stopTicking()
        if let current {
            try? FileManager.default.removeItem(at: outbox.directory.appendingPathComponent(current.fileName))
        }
        current = nil
        elapsed = 0
        state = .idle
    }

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
                try? await Task.sleep(nanoseconds: 100_000_000)
                self?.tick()
            }
        }
    }

    private func stopTicking() {
        tickTask?.cancel()
        tickTask = nil
    }
}
