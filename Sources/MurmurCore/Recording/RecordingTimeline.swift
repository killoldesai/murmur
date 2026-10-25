import Foundation

/// Tracks elapsed recording time across pauses, and bookmark times. Pure value logic: the caller
/// passes the current time, so it is deterministic in tests.
public struct RecordingTimeline: Equatable, Sendable {
    private var accumulated: TimeInterval = 0
    private var runningSince: Date?
    public private(set) var bookmarks: [TimeInterval] = []

    public init() {}

    public var isRunning: Bool { runningSince != nil }

    public mutating func start(at now: Date) {
        guard runningSince == nil else { return }
        runningSince = now
    }

    public mutating func pause(at now: Date) {
        guard let since = runningSince else { return }
        accumulated += max(0, now.timeIntervalSince(since))
        runningSince = nil
    }

    public mutating func resume(at now: Date) {
        start(at: now)
    }

    public func elapsed(at now: Date) -> TimeInterval {
        guard let since = runningSince else { return accumulated }
        return accumulated + max(0, now.timeIntervalSince(since))
    }

    /// Records a bookmark at the current elapsed time and returns that time.
    @discardableResult
    public mutating func addBookmark(at now: Date) -> TimeInterval {
        let t = elapsed(at: now)
        bookmarks.append(t)
        return t
    }
}
