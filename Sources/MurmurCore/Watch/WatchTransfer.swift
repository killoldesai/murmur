import Foundation

/// One recording made on the Apple Watch. The recording id is the idempotency key: the iPhone
/// ignores an id it has already turned into a note, so a retry never makes a duplicate.
public struct WatchTransfer: Codable, Equatable, Identifiable, Sendable {
    public let id: UUID
    public let createdAt: Date
    public var duration: TimeInterval
    /// File name on the watch (an m4a next to the outbox).
    public let fileName: String

    public init(id: UUID = UUID(), createdAt: Date = Date(), duration: TimeInterval, fileName: String? = nil) {
        self.id = id
        self.createdAt = createdAt
        self.duration = duration
        self.fileName = fileName ?? "\(id.uuidString.lowercased()).m4a"
    }

    /// What travels with the file through Watch Connectivity (property-list values only).
    public var metadata: [String: String] {
        [
            "id": id.uuidString,
            "createdAt": String(createdAt.timeIntervalSince1970),
            "duration": String(duration),
            "fileName": fileName,
        ]
    }

    public init?(metadata: [String: Any]?) {
        guard
            let metadata,
            let idText = metadata["id"] as? String, let id = UUID(uuidString: idText),
            let createdText = metadata["createdAt"] as? String, let created = TimeInterval(createdText),
            let durationText = metadata["duration"] as? String, let duration = TimeInterval(durationText),
            let fileName = metadata["fileName"] as? String
        else { return nil }
        self.init(id: id, createdAt: Date(timeIntervalSince1970: created), duration: duration, fileName: fileName)
    }
}

public enum WatchDelivery: String, Codable, Sendable {
    /// Saved on the watch, not handed to Watch Connectivity yet (or the transfer failed).
    case waiting
    /// Queued with Watch Connectivity; it arrives when the iPhone is in range.
    case sending
    /// The iPhone has the file.
    case delivered
}

/// A recording on the watch with its delivery status.
public struct WatchRecordingEntry: Codable, Equatable, Identifiable, Sendable {
    public var transfer: WatchTransfer
    public var delivery: WatchDelivery
    public var id: UUID { transfer.id }

    public init(transfer: WatchTransfer, delivery: WatchDelivery = .waiting) {
        self.transfer = transfer
        self.delivery = delivery
    }

    /// "Today · 0:58" style line for the Recent list.
    public func meta(now: Date = Date(), calendar: Calendar = .current) -> String {
        let day: String
        if calendar.isDate(transfer.createdAt, inSameDayAs: now) {
            day = "Today"
        } else if let yesterday = calendar.date(byAdding: .day, value: -1, to: now), calendar.isDate(transfer.createdAt, inSameDayAs: yesterday) {
            day = "Yesterday"
        } else {
            day = transfer.createdAt.formatted(.dateTime.month(.abbreviated).day())
        }
        return "\(day) · \(Timecode.format(transfer.duration))"
    }

    public var title: String {
        "Memo " + transfer.createdAt.formatted(.dateTime.hour().minute())
    }
}
