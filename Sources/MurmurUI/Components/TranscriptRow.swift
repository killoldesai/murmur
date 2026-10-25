import SwiftUI

/// One transcript segment. Normal, currently playing (selected fill + accent border) or being edited.
public struct TranscriptRow: View {
    public enum State {
        case normal
        case playing
        case editing
    }

    let speaker: String?
    let speakerColor: Color
    let timestamp: String
    let text: String
    let state: State

    public init(
        speaker: String? = nil,
        speakerColor: Color = MurmurTheme.Colors.accent,
        timestamp: String,
        text: String,
        state: State = .normal
    ) {
        self.speaker = speaker
        self.speakerColor = speakerColor
        self.timestamp = timestamp
        self.text = text
        self.state = state
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                if let speaker {
                    Circle().fill(speakerColor).frame(width: 8, height: 8)
                    Text(speaker)
                        .font(MurmurTheme.Fonts.caption.weight(.bold))
                        .foregroundStyle(speakerColor)
                }
                Text(timestamp)
                    .font(MurmurTheme.Fonts.caption.monospacedDigit())
                    .foregroundStyle(MurmurTheme.Colors.textTertiary)
                Spacer(minLength: 0)
                if state == .playing {
                    EqualizerBars()
                }
            }
            Text(text)
                .font(MurmurTheme.Fonts.body)
                .foregroundStyle(MurmurTheme.Colors.textPrimary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(state == .playing ? MurmurTheme.Colors.selectedFill : MurmurTheme.Colors.surface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(
                    state == .normal ? MurmurTheme.Colors.border : MurmurTheme.Colors.accent,
                    lineWidth: state == .normal ? MurmurTheme.Metrics.borderWidth : MurmurTheme.Metrics.selectedBorderWidth
                )
        )
        .animation(.easeInOut(duration: 0.35), value: state)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(state == .playing ? .isSelected : [])
    }
}

/// Three small bars that bounce while a line is playing. Static under Reduce Motion.
struct EqualizerBars: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation(paused: reduceMotion)) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            HStack(alignment: .bottom, spacing: 2) {
                ForEach(0..<3, id: \.self) { i in
                    let level = reduceMotion ? 0.6 : 0.35 + 0.65 * abs(sin(t * 4 + Double(i) * 1.3))
                    Capsule()
                        .fill(MurmurTheme.Colors.accent)
                        .frame(width: 3, height: 14 * level)
                }
            }
            .frame(height: 14, alignment: .bottom)
        }
        .accessibilityHidden(true)
    }
}
