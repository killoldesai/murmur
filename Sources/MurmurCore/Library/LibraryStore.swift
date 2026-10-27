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

    public func renameFolder(_ folder: Folder, to name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed != folder.name else { return }
        folder.name = trimmed
        save()
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

    /// With iCloud sync, deleting a note on one device leaves its audio file behind on the device
    /// that recorded it. This removes audio files that no note uses, once they are older than
    /// `age` (so a file that is still being imported or recorded is never touched).
    /// - Returns: how many files were removed.
    @discardableResult
    public func removeOrphanedAudio(olderThan age: TimeInterval = 86_400, now: Date = Date()) -> Int {
        let notes = (try? context.fetch(FetchDescriptor<Note>())) ?? []
        let used = Set(notes.compactMap(\.audioFileName))
        var removed = 0
        for file in files.allFiles() where !used.contains(file.name) && now.timeIntervalSince(file.modified) > age {
            files.delete(file.name)
            removed += 1
        }
        return removed
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

    /// Stores a summary on the note (as JSON text in `Note.summary`), or removes it with `nil`.
    public func setSummary(_ summary: NoteSummary?, for note: Note) {
        note.summary = summary?.encoded()
        save()
    }

    /// Ticks or unticks one action item of the note's summary.
    public func toggleActionItem(_ id: UUID, in note: Note) {
        guard var summary = NoteSummary.decode(note.summary),
              let index = summary.actionItems.firstIndex(where: { $0.id == id }) else { return }
        summary.actionItems[index].done.toggle()
        note.summary = summary.encoded()
        save()
    }

    private func save() { try? context.save() }
}

extension ModelContext {
    /// The folder with this id, or `nil` (also when it was deleted since the setting was saved).
    func folder(withID id: UUID?) -> Folder? {
        guard let id else { return nil }
        return ((try? fetch(FetchDescriptor<Folder>())) ?? []).first { $0.id == id }
    }
}
