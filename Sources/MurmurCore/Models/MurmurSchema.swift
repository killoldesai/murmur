import Foundation
import SwiftData

/// Builds the one shared SwiftData container used by every app target.
public enum MurmurSchema {
    public static var schema: Schema {
        Schema([Note.self, Folder.self, DictionaryWord.self])
    }

    /// - Parameter inMemory: `true` for tests and previews (nothing is written to disk).
    /// iCloud sync is OFF for now. Turning it on later needs an iCloud container, entitlements
    /// and the Apple Developer account; the models are already CloudKit-compatible.
    public static func makeContainer(inMemory: Bool = false) throws -> ModelContainer {
        let configuration = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: inMemory,
            cloudKitDatabase: .none
        )
        return try ModelContainer(for: schema, configurations: [configuration])
    }
}
