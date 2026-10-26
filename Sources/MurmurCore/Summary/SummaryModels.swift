import Foundation

public enum SummaryTemplate: String, Codable, CaseIterable, Identifiable, Sendable {
    case meeting, lecture, bullets

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .meeting: "Meeting"
        case .lecture: "Lecture"
        case .bullets: "Bullet points"
        }
    }

    /// Only meeting notes ask the model for action items.
    public var hasActionItems: Bool { self == .meeting }
}

public struct ActionItem: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var text: String
    public var owner: String?
    public var due: String?
    public var done: Bool

    public init(id: UUID = UUID(), text: String, owner: String? = nil, due: String? = nil, done: Bool = false) {
        self.id = id
        self.text = text
        self.owner = owner
        self.due = due
        self.done = done
    }

    /// "Priya · by Friday" (the deadline is kept as it was said)
    public var metaLine: String? {
        let parts = [owner, due].compactMap { $0 }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }
}

/// A note's summary. Stored as JSON text in `Note.summary`, so the SwiftData schema is unchanged.
/// Older plain-text summaries still load (as text with no action items).
public struct NoteSummary: Codable, Equatable, Sendable {
    public var template: SummaryTemplate
    public var text: String
    public var actionItems: [ActionItem]
    public var generatedAt: Date

    public init(template: SummaryTemplate, text: String, actionItems: [ActionItem] = [], generatedAt: Date = Date()) {
        self.template = template
        self.text = text
        self.actionItems = actionItems
        self.generatedAt = generatedAt
    }

    public func encoded() -> String {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        guard let data = try? encoder.encode(self), let text = String(data: data, encoding: .utf8) else { return self.text }
        return text
    }

    public static func decode(_ raw: String?) -> NoteSummary? {
        guard let raw, !raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        if raw.hasPrefix("{") {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            if let data = raw.data(using: .utf8), let summary = try? decoder.decode(NoteSummary.self, from: data) {
                return summary
            }
        }
        return NoteSummary(template: .meeting, text: raw)
    }

    /// Plain text for export and copy: the summary, then action items as a checklist.
    public var plainText: String {
        var out = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if !actionItems.isEmpty {
            out += "\n\nAction items:\n" + actionItems.map { item in
                let meta = item.metaLine.map { " (\($0))" } ?? ""
                return "- [\(item.done ? "x" : " ")] \(item.text)\(meta)"
            }.joined(separator: "\n")
        }
        return out
    }

    /// Plain text of whatever is stored in `Note.summary`, or `nil` when there is none.
    public static func plainText(from raw: String?) -> String? {
        decode(raw)?.plainText
    }
}

public enum SummaryAvailability: Equatable, Sendable {
    case available
    /// The reason is written for the user.
    case unavailable(String)
}

public enum SummaryError: LocalizedError, Equatable {
    case unavailable
    case emptyTranscript
    case refused
    case failed

    public var errorDescription: String? {
        switch self {
        case .unavailable: "Summaries need Apple Intelligence on this device."
        case .emptyTranscript: "There’s no transcript to summarize."
        case .refused: "Apple Intelligence declined to summarize this text."
        case .failed: "The summary couldn’t be created. Try again."
        }
    }
}

public protocol SummaryService: Sendable {
    var availability: SummaryAvailability { get }
    func summarize(
        segments: [TranscriptSegment],
        speakerNames: [String],
        template: SummaryTemplate,
        onProgress: @escaping @Sendable (String) -> Void
    ) async throws -> NoteSummary
}
