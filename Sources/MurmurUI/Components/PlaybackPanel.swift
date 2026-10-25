import SwiftUI

/// Note-screen player: scrub track with a knob, time, back 15 s, play/pause, forward 15 s, speed.
public struct PlaybackPanel: View {
    let progress: Double
    let timeText: String
    let isPlaying: Bool
    let speedLabel: String
    let isEnabled: Bool
    let onSeek: (Double) -> Void
    let onToggle: () -> Void
    let onSkip: (TimeInterval) -> Void
    let onSpeed: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var dragFraction: Double?

    public init(
        progress: Double,
        timeText: String,
        isPlaying: Bool,
        speedLabel: String,
        isEnabled: Bool = true,
        onSeek: @escaping (Double) -> Void,
        onToggle: @escaping () -> Void,
        onSkip: @escaping (TimeInterval) -> Void,
        onSpeed: @escaping () -> Void
    ) {
        self.progress = min(1, max(0, progress))
        self.timeText = timeText
        self.isPlaying = isPlaying
        self.speedLabel = speedLabel
        self.isEnabled = isEnabled
        self.onSeek = onSeek
        self.onToggle = onToggle
        self.onSkip = onSkip
        self.onSpeed = onSpeed
    }

    private var shown: Double { dragFraction ?? progress }

    public var body: some View {
        VStack(spacing: 12) {
            scrubber
            HStack {
                Text(timeText)
                    .font(MurmurTheme.Fonts.caption.monospacedDigit())
                    .foregroundStyle(MurmurTheme.Colors.textSecondary)
                    .frame(minWidth: 96, alignment: .leading)
                Spacer(minLength: 0)
                HStack(spacing: 14) {
                    skipButton("gobackward.15", label: "Back 15 seconds", seconds: -15)
                    Button(action: onToggle) {
                        Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                            .font(.title2)
                            .foregroundStyle(MurmurTheme.Colors.onAccent)
                            .frame(width: 58, height: 58)
                            .background(Circle().fill(MurmurTheme.Colors.accent))
                    }
                    .buttonStyle(MurmurPressStyle())
                    .accessibilityLabel(isPlaying ? "Pause" : "Play")
                    skipButton("goforward.15", label: "Forward 15 seconds", seconds: 15)
                }
                Spacer(minLength: 0)
                Button(action: onSpeed) {
                    Text(speedLabel)
                        .font(MurmurTheme.Fonts.caption.weight(.bold))
                        .foregroundStyle(MurmurTheme.Colors.textPrimary)
                        .frame(minWidth: 60, minHeight: MurmurTheme.Metrics.minTapTarget)
                        .background(Capsule().fill(MurmurTheme.Colors.raised))
                        .overlay(Capsule().strokeBorder(MurmurTheme.Colors.border, lineWidth: MurmurTheme.Metrics.borderWidth))
                }
                .buttonStyle(MurmurPressStyle())
                .accessibilityLabel("Playback speed \(speedLabel)")
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 16)
        .background(
            RoundedRectangle(cornerRadius: 28, style: .continuous).fill(MurmurTheme.Colors.surface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .strokeBorder(MurmurTheme.Colors.border, lineWidth: MurmurTheme.Metrics.borderWidth)
        )
        .opacity(isEnabled ? 1 : 0.5)
        .disabled(!isEnabled)
    }

    private func skipButton(_ symbol: String, label: String, seconds: TimeInterval) -> some View {
        Button { onSkip(seconds) } label: {
            Image(systemName: symbol)
                .font(.title3)
                .foregroundStyle(MurmurTheme.Colors.textPrimary)
                .frame(width: MurmurTheme.Metrics.minTapTarget, height: MurmurTheme.Metrics.minTapTarget)
        }
        .buttonStyle(MurmurPressStyle())
        .accessibilityLabel(label)
    }

    private var scrubber: some View {
        GeometryReader { geo in
            let width = geo.size.width
            ZStack(alignment: .leading) {
                Capsule().fill(MurmurTheme.Colors.raised).frame(height: 5)
                Capsule().fill(MurmurTheme.Colors.accent).frame(width: width * shown, height: 5)
                Circle()
                    .fill(MurmurTheme.Colors.textPrimary)
                    .overlay(Circle().strokeBorder(MurmurTheme.Colors.accent, lineWidth: 3))
                    .frame(width: 15, height: 15)
                    .offset(x: width * shown - 7.5)
            }
            .frame(maxHeight: .infinity)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in dragFraction = min(1, max(0, value.location.x / max(1, width))) }
                    .onEnded { value in
                        onSeek(min(1, max(0, value.location.x / max(1, width))))
                        dragFraction = nil
                    }
            )
        }
        .frame(height: 28)
        .accessibilityElement()
        .accessibilityLabel("Playback position")
        .accessibilityValue(timeText)
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: onSkip(15)
            case .decrement: onSkip(-15)
            @unknown default: break
            }
        }
    }
}

/// Round record button for the Library bottom bar. Breathes slowly; still under Reduce Motion.
public struct RecordButton: View {
    let action: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var breathe = false

    public init(action: @escaping () -> Void) { self.action = action }

    public var body: some View {
        Button(action: action) {
            Image(systemName: "mic.fill")
                .font(.system(size: 32, weight: .semibold))
                .foregroundStyle(MurmurTheme.Colors.onAccent)
                .frame(width: 80, height: 80)
                .background(Circle().fill(MurmurTheme.Colors.accent))
                .scaleEffect(breathe && !reduceMotion ? 1.06 : 1)
        }
        .buttonStyle(MurmurPressStyle())
        .accessibilityLabel("Start recording")
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true)) { breathe = true }
        }
    }
}

/// Small coloured circle with a speaker's initial.
public struct SpeakerBadge: View {
    let initial: String
    let color: Color

    public init(initial: String, color: Color) {
        self.initial = initial
        self.color = color
    }

    public var body: some View {
        Text(initial)
            .font(.system(.caption2, weight: .heavy))
            .foregroundStyle(MurmurTheme.Colors.background)
            .frame(width: 22, height: 22)
            .background(Circle().fill(color))
            .accessibilityHidden(true)
    }
}
