import Foundation
import SwiftData

/// iPhone side: turns a recording that arrived from the watch into a queued note, once.
@MainActor
public final class WatchInbox {
    private let context: ModelContext
    private let files: AudioFileStore
    private let converter: AudioConverting
    private let defaults: UserDefaults
    private let receiptsKey = "watch.receivedIDs"

    public init(context: ModelContext, files: AudioFileStore, converter: AudioConverting, defaults: UserDefaults = .standard) {
        self.context = context
        self.files = files
        self.converter = converter
        self.defaults = defaults
    }

    public func hasReceived(_ id: UUID) -> Bool {
        receivedIDs.contains(id.uuidString)
    }

    /// Converts the file for Whisper, adds a queued note marked "From Watch" and remembers the id.
    /// - Returns: the note, or `nil` when this id was already received or the file could not be read.
    @discardableResult
    public func receive(fileURL: URL, transfer: WatchTransfer) async -> Note? {
        guard !hasReceived(transfer.id) else { return nil }
        let fileName = files.newFileName(id: transfer.id, ext: "wav")
        do {
            try files.ensureDirectory()
            let duration = try await converter.convert(from: fileURL, to: files.url(for: fileName)) { _ in }
            let note = Note(
                title: "Watch " + RecordingNoteStore.defaultTitle(for: transfer.createdAt),
                createdAt: transfer.createdAt,
                duration: duration > 0 ? duration : transfer.duration,
                audioFileName: fileName,
                source: .watch,
                status: .queued
            )
            context.insert(note)
            try context.save()
            remember(transfer.id)
            return note
        } catch {
            files.delete(fileName)
            return nil
        }
    }

    private var receivedIDs: [String] {
        defaults.stringArray(forKey: receiptsKey) ?? []
    }

    private func remember(_ id: UUID) {
        // Keep the newest 500 ids; far more than a watch could resend.
        defaults.set(Array((receivedIDs + [id.uuidString]).suffix(500)), forKey: receiptsKey)
    }
}
