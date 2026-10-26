import Foundation

public enum ExportArtifact: Equatable {
    case file(URL)
    case text(String)
}

public enum ExportError: LocalizedError {
    case noAudio

    public var errorDescription: String? {
        switch self {
        case .noAudio: "This note has no audio file to export."
        }
    }
}

/// Prepares what the share sheet or clipboard receives.
@MainActor
public struct ExportService {
    private let files: AudioFileStore
    private let tempDirectory: URL

    public init(files: AudioFileStore, tempDirectory: URL = FileManager.default.temporaryDirectory) {
        self.files = files
        self.tempDirectory = tempDirectory
    }

    public func prepare(note: Note, format: ExportFormat, options: ExportOptions) async throws -> ExportArtifact {
        let baseName = Exporter.fileName(for: note.title)
        switch format {
        case .copy:
            return .text(Exporter.text(for: note, options: options))
        case .text:
            return .file(try write(Exporter.text(for: note, options: options), name: baseName, ext: "txt"))
        case .subtitles:
            return .file(try write(Exporter.srt(for: note, options: options), name: baseName, ext: "srt"))
        case .audio:
            guard let name = note.audioFileName, files.exists(name) else { throw ExportError.noAudio }
            let destination = try newFolder().appendingPathComponent("\(baseName).m4a")
            #if os(watchOS)
            throw ExportError.noAudio
            #else
            try await AudioTranscoder.exportM4A(from: files.url(for: name), to: destination)
            #endif
            return .file(destination)
        }
    }

    /// A `.md` file named after the note. Used by the Mac export sheet.
    public func prepareMarkdown(note: Note, options: ExportOptions) throws -> URL {
        try write(Exporter.markdown(for: note, options: options), name: Exporter.fileName(for: note.title), ext: "md")
    }

    private func write(_ text: String, name: String, ext: String) throws -> URL {
        let url = try newFolder().appendingPathComponent("\(name).\(ext)")
        try text.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    /// A fresh folder per export, so the shared file keeps the note's name.
    private func newFolder() throws -> URL {
        let folder = tempDirectory.appendingPathComponent("Murmur Export/\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }
}
