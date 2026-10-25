import Foundation
import Observation
import SwiftData

public enum ImportFormats {
    /// What AVFoundation reads on every Apple platform.
    public static let supportedExtensions: Set<String> = [
        "mp3", "m4a", "wav", "aac", "aif", "aiff", "caf", "flac", "mp4", "mov", "m4v",
    ]

    public static func isSupported(_ url: URL) -> Bool {
        supportedExtensions.contains(url.pathExtension.lowercased())
    }

    /// File name without its extension, used as the note title.
    public static func title(for url: URL) -> String {
        let name = url.deletingPathExtension().lastPathComponent.trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty ? "Imported file" : name
    }
}

public enum ImportState: Equatable, Sendable {
    case waiting
    case converting(Double)
    case done
    case failed(String)
}

public struct ImportItem: Identifiable, Equatable, Sendable {
    public let id: UUID
    public let sourceURL: URL
    public let deleteSourceAfter: Bool
    public var state: ImportState
    public var duration: TimeInterval?

    public var displayName: String { sourceURL.lastPathComponent }
    public var extensionLabel: String { sourceURL.pathExtension.uppercased() }
}

public protocol AudioConverting: Sendable {
    /// Converts `source` to 16 kHz mono PCM at `destination` and returns the duration.
    func convert(from source: URL, to destination: URL, onProgress: @escaping @Sendable (Double) -> Void) async throws -> TimeInterval
}

public struct WhisperWAVConverter: AudioConverting {
    public init() {}

    public func convert(from source: URL, to destination: URL, onProgress: @escaping @Sendable (Double) -> Void) async throws -> TimeInterval {
        try await AudioTranscoder.convertToWhisperWAV(from: source, to: destination, onProgress: onProgress)
    }
}

/// Converts imported files one after another and adds each as a queued note, which the
/// transcription queue then picks up.
@MainActor
@Observable
public final class ImportQueue {
    public private(set) var items: [ImportItem] = []
    /// Called after each note is added, so the app can start transcription.
    @ObservationIgnored public var onNoteAdded: (@MainActor () -> Void)?

    @ObservationIgnored private let context: ModelContext
    @ObservationIgnored private let files: AudioFileStore
    @ObservationIgnored private let converter: AudioConverting
    @ObservationIgnored private var task: Task<Void, Never>?

    public init(context: ModelContext, files: AudioFileStore, converter: AudioConverting = WhisperWAVConverter()) {
        self.context = context
        self.files = files
        self.converter = converter
    }

    public var doneCount: Int { items.filter { $0.state == .done }.count }
    public var summary: String { items.isEmpty ? "Nothing queued" : "\(doneCount) of \(items.count) done" }
    public var isWorking: Bool { task != nil }

    /// Adds files to the queue and starts converting.
    /// - Returns: how many files were skipped because the type is not supported.
    @discardableResult
    public func enqueue(_ urls: [URL], deleteSourcesAfter: Bool = false) -> Int {
        var skipped = 0
        for url in urls {
            guard ImportFormats.isSupported(url) else { skipped += 1; continue }
            items.append(ImportItem(id: UUID(), sourceURL: url, deleteSourceAfter: deleteSourcesAfter, state: .waiting))
        }
        start()
        return skipped
    }

    public func start() {
        guard task == nil else { return }
        task = Task {
            await self.processAll()
            self.task = nil
        }
    }

    public func clearFinished() {
        items.removeAll { $0.state == .done }
    }

    /// Converts every waiting item. Returns when none are left.
    public func processAll() async {
        while let index = items.firstIndex(where: { $0.state == .waiting }) {
            await process(itemID: items[index].id)
        }
    }

    private func process(itemID: UUID) async {
        guard let item = items.first(where: { $0.id == itemID }) else { return }
        update(itemID) { $0.state = .converting(0) }

        let scoped = item.sourceURL.startAccessingSecurityScopedResource()
        defer {
            if scoped { item.sourceURL.stopAccessingSecurityScopedResource() }
            if item.deleteSourceAfter { try? FileManager.default.removeItem(at: item.sourceURL) }
        }

        let fileName = files.newFileName(ext: "wav")
        do {
            try files.ensureDirectory()
            let duration = try await converter.convert(from: item.sourceURL, to: files.url(for: fileName)) { fraction in
                Task { @MainActor [weak self] in
                    self?.update(itemID) { item in
                        if case .converting(let current) = item.state, fraction > current {
                            item.state = .converting(fraction)
                        }
                    }
                }
            }
            let note = Note(
                title: ImportFormats.title(for: item.sourceURL),
                createdAt: Date(),
                duration: duration,
                audioFileName: fileName,
                source: .importedFile,
                status: .queued
            )
            context.insert(note)
            try context.save()
            update(itemID) {
                $0.state = .done
                $0.duration = duration
            }
            onNoteAdded?()
        } catch {
            files.delete(fileName)
            let message = (error as? LocalizedError)?.errorDescription ?? "This file couldn’t be imported."
            update(itemID) { $0.state = .failed(message) }
        }
    }

    private func update(_ id: UUID, _ change: (inout ImportItem) -> Void) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        change(&items[index])
    }
}
