import Foundation

public struct TranscriptionOptions: Sendable, Equatable {
    /// Language code such as "en". `nil` detects the language.
    public var language: String?
    /// Names and terms from the user's dictionary; they bias the model toward these spellings.
    public var vocabulary: [String]

    public init(language: String? = nil, vocabulary: [String] = []) {
        self.language = language
        self.vocabulary = vocabulary
    }
}

public struct TranscriptionProgressUpdate: Sendable, Equatable {
    /// 0...1 share of the audio that has been transcribed.
    public var fraction: Double
    /// Segments found so far, for the live preview.
    public var segments: [TranscriptSegment]

    public init(fraction: Double, segments: [TranscriptSegment]) {
        self.fraction = fraction
        self.segments = segments
    }
}

public struct TranscriptionOutput: Sendable, Equatable {
    public var segments: [TranscriptSegment]
    public var language: String?

    public init(segments: [TranscriptSegment], language: String?) {
        self.segments = segments
        self.language = language
    }

    public var text: String { segments.joinedText }
}

/// Turns an audio file into timed text. The real implementation (WhisperKit) is in
/// `MurmurWhisper`; tests and previews use fakes.
public protocol TranscriptionEngine: Sendable {
    func transcribe(
        audioURL: URL,
        duration: TimeInterval,
        options: TranscriptionOptions,
        onProgress: @escaping @Sendable (TranscriptionProgressUpdate) -> Void
    ) async throws -> TranscriptionOutput
}

/// How much faster than real time the transcription runs, e.g. "17× real time".
public enum RealtimeFactor {
    /// Audio seconds processed per second of work, or `nil` until there is enough to measure.
    public static func value(audioSeconds: TimeInterval, elapsed: TimeInterval) -> Double? {
        guard audioSeconds > 0, elapsed >= 1 else { return nil }
        return audioSeconds / elapsed
    }

    public static func text(_ factor: Double?) -> String {
        guard let factor, factor.isFinite, factor > 0 else { return "—" }
        return factor >= 10 ? "\(Int(factor.rounded()))× real time" : String(format: "%.1f× real time", factor)
    }
}

/// Estimates time left from how far the work has got.
public struct ETAEstimator: Sendable {
    private let start: Date

    public init(start: Date) { self.start = start }

    /// Seconds left, or `nil` until enough progress exists for a sensible guess.
    public func remaining(fraction: Double, at now: Date) -> TimeInterval? {
        guard fraction >= 0.05, fraction < 1 else { return fraction >= 1 ? 0 : nil }
        let elapsed = now.timeIntervalSince(start)
        guard elapsed > 0 else { return nil }
        return elapsed / fraction * (1 - fraction)
    }

    /// "About 12s left", "About 3 min left".
    public static func text(for seconds: TimeInterval?) -> String {
        guard let seconds else { return "Estimating…" }
        if seconds < 1 { return "Almost done" }
        if seconds < 60 { return "About \(Int(seconds.rounded()))s left" }
        return "About \(Int((seconds / 60).rounded(.up))) min left"
    }
}
