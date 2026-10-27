import Foundation

/// One card on the Folders screen.
public struct FolderCard: Identifiable, Equatable, Sendable {
    public enum Kind: Equatable, Sendable {
        case folder(UUID)
        /// The built-in "From Watch" view of notes recorded on the Apple Watch.
        case fromWatch
    }

    public let kind: Kind
    public let name: String
    /// "8 notes · 5h 12m", "Empty" or "Smart folder".
    public let meta: String
    public let colorIndex: Int

    public var id: String {
        switch kind {
        case .folder(let id): id.uuidString
        case .fromWatch: "from-watch"
        }
    }
}

/// What the Folders screen shows: a card per folder with its note count and total time.
public enum FolderOverview {
    /// "1h 05m", "12m" or "under 1m".
    public static func duration(_ seconds: TimeInterval) -> String {
        let total = max(0, Int(seconds))
        if total > 0 && total < 60 { return "under 1m" }
        let minutes = total / 60
        if minutes >= 60 { return String(format: "%dh %02dm", minutes / 60, minutes % 60) }
        return "\(minutes)m"
    }

    /// "8 notes · 5h 12m", "1 note · 4m" or "Empty".
    public static func meta(count: Int, seconds: TimeInterval) -> String {
        guard count > 0 else { return "Empty" }
        return "\(count) note\(count == 1 ? "" : "s") · \(duration(seconds))"
    }

    /// Folders in their saved order, then "From Watch" when any note came from the watch.
    @MainActor
    public static func cards(folders: [Folder], notes: [Note]) -> [FolderCard] {
        var cards = folders.sorted { $0.sortOrder < $1.sortOrder }.map { folder -> FolderCard in
            let inside = notes.filter { $0.folder?.id == folder.id }
            return FolderCard(
                kind: .folder(folder.id),
                name: folder.name,
                meta: meta(count: inside.count, seconds: inside.reduce(0) { $0 + $1.duration }),
                colorIndex: folder.colorIndex
            )
        }
        if notes.contains(where: { $0.source == .watch }) {
            cards.append(FolderCard(kind: .fromWatch, name: "From Watch", meta: "Smart folder", colorIndex: 4))
        }
        return cards
    }

    /// "6 folders · 21 notes".
    public static func subtitle(folderCount: Int, noteCount: Int) -> String {
        "\(folderCount) folder\(folderCount == 1 ? "" : "s") · \(noteCount) note\(noteCount == 1 ? "" : "s")"
    }
}

/// How far a row slides when the person swipes it to reveal Delete.
public enum SwipeReveal {
    /// The row's horizontal offset (zero or negative) while the finger is down.
    public static func offset(revealed: Bool, translation: Double, buttonWidth: Double) -> Double {
        let raw = (revealed ? -buttonWidth : 0) + translation
        if raw > 0 { return 0 }
        if raw < -buttonWidth { return -buttonWidth + (raw + buttonWidth) * 0.25 }   // resists past fully open
        return raw
    }

    /// Whether the button stays revealed once the finger lifts. `predictedEnd` is where the
    /// gesture would stop with its momentum.
    public static func settle(revealed: Bool, predictedEnd: Double, buttonWidth: Double) -> Bool {
        let target = (revealed ? -buttonWidth : 0) + predictedEnd
        return target < -buttonWidth / 2
    }
}

/// The banner on the Library that says new Apple Watch recordings arrived.
public enum WatchBanner {
    public static func text(count: Int) -> String {
        count == 1 ? "1 new recording from your Apple Watch" : "\(count) new recordings from your Apple Watch"
    }
}
