import Foundation

/// A plain file copy of the SwiftData store, made once before iCloud sync is first switched on,
/// so a bad first sync can never cost the person their notes.
public enum StoreBackup {
    /// Copies the store and its side files (`-wal`, `-shm`) into a new dated folder.
    /// Call before the store is opened, so the files are not changing.
    /// - Returns: the backup folder, or `nil` when there is no store yet.
    @discardableResult
    public static func copyStore(at storeURL: URL, into backups: URL, now: Date = Date()) throws -> URL? {
        let fm = FileManager.default
        guard fm.fileExists(atPath: storeURL.path) else { return nil }
        let stamp = DateFormatter()
        stamp.locale = Locale(identifier: "en_US_POSIX")
        stamp.dateFormat = "yyyyMMdd-HHmmss"
        let folder = backups.appendingPathComponent("before-icloud-\(stamp.string(from: now))", isDirectory: true)
        try fm.createDirectory(at: folder, withIntermediateDirectories: true)
        for suffix in ["", "-wal", "-shm"] {
            let source = URL(fileURLWithPath: storeURL.path + suffix)
            guard fm.fileExists(atPath: source.path) else { continue }
            try fm.copyItem(at: source, to: folder.appendingPathComponent(source.lastPathComponent))
        }
        return folder
    }
}
