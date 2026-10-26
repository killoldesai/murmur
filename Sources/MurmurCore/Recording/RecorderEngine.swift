import Foundation
import AVFoundation

public enum RecorderError: Error, Equatable {
    case permissionDenied
    case couldNotStart(String)
}

/// The hardware side of recording. `RecordingController` talks to this protocol so the logic can
/// be tested with a fake and shown with a demo engine in simulator screenshots.
@MainActor
public protocol RecorderEngine: AnyObject {
    /// Called with `true` when the system interrupts recording (a phone call, Siri) and `false` when it ends.
    var onInterruption: (@MainActor (Bool) -> Void)? { get set }
    func requestPermission() async -> Bool
    func start(fileURL: URL) throws
    func pause()
    func resume()
    func stop()
    /// Current average input power in dB (0 loudest, about -160 silence).
    func averagePowerDecibels() -> Float
}

#if !os(watchOS)
/// Records 16 kHz mono 16-bit PCM to a CAF file with `AVAudioRecorder`.
/// Needs a real microphone: it cannot be exercised in CI or the simulator.
@MainActor
public final class AVAudioRecorderEngine: RecorderEngine {
    public var onInterruption: (@MainActor (Bool) -> Void)?
    private var recorder: AVAudioRecorder?
    private var interruptionObserver: NSObjectProtocol?

    public init() {}

    public func requestPermission() async -> Bool {
        await AVAudioApplication.requestRecordPermission()
    }

    public func start(fileURL: URL) throws {
        #if os(iOS)
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker])
        try session.setActive(true)
        interruptionObserver = NotificationCenter.default.addObserver(
            forName: AVAudioSession.interruptionNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard
                let raw = notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
                let type = AVAudioSession.InterruptionType(rawValue: raw)
            else { return }
            MainActor.assumeIsolated {
                self?.onInterruption?(type == .began)
            }
        }
        #endif

        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatLinearPCM),
            AVSampleRateKey: 16_000,
            AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: false,
        ]
        let recorder = try AVAudioRecorder(url: fileURL, settings: settings)
        recorder.isMeteringEnabled = true
        guard recorder.record() else {
            throw RecorderError.couldNotStart("The microphone could not be started.")
        }
        self.recorder = recorder
    }

    public func pause() {
        recorder?.pause()
    }

    public func resume() {
        recorder?.record()
    }

    public func stop() {
        recorder?.stop()
        recorder = nil
        if let observer = interruptionObserver {
            NotificationCenter.default.removeObserver(observer)
            interruptionObserver = nil
        }
        #if os(iOS)
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        #endif
    }

    public func averagePowerDecibels() -> Float {
        guard let recorder else { return -160 }
        recorder.updateMeters()
        return recorder.averagePower(forChannel: 0)
    }
}

#endif

/// A fake microphone that writes no file and produces a moving level. Used for SwiftUI previews
/// and for simulator screenshots in CI, where there is no microphone.
@MainActor
public final class DemoRecorderEngine: RecorderEngine {
    public var onInterruption: (@MainActor (Bool) -> Void)?
    private var paused = false
    private let startedAt = Date()

    public init() {}

    public func requestPermission() async -> Bool { true }
    public func start(fileURL: URL) throws {}
    public func pause() { paused = true }
    public func resume() { paused = false }
    public func stop() {}

    public func averagePowerDecibels() -> Float {
        let t = Date().timeIntervalSince(startedAt)
        let swell = abs(sin(t * 2.1)) * 0.6 + abs(sin(t * 5.3 + 1)) * 0.4
        return Float(-46 + 34 * swell)
    }
}
