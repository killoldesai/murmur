import SwiftUI
import MurmurCore
import MurmurUI

/// Progress while a recording is transcribed. Matches design/iphone/Transcribing.dc.html.
/// Pure display: the caller passes the numbers, so it works with the real queue and the CI demo.
struct TranscribingScreen: View {
    enum Phase: Equatable {
        case working
        case done
        case failed(String)
    }

    let phase: Phase
    let fraction: Double
    let etaText: String
    let segments: [TranscriptSegment]
    let onLater: () -> Void
    let onOpen: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var spin = false
    @State private var pulse = false

    private var percent: Int { Int((min(1, max(0, fraction)) * 100).rounded()) }
    private var isWorking: Bool { phase == .working }

    private var heading: String {
        switch phase {
        case .working: "Transcribing on your iPhone"
        case .done: "Transcript ready"
        case .failed: "Couldn’t transcribe"
        }
    }

    private var subheading: String {
        if case .failed(let message) = phase { return message }
        return "Whisper runs right on your iPhone. Nothing is uploaded, ever."
    }

    var body: some View {
        ZStack {
            MurmurTheme.Colors.background.ignoresSafeArea()
            VStack(spacing: 0) {
                VStack(spacing: 26) {
                    ring
                    VStack(spacing: 8) {
                        Text(heading)
                            .font(MurmurTheme.Fonts.heading)
                            .foregroundStyle(MurmurTheme.Colors.textPrimary)
                            .accessibilityAddTraits(.isHeader)
                        Text(subheading)
                            .font(.subheadline)
                            .foregroundStyle(MurmurTheme.Colors.textSecondary)
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: 290)
                    }
                }
                .padding(.top, 24)
                .murmurEntrance(index: 0)

                preview
                    .padding(.top, 28)
                    .murmurEntrance(index: 1)

                Group {
                    switch phase {
                    case .done: PrimaryButton("Open transcript", action: onOpen)
                    case .working: SecondaryButton("Transcribe later", action: onLater)
                    case .failed: SecondaryButton("Close", action: onLater)
                    }
                }
                .padding(.top, 16)
            }
            .padding(.horizontal, MurmurTheme.Metrics.screenPadding)
            .padding(.top, 24)
            .padding(.bottom, 16)
        }
        .preferredColorScheme(.dark)
        .sensoryFeedback(.success, trigger: phase == .done)
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.linear(duration: 2.2).repeatForever(autoreverses: false)) { spin = true }
            withAnimation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true)) { pulse = true }
        }
    }

    private var ring: some View {
        let size = MurmurTheme.Metrics.progressRingSize
        return ZStack {
            Circle()
                .fill(MurmurTheme.Colors.panel)
                .overlay(Circle().strokeBorder(MurmurTheme.Colors.border, lineWidth: MurmurTheme.Metrics.borderWidth))
                .padding(18)
            ProgressRing(progress: phase == .done ? 1 : fraction, lineWidth: 9)
            if isWorking && !reduceMotion {
                Circle()
                    .fill(MurmurTheme.Colors.textPrimary)
                    .frame(width: 8, height: 8)
                    .offset(y: -(size / 2 - 5))
                    .rotationEffect(.degrees(spin ? 360 : 0))
                    .accessibilityHidden(true)
            }
            VStack(spacing: 2) {
                HStack(alignment: .firstTextBaseline, spacing: 0) {
                    Text("\(phase == .done ? 100 : percent)")
                        .font(MurmurTheme.Fonts.percent)
                    Text("%")
                        .font(.title3)
                        .foregroundStyle(MurmurTheme.Colors.textSecondary)
                }
                .foregroundStyle(MurmurTheme.Colors.textPrimary)
                Text(phase == .done ? "Done" : etaText)
                    .font(.footnote)
                    .foregroundStyle(MurmurTheme.Colors.textSecondary)
            }
        }
        .frame(width: size, height: size)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Transcription \(phase == .done ? 100 : percent) percent complete")
        .accessibilityValue(phase == .done ? "Done" : etaText)
    }

    private var preview: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Circle()
                    .fill(MurmurTheme.Colors.accent)
                    .frame(width: 6, height: 6)
                    .opacity(pulse && isWorking ? 1 : 0.4)
                Text("Live preview").murmurSectionLabel()
            }
            ForEach(Array(segments.suffix(6))) { segment in
                HStack(alignment: .top, spacing: 12) {
                    Text(Timecode.format(segment.start))
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(MurmurTheme.Colors.accent)
                        .frame(minWidth: 38, alignment: .leading)
                        .padding(.top, 2)
                    Text(segment.text)
                        .font(.callout)
                        .foregroundStyle(MurmurTheme.Colors.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .transition(reduceMotion ? .identity : .move(edge: .bottom).combined(with: .opacity))
            }
            if isWorking {
                HStack(spacing: 12) {
                    Color.clear.frame(width: 38, height: 1)
                    Capsule()
                        .fill(MurmurTheme.Colors.raised)
                        .frame(height: 12)
                        .opacity(pulse ? 1 : 0.5)
                        .padding(.trailing, 80)
                }
                .accessibilityHidden(true)
            }
            Spacer(minLength: 0)
        }
        .padding(18)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .murmurCard()
        .clipped()
        .animation(reduceMotion ? nil : MurmurMotion.spring, value: segments.count)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Live preview")
    }
}
