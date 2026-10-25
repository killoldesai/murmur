import Foundation

/// One timed piece of a transcript. Stored inside `Note.segments` as a Codable value.
public struct TranscriptSegment: Codable, Hashable, Sendable, Identifiable {
    public var id: UUID
    public var start: TimeInterval
    public var end: TimeInterval
    public var text: String
    /// Index into `Note.speakerNames`. `nil` means no speaker assigned.
    public var speakerIndex: Int?

    public init(
        id: UUID = UUID(),
        start: TimeInterval,
        end: TimeInterval,
        text: String,
        speakerIndex: Int? = nil
    ) {
        self.id = id
        self.start = start
        self.end = end
        self.text = text
        self.speakerIndex = speakerIndex
    }
}

public extension Array where Element == TranscriptSegment {
    /// Index of the segment playing at `time`, for syncing the transcript to audio playback.
    /// Segments must be sorted by start time. Gaps between segments resolve to the previous
    /// segment; a time before the first segment returns `nil`.
    func indexPlaying(at time: TimeInterval) -> Int? {
        guard let first = first, time >= first.start else { return nil }
        var low = 0
        var high = count - 1
        while low < high {
            let mid = (low + high + 1) / 2
            if self[mid].start <= time {
                low = mid
            } else {
                high = mid - 1
            }
        }
        return low
    }

    /// Plain transcript text, one segment per paragraph.
    var joinedText: String {
        map(\.text).joined(separator: "\n")
    }
}
