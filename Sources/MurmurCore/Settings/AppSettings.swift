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
    /// Mac: show the menu bar item.
    public private(set) var showMenuBarIcon: Bool
    /// Mac: hide the Dock icon (the menu bar item stays).
    public private(set) var hideDockIcon: Bool
    /// Mac: the global shortcut that starts a recording.
    public private(set) var recordShortcut: RecordShortcut
    /// The person's iCloud sync choice. It takes effect the next time the app opens.
    public private(set) var iCloudSyncEnabled: Bool
    /// What sync is doing in this run (set once at launch from `MurmurSchema.openStore`).
    public var syncState: SyncState = .off
    /// What happens to a recording's audio once it has been transcribed.
    public private(set) var audioFormat: AudioFormat
    /// Apple Watch recordings that arrived since the person last looked (the Library banner).
    public private(set) var newWatchRecordings: Int
    /// Mac: the folder new recordings and imports are filed in. `nil` leaves them unfiled.
    public private(set) var defaultFolderID: UUID?
    /// Mac: the microphone to record from (its device UID). `nil` uses the system default.
    public private(set) var inputDeviceUID: String?

    @ObservationIgnored private let defaults: UserDefaults

    private enum Key {
        static let deleteAudio = "settings.deleteAudioAfterTranscribing"
        static let haptics = "settings.haptics"
        static let language = "settings.language"
        static let onboarded = "settings.onboardingDone"
        static let menuBar = "settings.showMenuBarIcon"
        static let hideDock = "settings.hideDockIcon"
        static let shortcut = "settings.recordShortcut"
        static let iCloud = ICloudSync.defaultsKey
        static let audioFormat = "settings.audioFormat"
        static let newWatch = "settings.newWatchRecordings"
        static let defaultFolder = "settings.defaultFolderID"
        static let inputDevice = "settings.inputDeviceUID"
    }

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        deleteAudioAfterTranscribing = defaults.bool(forKey: Key.deleteAudio)
        hapticsEnabled = defaults.object(forKey: Key.haptics) as? Bool ?? true
        language = defaults.string(forKey: Key.language)
        hasCompletedOnboarding = defaults.bool(forKey: Key.onboarded)
        showMenuBarIcon = defaults.object(forKey: Key.menuBar) as? Bool ?? true
        hideDockIcon = defaults.bool(forKey: Key.hideDock)
        recordShortcut = RecordShortcut.decode(defaults.string(forKey: Key.shortcut)) ?? .default
        iCloudSyncEnabled = defaults.bool(forKey: Key.iCloud)
        audioFormat = AudioFormat(rawValue: defaults.string(forKey: Key.audioFormat) ?? "") ?? .m4a
        newWatchRecordings = defaults.integer(forKey: Key.newWatch)
        defaultFolderID = defaults.string(forKey: Key.defaultFolder).flatMap(UUID.init(uuidString:))
        inputDeviceUID = defaults.string(forKey: Key.inputDevice)
    }

    public func setDefaultFolderID(_ value: UUID?) {
        defaultFolderID = value
        if let value { defaults.set(value.uuidString, forKey: Key.defaultFolder) } else { defaults.removeObject(forKey: Key.defaultFolder) }
    }

    public func setInputDeviceUID(_ value: String?) {
        inputDeviceUID = value
        if let value { defaults.set(value, forKey: Key.inputDevice) } else { defaults.removeObject(forKey: Key.inputDevice) }
    }

    public func setAudioFormat(_ value: AudioFormat) {
        audioFormat = value
        defaults.set(value.rawValue, forKey: Key.audioFormat)
    }

    public func noteWatchRecordingReceived() {
        newWatchRecordings += 1
        defaults.set(newWatchRecordings, forKey: Key.newWatch)
    }

    public func clearNewWatchRecordings() {
        newWatchRecordings = 0
        defaults.set(0, forKey: Key.newWatch)
    }

    public func setICloudSyncEnabled(_ value: Bool) {
        iCloudSyncEnabled = value
        defaults.set(value, forKey: Key.iCloud)
    }

    /// True while notes from other devices may be in the store.
    public var isSyncActive: Bool { syncState == .active }

    /// Shown under the iCloud switch.
    public var syncMessage: String {
        ICloudSync.message(enabled: iCloudSyncEnabled, state: syncState)
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

    public func setShowMenuBarIcon(_ value: Bool) {
        showMenuBarIcon = value
        defaults.set(value, forKey: Key.menuBar)
    }

    /// Ignores shortcuts that are not valid (no Control, Option or Command).
    public func setRecordShortcut(_ value: RecordShortcut) {
        guard value.isValid else { return }
        recordShortcut = value
        defaults.set(value.encoded(), forKey: Key.shortcut)
    }

    public func setHideDockIcon(_ value: Bool) {
        hideDockIcon = value
        defaults.set(value, forKey: Key.hideDock)
    }

    public func completeOnboarding() {
        hasCompletedOnboarding = true
        defaults.set(true, forKey: Key.onboarded)
    }
}
