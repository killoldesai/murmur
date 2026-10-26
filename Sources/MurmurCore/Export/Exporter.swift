import Foundation

public struct ExportOptions: Equatable, Sendable {
    public var speakerLabels: Bool
    public var timestamps: Bool
    public var summary: Bool

    public init(speakerLabels: Bool = true, timestamps: Bool = false, summary: Bool = true) {
        self.speakerLabels = speakerLabels
        self.timestamps = timestamps
        self.summary = summary
    }
}

public enum ExportFormat: String, CaseIterable, Identifiable, Sendable {
    case text, subtitles, audio, copy

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .text: "Text"
        case .subtitles: "Subtitles"
        case .audio: "Audio"
        case .copy: "Copy text"
        }
    }

    public var detail: String {
        switch self {
        case .text: ".txt file"
        case .subtitles: ".srt for video"
        case .audio: ".m4a recording"
        case .copy: "To clipboard"
        }
    }

    /// Whether the speaker, timestamp and summary options apply.
    public var usesTextOptions: Bool { self != .audio }

    public var actionTitle: String {
        switch self {
        case .text: "Share .txt"
        case .subtitles: "Share .srt"
        case .audio: "Share audio"
        case .copy: "Copy to clipboard"
        }
    }
}

/// Builds TXT and SRT output from a transcript. Pure functions.
public enum Exporter {
    public static func text(for note: Note, options: ExportOptions) -> String {
        text(title: note.title, segments: note.segments, fallbackText: note.transcript,
             speakerNames: note.speakerNames, summary: NoteSummary.plainText(from: note.summary), options: options)
    }

    public static func srt(for note: Note, options: ExportOptions) -> String {
        srt(segments: note.segments, speakerNames: note.speakerNames, options: options)
    }

    public static func text(
        title: String,
        segments: [TranscriptSegment],
        fallbackText: String = "",
        speakerNames: [String],
        summary: String?,
        options: ExportOptions
    ) -> String {
        var blocks: [String] = [title]
        if options.summary, let summary, !summary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            blocks.append("Summary\n" + summary.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        if segments.isEmpty {
            let fallback = fallbackText.trimmingCharacters(in: .whitespacesAndNewlines)
            if !fallback.isEmpty { blocks.append(fallback) }
        } else {
            let lines = segments.map { segment -> String in
                var parts: [String] = []
                if options.timestamps { parts.append("[\(Timecode.format(segment.start))]") }
                if options.speakerLabels, let index = segment.speakerIndex {
                    parts.append(Speakers.name(at: index, in: speakerNames) + ":")
                }
                parts.append(segment.text)
                return parts.joined(separator: " ")
            }
            blocks.append(lines.joined(separator: "\n"))
        }
        return blocks.joined(separator: "\n\n") + "\n"
    }

    /// Markdown for Notion or Obsidian: title, summary with a task list, then the transcript.
    public static func markdown(for note: Note, options: ExportOptions) -> String {
        markdown(title: note.title, segments: note.segments, fallbackText: note.transcript,
                 speakerNames: note.speakerNames, summary: NoteSummary.decode(note.summary), options: options)
    }

    public static func markdown(
        title: String,
        segments: [TranscriptSegment],
        fallbackText: String = "",
        speakerNames: [String],
        summary: NoteSummary?,
        options: ExportOptions
    ) -> String {
        var blocks: [String] = ["# " + title]
        if options.summary, let summary {
            let body = summary.text.trimmingCharacters(in: .whitespacesAndNewlines)
            if !body.isEmpty { blocks.append("## Summary\n\n" + body) }
            if !summary.actionItems.isEmpty {
                let tasks = summary.actionItems.map { item -> String in
                    var line = "- [" + (item.done ? "x" : " ") + "] " + item.text
                    if let meta = item.metaLine { line += " (" + meta + ")" }
                    return line
                }
                blocks.append("## Action items\n\n" + tasks.joined(separator: "\n"))
            }
        }
        if segments.isEmpty {
            let fallback = fallbackText.trimmingCharacters(in: .whitespacesAndNewlines)
            if !fallback.isEmpty { blocks.append("## Transcript\n\n" + fallback) }
        } else {
            let lines = segments.map { segment -> String in
                var parts: [String] = []
                if options.timestamps { parts.append("`" + Timecode.format(segment.start) + "`") }
                if options.speakerLabels, let index = segment.speakerIndex {
                    parts.append("**" + Speakers.name(at: index, in: speakerNames) + ":**")
                }
                parts.append(segment.text)
                return parts.joined(separator: " ")
            }
            blocks.append("## Transcript\n\n" + lines.joined(separator: "\n\n"))
        }
        return blocks.joined(separator: "\n\n") + "\n"
    }

    public static func srt(segments: [TranscriptSegment], speakerNames: [String], options: ExportOptions) -> String {
        var cues: [String] = []
        for segment in segments where !segment.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let start = max(0, segment.start)
            let end = segment.end > start ? segment.end : start + 1
            var line = segment.text
            if options.speakerLabels, let index = segment.speakerIndex {
                line = Speakers.name(at: index, in: speakerNames) + ": " + line
            }
            cues.append("\(cues.count + 1)\n\(srtTime(start)) --> \(srtTime(end))\n\(line)")
        }
        return cues.isEmpty ? "" : cues.joined(separator: "\n\n") + "\n"
    }

    /// "00:01:02,500"
    public static func srtTime(_ seconds: TimeInterval) -> String {
        let total = Int((max(0, seconds.isFinite ? seconds : 0) * 1000).rounded())
        let ms = total % 1000
        let s = (total / 1000) % 60
        let m = (total / 60_000) % 60
        let h = total / 3_600_000
        return String(format: "%02d:%02d:%02d,%03d", h, m, s, ms)
    }

    /// A file name that is safe on every platform, without the extension.
    public static func fileName(for title: String) -> String {
        let blocked = CharacterSet(charactersIn: "/\\:*?\"<>|").union(.controlCharacters)
        let cleaned = title.unicodeScalars.map { blocked.contains($0) ? "-" : String($0) }.joined()
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let limited = String(cleaned.prefix(80)).trimmingCharacters(in: .whitespacesAndNewlines)
        return limited.isEmpty ? "Murmur note" : limited
    }
}
