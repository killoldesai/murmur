import Foundation
import SwiftData

/// Builds the one shared SwiftData container used by every app target.
public enum MurmurSchema {
    public static var schema: Schema {
        Schema([Note.self, Folder.self, DictionaryWord.self])
    }

    /// A local-only container.
    /// - Parameter inMemory: `true` for tests and previews (nothing is written to disk).
    public static func makeContainer(inMemory: Bool = false) throws -> ModelContainer {
        let configuration = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: inMemory,
            cloudKitDatabase: .none
        )
        return try ModelContainer(for: schema, configurations: [configuration])
    }

    /// Opens the real store for the app. iCloud sync is used only when the person turned it on
    /// in Settings and this device is signed in to iCloud. The same store file is used either
    /// way, so switching sync on or off never moves or copies notes. The first time sync is
    /// switched on, the existing store is copied to a backup folder first.
    ///
    /// If opening with iCloud fails (for example the iCloud capability is missing from a build),
    /// the app falls back to the local store and reports `.unavailable`.
    public static func openStore(
        defaults: UserDefaults = .standard,
        signedIn: Bool = ICloudSync.isSignedIn
    ) throws -> (container: ModelContainer, state: SyncState) {
        let wanted = ICloudSync.decide(enabled: ICloudSync.isEnabled(defaults), signedIn: signedIn)
        guard wanted == .active else {
            return (try makeContainer(), wanted)
        }

        if !defaults.bool(forKey: ICloudSync.backupDoneKey) {
            backUpLocalStore()
            defaults.set(true, forKey: ICloudSync.backupDoneKey)
        }
        do {
            let configuration = ModelConfiguration(
                schema: schema,
                cloudKitDatabase: .private(ICloudSync.containerIdentifier)
            )
            let container = try ModelContainer(for: schema, configurations: [configuration])
            return (container, .active)
        } catch {
            return (try makeContainer(), .unavailable(error.localizedDescription))
        }
    }

    private static func backUpLocalStore() {
        let storeURL = ModelConfiguration(schema: schema, cloudKitDatabase: .none).url
        guard let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else { return }
        let backups = support.appendingPathComponent("Murmur/Backups", isDirectory: true)
        _ = try? StoreBackup.copyStore(at: storeURL, into: backups)
    }
}
