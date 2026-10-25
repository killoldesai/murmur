import Foundation
import AVFoundation
import MurmurCore
import WhisperKit

/// Thread-safe scratch space shared with WhisperKit's callbacks, which run on other threads.
private final class RunState: @unchecked Sendable {
    private let lock = NSLock()
    private var found: [TranscriptSegment] = []
    private var isCancelled = false

    func add(_ segments: [TranscriptSegment]) -> [TranscriptSegment] {
        lock.lock(); defer { lock.unlock() }
        found.append(contentsOf: segments)
        return found.sorted { $0.start < $1.start }
    }

    func cancel() {
        lock.lock(); isCancelled = true; lock.unlock()
    }

    var cancelled: Bool {
        lock.lock(); defer { lock.unlock() }
        return isCancelled
    }
}

/// Runs Whisper on the device through WhisperKit. The model loads on first use and stays loaded.
public actor WhisperKitEngine: TranscriptionEngine {
    private let modelFolder: URL
    private var pipe: WhisperKit?

    /// Audio longer than this is streamed from disk in chunks to keep memory low.
    private static let streamingThreshold: TimeInterval = 10 * 60

    public init(modelFolder: URL) {
        self.modelFolder = modelFolder
    }

    private func loadedPipe() async throws -> WhisperKit {
        if let pipe { return pipe }
        let config = WhisperKitConfig(
            modelFolder: modelFolder.path,
            verbose: false,
            load: true,
            download: false
        )
        let created = try await WhisperKit(config)
        pipe = created
        return created
    }

    public func transcribe(
        audioURL: URL,
        duration: TimeInterval,
        options: TranscriptionOptions,
        onProgress: @escaping @Sendable (TranscriptionProgressUpdate) -> Void
    ) async throws -> TranscriptionOutput {
        let pipe = try await loadedPipe()
        let total = duration > 0 ? duration : Self.audioDuration(of: audioURL)
        let state = RunState()

        var decoding = DecodingOptions(
            verbose: false,
            task: .transcribe,
            language: options.language,
            detectLanguage: options.language == nil,
            skipSpecialTokens: true,
            chunkingStrategy: .vad
        )
        if !options.vocabulary.isEmpty, let tokenizer = pipe.tokenizer {
            let prompt = " " + options.vocabulary.joined(separator: ", ")
            decoding.promptTokens = Array(tokenizer.encode(text: prompt).prefix(100))
        }

        pipe.segmentDiscoveryCallback = { segments in
            let converted = Self.convert(segments)
            let all = state.add(converted)
            let end = all.last?.end ?? 0
            let fraction = total > 0 ? min(0.99, end / total) : 0
            onProgress(TranscriptionProgressUpdate(fraction: fraction, segments: all))
        }
        defer { pipe.segmentDiscoveryCallback = nil }

        let inputOptions = AudioInputOptions(
            audioLoadingMode: total > Self.streamingThreshold ? .incremental : .fullFile
        )

        let results = try await withTaskCancellationHandler {
            try await pipe.transcribe(
                audioPath: audioURL.path,
                audioInputOptions: inputOptions,
                decodeOptions: decoding,
                callback: { _ -> Bool? in state.cancelled ? false : nil }
            )
        } onCancel: {
            state.cancel()
        }
        try Task.checkCancellation()

        let segments = Self.convert(results.flatMap { $0.segments }).sorted { $0.start < $1.start }
        return TranscriptionOutput(segments: segments, language: results.first?.language)
    }

    // MARK: - Helpers

    private static func convert(_ segments: [TranscriptionSegment]) -> [TranscriptSegment] {
        segments.compactMap { segment in
            let text = segment.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { return nil }
            return TranscriptSegment(start: Double(segment.start), end: Double(segment.end), text: text)
        }
    }

    private static func audioDuration(of url: URL) -> TimeInterval {
        guard let file = try? AVAudioFile(forReading: url), file.processingFormat.sampleRate > 0 else { return 0 }
        return Double(file.length) / file.processingFormat.sampleRate
    }
}
