import Foundation

public enum SearchScope: String, CaseIterable, Identifiable, Sendable {
    case all, transcripts, summaries

    public var id: String { rawValue }
    public var title: String {
        switch self {
        case .all: "All"
        case .transcripts: "Transcripts"
        case .summaries: "Summaries"
        }
    }
}

public struct SearchHit: Identifiable, Equatable, Sendable {
    public let id: UUID
    /// "00:04" for a transcript line, "AI" for the summary.
    public let label: String
    public let snippet: TextSearch.Snippet
    public let isSummary: Bool
}

public struct SearchResult: Identifiable {
    public let note: Note
    /// A few example hits to show under the title.
    public let hits: [SearchHit]
    /// All matches in the note, including those not shown.
    public let count: Int

    public var id: UUID { note.id }
    public var countText: String { "\(count) match\(count == 1 ? "" : "es")" }
}

public enum NoteSearch {
    /// Notes whose transcript or summary contains `query`, in the order given.
    public static func search(_ rawQuery: String, in notes: [Note], scope: SearchScope = .all, maxHitsPerNote: Int = 3) -> [SearchResult] {
        let query = rawQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return [] }
        var results: [SearchResult] = []

        for note in notes {
            var transcriptHits: [SearchHit] = []
            var transcriptCount = 0
            if scope != .summaries {
                if note.segments.isEmpty {
                    scan(note.transcript, label: "", isSummary: false, query: query, limit: maxHitsPerNote,
                         hits: &transcriptHits, count: &transcriptCount)
                } else {
                    for segment in note.segments {
                        scan(segment.text, label: Timecode.format(segment.start), isSummary: false, query: query,
                             limit: maxHitsPerNote, hits: &transcriptHits, count: &transcriptCount)
                    }
                }
            }

            var summaryHits: [SearchHit] = []
            var summaryCount = 0
            if scope != .transcripts, let text = NoteSummary.plainText(from: note.summary) {
                scan(text, label: "AI", isSummary: true, query: query, limit: maxHitsPerNote,
                     hits: &summaryHits, count: &summaryCount)
            }

            let total = transcriptCount + summaryCount
            guard total > 0 else { continue }
            // Leave room for one summary hit so it is never crowded out by the transcript.
            var chosen = Array(transcriptHits.prefix(summaryHits.isEmpty ? maxHitsPerNote : max(maxHitsPerNote - 1, 0)))
            chosen += summaryHits.prefix(max(maxHitsPerNote - chosen.count, 0))
            results.append(SearchResult(note: note, hits: chosen, count: total))
        }
        return results
    }

    /// "5 results in 3 notes"
    public static func summaryLine(for results: [SearchResult]) -> String {
        let matches = results.reduce(0) { $0 + $1.count }
        return "\(matches) result\(matches == 1 ? "" : "s") in \(results.count) note\(results.count == 1 ? "" : "s")"
    }

    private static func scan(_ text: String, label: String, isSummary: Bool, query: String, limit: Int,
                             hits: inout [SearchHit], count: inout Int) {
        for range in TextSearch.ranges(of: query, in: text) {
            count += 1
            if hits.count < limit {
                hits.append(SearchHit(id: UUID(), label: label,
                                      snippet: TextSearch.snippet(in: text, range: range), isSummary: isSummary))
            }
        }
    }
}

/// One transcript line in the iPad search preview.
public struct ContextLine: Identifiable, Equatable, Sendable {
    public let id: UUID
    public let timestamp: String
    public let text: String
    /// Matches inside `text`; empty for a neighbouring line shown only for context.
    public let spans: [HighlightSpan]
    public var isMatch: Bool { !spans.isEmpty }
}

public enum SearchContext {
    /// Lines of a note that contain `query`, each with `radius` lines of context either side,
    /// in transcript order. Only the first `maxMatches` matching lines are used.
    public static func lines(for note: Note, query rawQuery: String, radius: Int = 1, maxMatches: Int = 6) -> [ContextLine] {
        let query = rawQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        let segments = note.segments
        guard !query.isEmpty, !segments.isEmpty else { return [] }

        var matchIndexes: [Int] = []
        for (index, segment) in segments.enumerated() where !TextSearch.ranges(of: query, in: segment.text).isEmpty {
            matchIndexes.append(index)
            if matchIndexes.count == maxMatches { break }
        }

        var wanted = Set<Int>()
        for index in matchIndexes {
            for neighbour in max(0, index - radius)...min(segments.count - 1, index + radius) {
                wanted.insert(neighbour)
            }
        }

        return wanted.sorted().map { index in
            let segment = segments[index]
            let spans = TextSearch.offsets(of: query, in: segment.text).map {
                HighlightSpan(offset: $0.lowerBound, length: $0.count, isCurrent: true)
            }
            return ContextLine(id: segment.id, timestamp: Timecode.format(segment.start), text: segment.text, spans: spans)
        }
    }
}
