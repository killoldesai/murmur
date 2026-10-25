import SwiftUI

/// Bar waveform. `levels` are 0...1 and come from mic metering while recording.
/// Pure presentation: it animates between level changes but computes nothing itself.
public struct Waveform: View {
    let levels: [CGFloat]
    let height: CGFloat
    let color: Color
    let spacing: CGFloat
    let barWidth: CGFloat

    public init(
        levels: [CGFloat],
        height: CGFloat = 64,
        color: Color = MurmurTheme.Colors.accent,
        spacing: CGFloat = 3,
        barWidth: CGFloat = 4
    ) {
        self.levels = levels
        self.height = height
        self.color = color
        self.spacing = spacing
        self.barWidth = barWidth
    }

    public var body: some View {
        HStack(alignment: .center, spacing: spacing) {
            ForEach(levels.indices, id: \.self) { i in
                Capsule()
                    .fill(color)
                    .frame(width: barWidth, height: max(4, min(1, max(0, levels[i])) * height))
            }
        }
        .frame(height: height)
        .animation(.easeOut(duration: 0.12), value: levels)
        .accessibilityHidden(true)
    }
}

/// Circular progress: accent arc over a raised track, starting at 12 o'clock.
public struct ProgressRing: View {
    let progress: Double
    let lineWidth: CGFloat

    public init(progress: Double, lineWidth: CGFloat = 8) {
        self.progress = min(1, max(0, progress))
        self.lineWidth = lineWidth
    }

    public var body: some View {
        ZStack {
            Circle().stroke(MurmurTheme.Colors.raised, lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: progress)
                .stroke(MurmurTheme.Colors.accent, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.easeOut(duration: 0.25), value: progress)
        }
        .accessibilityElement()
        .accessibilityLabel("Progress")
        .accessibilityValue("\(Int(progress * 100)) percent")
    }
}
