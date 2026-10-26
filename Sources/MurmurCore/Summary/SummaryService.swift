import Foundation
#if canImport(FoundationModels)
import FoundationModels
#endif

#if canImport(FoundationModels)
/// Apple's on-device language model (Apple Intelligence). iOS 26 and later.
@available(iOS 26.0, macOS 26.0, *)
public struct FoundationModelsGenerator: TextGenerator {
    public init() {}

    public static var availability: SummaryAvailability {
        switch SystemLanguageModel.default.availability {
        case .available:
            return .available
        case .unavailable(let reason):
            switch reason {
            case .deviceNotEligible:
                return .unavailable("This device doesn’t support Apple Intelligence.")
            case .appleIntelligenceNotEnabled:
                return .unavailable("Turn on Apple Intelligence in Settings to create summaries.")
            case .modelNotReady:
                return .unavailable("The on-device model is still getting ready. Try again later.")
            @unknown default:
                return .unavailable("Apple Intelligence isn’t available right now.")
            }
        }
    }

    public func generate(instructions: String, prompt: String) async throws -> String {
        let session = LanguageModelSession(instructions: instructions)
        do {
            return try await session.respond(to: prompt).content
        } catch let error as LanguageModelSession.GenerationError {
            switch error {
            case .guardrailViolation: throw SummaryError.refused
            default: throw SummaryError.failed
            }
        }
    }
}
#endif

/// The summary service the app uses: Apple's on-device model where it exists, otherwise
/// "unavailable" (the Summary tab is hidden).
public struct OnDeviceSummaryService: SummaryService {
    public init() {}

    public var availability: SummaryAvailability {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, macOS 26.0, *) { return FoundationModelsGenerator.availability }
        #endif
        return .unavailable("Summaries need iOS 26 and a device with Apple Intelligence.")
    }

    public func summarize(
        segments: [TranscriptSegment],
        speakerNames: [String],
        template: SummaryTemplate,
        onProgress: @escaping @Sendable (String) -> Void
    ) async throws -> NoteSummary {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, macOS 26.0, *) {
            return try await Summarizer(generator: FoundationModelsGenerator())
                .summarize(segments: segments, speakerNames: speakerNames, template: template, onProgress: onProgress)
        }
        #endif
        throw SummaryError.unavailable
    }
}
