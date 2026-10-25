import Foundation

/// Edits a list of transcript segments with undo. Pure value logic; the Edit screen holds one.
public struct TranscriptEditor: Equatable {
    public private(set) var segments: [TranscriptSegment]
    private let original: [TranscriptSegment]
    private var history: [[TranscriptSegment]] = []
    /// Consecutive text edits to the same segment share one undo step.
    private var coalescingID: UUID?

    public init(segments: [TranscriptSegment]) {
        self.segments = segments
        self.original = segments
    }

    public var canUndo: Bool { !history.isEmpty }
    public var hasChanges: Bool { segments != original }

    public func index(of id: UUID) -> Int? { segments.firstIndex { $0.id == id } }

    public func canMerge(_ id: UUID) -> Bool {
        guard let i = index(of: id) else { return false }
        return i + 1 < segments.count
    }

    public mutating func setText(_ text: String, for id: UUID) {
        guard let i = index(of: id), segments[i].text != text else { return }
        if coalescingID != id { pushHistory() }
        coalescingID = id
        segments[i].text = text
    }

    public mutating func setSpeaker(_ speaker: Int?, for id: UUID) {
        guard let i = index(of: id), segments[i].speakerIndex != speaker else { return }
        pushHistory()
        segments[i].speakerIndex = speaker
    }

    /// Splits a segment at a character offset. The cut time is interpolated by text position.
    /// - Returns: the id of the new second half, or `nil` if either half would be empty.
    @discardableResult
    public mutating func split(_ id: UUID, atCharacterOffset offset: Int) -> UUID? {
        guard let i = index(of: id) else { return nil }
        let segment = segments[i]
        let characters = Array(segment.text)
        guard offset > 0, offset < characters.count else { return nil }
        let first = String(characters[..<offset]).trimmingCharacters(in: .whitespacesAndNewlines)
        let second = String(characters[offset...]).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !first.isEmpty, !second.isEmpty else { return nil }

        pushHistory()
        let cut = segment.start + (segment.end - segment.start) * Double(offset) / Double(characters.count)
        segments[i].text = first
        segments[i].end = cut
        let tail = TranscriptSegment(start: cut, end: segment.end, text: second, speakerIndex: segment.speakerIndex)
        segments.insert(tail, at: i + 1)
        return tail.id
    }

    /// Joins a segment with the one after it. The first segment's speaker is kept.
    @discardableResult
    public mutating func merge(_ id: UUID) -> Bool {
        guard let i = index(of: id), i + 1 < segments.count else { return false }
        pushHistory()
        let next = segments.remove(at: i + 1)
        segments[i].text = segments[i].text + " " + next.text
        segments[i].end = next.end
        return true
    }

    public mutating func delete(_ id: UUID) {
        guard let i = index(of: id) else { return }
        pushHistory()
        segments.remove(at: i)
    }

    public mutating func undo() {
        guard let previous = history.popLast() else { return }
        segments = previous
        coalescingID = nil
    }

    private mutating func pushHistory() {
        history.append(segments)
        coalescingID = nil
    }
}

/// Speaker labels for a note. `speakerNames[i]` names speaker `i`; unnamed ones get "Speaker N".
public enum Speakers {
    public static func name(at index: Int, in names: [String]) -> String {
        if names.indices.contains(index), !names[index].trimmingCharacters(in: .whitespaces).isEmpty {
            return names[index]
        }
        return "Speaker \(index + 1)"
    }

    public static func initial(at index: Int, in names: [String]) -> String {
        String(name(at: index, in: names).first(where: \.isLetter) ?? "S").uppercased()
    }

    /// How many speaker chips to offer: every named speaker plus any index used by a segment.
    public static func count(names: [String], segments: [TranscriptSegment]) -> Int {
        max(names.count, (segments.compactMap(\.speakerIndex).max() ?? -1) + 1)
    }
}
