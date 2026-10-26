import Foundation
import Observation

public struct TranscriptionLanguage: Equatable, Identifiable, Sendable {
    /// Whisper language code, or `nil` to detect it.
    public let code: String?
    public let name: String
    public var id: String { code ?? "auto" }

    public static let all: [TranscriptionLanguage] = [
        .init(code: nil, name: "Auto-detect"),
        .init(code: "en", name: "English"),
        .init(code: "es", name: "Spanish"),
        .init(code: "fr", name: "French"),
        .init(code: "de", name: "German"),
        .init(code: "it", name: "Italian"),
        .init(code: "pt", name: "Portuguese"),
        .init(code: "nl", name: "Dutch"),
        .init(code: "ru", name: "Russian"),
        .init(code: "ja", name: "Japanese"),
        .init(code: "ko", name: "Korean"),
        .init(code: "zh", name: "Chinese"),
        .init(code: "hi", name: "Hindi"),
        .init(code: "ar", name: "Arabic")
    ]

    public static func name(for code: String?) -> String {
        all.first { $0.code == code }?.name ?? "Auto-detect"
    }
}

/// Preferences kept on this device (UserDefaults).
@MainActor
@Observable
public final class AppSettings {
    public private(set) var deleteAudioAfterTranscribing: Bool
    public private(set) var hapticsEnabled: Bool
    /// `nil` detects the language of each recording.
    public private(set) var language: String?
    public private(set) var hasCompletedOnboarding: Bool

    @ObservationIgnored private let defaults: UserDefaults

    private enum Key {
        static let deleteAudio = "settings.deleteAudioAfterTranscribing"
        static let haptics = "settings.haptics"
        static let language = "settings.language"
        static let onboarded = "settings.onboardingDone"
    }

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        deleteAudioAfterTranscribing = defaults.bool(forKey: Key.deleteAudio)
        hapticsEnabled = defaults.object(forKey: Key.haptics) as? Bool ?? true
        language = defaults.string(forKey: Key.language)
        hasCompletedOnboarding = defaults.bool(forKey: Key.onboarded)
    }

    public func setDeleteAudioAfterTranscribing(_ value: Bool) {
        deleteAudioAfterTranscribing = value
        defaults.set(value, forKey: Key.deleteAudio)
    }

    public func setHapticsEnabled(_ value: Bool) {
        hapticsEnabled = value
        defaults.set(value, forKey: Key.haptics)
    }

    public func setLanguage(_ code: String?) {
        language = code
        if let code { defaults.set(code, forKey: Key.language) } else { defaults.removeObject(forKey: Key.language) }
    }

    public func completeOnboarding() {
        hasCompletedOnboarding = true
        defaults.set(true, forKey: Key.onboarded)
    }
}
