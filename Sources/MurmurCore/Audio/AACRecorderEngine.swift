import Foundation

#if os(watchOS)
import AVFoundation

/// Records 16 kHz mono AAC (m4a) on the Apple Watch with `AVAudioRecorder`. Small files, and
/// plenty for speech. Needs a real watch for the microphone and background recording.
@MainActor
public final class AACRecorderEngine: RecorderEngine {
    public var onInterruption: (@MainActor (Bool) -> Void)?
    private var recorder: AVAudioRecorder?

    public init() {}

    public func requestPermission() async -> Bool {
        let allowed = await withCheckedContinuation { continuation in
            AVAudioSession.sharedInstance().requestRecordPermission { continuation.resume(returning: $0) }
        }
        guard allowed else { return false }
        // watchOS activates the audio session asynchronously; do it before the first recording.
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playAndRecord, mode: .default)
        return await withCheckedContinuation { continuation in
            session.activate(options: []) { activated, _ in continuation.resume(returning: activated) }
        }
    }

    public func start(fileURL: URL) throws {
        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
            AVSampleRateKey: 16_000,
            AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.medium.rawValue,
        ]
        let recorder = try AVAudioRecorder(url: fileURL, settings: settings)
        recorder.isMeteringEnabled = true
        guard recorder.record() else { throw RecorderError.couldNotStart("The microphone could not be started.") }
        self.recorder = recorder
    }

    public func pause() { recorder?.pause() }
    public func resume() { recorder?.record() }

    public func stop() {
        recorder?.stop()
        recorder = nil
    }

    public func averagePowerDecibels() -> Float {
        guard let recorder else { return -160 }
        recorder.updateMeters()
        return recorder.averagePower(forChannel: 0)
    }
}
#endif
