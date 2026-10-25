import Foundation

/// Formats durations for timers, playback bars and note metadata.
public enum Timecode {
    /// `65` -> "01:05", `3725` -> "1:02:05". Negative and NaN values clamp to zero.
    public static func format(_ seconds: TimeInterval) -> String {
        let total = seconds.isFinite ? max(0, Int(seconds)) : 0
        let h = total / 3600
        let m = (total % 3600) / 60
        let s = total % 60
        if h > 0 {
            return String(format: "%d:%02d:%02d", h, m, s)
        }
        return String(format: "%02d:%02d", m, s)
    }
}
