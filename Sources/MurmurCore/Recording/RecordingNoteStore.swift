import Foundation
import AVFoundation
import SwiftData

/// Creates, finishes, discards and recovers the `Note` that goes with a recording.
///
/// The note is saved the moment recording starts (status `.recording`). If the app is killed
/// mid-recording, `recoverInterruptedRecordings()` finds it on the next launch and queues the
/// audio that was captured for transcription, so at most the last moments are lost.
@MainActor
public final class RecordingNoteStore {
    private let context: ModelContext
    private let files: AudioFileStore

    public init(context: ModelContext, files: AudioFileStore) {
        self.context = context
        self.files = files
    }

    public static func defaultTitle(for date: Date) -> String {
        "Recording " + date.formatted(.dateTime.month(.abbreviated).day().hour().minute())
    }

    public func beginNote(now: Date = Date()) throws -> Note {
        let note = Note(
            title: Self.defaultTitle(for: now),
            createdAt: now,
            audioFileName: files.newFileName(),
            source: .recording,
            status: .recording
        )
        context.insert(note)
        try context.save()
        return note
    }

    /// Saves bookmarks mid-recording so they survive a crash.
    public func saveBookmarks(_ bookmarks: [TimeInterval], for note: Note) throws {
        note.bookmarks = bookmarks
        try context.save()
    }

    public func finishNote(_ note: Note, duration: TimeInterval, bookmarks: [TimeInterval]) throws {
        note.duration = duration
        note.bookmarks = bookmarks
        note.status = .queued
        try context.save()
    }

    /// Deletes the note and its audio file.
    public func discard(_ note: Note) throws {
        if let name = note.audioFileName {
            files.delete(name)
        }
        context.delete(note)
        try context.save()
    }

    /// Call once at launch. Notes still marked `.recording` were interrupted by a crash or kill.
    /// Ones with audio on disk are queued for transcription; ones without are marked failed.
    /// - Returns: how many notes were recovered (queued).
    @discardableResult
    public func recoverInterruptedRecordings() throws -> Int {
        let all = try context.fetch(FetchDescriptor<Note>())
        var recovered = 0
        for note in all where note.status == .recording {
            guard let name = note.audioFileName, files.exists(name) else {
                note.status = .failed
                continue
            }
            if note.duration == 0, let seconds = Self.audioDuration(of: files.url(for: name)) {
                note.duration = seconds
            }
            note.status = .queued
            recovered += 1
        }
        try context.save()
        return recovered
    }

    static func audioDuration(of url: URL) -> TimeInterval? {
        guard let file = try? AVAudioFile(forReading: url) else { return nil }
        let rate = file.processingFormat.sampleRate
        return rate > 0 ? Double(file.length) / rate : nil
    }
}
