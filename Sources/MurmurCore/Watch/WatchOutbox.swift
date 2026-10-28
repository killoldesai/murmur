import Foundation
import Observation

/// The watch's list of recordings and what has happened to each, saved as JSON next to the audio.
/// Newest first. Audio stays on the watch until the person deletes the recording (so it can be
/// played back), except that delivered recordings beyond the newest `keepDelivered` are cleaned up.
@MainActor
@Observable
public final class WatchOutbox {
    public private(set) var entries: [WatchRecordingEntry] = []
    /// Called after every change (the watch app uses it to refresh complications).
    @ObservationIgnored public var onChange: (@MainActor () -> Void)?

    public let directory: URL
    @ObservationIgnored private let keepDelivered: Int
    private var indexURL: URL { directory.appendingPathComponent("outbox.json") }

    public init(directory: URL, keepDelivered: Int = 10) {
        self.directory = directory
        self.keepDelivered = keepDelivered
        load()
    }

    // MARK: Reading

    public func audioURL(for entry: WatchRecordingEntry) -> URL {
        directory.appendingPathComponent(entry.transfer.fileName)
    }

    public func recent(limit: Int = 10) -> [WatchRecordingEntry] {
        Array(entries.prefix(limit))
    }

    /// Recordings the iPhone does not have yet.
    public var waitingCount: Int { entries.filter { $0.delivery != .delivered }.count }

    public func notesToday(now: Date = Date(), calendar: Calendar = .current) -> Int {
        entries.filter { calendar.isDate($0.transfer.createdAt, inSameDayAs: now) }.count
    }

    public func entry(id: UUID) -> WatchRecordingEntry? {
        entries.first { $0.id == id }
    }

    // MARK: Changing

    public func add(_ transfer: WatchTransfer) {
        guard entry(id: transfer.id) == nil else { return }
        entries.insert(WatchRecordingEntry(transfer: transfer), at: 0)
        entries.sort { $0.transfer.createdAt > $1.transfer.createdAt }
        changed()
    }

    public func setDelivery(_ delivery: WatchDelivery, for id: UUID) {
        guard let index = entries.firstIndex(where: { $0.id == id }), entries[index].delivery != delivery else { return }
        entries[index].delivery = delivery
        trimDelivered()
        changed()
    }

    public func delete(id: UUID) {
        guard let entry = entry(id: id) else { return }
        try? FileManager.default.removeItem(at: audioURL(for: entry))
        entries.removeAll { $0.id == id }
        changed()
    }

    /// Entries whose audio file is gone cannot be sent or played; drop them.
    public func removeMissingFiles() {
        let missing = entries.filter { !FileManager.default.fileExists(atPath: audioURL(for: $0).path) }
        guard !missing.isEmpty else { return }
        entries.removeAll { entry in missing.contains { $0.id == entry.id } }
        changed()
    }

    // MARK: Saving

    private func trimDelivered() {
        let delivered = entries.filter { $0.delivery == .delivered }
        guard delivered.count > keepDelivered else { return }
        for old in delivered.dropFirst(keepDelivered) {
            try? FileManager.default.removeItem(at: audioURL(for: old))
            entries.removeAll { $0.id == old.id }
        }
    }

    private func changed() {
        save()
        onChange?()
    }

    private func save() {
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        if let data = try? encoder.encode(entries) {
            try? data.write(to: indexURL, options: .atomic)
        }
    }

    private func load() {
        guard let data = try? Data(contentsOf: indexURL) else { return }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        entries = (try? decoder.decode([WatchRecordingEntry].self, from: data)) ?? []
    }
}

/// What the complications and Smart Stack widget show. The app writes it; the widget reads it.
public struct WatchSnapshot: Codable, Equatable, Sendable {
    public struct Memo: Codable, Equatable, Sendable {
        public var title: String
        public var detail: String

        public init(title: String, detail: String) {
            self.title = title
            self.detail = detail
        }
    }

    public var notesToday: Int
    public var waitingCount: Int
    public var lastMemoText: String
    public var recent: [Memo]

    public init(notesToday: Int, waitingCount: Int, lastMemoText: String, recent: [Memo]) {
        self.notesToday = notesToday
        self.waitingCount = waitingCount
        self.lastMemoText = lastMemoText
        self.recent = recent
    }

    public static let empty = WatchSnapshot(notesToday: 0, waitingCount: 0, lastMemoText: "No memos yet", recent: [])

    /// App group shared by the watch app and its widget. It must be added as a capability when the
    /// app is signed; without it the widget simply shows `empty`.
    public static let appGroup = "group.com.appyzone.murmur"
    private static let key = "watch.snapshot"

    @MainActor
    public static func make(from outbox: WatchOutbox, now: Date = Date(), calendar: Calendar = .current) -> WatchSnapshot {
        let recent = outbox.recent(limit: 2)
        func status(_ entry: WatchRecordingEntry) -> String {
            switch entry.delivery {
            case .delivered: "Sent to iPhone"
            case .sending: "Sending"
            case .waiting: "Waiting for iPhone"
            }
        }
        let last = recent.first.map { "Last memo \(Timecode.format($0.transfer.duration)) · \(status($0).lowercased())" } ?? "No memos yet"
        return WatchSnapshot(
            notesToday: outbox.notesToday(now: now, calendar: calendar),
            waitingCount: outbox.waitingCount,
            lastMemoText: last,
            recent: recent.map { Memo(title: $0.title, detail: status($0)) }
        )
    }

    public func save(to defaults: UserDefaults? = UserDefaults(suiteName: WatchSnapshot.appGroup)) {
        guard let data = try? JSONEncoder().encode(self) else { return }
        defaults?.set(data, forKey: Self.key)
    }

    public static func load(from defaults: UserDefaults? = UserDefaults(suiteName: WatchSnapshot.appGroup)) -> WatchSnapshot {
        guard let data = defaults?.data(forKey: key), let value = try? JSONDecoder().decode(WatchSnapshot.self, from: data) else {
            return .empty
        }
        return value
    }
}
