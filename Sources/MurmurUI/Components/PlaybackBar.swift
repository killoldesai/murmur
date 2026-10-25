import SwiftUI
import MurmurCore

/// Play/pause, scrub track, elapsed/total time and a speed pill.
public struct PlaybackBar: View {
    let progress: Double          // 0...1
    let elapsed: TimeInterval
    let total: TimeInterval
    let isPlaying: Bool
    let speedLabel: String
    let onTogglePlay: () -> Void
    let onSpeedTap: () -> Void

    public init(
        progress: Double,
        elapsed: TimeInterval,
        total: TimeInterval,
        isPlaying: Bool,
        speedLabel: String = "1×",
        onTogglePlay: @escaping () -> Void,
        onSpeedTap: @escaping () -> Void = {}
    ) {
        self.progress = min(1, max(0, progress))
        self.elapsed = elapsed
        self.total = total
        self.isPlaying = isPlaying
        self.speedLabel = speedLabel
        self.onTogglePlay = onTogglePlay
        self.onSpeedTap = onSpeedTap
    }

    public var body: some View {
        VStack(spacing: 10) {
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(MurmurTheme.Colors.raised)
                    Capsule()
                        .fill(MurmurTheme.Colors.accent)
                        .frame(width: max(6, geo.size.width * progress))
                }
            }
            .frame(height: 6)
            .accessibilityElement()
            .accessibilityLabel("Playback position")
            .accessibilityValue("\(Timecode.format(elapsed)) of \(Timecode.format(total))")

            HStack(spacing: 12) {
                Button(action: onTogglePlay) {
                    Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                        .font(.title3)
                        .foregroundStyle(MurmurTheme.Colors.onAccent)
                        .frame(width: MurmurTheme.Metrics.minTapTarget, height: MurmurTheme.Metrics.minTapTarget)
                        .background(Circle().fill(MurmurTheme.Colors.accent))
                }
                .buttonStyle(MurmurPressStyle())
                .accessibilityLabel(isPlaying ? "Pause" : "Play")

                Text("\(Timecode.format(elapsed)) / \(Timecode.format(total))")
                    .font(MurmurTheme.Fonts.caption.monospacedDigit())
                    .foregroundStyle(MurmurTheme.Colors.textSecondary)

                Spacer(minLength: 0)

                Button(action: onSpeedTap) {
                    Text(speedLabel)
                        .font(MurmurTheme.Fonts.caption.weight(.bold))
                        .foregroundStyle(MurmurTheme.Colors.textPrimary)
                        .padding(.horizontal, 14)
                        .frame(minHeight: MurmurTheme.Metrics.minTapTarget)
                        .background(Capsule().fill(MurmurTheme.Colors.raised))
                        .overlay(Capsule().strokeBorder(MurmurTheme.Colors.border, lineWidth: MurmurTheme.Metrics.borderWidth))
                }
                .buttonStyle(MurmurPressStyle())
                .accessibilityLabel("Playback speed \(speedLabel)")
            }
        }
        .padding(16)
        .murmurCard()
    }
}
