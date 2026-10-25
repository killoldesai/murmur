import Foundation

/// Converts microphone power readings into a 0...1 bar height.
public enum MeterLevel {
    /// - Parameter decibels: average power, 0 dB (loudest) down to about -160 dB (silence).
    /// - Parameter floor: anything at or below this reads as 0, so a quiet room looks quiet.
    /// Normal speech at arm's length is roughly -35 to -15 dB.
    public static func normalized(decibels: Float, floor: Float = -50) -> Double {
        guard decibels.isFinite, floor < 0 else { return 0 }
        if decibels <= floor { return 0 }
        if decibels >= 0 { return 1 }
        return Double((decibels - floor) / -floor)
    }
}
