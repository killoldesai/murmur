import SwiftUI

/// The big round timer on the record screen: a quiet orb, a rotating accent arc while recording,
/// and the status, time and caption inside.
public struct RecordingOrb: View {
    let statusLabel: String
    let time: String
    let caption: String
    let isRunning: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(statusLabel: String, time: String, caption: String = "New recording", isRunning: Bool) {
        self.statusLabel = statusLabel
        self.time = time
        self.caption = caption
        self.isRunning = isRunning
    }

    private var statusColor: Color {
        isRunning ? MurmurTheme.Colors.record : MurmurTheme.Colors.textSecondary
    }

    public var body: some View {
        TimelineView(.animation(paused: !isRunning || reduceMotion)) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            let angle = reduceMotion ? 0 : (t.truncatingRemainder(dividingBy: 3) / 3) * 360
            let breathe = reduceMotion || !isRunning ? 1 : 1 + 0.025 * sin(t * (2 * .pi / 2.4))
            let blink = reduceMotion || !isRunning ? 1 : 0.6 + 0.4 * cos(t * (2 * .pi / 1.2))

            ZStack {
                Circle()
                    .fill(MurmurTheme.Colors.panel)
                    .overlay(Circle().strokeBorder(MurmurTheme.Colors.border, lineWidth: 1))
                    .padding(14)
                    .scaleEffect(breathe)

                Circle()
                    .strokeBorder(MurmurTheme.Colors.border, lineWidth: 3)
                Circle()
                    .trim(from: 0, to: 0.25)
                    .stroke(MurmurTheme.Colors.accent, style: StrokeStyle(lineWidth: 3, lineCap: .butt))
                    .padding(1.5)
                    .rotationEffect(.degrees(angle - 135))
                    .opacity(isRunning ? 1 : 0.35)

                Circle()
                    .fill(MurmurTheme.Colors.surface)
                    .overlay(Circle().strokeBorder(MurmurTheme.Colors.border, lineWidth: 1))
                    .frame(width: 200, height: 200)

                VStack(spacing: 6) {
                    HStack(spacing: 7) {
                        Circle().fill(statusColor).frame(width: 7, height: 7).opacity(blink)
                        Text(statusLabel)
                            .font(.footnote.weight(.semibold))
                            .textCase(.uppercase)
                            .tracking(0.5)
                            .foregroundStyle(statusColor)
                    }
                    Text(time)
                        .font(.system(size: 52, weight: .light).monospacedDigit())
                        .foregroundStyle(MurmurTheme.Colors.textPrimary)
                        .minimumScaleFactor(0.6)
                        .lineLimit(1)
                    Text(caption)
                        .font(.footnote)
                        .foregroundStyle(MurmurTheme.Colors.textSecondary)
                }
                .frame(width: 180)
            }
            .frame(width: 260, height: 260)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(statusLabel), \(time)")
    }
}

/// Red stop button with a halo ring that ripples outward while recording.
public struct StopButton: View {
    let isRunning: Bool
    let action: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(isRunning: Bool, action: @escaping () -> Void) {
        self.isRunning = isRunning
        self.action = action
    }

    public var body: some View {
        ZStack {
            TimelineView(.animation(paused: !isRunning || reduceMotion)) { context in
                let t = context.date.timeIntervalSinceReferenceDate
                let p = (t.truncatingRemainder(dividingBy: 1.8)) / 1.8
                Circle()
                    .stroke(MurmurTheme.Colors.record, lineWidth: 2)
                    .scaleEffect(0.9 + 0.7 * p)
                    .opacity(reduceMotion || !isRunning ? 0 : 0.6 * (1 - p))
            }
            .frame(width: 78, height: 78)
            .accessibilityHidden(true)

            Button(action: action) {
                Circle()
                    .fill(MurmurTheme.Colors.record)
                    .frame(width: 78, height: 78)
                    .overlay(
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .fill(Color.white)
                            .frame(width: 24, height: 24)
                    )
            }
            .buttonStyle(MurmurPressStyle())
            .accessibilityLabel("Stop and transcribe")
        }
        .frame(width: 78, height: 78)
    }
}

/// Round 54 pt secondary control (bookmark, pause, resume).
public struct RoundControlButton: View {
    let systemImage: String
    let label: String
    let isAccent: Bool
    let action: () -> Void

    public init(systemImage: String, label: String, isAccent: Bool = false, action: @escaping () -> Void) {
        self.systemImage = systemImage
        self.label = label
        self.isAccent = isAccent
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(isAccent ? MurmurTheme.Colors.onAccent : MurmurTheme.Colors.textPrimary)
                .frame(width: 54, height: 54)
                .background(Circle().fill(isAccent ? MurmurTheme.Colors.accent : MurmurTheme.Colors.raised))
                .overlay(Circle().strokeBorder(MurmurTheme.Colors.border, lineWidth: isAccent ? 0 : 1))
        }
        .buttonStyle(MurmurPressStyle())
        .accessibilityLabel(label)
    }
}

/// Small pill used for header chips such as "Private · Offline".
public struct StatusPill: View {
    let text: String
    let systemImage: String?

    public init(_ text: String, systemImage: String? = nil) {
        self.text = text
        self.systemImage = systemImage
    }

    public var body: some View {
        HStack(spacing: 6) {
            if let systemImage {
                Image(systemName: systemImage)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(MurmurTheme.Colors.accent)
            }
            Text(text)
                .font(.footnote)
                .foregroundStyle(MurmurTheme.Colors.textSecondary)
        }
        .padding(.horizontal, 14)
        .frame(minHeight: 34)
        .background(Capsule().fill(MurmurTheme.Colors.surface))
        .overlay(Capsule().strokeBorder(MurmurTheme.Colors.border, lineWidth: 1))
    }
}
