import Foundation
import Observation

/// Drives the Summary tab: availability, the chosen template, and one generation at a time.
@MainActor
@Observable
public final class SummaryController {
    public enum State: Equatable {
        case idle
        case generating(String)
        case failed(String)
    }

    public private(set) var state: State = .idle
    public var template: SummaryTemplate = .meeting

    @ObservationIgnored private let service: SummaryService
    @ObservationIgnored private var task: Task<NoteSummary?, Never>?

    public init(service: SummaryService) {
        self.service = service
    }

    public var availability: SummaryAvailability { service.availability }
    public var isGenerating: Bool {
        if case .generating = state { return true }
        return false
    }

    /// Creates a summary of the note's transcript. The caller saves the result.
    /// - Returns: `nil` when it failed (see `state`) or was cancelled.
    public func generate(segments: [TranscriptSegment], speakerNames: [String]) async -> NoteSummary? {
        guard !isGenerating else { return nil }
        if case .unavailable(let reason) = service.availability {
            state = .failed(reason)
            return nil
        }
        guard !segments.isEmpty else {
            state = .failed(SummaryError.emptyTranscript.errorDescription ?? "")
            return nil
        }
        state = .generating("Starting…")
        let template = self.template
        let service = self.service
        let work = Task { () -> NoteSummary? in
            do {
                let summary = try await service.summarize(segments: segments, speakerNames: speakerNames, template: template) { message in
                    Task { @MainActor [weak self] in
                        guard let self, self.isGenerating else { return }
                        self.state = .generating(message)
                    }
                }
                return summary
            } catch is CancellationError {
                return nil
            } catch {
                await MainActor.run { [weak self] in
                    self?.state = .failed((error as? LocalizedError)?.errorDescription ?? SummaryError.failed.errorDescription ?? "")
                }
                return nil
            }
        }
        task = work
        let result = await work.value
        task = nil
        if result != nil || !isFailed { state = .idle }
        return result
    }

    public func cancel() {
        task?.cancel()
    }

    public func dismissError() {
        if isFailed { state = .idle }
    }

    private var isFailed: Bool {
        if case .failed = state { return true }
        return false
    }
}
