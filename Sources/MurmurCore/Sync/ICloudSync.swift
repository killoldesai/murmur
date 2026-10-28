import Foundation

/// Where iCloud sync stands. Sync is opt-in, off by default, and only ever uses the person's
/// own private iCloud database: no server, no account of ours.
public enum SyncState: Equatable, Sendable {
    /// The person has not turned sync on.
    case off
    /// Notes sync through the private iCloud database.
    case active
    /// Sync is on, but this device is not signed in to iCloud.
    case needsSignIn
    /// Sync is on, but the store could not be opened with iCloud (missing capability, no account
    /// access). The app keeps working on local data. The text is for the Settings screen.
    case unavailable(String)
}

public enum ICloudSync {
    /// Must match the container in the Apple Developer account and in the entitlements.
    public static let containerIdentifier = "iCloud.com.appyzone.murmur"
    public static let defaultsKey = "settings.iCloudSync"
    static let backupDoneKey = "sync.localBackupMade"

    public static func isEnabled(_ defaults: UserDefaults = .standard) -> Bool {
        defaults.bool(forKey: defaultsKey)
    }

    /// Whether this device is signed in to iCloud.
    public static var isSignedIn: Bool {
        #if os(iOS) || os(macOS)
        FileManager.default.ubiquityIdentityToken != nil
        #else
        false
        #endif
    }

    /// What should happen at launch for a given preference and account state.
    public static func decide(enabled: Bool, signedIn: Bool) -> SyncState {
        guard enabled else { return .off }
        return signedIn ? .active : .needsSignIn
    }

    /// A sentence for Settings under the iCloud switch.
    public static func message(enabled: Bool, state: SyncState) -> String {
        switch state {
        case .active where !enabled:
            return "Sync turns off the next time you open Murmur. Notes already in iCloud stay there."
        case .off where enabled:
            return "Sync starts the next time you open Murmur."
        case .active:
            return "Notes, transcripts, folders and dictionary words sync through your private iCloud. Audio stays on the device that recorded it."
        case .needsSignIn:
            return "Sign in to iCloud in the Settings app (System Settings on Mac) to start syncing."
        case .unavailable(let reason):
            return "iCloud isn’t available right now, so Murmur is using this device only. \(reason)"
        case .off:
            return "Keep notes, transcripts, folders and dictionary words in step across your iPhone, iPad and Mac through your own iCloud. Audio stays on the device that recorded it."
        }
    }
}

/// Whether a note's audio can be played on this device. With sync on, a note recorded elsewhere
/// arrives with its transcript but not its audio.
public enum AudioAvailability: Equatable, Sendable {
    case here
    /// The audio file was removed on purpose (Delete audio after transcribing).
    case deleted
    /// The recording lives on another of the person's devices.
    case onAnotherDevice

    @MainActor
    public static func of(_ note: Note, files: AudioFileStore, syncActive: Bool) -> AudioAvailability {
        guard let name = note.audioFileName else { return .deleted }
        if syncActive && !files.exists(name) { return .onAnotherDevice }
        return .here
    }
}
