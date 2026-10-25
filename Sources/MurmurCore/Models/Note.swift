import Foundation
import SwiftData

public enum NoteSource: String, Codable, Sendable, CaseIterable {
    case recording
    case importedFile
    case watch
}

public enum NoteStatus: String, Codable, Sendable, CaseIterable {
    case recording
    case queued
    case transcribing
    case ready
    case failed
}

/// A recording and its transcript.
///
/// SCHEMA RULES (shared by iPhone, iPad, Mac and Watch, and meant to sync through CloudKit):
/// every stored property has a default value, relationships are optional, and there are no
/// unique constraints. Ask the owner before changing any stored property.
@Model
public final class Note {
    public var id: UUID = UUID()
    public var title: String = "Untitled"
    public var createdAt: Date = Date()
    /// Seconds.
    public var duration: TimeInterval = 0
    /// File name only (not a full URL): the app container path changes between installs and devices.
    /// Resolve it against the app's audio directory.
    public var audioFileName: String?
    public var transcript: String = ""
    public var segments: [TranscriptSegment] = []
    public var summary: String?
    /// Bookmark times in seconds, added while recording.
    public var bookmarks: [TimeInterval] = []
    /// ISO language code, e.g. "en". `nil` until detected.
    public var language: String?
    /// Display names; `TranscriptSegment.speakerIndex` indexes into this list.
    public var speakerNames: [String] = []
    var sourceRaw: String = NoteSource.recording.rawValue
    var statusRaw: String = NoteStatus.ready.rawValue
    public var folder: Folder?

    public init(
        title: String = "Untitled",
        createdAt: Date = Date(),
        duration: TimeInterval = 0,
        audioFileName: String? = nil,
        source: NoteSource = .recording,
        status: NoteStatus = .ready
    ) {
        self.title = title
        self.createdAt = createdAt
        self.duration = duration
        self.audioFileName = audioFileName
        self.sourceRaw = source.rawValue
        self.statusRaw = status.rawValue
    }

    public var source: NoteSource {
        get { NoteSource(rawValue: sourceRaw) ?? .recording }
        set { sourceRaw = newValue.rawValue }
    }

    public var status: NoteStatus {
        get { NoteStatus(rawValue: statusRaw) ?? .ready }
        set { statusRaw = newValue.rawValue }
    }
}
