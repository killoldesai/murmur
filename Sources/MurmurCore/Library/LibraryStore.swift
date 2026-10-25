import Foundation
import SwiftData

/// Actions on notes and folders that the Library and Note screens trigger.
@MainActor
public final class LibraryStore {
    private let context: ModelContext
    private let files: AudioFileStore

    public init(context: ModelContext, files: AudioFileStore) {
        self.context = context
        self.files = files
    }

    @discardableResult
    public func createFolder(name: String, colorIndex: Int? = nil) -> Folder? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let existing = (try? context.fetch(FetchDescriptor<Folder>())) ?? []
        let folder = Folder(
            name: trimmed,
            colorIndex: colorIndex ?? existing.count,
            sortOrder: (existing.map(\.sortOrder).max() ?? -1) + 1
        )
        context.insert(folder)
        save()
        return folder
    }

    public func deleteFolder(_ folder: Folder) {
        context.delete(folder)   // notes become unfiled (nullify rule)
        save()
    }

    public func rename(_ note: Note, to title: String) {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed != note.title else { return }
        note.title = trimmed
        save()
    }

    public func move(_ note: Note, to folder: Folder?) {
        note.folder = folder
        save()
    }

    /// Deletes the note and its audio file.
    public func delete(_ note: Note) {
        if let name = note.audioFileName { files.delete(name) }
        context.delete(note)
        save()
    }

    /// Saves an edited transcript and keeps the plain-text copy in step.
    public func applyEdit(_ segments: [TranscriptSegment], to note: Note) {
        note.segments = segments
        note.transcript = segments.joinedText
        save()
    }

    /// Adds a named speaker to the note.
    /// - Returns: the new speaker's index.
    @discardableResult
    public func addSpeaker(named name: String, to note: Note) -> Int {
        var names = note.speakerNames
        let count = Speakers.count(names: names, segments: note.segments)
        while names.count < count { names.append("") }
        names.append(name.trimmingCharacters(in: .whitespacesAndNewlines))
        note.speakerNames = names
        save()
        return names.count - 1
    }

    public func renameSpeaker(at index: Int, to name: String, in note: Note) {
        var names = note.speakerNames
        while names.count <= index { names.append("") }
        names[index] = name.trimmingCharacters(in: .whitespacesAndNewlines)
        note.speakerNames = names
        save()
    }

    private func save() { try? context.save() }
}
