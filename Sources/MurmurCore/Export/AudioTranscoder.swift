#if !os(watchOS)
import Foundation
import AVFoundation

public enum AudioTranscodeError: LocalizedError, Equatable {
    case noAudioTrack
    case cannotRead
    case cannotWrite
    case exportFailed

    public var errorDescription: String? {
        switch self {
        case .noAudioTrack: "This file has no audio."
        case .cannotRead: "This file couldn’t be read."
        case .cannotWrite: "The converted audio couldn’t be saved."
        case .exportFailed: "The audio couldn’t be exported."
        }
    }
}

/// Audio conversions with AVFoundation. Both run in chunks, so memory stays small for long files.
public enum AudioTranscoder {
    /// 16 kHz mono 16-bit PCM, the format Whisper wants.
    static let whisperSettings: [String: Any] = [
        AVFormatIDKey: kAudioFormatLinearPCM,
        AVSampleRateKey: 16_000,
        AVNumberOfChannelsKey: 1,
        AVLinearPCMBitDepthKey: 16,
        AVLinearPCMIsFloatKey: false,
        AVLinearPCMIsBigEndianKey: false,
        AVLinearPCMIsNonInterleaved: false,
    ]

    /// Exports any audio file as AAC in an `.m4a` file (used to share a recording).
    public static func exportM4A(from source: URL, to destination: URL) async throws {
        try? FileManager.default.removeItem(at: destination)
        let asset = AVURLAsset(url: source)
        guard let session = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetAppleM4A) else {
            throw AudioTranscodeError.exportFailed
        }
        do {
            try await session.export(to: destination, as: .m4a)
        } catch {
            throw AudioTranscodeError.exportFailed
        }
    }

    /// Converts audio or video (mp3, m4a, wav, mp4, mov, …) to a 16 kHz mono 16-bit WAV file.
    /// - Returns: the duration in seconds.
    public static func convertToWhisperWAV(
        from source: URL,
        to destination: URL,
        onProgress: @escaping @Sendable (Double) -> Void
    ) async throws -> TimeInterval {
        let asset = AVURLAsset(url: source)
        guard let track = try? await asset.loadTracks(withMediaType: .audio).first else {
            throw AudioTranscodeError.noAudioTrack
        }
        let duration = (try? await asset.load(.duration).seconds) ?? 0

        let reader = try AVAssetReader(asset: asset)
        let output = AVAssetReaderTrackOutput(track: track, outputSettings: whisperSettings)
        guard reader.canAdd(output) else { throw AudioTranscodeError.cannotRead }
        reader.add(output)

        try? FileManager.default.removeItem(at: destination)
        let writer = try AVAssetWriter(outputURL: destination, fileType: .wav)
        let input = AVAssetWriterInput(mediaType: .audio, outputSettings: whisperSettings)
        guard writer.canAdd(input) else { throw AudioTranscodeError.cannotWrite }
        writer.add(input)

        guard reader.startReading() else { throw reader.error ?? AudioTranscodeError.cannotRead }
        guard writer.startWriting() else { throw writer.error ?? AudioTranscodeError.cannotWrite }
        writer.startSession(atSourceTime: .zero)

        let pump = Pump(reader: reader, output: output, writer: writer, input: input,
                        duration: duration, onProgress: onProgress)
        try await withTaskCancellationHandler {
            try await pump.run()
        } onCancel: {
            pump.cancel()
        }
        onProgress(1)
        return duration
    }

    /// Moves sample buffers from the reader to the writer on a private queue.
    private final class Pump: @unchecked Sendable {
        let reader: AVAssetReader
        let output: AVAssetReaderTrackOutput
        let writer: AVAssetWriter
        let input: AVAssetWriterInput
        let duration: TimeInterval
        let onProgress: @Sendable (Double) -> Void
        private let queue = DispatchQueue(label: "app.murmur.transcode")
        private let lock = NSLock()
        private var finished = false
        private var cancelled = false

        init(reader: AVAssetReader, output: AVAssetReaderTrackOutput, writer: AVAssetWriter, input: AVAssetWriterInput,
             duration: TimeInterval, onProgress: @escaping @Sendable (Double) -> Void) {
            self.reader = reader
            self.output = output
            self.writer = writer
            self.input = input
            self.duration = duration
            self.onProgress = onProgress
        }

        func cancel() {
            lock.lock(); cancelled = true; lock.unlock()
            reader.cancelReading()
        }

        private var isCancelled: Bool {
            lock.lock(); defer { lock.unlock() }
            return cancelled
        }

        /// Returns `true` the first time, so the continuation is resumed exactly once.
        private func claimFinish() -> Bool {
            lock.lock(); defer { lock.unlock() }
            if finished { return false }
            finished = true
            return true
        }

        func run() async throws {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                input.requestMediaDataWhenReady(on: queue) { [self] in
                    while input.isReadyForMoreMediaData {
                        if isCancelled {
                            fail(CancellationError(), continuation)
                            return
                        }
                        guard let buffer = output.copyNextSampleBuffer() else {
                            if reader.status == .failed {
                                fail(reader.error ?? AudioTranscodeError.cannotRead, continuation)
                            } else if reader.status == .cancelled {
                                fail(CancellationError(), continuation)
                            } else {
                                input.markAsFinished()
                                writer.finishWriting { [self] in
                                    guard claimFinish() else { return }
                                    if writer.status == .completed {
                                        continuation.resume()
                                    } else {
                                        continuation.resume(throwing: writer.error ?? AudioTranscodeError.cannotWrite)
                                    }
                                }
                            }
                            return
                        }
                        if duration > 0 {
                            let t = CMSampleBufferGetPresentationTimeStamp(buffer).seconds
                            onProgress(min(0.99, max(0, t / duration)))
                        }
                        if !input.append(buffer) {
                            fail(writer.error ?? AudioTranscodeError.cannotWrite, continuation)
                            return
                        }
                    }
                }
            }
        }

        private func fail(_ error: Error, _ continuation: CheckedContinuation<Void, Error>) {
            input.markAsFinished()
            writer.cancelWriting()
            guard claimFinish() else { return }
            continuation.resume(throwing: error)
        }
    }
}
#endif
