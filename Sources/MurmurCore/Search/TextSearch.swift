import Foundation

/// Case- and accent-insensitive text search with short context snippets.
public enum TextSearch {
    static let options: String.CompareOptions = [.caseInsensitive, .diacriticInsensitive]

    public struct Snippet: Equatable, Sendable {
        public var pre: String
        public var word: String
        public var post: String
    }

    /// Every non-overlapping match of `query` in `text`, in order. An empty query matches nothing.
    public static func ranges(of query: String, in text: String) -> [Range<String.Index>] {
        guard !query.isEmpty else { return [] }
        var result: [Range<String.Index>] = []
        var start = text.startIndex
        while start < text.endIndex,
              let found = text.range(of: query, options: options, range: start..<text.endIndex),
              !found.isEmpty {
            result.append(found)
            start = found.upperBound
        }
        return result
    }

    /// The same matches as character offsets from the start of `text`.
    public static func offsets(of query: String, in text: String) -> [Range<Int>] {
        ranges(of: query, in: text).map { range in
            let lower = text.distance(from: text.startIndex, to: range.lowerBound)
            let upper = text.distance(from: text.startIndex, to: range.upperBound)
            return lower..<upper
        }
    }

    /// `text` with every match replaced, and how many were replaced.
    public static func replacingAll(of query: String, with replacement: String, in text: String) -> (text: String, count: Int) {
        let found = ranges(of: query, in: text)
        guard !found.isEmpty else { return (text, 0) }
        var out = ""
        var cursor = text.startIndex
        for range in found {
            out += text[cursor..<range.lowerBound]
            out += replacement
            cursor = range.upperBound
        }
        out += text[cursor...]
        return (out, found.count)
    }

    /// `text` with only the `occurrence`-th match replaced, or `nil` if there is no such match.
    public static func replacing(occurrence: Int, of query: String, with replacement: String, in text: String) -> String? {
        let found = ranges(of: query, in: text)
        guard found.indices.contains(occurrence) else { return nil }
        var copy = text
        copy.replaceSubrange(found[occurrence], with: replacement)
        return copy
    }

    /// Words around a match, cut at word boundaries, with "…" where text was left out.
    public static func snippet(in text: String, range: Range<String.Index>, before: Int = 36, after: Int = 56) -> Snippet {
        let preFull = String(text[text.startIndex..<range.lowerBound]).replacingOccurrences(of: "\n", with: " ")
        let postFull = String(text[range.upperBound...]).replacingOccurrences(of: "\n", with: " ")
        let word = String(text[range])

        var pre = preFull
        if preFull.count > before {
            var tail = Substring(String(preFull.suffix(before)))
            let previous = preFull.dropLast(before).last
            if let previous, !previous.isWhitespace, let space = tail.firstIndex(of: " ") {
                tail = tail[tail.index(after: space)...]
            }
            pre = "…" + String(tail)
        }

        var post = postFull
        if postFull.count > after {
            var head = Substring(String(postFull.prefix(after)))
            let next = postFull.dropFirst(after).first
            if let next, !next.isWhitespace, let space = head.lastIndex(of: " ") {
                head = head[..<space]
            }
            post = String(head) + "…"
        }
        return Snippet(pre: pre, word: word, post: post)
    }
}
