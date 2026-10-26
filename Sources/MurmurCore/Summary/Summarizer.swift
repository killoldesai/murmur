import Foundation

/// Produces text from instructions and a prompt. The real one is Apple's on-device model.
public protocol TextGenerator: Sendable {
    func generate(instructions: String, prompt: String) async throws -> String
}

public enum TranscriptFormatter {
    /// One line per segment: "Priya: Sounds good." Speakers are named when known.
    public static func lines(segments: [TranscriptSegment], speakerNames: [String]) -> [String] {
        segments.compactMap { segment in
            let text = segment.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { return nil }
            if let index = segment.speakerIndex {
                return Speakers.name(at: index, in: speakerNames) + ": " + text
            }
            return text
        }
    }
}

public enum TranscriptChunker {
    /// Groups lines into chunks of at most `maxCharacters`, never splitting a line unless the
    /// line alone is longer than the limit.
    public static func chunks(of lines: [String], maxCharacters: Int) -> [String] {
        var result: [String] = []
        var current = ""
        func flush() {
            if !current.isEmpty { result.append(current); current = "" }
        }
        for line in lines {
            for piece in split(line, max: maxCharacters) {
                if !current.isEmpty, current.count + 1 + piece.count > maxCharacters { flush() }
                current += (current.isEmpty ? "" : "\n") + piece
            }
        }
        flush()
        return result
    }

    /// Cuts an over-long line at the last space before the limit.
    static func split(_ line: String, max: Int) -> [String] {
        guard line.count > max, max > 0 else { return [line] }
        var pieces: [String] = []
        var rest = Substring(line)
        while rest.count > max {
            let window = rest.prefix(max)
            let cut = window.lastIndex(of: " ").map { window.distance(from: window.startIndex, to: $0) } ?? max
            let size = cut > 0 ? cut : max
            pieces.append(String(rest.prefix(size)).trimmingCharacters(in: .whitespaces))
            rest = rest.dropFirst(size).drop(while: { $0 == " " })
        }
        if !rest.isEmpty { pieces.append(String(rest)) }
        return pieces
    }
}

public enum SummaryParser {
    /// Reads the model's reply, which follows "SUMMARY: … ACTION ITEMS: - task | owner | due".
    /// A reply without the markers is kept whole as the summary.
    public static func parse(_ raw: String, template: SummaryTemplate, generatedAt: Date = Date()) -> NoteSummary {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let summaryRange = text.range(of: "SUMMARY:", options: [.caseInsensitive])
        let actionRange = text.range(of: "ACTION ITEMS:", options: [.caseInsensitive])

        var summaryText = text
        var itemsText = ""
        if let actionRange {
            let startOfSummary = summaryRange?.upperBound ?? text.startIndex
            summaryText = startOfSummary <= actionRange.lowerBound ? String(text[startOfSummary..<actionRange.lowerBound]) : ""
            itemsText = String(text[actionRange.upperBound...])
        } else if let summaryRange {
            summaryText = String(text[summaryRange.upperBound...])
        }

        let items = template.hasActionItems ? parseItems(itemsText) : []
        return NoteSummary(
            template: template,
            text: summaryText.trimmingCharacters(in: .whitespacesAndNewlines),
            actionItems: items,
            generatedAt: generatedAt
        )
    }

    static func parseItems(_ block: String) -> [ActionItem] {
        block.split(whereSeparator: \.isNewline).compactMap { rawLine in
            var line = rawLine.trimmingCharacters(in: .whitespaces)
            for marker in ["- ", "• ", "* ", "– "] where line.hasPrefix(marker) {
                line = String(line.dropFirst(marker.count)).trimmingCharacters(in: .whitespaces)
                break
            }
            guard !line.isEmpty, line.lowercased() != "none", line.lowercased() != "none." else { return nil }
            let parts = line.split(separator: "|", omittingEmptySubsequences: false)
                .map { $0.trimmingCharacters(in: .whitespaces) }
            let task = parts[0]
            guard !task.isEmpty else { return nil }
            return ActionItem(text: task, owner: clean(parts.count > 1 ? parts[1] : nil), due: clean(parts.count > 2 ? parts[2] : nil))
        }
    }

    private static func clean(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: CharacterSet.whitespaces.union(CharacterSet(charactersIn: "<>")))
        let lowered = trimmed.lowercased()
        return ["", "?", "none", "n/a", "unknown", "unassigned"].contains(lowered) ? nil : trimmed
    }
}

/// Summarizes a transcript of any length: short ones in one request, long ones in parts that are
/// then combined, because the on-device model has a small context window.
public struct Summarizer: Sendable {
    private let generator: TextGenerator
    private let maxChunkCharacters: Int

    public init(generator: TextGenerator, maxChunkCharacters: Int = 6_000) {
        self.generator = generator
        self.maxChunkCharacters = maxChunkCharacters
    }

    static let formatRules = """
    Reply in exactly this format and nothing else:
    SUMMARY:
    <the summary>
    ACTION ITEMS:
    - <task> | <person or ?> | <deadline as said, such as "by Friday" or "next week", or ?>
    Write "- none" under ACTION ITEMS if there are none. Use only what was said. Never invent names, dates or tasks.
    """

    static func instructions(for template: SummaryTemplate) -> String {
        switch template {
        case .meeting:
            "You write concise meeting notes. In SUMMARY write 2 to 4 sentences covering the decisions and key points. In ACTION ITEMS list every task someone agreed to do.\n" + formatRules
        case .lecture:
            "You write study notes from a lecture. In SUMMARY write 4 to 7 short lines, each starting with “• ”, covering the key concepts and definitions. There are no action items: write “- none”.\n" + formatRules
        case .bullets:
            "You summarize a recording as bullet points. In SUMMARY write 5 to 8 short lines, each starting with “• ”, covering the main points in order. There are no action items: write “- none”.\n" + formatRules
        }
    }

    static let partInstructions = "You condense one part of a longer recording into short notes. In SUMMARY write 3 to 5 sentences with the key points. In ACTION ITEMS list tasks that people agreed to do.\n" + formatRules

    public func summarize(
        segments: [TranscriptSegment],
        speakerNames: [String],
        template: SummaryTemplate,
        onProgress: @escaping @Sendable (String) -> Void = { _ in }
    ) async throws -> NoteSummary {
        let lines = TranscriptFormatter.lines(segments: segments, speakerNames: speakerNames)
        guard !lines.isEmpty else { throw SummaryError.emptyTranscript }
        let chunks = TranscriptChunker.chunks(of: lines, maxCharacters: maxChunkCharacters)

        if chunks.count == 1 {
            onProgress("Summarizing…")
            let raw = try await generator.generate(instructions: Self.instructions(for: template),
                                                   prompt: "Transcript:\n" + chunks[0])
            return SummaryParser.parse(raw, template: template)
        }

        var partials: [String] = []
        for (index, chunk) in chunks.enumerated() {
            try Task.checkCancellation()
            onProgress("Reading part \(index + 1) of \(chunks.count)…")
            partials.append(try await generator.generate(instructions: Self.partInstructions,
                                                         prompt: "Transcript, part \(index + 1) of \(chunks.count):\n" + chunk))
        }
        onProgress("Putting it together…")
        let combined = try await reduce(partials, depth: 0)
        let raw = try await generator.generate(instructions: Self.instructions(for: template),
                                               prompt: "These are notes from consecutive parts of one recording. Combine them into one result.\n" + combined)
        return SummaryParser.parse(raw, template: template)
    }

    /// Shrinks the partial notes until they fit in one request.
    private func reduce(_ texts: [String], depth: Int) async throws -> String {
        let joined = texts.enumerated().map { "Part \($0.offset + 1):\n\($0.element)" }.joined(separator: "\n\n")
        if joined.count <= maxChunkCharacters { return joined }
        if depth >= 6 { return String(joined.prefix(maxChunkCharacters)) }
        let groups = TranscriptChunker.chunks(of: joined.components(separatedBy: "\n"), maxCharacters: maxChunkCharacters)
        var shorter: [String] = []
        for group in groups {
            try Task.checkCancellation()
            shorter.append(try await generator.generate(instructions: Self.partInstructions, prompt: "Notes:\n" + group))
        }
        return try await reduce(shorter, depth: depth + 1)
    }
}
