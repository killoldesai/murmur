import SwiftUI
import MurmurUI

/// Shown once, before onboarding. Matches design/iphone/Splash.dc.html.
struct SplashScreen: View {
    let onBegin: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var built = false
    @State private var swaying = false

    private let heights: [CGFloat] = [56, 34, 12, 34, 56]

    var body: some View {
        Button(action: onBegin) {
            ZStack {
                MurmurTheme.Colors.background.ignoresSafeArea()
                VStack(spacing: 28) {
                    icon
                    VStack(spacing: 8) {
                        Text("Murmur")
                            .font(.system(size: 36, weight: .heavy))
                            .foregroundStyle(MurmurTheme.Colors.textPrimary)
                        Text("Private voice to text")
                            .font(MurmurTheme.Fonts.body)
                            .foregroundStyle(MurmurTheme.Colors.textSecondary)
                    }
                    .murmurEntrance(index: 3)
                }
                .padding(.bottom, 60)
                VStack {
                    Spacer()
                    Text("Tap to begin")
                        .font(.footnote)
                        .foregroundStyle(MurmurTheme.Colors.textTertiary)
                        .padding(.bottom, 52)
                        .murmurEntrance(index: 5)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Murmur. Private voice to text")
        .accessibilityHint("Double tap to begin")
        .preferredColorScheme(.dark)
        .task {
            if reduceMotion {
                built = true
                return
            }
            withAnimation(.spring(response: 0.6, dampingFraction: 0.7)) { built = true }
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            withAnimation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true)) { swaying = true }
        }
    }

    private var icon: some View {
        HStack(spacing: 10) {
            ForEach(Array(heights.enumerated()), id: \.offset) { index, height in
                Capsule()
                    .fill(MurmurTheme.Colors.accent)
                    .frame(width: 9, height: height)
                    .scaleEffect(y: barScale(index), anchor: .center)
                    .animation(reduceMotion ? nil : .spring(response: 0.5, dampingFraction: 0.75).delay(0.3 + Double(index) * 0.08), value: built)
            }
        }
        .frame(width: 120, height: 120)
        .background(RoundedRectangle(cornerRadius: 27, style: .continuous).fill(MurmurTheme.Colors.surface))
        .overlay(RoundedRectangle(cornerRadius: 27, style: .continuous).strokeBorder(MurmurTheme.Colors.border))
        .scaleEffect(built ? 1 : 0.6)
        .opacity(built ? 1 : 0)
        .accessibilityHidden(true)
    }

    /// Bars grow in one after another, then sway out of step.
    private func barScale(_ index: Int) -> CGFloat {
        guard built else { return 0.01 }
        guard swaying else { return 1 }
        return index.isMultiple(of: 2) ? 0.55 : 1
    }
}
