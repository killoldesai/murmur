import Foundation
import Observation

public struct FindReplaceMatch: Equatable, Sendable {
    public let segmentIndex: Int
    /// Which match this is within its segment (0 for the first).
    public let occurrence: Int
    /// Character offset in the segment text.
    public let offset: Int
    public let length: Int
}

public struct HighlightSpan: Equatable, Sendable {
    public let offset: Int
    public let length: Int
    public let isCurrent: Bool
}

/// Find and replace across one note's transcript. Every replace is saved to the note straight away.
@MainActor
@Observable
public final class FindReplaceController {
    public private(set) var find: String
    public var replacement: String
    public var addToDictionary = true
    public private(set) var segments: [TranscriptSegment]
    public private(set) var matches: [FindReplaceMatch] = []
    public private(set) var currentIndex = 0

    @ObservationIgnored private let note: Note
    @ObservationIgnored private let library: LibraryStore
    @ObservationIgnored private let dictionary: DictionaryStore

    public init(note: Note, library: LibraryStore, dictionary: DictionaryStore, find: String = "", replacement: String = "") {
        self.note = note
        self.library = library
        self.dictionary = dictionary
        self.find = find
        self.replacement = replacement
        self.segments = note.segments
        recompute(after: nil)
    }

    public var current: FindReplaceMatch? {
        matches.indices.contains(currentIndex) ? matches[currentIndex] : nil
    }

    public var canReplace: Bool { !matches.isEmpty }

    /// "2 of 3", "No matches", or nothing while the Find box is empty.
    public var counterText: String {
        if find.isEmpty { return "" }
        return matches.isEmpty ? "No matches" : "\(currentIndex + 1) of \(matches.count)"
    }

    /// Whether the replacement is a new word that can go in the dictionary.
    public var canAddToDictionary: Bool {
        !replacement.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    public func setFind(_ text: String) {
        guard text != find else { return }
        find = text
        recompute(after: nil)
    }

    public func next() { step(1) }
    public func previous() { step(-1) }

    private func step(_ direction: Int) {
        guard !matches.isEmpty else { return }
        currentIndex = (currentIndex + direction + matches.count) % matches.count
    }

    /// Replaces the highlighted match and moves to the next one.
    /// - Returns: `false` when there was nothing to replace.
    @discardableResult
    public func replaceCurrent() -> Bool {
        guard let match = current,
              let updated = TextSearch.replacing(occurrence: match.occurrence, of: find, with: replacement,
                                                 in: segments[match.segmentIndex].text) else { return false }
        segments[match.segmentIndex].text = updated
        commit()
        recompute(after: (match.segmentIndex, match.offset + replacement.count))
        return true
    }

    /// Replaces every match.
    /// - Returns: how many were replaced.
    @discardableResult
    public func replaceAll() -> Int {
        var total = 0
        for index in segments.indices {
            let result = TextSearch.replacingAll(of: find, with: replacement, in: segments[index].text)
            if result.count > 0 {
                segments[index].text = result.text
                total += result.count
            }
        }
        guard total > 0 else { return 0 }
        commit()
        recompute(after: nil)
        return total
    }

    /// Highlighted ranges in one transcript line, with the current match marked.
    public func spans(inSegment index: Int) -> [HighlightSpan] {
        let currentMatch = current
        return matches.filter { $0.segmentIndex == index }.map {
            HighlightSpan(offset: $0.offset, length: $0.length, isCurrent: $0 == currentMatch)
        }
    }

    private func commit() {
        library.applyEdit(segments, to: note)
        if addToDictionary && canAddToDictionary { dictionary.add(replacement) }
    }

    /// Rebuilds the match list. With `after`, the current match becomes the first one at or after
    /// that position (wrapping to the start), so a replacement is never matched again.
    private func recompute(after position: (segment: Int, offset: Int)?) {
        var found: [FindReplaceMatch] = []
        if !find.isEmpty {
            for (index, segment) in segments.enumerated() {
                for (occurrence, range) in TextSearch.offsets(of: find, in: segment.text).enumerated() {
                    found.append(FindReplaceMatch(segmentIndex: index, occurrence: occurrence,
                                                  offset: range.lowerBound, length: range.count))
                }
            }
        }
        matches = found
        guard !found.isEmpty else { currentIndex = 0; return }
        if let position {
            currentIndex = found.firstIndex {
                $0.segmentIndex > position.segment || ($0.segmentIndex == position.segment && $0.offset >= position.offset)
            } ?? 0
        } else {
            currentIndex = 0
        }
    }
}
