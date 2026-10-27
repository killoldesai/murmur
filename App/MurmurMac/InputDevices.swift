import AVFoundation
import AudioToolbox
import CoreAudio
import MurmurCore

/// A microphone the Mac can record from.
struct MicChoice: Identifiable, Equatable {
    /// The device's unique ID (the same string CoreAudio calls its UID).
    let id: String
    let name: String
}

enum MicDevices {
    /// Built-in and external microphones that are connected now.
    static func available() -> [MicChoice] {
        let discovery = AVCaptureDevice.DiscoverySession(
            deviceTypes: [.microphone, .external],
            mediaType: .audio,
            position: .unspecified
        )
        return discovery.devices.map { MicChoice(id: $0.uniqueID, name: $0.localizedName) }
    }

    /// The device to record from, or `nil` to use the system default. A saved choice that is
    /// no longer connected falls back to the default instead of failing to record.
    static func resolvedUID(saved: String?) -> String? {
        guard let saved, available().contains(where: { $0.id == saved }) else { return nil }
        return saved
    }
}

/// Records from one chosen microphone (instead of the system default) with `AVAudioEngine`.
/// Writes the same file as `AVAudioRecorderEngine`: 16 kHz mono 16-bit PCM in a CAF.
/// Only used when a microphone is picked in Settings. Needs a real Mac to verify.
@MainActor
final class DeviceRecorderEngine: RecorderEngine {
    var onInterruption: (@MainActor (Bool) -> Void)?
    private let deviceUID: String
    private let engine = AVAudioEngine()
    private let writer = TapWriter()

    init(deviceUID: String) {
        self.deviceUID = deviceUID
    }

    func requestPermission() async -> Bool {
        await AVAudioApplication.requestRecordPermission()
    }

    func start(fileURL: URL) throws {
        let failure = RecorderError.couldNotStart("That microphone could not be started. Pick another one in Settings.")
        guard let deviceID = Self.deviceID(forUID: deviceUID) else { throw failure }
        let input = engine.inputNode
        guard let unit = input.audioUnit else { throw failure }
        var device = deviceID
        let status = AudioUnitSetProperty(
            unit,
            kAudioOutputUnitProperty_CurrentDevice,
            kAudioUnitScope_Global,
            0,
            &device,
            UInt32(MemoryLayout<AudioDeviceID>.size)
        )
        guard status == noErr else { throw failure }

        let hardware = input.outputFormat(forBus: 0)
        guard hardware.sampleRate > 0,
              let target = AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: 16_000, channels: 1, interleaved: true),
              let converter = AVAudioConverter(from: hardware, to: target) else { throw failure }
        let file = try AVAudioFile(
            forWriting: fileURL,
            settings: target.settings,
            commonFormat: .pcmFormatInt16,
            interleaved: true
        )
        writer.begin(file: file, converter: converter, target: target)
        writer.install(on: input, format: hardware)
        engine.prepare()
        do {
            try engine.start()
        } catch {
            input.removeTap(onBus: 0)
            writer.finish()
            throw failure
        }
    }

    func pause() { writer.setPaused(true) }
    func resume() { writer.setPaused(false) }

    func stop() {
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        writer.finish()
    }

    func averagePowerDecibels() -> Float { writer.level }

    /// CoreAudio's device ID for a device UID.
    nonisolated private static func deviceID(forUID uid: String) -> AudioDeviceID? {
        var uidRef: CFString = uid as CFString
        var deviceID = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyTranslateUIDToDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        let status = withUnsafePointer(to: &uidRef) { pointer in
            AudioObjectGetPropertyData(
                AudioObjectID(kAudioObjectSystemObject),
                &address,
                UInt32(MemoryLayout<CFString>.size),
                pointer,
                &size,
                &deviceID
            )
        }
        return status == noErr && deviceID != 0 ? deviceID : nil
    }
}

/// Runs on the audio thread: converts each buffer to the file format, writes it, and keeps the
/// current level. Not main-actor isolated on purpose; the state is guarded by a lock.
private final class TapWriter: @unchecked Sendable {
    private let lock = NSLock()
    private var file: AVAudioFile?
    private var converter: AVAudioConverter?
    private var target: AVAudioFormat?
    private var paused = false
    private var currentLevel: Float = -160

    var level: Float {
        lock.lock(); defer { lock.unlock() }
        return currentLevel
    }

    func begin(file: AVAudioFile, converter: AVAudioConverter, target: AVAudioFormat) {
        lock.lock(); defer { lock.unlock() }
        self.file = file
        self.converter = converter
        self.target = target
        paused = false
        currentLevel = -160
    }

    func setPaused(_ value: Bool) {
        lock.lock(); defer { lock.unlock() }
        paused = value
        if value { currentLevel = -160 }
    }

    func finish() {
        lock.lock(); defer { lock.unlock() }
        file = nil          // closing the file writes its header
        converter = nil
    }

    func install(on node: AVAudioInputNode, format: AVAudioFormat) {
        node.installTap(onBus: 0, bufferSize: 4096, format: format) { [self] buffer, _ in
            process(buffer)
        }
    }

    private final class Once: @unchecked Sendable { var used = false }

    private func process(_ buffer: AVAudioPCMBuffer) {
        lock.lock()
        let file = file, converter = converter, target = target, paused = paused
        lock.unlock()
        updateLevel(from: buffer, paused: paused)
        guard !paused, let file, let converter, let target else { return }

        let ratio = target.sampleRate / buffer.format.sampleRate
        let capacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio) + 64
        guard let output = AVAudioPCMBuffer(pcmFormat: target, frameCapacity: capacity) else { return }
        let once = Once()
        var error: NSError?
        converter.convert(to: output, error: &error) { _, status in
            if once.used {
                status.pointee = .noDataNow
                return nil
            }
            once.used = true
            status.pointee = .haveData
            return buffer
        }
        if error == nil, output.frameLength > 0 {
            try? file.write(from: output)
        }
    }

    private func updateLevel(from buffer: AVAudioPCMBuffer, paused: Bool) {
        guard !paused, let samples = buffer.floatChannelData?[0], buffer.frameLength > 0 else { return }
        var sum: Float = 0
        for index in 0..<Int(buffer.frameLength) { sum += samples[index] * samples[index] }
        let rms = (sum / Float(buffer.frameLength)).squareRoot()
        let decibels = rms > 0 ? max(-160, 20 * log10(rms)) : -160
        lock.lock()
        currentLevel = decibels
        lock.unlock()
    }
}
