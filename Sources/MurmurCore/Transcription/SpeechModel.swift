import Foundation

/// A Whisper model the user can download. `variant` is the WhisperKit model name.
public struct SpeechModel: Identifiable, Equatable, Sendable {
    public let id: String
    public let variant: String
    public let title: String
    public let subtitle: String
    public let approximateBytes: Int64
    public let isRecommended: Bool

    public init(id: String, variant: String, title: String, subtitle: String,
                approximateBytes: Int64, isRecommended: Bool = false) {
        self.id = id
        self.variant = variant
        self.title = title
        self.subtitle = subtitle
        self.approximateBytes = approximateBytes
        self.isRecommended = isRecommended
    }

    /// Whisper Large v3 Turbo, compressed. Needs an iPhone with an A16 chip or newer.
    public static let large = SpeechModel(
        id: "large",
        variant: "openai_whisper-large-v3-v20240930_turbo_632MB",
        title: "Best accuracy",
        subtitle: "Whisper Large v3 Turbo · 100+ languages",
        approximateBytes: 632_000_000,
        isRecommended: true
    )

    public static let small = SpeechModel(
        id: "small",
        variant: "openai_whisper-small",
        title: "Faster & lighter",
        subtitle: "Whisper Small · good for clear speech",
        approximateBytes: 500_000_000
    )

    /// For automated tests only. Not offered to users.
    public static let tiny = SpeechModel(
        id: "tiny",
        variant: "openai_whisper-tiny",
        title: "Tiny (tests)",
        subtitle: "Whisper Tiny",
        approximateBytes: 80_000_000
    )

    /// The models shown on the download screen, in order.
    public static let choices: [SpeechModel] = [.large, .small]

    public static func model(withID id: String) -> SpeechModel? {
        ([large, small, tiny]).first { $0.id == id }
    }
}

public enum ByteText {
    /// "1.60 GB" or "632 MB". Decimal units, as Apple shows them.
    public static func format(_ bytes: Int64) -> String {
        let b = Double(max(0, bytes))
        if b >= 1_000_000_000 { return String(format: "%.2f GB", b / 1_000_000_000) }
        return String(format: "%.0f MB", b / 1_000_000)
    }
}
