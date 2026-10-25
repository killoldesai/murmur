import Foundation
import AVFoundation
import Observation

/// Plays one audio file. The real one wraps `AVAudioPlayer`; tests and CI use fakes.
@MainActor
public protocol PlayerEngine: AnyObject {
    var duration: TimeInterval { get }
    var currentTime: TimeInterval { get set }
    var isPlaying: Bool { get }
    var rate: Float { get set }
    func load(url: URL) throws
    func play()
    func pause()
}

@MainActor
public final class AVAudioPlayerEngine: PlayerEngine {
    private var player: AVAudioPlayer?

    public init() {}

    public var duration: TimeInterval { player?.duration ?? 0 }
    public var currentTime: TimeInterval {
        get { player?.currentTime ?? 0 }
        set { player?.currentTime = newValue }
    }
    public var isPlaying: Bool { player?.isPlaying ?? false }
    public var rate: Float {
        get { player?.rate ?? 1 }
        set { player?.rate = newValue }
    }

    public func load(url: URL) throws {
        #if os(iOS)
        try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
        #endif
        let player = try AVAudioPlayer(contentsOf: url)
        player.enableRate = true
        player.prepareToPlay()
        self.player = player
    }

    public func play() {
        #if os(iOS)
        try? AVAudioSession.sharedInstance().setActive(true)
        #endif
        player?.play()
    }

    public func pause() { player?.pause() }
}

/// Fake player for previews and CI screenshots: time advances only through `advance(by:)`.
@MainActor
public final class DemoPlayerEngine: PlayerEngine {
    public var duration: TimeInterval
    public var currentTime: TimeInterval = 0
    public private(set) var isPlaying = false
    public var rate: Float = 1

    public init(duration: TimeInterval) { self.duration = duration }

    public func load(url: URL) throws {}
    public func play() { isPlaying = true }
    public func pause() { isPlaying = false }

    public func advance(by seconds: TimeInterval) {
        guard isPlaying else { return }
        currentTime = min(duration, currentTime + seconds * Double(rate))
        if currentTime >= duration { isPlaying = false }
    }
}

/// Drives the Note screen: play, pause, seek, speed, and which transcript line is playing.
@MainActor
@Observable
public final class PlaybackController {
    public static let speeds: [Float] = [1, 1.5, 2]
    public static let skipSeconds: TimeInterval = 15

    public private(set) var isPlaying = false
    public private(set) var currentTime: TimeInterval = 0
    public private(set) var duration: TimeInterval = 0
    public private(set) var speedIndex = 0
    public private(set) var loadError: String?
    public var segments: [TranscriptSegment]

    @ObservationIgnored private let engine: PlayerEngine
    @ObservationIgnored private let autoTick: Bool
    @ObservationIgnored private var tickTask: Task<Void, Never>?

    public init(engine: PlayerEngine, segments: [TranscriptSegment] = [], autoTick: Bool = true) {
        self.engine = engine
        self.segments = segments
        self.autoTick = autoTick
    }

    public var speed: Float { Self.speeds[speedIndex] }
    public var speedLabel: String { speed == speed.rounded() ? "\(Int(speed))×" : "\(speed)×" }
    public var progress: Double { duration > 0 ? min(1, max(0, currentTime / duration)) : 0 }
    public var timeText: String { "\(Timecode.format(currentTime)) / \(Timecode.format(duration))" }
    public var playingIndex: Int? { segments.indexPlaying(at: currentTime) }

    /// Loads the audio. On failure `loadError` explains and playback stays disabled.
    public func load(url: URL, fallbackDuration: TimeInterval = 0) {
        do {
            try engine.load(url: url)
            duration = engine.duration > 0 ? engine.duration : fallbackDuration
            loadError = nil
        } catch {
            duration = fallbackDuration
            loadError = "The audio file couldn’t be opened."
        }
    }

    /// Starts the clock that keeps `currentTime` in step with the player.
    public func start() {
        guard autoTick, tickTask == nil else { return }
        tickTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 100_000_000)
                self?.tick()
            }
        }
    }

    public func stop() {
        tickTask?.cancel()
        tickTask = nil
        engine.pause()
        tick()
    }

    public func tick() {
        currentTime = engine.currentTime
        isPlaying = engine.isPlaying
    }

    public func toggle() {
        guard loadError == nil else { return }
        if engine.isPlaying {
            engine.pause()
        } else {
            // Restart from the top when the end was reached.
            if duration > 0, engine.currentTime >= duration - 0.05 { engine.currentTime = 0 }
            engine.rate = speed
            engine.play()
        }
        tick()
    }

    public func seek(to time: TimeInterval) {
        engine.currentTime = min(max(0, time), max(duration, 0))
        tick()
    }

    public func seek(toFraction fraction: Double) {
        seek(to: duration * min(1, max(0, fraction)))
    }

    public func skip(by seconds: TimeInterval) {
        seek(to: engine.currentTime + seconds)
    }

    /// Jumps to a transcript line and starts playing from there.
    public func play(segment: TranscriptSegment) {
        seek(to: segment.start)
        if !engine.isPlaying { toggle() }
    }

    public func cycleSpeed() {
        speedIndex = (speedIndex + 1) % Self.speeds.count
        engine.rate = speed
    }
}
