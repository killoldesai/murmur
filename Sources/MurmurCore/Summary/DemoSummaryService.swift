import Foundation

/// A fake summary service for previews, CI screenshots and tests.
public struct DemoSummaryService: SummaryService {
    public var availability: SummaryAvailability
    public var result: NoteSummary?
    public var error: SummaryError?
    public var delayNanoseconds: UInt64

    public init(availability: SummaryAvailability = .available, result: NoteSummary? = nil,
                error: SummaryError? = nil, delayNanoseconds: UInt64 = 0) {
        self.availability = availability
        self.result = result
        self.error = error
        self.delayNanoseconds = delayNanoseconds
    }

    public static let sample = NoteSummary(
        template: .meeting,
        text: "The team chose to ship the Apple Watch app before iCloud sync. Design will confirm the Watch scope this week, and the Q4 timeline moves out by two weeks to make room.",
        actionItems: [
            ActionItem(text: "Update the Q4 timeline and share it", owner: "Priya", due: "by Friday", done: true),
            ActionItem(text: "Confirm Watch app scope with design", owner: "Alex", due: "this week"),
            ActionItem(text: "Start the CloudKit migration spike", owner: "Jordan", due: "next week")
        ],
        generatedAt: Date(timeIntervalSince1970: 1_761_400_000)
    )

    public func summarize(
        segments: [TranscriptSegment], speakerNames: [String], template: SummaryTemplate,
        onProgress: @escaping @Sendable (String) -> Void
    ) async throws -> NoteSummary {
        onProgress("Summarizing…")
        if delayNanoseconds > 0 { try await Task.sleep(nanoseconds: delayNanoseconds) }
        if let error { throw error }
        var summary = result ?? Self.sample
        summary.template = template
        if !template.hasActionItems { summary.actionItems = [] }
        return summary
    }
}
