import Foundation

/// Where recordings live on disk. Notes store only the file name; this resolves it to a URL.
public struct AudioFileStore: Sendable {
    public let directory: URL

    public init(directory: URL) {
        self.directory = directory
    }

    /// `Application Support/Murmur/Audio`
    public static var standard: AudioFileStore {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return AudioFileStore(directory: base.appendingPathComponent("Murmur/Audio", isDirectory: true))
    }

    /// Recordings are 16 kHz mono 16-bit PCM in a CAF container: the format Whisper wants, and a
    /// CAF file stays readable even if the app is killed mid-recording (an m4a would not).
    public func newFileName(id: UUID = UUID()) -> String {
        "\(id.uuidString.lowercased()).caf"
    }

    public func url(for fileName: String) -> URL {
        directory.appendingPathComponent(fileName, isDirectory: false)
    }

    public func ensureDirectory() throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    public func exists(_ fileName: String) -> Bool {
        FileManager.default.fileExists(atPath: url(for: fileName).path)
    }

    public func delete(_ fileName: String) {
        try? FileManager.default.removeItem(at: url(for: fileName))
    }
}
