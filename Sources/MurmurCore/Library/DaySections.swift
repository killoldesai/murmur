import Foundation

public struct NoteSection: Identifiable {
    public let id: Date
    public let title: String
    public let notes: [Note]
}

/// Groups notes by the day they were made: "Today", "Yesterday", then "Oct 23" style dates.
public enum DaySections {
    public static func make(from notes: [Note], now: Date = Date(), calendar: Calendar = .current) -> [NoteSection] {
        let grouped = Dictionary(grouping: notes) { calendar.startOfDay(for: $0.createdAt) }
        return grouped.keys.sorted(by: >).map { day in
            NoteSection(
                id: day,
                title: title(for: day, now: now, calendar: calendar),
                notes: grouped[day]!.sorted { $0.createdAt > $1.createdAt }
            )
        }
    }

    public static func title(for day: Date, now: Date, calendar: Calendar) -> String {
        if calendar.isDate(day, inSameDayAs: now) { return "Today" }
        if let yesterday = calendar.date(byAdding: .day, value: -1, to: now), calendar.isDate(day, inSameDayAs: yesterday) {
            return "Yesterday"
        }
        if calendar.component(.year, from: day) == calendar.component(.year, from: now) {
            return day.formatted(.dateTime.month(.abbreviated).day())
        }
        return day.formatted(.dateTime.month(.abbreviated).day().year())
    }
}

/// Short text shown on note cards.
public enum NoteSummaryText {
    /// First ~100 characters of the transcript on one line, or `nil` when there is none.
    public static func snippet(for note: Note, limit: Int = 100) -> String? {
        let flat = note.transcript.split(whereSeparator: \.isNewline).joined(separator: " ")
            .trimmingCharacters(in: .whitespaces)
        guard !flat.isEmpty else { return nil }
        guard flat.count > limit else { return flat }
        return String(flat.prefix(limit)).trimmingCharacters(in: .whitespaces) + "…"
    }

    /// "3 speakers · 10:30 AM", with "From Apple Watch" for watch notes.
    public static func metaLine(for note: Note) -> String {
        var parts: [String] = []
        if note.source == .watch { parts.append("From Apple Watch") }
        let speakers = Set(note.segments.compactMap(\.speakerIndex)).count
        if speakers > 0 { parts.append("\(speakers) speaker\(speakers == 1 ? "" : "s")") }
        parts.append(note.createdAt.formatted(.dateTime.hour().minute()))
        return parts.joined(separator: " · ")
    }

    /// Status shown instead of a snippet while a note is not transcribed yet.
    public static func statusText(_ status: NoteStatus) -> String? {
        switch status {
        case .recording: "Recording…"
        case .queued: "Waiting to transcribe"
        case .transcribing: "Transcribing…"
        case .failed: "Couldn’t transcribe. Tap to retry."
        case .ready: nil
        }
    }
}

public enum Greeting {
    /// "Good morning" before noon, "Good afternoon" before 5 pm, otherwise "Good evening".
    public static func text(at date: Date = Date(), calendar: Calendar = .current) -> String {
        switch calendar.component(.hour, from: date) {
        case 5..<12: "Good morning"
        case 12..<17: "Good afternoon"
        default: "Good evening"
        }
    }
}

public enum NoteFilter {
    /// Notes in the given folder, or all notes when `folderID` is `nil`.
    public static func filter(_ notes: [Note], folderID: UUID?) -> [Note] {
        guard let folderID else { return notes }
        return notes.filter { $0.folder?.id == folderID }
    }

    /// Notes from the last `days` days (the Mac sidebar's "Recent").
    public static func recent(_ notes: [Note], days: Int = 7, now: Date = Date()) -> [Note] {
        let cutoff = now.addingTimeInterval(-Double(days) * 86_400)
        return notes.filter { $0.createdAt >= cutoff }
    }

    public static func fromWatch(_ notes: [Note]) -> [Note] {
        notes.filter { $0.source == .watch }
    }
}

/// The batch queue's totals (done, waiting, time left) for the Mac queue screen.
public struct QueueStats: Equatable, Sendable {
    public let done: Int
    public let waiting: Int
    public let working: Int
    /// `nil` when work is pending but there is no speed to estimate from yet.
    public let secondsLeft: TimeInterval?

    /// - Parameters:
    ///   - currentETA: seconds left for the note being transcribed, if known.
    ///   - speed: audio seconds per second of work, if known.
    public static func make(notes: [Note], currentETA: TimeInterval?, speed: Double?) -> QueueStats {
        let done = notes.filter { $0.status == .ready }.count
        let queued = notes.filter { $0.status == .queued }
        let working = notes.filter { $0.status == .transcribing }.count
        let pending = queued.count + working
        guard pending > 0 else { return QueueStats(done: done, waiting: 0, working: 0, secondsLeft: 0) }
        var left: TimeInterval?
        if let speed, speed > 0 {
            let waitingAudio = queued.reduce(0) { $0 + $1.duration }
            left = (working > 0 ? (currentETA ?? 0) : 0) + waitingAudio / speed
        }
        return QueueStats(done: done, waiting: queued.count, working: working, secondsLeft: left)
    }
}

public extension NoteSummaryText {
    /// "Oct 25 · 42:10 · 3 speakers" under the title on the Note screen.
    static func headerLine(for note: Note) -> String {
        var parts = [
            note.createdAt.formatted(.dateTime.month(.abbreviated).day()),
            Timecode.format(note.duration),
        ]
        let speakers = Set(note.segments.compactMap(\.speakerIndex)).count
        if speakers > 0 { parts.append("\(speakers) speaker\(speakers == 1 ? "" : "s")") }
        return parts.joined(separator: " · ")
    }
}
