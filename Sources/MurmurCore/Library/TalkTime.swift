import Foundation

/// One speaker's share of the talking in a note (the bars in the iPad summary panel).
public struct SpeakerShare: Identifiable, Equatable, Sendable {
    public var id: Int { index }
    public let index: Int
    public let name: String
    /// 0...1, all shares add up to 1.
    public let fraction: Double
    public var percent: Int { Int((fraction * 100).rounded()) }
}

public enum TalkTime {
    /// Talk time per speaker, longest first. Segments without a speaker are ignored.
    public static func shares(segments: [TranscriptSegment], names: [String]) -> [SpeakerShare] {
        var seconds: [Int: Double] = [:]
        for segment in segments {
            guard let speaker = segment.speakerIndex else { continue }
            seconds[speaker, default: 0] += max(0, segment.end - segment.start)
        }
        let total = seconds.values.reduce(0, +)
        guard total > 0 else { return [] }
        return seconds
            .map { SpeakerShare(index: $0.key, name: Speakers.name(at: $0.key, in: names), fraction: $0.value / total) }
            .sorted { $0.fraction == $1.fraction ? $0.index < $1.index : $0.fraction > $1.fraction }
    }
}
